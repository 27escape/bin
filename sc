#!/usr/bin/env perl
# PODNAME: sc

# ABSTRACT: expand shellcheck error codes to web pages

=head1 NAME

sc

=head1 SYNOPSIS

    >   ..options..

    to get full help use
    >  --help

=head1 DESCRIPTION

expand shellcheck error codes to a webpage

=cut

#
# (c) yourname, your@email.address.com
# this code is released under some License

use 5.10.0 ;
use strict ;
use warnings ;
use App::Basis ;

my $SHELLCHECK = "https://github.com/koalaman/shellcheck/wiki" ;
my $min_error  = 1000 ;
my $max_error  = 2212 ;

# -----------------------------------------------------------------------------
# main

my %opt = init_app(
    help_text    => "expand a shellcheck error code to a webpage",
    help_cmdline => "code",
    options      => { 'verbose|v' => 'Dump extra useful information', },
) ;

my $default_error =
    "code should be a number between $min_error and $max_error, can be preceeded with SC, ie 1000 or SC1000"
    ;
my $code = $ARGV[0] ;
if ( $code !~ /^(sc)?(\d+)$/i ) {
    show_usage($default_error) ;
}
# rebuild the code nicely
$code = "$2" ;

if ( $code < $min_error || $code > $max_error ) {
    show_usage($default_error) ;
}

# launch the web page
my $cmd = "x-www-browser '$SHELLCHECK/SC$code' >/dev/null 2>&1" ;
# verbose("command is $cmd") ;
system($cmd) ;
