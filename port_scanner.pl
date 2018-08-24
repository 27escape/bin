#!/usr/bin/env perl
# http://perltricks.com/article/188/2015/8/15/Port-scanning-with-Perl--Part-II
########################################################
# Adapted from Penetration Testing With Perl           #
# by Douglas Berdeaux                                  #
# Chapter 3 IEEE 802.3 Wired Network Mapping with Perl #
########################################################
use warnings;
use strict;
use Getopt::Long;
use IO::Socket::INET;
use List::Util 'shuffle';
use Net::Address::IP::Local;
use Net::Pcap;
use Net::RawIP;
use NetPacket::Ethernet;
use NetPacket::ICMP;
use NetPacket::IP;
use NetPacket::TCP;
use NetPacket::UDP;
use POSIX qw/WNOHANG ceil/;
use Pod::Usage;
use Time::HiRes 'sleep';
use Time::Piece;

# orderly shutdown when signals received
BEGIN { $SIG{INT} = $SIG{TERM} = sub { exit 0 } }

my $start_time = localtime;
my $VERSION    = 0.02;
my $SOURCE     = 'github.com/dnmfarrell/Penetration-Testing-With-Perl';

GetOptions (
  'delay=f'     => \(my $delay = 1),
  'ip=s'        => \ my $target_ip,
  'range=s'     => \ my $port_range,
  'procs=i'     => \(my $procs = 50),
  'type=s'      => \(my $protocol = 'tcp'),
  'flag=s'      => \ my @flags,
  'verbose'     => \ my $verbose,
  'h|help|?'    => sub { pod2usage(2) },
);

# validate required args are given
die "Missing --ip parameter, try --help\n" unless $target_ip;

die "ip: $target_ip is not a valid ipv4 address\n"
  unless $target_ip =~ /[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+/;

# determine protocol to use
die "Unknown protocol type, try tcp or udp\n" unless $protocol =~ /^(?:tcp|udp)$/;

# set flags (tcp only, default to syn if no flags provided)
die "flags are for tcp only!\n" if $protocol ne 'tcp' && @flags;
$flags[0] = 'syn' unless @flags || $protocol eq 'udp';
my $flags = { map { $_ => 1 } @flags };
$flags = {} if exists $flags->{null};

# get local IP
my $local_ip = Net::Address::IP::Local->public;

# find a random free port by opening a socket using the protocol
my $local_port = do {
  my $socket = IO::Socket::INET->new(Proto => $protocol, LocalAddr => $local_ip);
  my $socket_port = $socket->sockport();
  $socket->close;
  $socket_port;
};

# build the port list
my %port_directory;
open my $port_file, '<', 'data/nmap-services.txt'
  or die "Error reading data/nmap-services.txt $!\n";
while (<$port_file>)
{
  next if /^#/; # skip comments
  chomp;
  my ($name, $number_protocol, $probability, $comments) = split /\t/;
  my ($port, $proto) = split /\//, $number_protocol;

  $port_directory{$number_protocol} = {
    port        => $port,
    proto       => $proto,
    name        => $name,
    probability => $probability,
    comments    => $comments,
  };
}

# use named ports if no range was provided
my @ports = shuffle do {
  unless ($port_range)
  {
    map { $port_directory{$_}->{port} }
      grep { $port_directory{$_}->{name} !~ /^unknown$/
             && $port_directory{$_}->{proto} eq $protocol } keys %port_directory;
  }
  else
  {
    my ($min, $max) = $port_range =~ /([0-9]+)-([0-9]+)/
      or die "port-range must be formatted like this: 100-1000\n";
    $min..$max;
  }
};

print "\n$0  Version $VERSION  Source: $SOURCE

$start_time

Starting port scan: type: $protocol, flags: @flags, $procs procs, $delay (secs) delay
Source host: $local_ip:$local_port, target host: $target_ip\n\n";

# apportion the ports to scan between processes
my $batch_size = ceil(@ports / $procs);

# if we're using tcp and DIDNT send syn/rst/ack
# then default status is open/filtered
my $default_port_status =
  ($protocol eq 'tcp' && 0 == grep { /^(?:syn|rst|ack)$/ } keys %$flags)
  ? 'open/filtered'
  : 'filtered';

my %port_scan_results = map { $_ => $default_port_status } @ports;
my @child_pids;

for (1..$procs)
{
  my @ports_to_scan = splice @ports, 0, $batch_size;
  my $parent = fork;
  die "unable to fork!\n" unless defined ($parent);

  if ($parent)
  {
    push(@child_pids, $parent);
    next;
  }

  # child waits until the parent signals to continue
  my $continue = 0;
  local $SIG{CONT} = sub { $continue = 1};
  until ($continue) {}

  for my $target_port (@ports_to_scan)
  {
    sleep($delay);
    send_packet($protocol, $target_port, $flags);
  }
  exit 0; # exit child
}

# setup parent packet capture
my $device_name = pcap_lookupdev(\my $err);
pcap_lookupnet($device_name, \my $net, \my $mask, \$err);
my $pcap = pcap_open_live($device_name, 1024, 0, 1000, \$err);
pcap_compile(
  $pcap,
  \my $filter,
  "(src net $target_ip) && (dst port $local_port)",
  0,
  $mask
);
pcap_setfilter($pcap,$filter);

# ready to rock, signal the child pids to start sending
kill CONT => $_ for @child_pids;

until (waitpid(-1, WNOHANG) == -1) # until all children exit
{
  my $packet_capture = pcap_next_ex($pcap,\my %header,\my $packet);
  if($packet_capture == 1)
  {
    my ($port, $status) = read_packet($packet);
    $port_scan_results{$port} = $status if $port;
  }
  elsif ($packet_capture == -1)
  {
    warn "libpcap errored while reading a packet\n";
  }
}

my $end_time = localtime;
my $duration = $end_time - $start_time;

for (sort { $a <=> $b } keys %port_scan_results)
{
  printf " %5u %-15s %-40s\n", $_, $port_scan_results{$_}, ($port_directory{"$_/$protocol"}->{name} || '')
    if $port_scan_results{$_} =~ /open/ || $verbose;
}

printf "\nScan duration: %u seconds\n%d ports scanned, %d filtered, %d closed, %d open\n\n",
  $duration,
  scalar(keys %port_scan_results),
  scalar(grep { $port_scan_results{$_} eq 'filtered' } keys %port_scan_results),
  scalar(grep { $port_scan_results{$_} eq 'closed'   } keys %port_scan_results),
  # includes open/filtered
  scalar(grep { $port_scan_results{$_} =~ /open/     } keys %port_scan_results);

END { pcap_close($pcap) if $pcap }

sub send_packet
{
  my ($protocol, $target_port, $flags) = @_;

  Net::RawIP->new({ ip => {
                      saddr => $local_ip,
                      daddr => $target_ip,
                    },
                    $protocol => {
                      source => $local_port,
                      dest   => $target_port,
                      %$flags,
                    },
                  })->send;
}

sub read_packet
{
  my $raw_data = shift;
  my $ip_data = NetPacket::Ethernet::strip($raw_data);
  my $ip_packet = NetPacket::IP->decode($ip_data);

  if ($ip_packet->{proto} == 6)
  {
    my $tcp = NetPacket::TCP->decode(NetPacket::IP::strip($ip_data));
    my $port = $tcp->{src_port};

    if ($tcp->{flags} & SYN)
    {
      return ($port, 'open');
    }
    elsif ($tcp->{flags} & RST)
    {
      return ($port, 'closed');
    }
    return ($port, 'unknown');
  }
  elsif ($ip_packet->{proto} == 17)
  {
    my $udp = NetPacket::UDP->decode(NetPacket::IP::strip($ip_data));
    my $port = $udp->{src_port};
    return ($port, 'open');
  }
  else
  {
    warn "Received unknown packet protocol: $ip_packet->{proto}\n";
  }
}

__END__

=head1 NAME

port_scanner - a concurrent randomized tcp/udp port scanner written in Perl

=head1 SYNOPSIS

port_scanner [options]

 Options:
  --ip,     -i   ip address to scan e.g. 10.30.1.52
  --type    -t   type of protocol to use either tcp or udp (defaults to tcp)
  --flag    -f   flag to set on tcp (defaults to SYN, use "null" for no flags)
  --range,  -r   range of ports to scan e.g. 10-857 (search named ports if range not provided)
  --delay,  -d   seconds to delay each packet send per process. Can be decimal (e.g. 0.5)
  --help,   -h   display this help text
  --verbose,-v   verbose mode, print closed and filtered ports
  --procs,  -p   how many concurrent packets to send at a time (defaults to 1)

=head2 Examples

Search all the named ports on host C<10.20.1.22>

  sudo ./port_scanner -i 10.20.1.22

Use local Perl installed with perlbrew or plenv

  sudo $(which perl) port_scanner -i 10.20.1.22

Search a defined range of ports on host C<10.20.1.22>

  sudo ./port_scanner --ip 10.20.1.22 --range 1-1450

=head3 Request frequency

C<port_scanner> can make concurrent requests, use the C<procs> and C<delay> to fine tune the request frequency you need.

Make 50 requests every 0.25 seconds print all results

  sudo ./port_scanner --ip 10.22.1.22  --delay 0.25 --procs 50 --verbose

Same thing, with abbreviated parameters

  sudo ./port_scanner -i 10.22.1.22 -d 0.25 -p 50 -v

=head3 Types of scans

Perform a TCP SYN scan (default)

  sudo ./port_scanner -i 10.22.1.22 -f syn

TCP null scan

  sudo ./port_scanner -i 10.22.1.22 -f null

TCP FIN scan

  sudo ./port_scanner -i 10.22.1.22 -f fin

TCP XMAS Scan

  sudo ./port_scanner -i 10.22.1.22 -f fin -f psh -f urg

UDP scan

  sudo ./port_scanner -i 10.22.1.22 -t udp

=head3 Tips

On Unix-based systems, use the C<procs> option to make concurrent requests, otherwise the scan can take a long time. On Windows, the Perl would need to be compiled with fork() emulation in order for the concurrent requests to work (I think - see C<perldoc perlfork>).

Some firewalls will filter packets if too many are sent - in these cases you may need to reduce the number of procs or increase the C<delay>. C<port_scanner> will warn if it receives ICMP packets which may can indicate flooding and the need to reduce request frequency.

C<port_scanner> defaults to a TCP SYN scan, but vastly different results can be obtained using the other options like C<-f fin>, C<-f null> and C<-t udp>. The target host response will vary (of course) by the host's OS and configuration.

=cut

