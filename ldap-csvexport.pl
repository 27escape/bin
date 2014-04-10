#!/usr/bin/perl
# ldap-csvexport.pl -H ldap.inview.local -b o=inviewtechnology -u "uid=kmulholland,ou=Infrastructure,ou=users,o=inviewtechnology" -a "sn,givenname,manager,title,mail,mobile,telephoneNumber,ou" -p `cat ~/.ldap_password` 

#############################################################################
#  Export LDAP entries in csv format to STDOUT                              #
#  Version: 1.2.1                                                           #
#  Author:  Benedikt Hallinger <beni@hallinger.org>                         #
#           FrenkX <FrenkX@tamotuA.de> (paging support)                     #
#                                                                           #
#  This program allows you to easily export entries to csv format.          #
#  It reads entries of an LDAP directory and prints selected attributes     #
#  in CSV format to STDOUT. Multi valued attributes will be separated by    #
#  an user definable character sequence.                                    #
#                                                                           #
#  Errors and verbose inforamtion are printed to STDERR.                    #
#  The exported data is usually in UTF8 but will be print like it is        #
#  fetched from the directory server. You can use 'recode' to convert.      #
#                                                                           #
#  Please call 'ldap-csvexpor.pl -h' for available command line             #
#  options and additional information.                                      #
#                                                                           #
#  Exit codes are as following:                                             #
#    0 = all ok                                                             #
#    1 = connection or bind error                                           #
#    2 = operational error                                                  #
#    3 = LDAP paging error                                                  #
#                                                                           #
#  Required modules are                                                     #
#    Net::LDAP                                                              #
#    Net::LDAP::Control::Paged                                              #
#    Net::LDAP::Constant                                                    #
#    Getopt::Std                                                            #
#  You can get these modules from your linux package system or from CPAN.   #
#                                                                           #
#  Hosted at Sourceforge: https://sourceforge.net/projects/ldap-csvexport/  #
#  Please report bugs and suggestions using the trackers there.             #
#                                                                           #
#############################################################################
#  This program is free software; you can redistribute it and/or modify     #
#  it under the terms of the GNU General Public License as published by     #
#  the Free Software Foundation; either version 2 of the License, or        #
#  (at your option) any later version.                                      #
#                                                                           #
#  This program is distributed in the hope that it will be useful,          #
#  but WITHOUT ANY WARRANTY; without even the implied warranty of           #
#  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the            #
#  GNU General Public License for more details.                             #
#                                                                           #
#  You should have received a copy of the GNU General Public License        #
#  along with this program; if not, write to the Free Software              #
#  Foundation, Inc., 59 Temple Place - Suite 330, Boston, MA  02111, USA.   #
#############################################################################

use strict;
use Net::LDAP;
use Net::LDAP::Control::Paged;
use Net::LDAP::Constant qw( LDAP_CONTROL_PAGED );
use Getopt::Std;

my $time_start = time; # for stats afterwards

#
# Parsing CMDline options
#
# Default values (and var assingment)
my $host        = 'ldap.inview.local';
my $searchbase  = 'o=inviewtechnology';
my $user        = '';
my $pass        = '';
my @attributes  = ();
# my $filter      = "(objectclass=Person)";
# get people who can login only
my $filter      = "(&(objectclass=Person)(logindisabled=FALSE))";
my $mvsep       = "|";
my $fieldquot   = '"';
my $fieldsep    = ";";
my $verbose     = 0;
my $singleval   = 0;
my $pagesize    = 100;
my $scope       = 'sub';

# Use Getopt to parse cmdline
my %Options;
my $arg_count = @ARGV;
my $arg_ok = getopts('1hva:u:p:b:H:f:m:q:S:s:l:', \%Options);
if ($Options{h}) {
        usage();
        help();
        exit 0;
}
if (!$arg_ok) {
        usage();
        exit 1;
}

# check for missing mandatory parameters
foreach my $o ('a', 'b') {
        if ( !defined($Options{$o}) ) {
                print STDERR "Parameter -$o is mandatory!\n";
                usage();
                exit 1;
        }
}

# set and verify options
if ($Options{'a'}){
	@attributes = split(/\s|,|\\;/, $Options{'a'}); 
}
if ($Options{'u'}){
        if (!$Options{p}) {
                print STDERR "If -u is given, -p is mandatory. Use '-p \'\'' if password is empty.\n";
                exit 1;
        }
        $user = $Options{'u'};
}
if ($Options{'S'}){
	if ($Options{'S'} =~ /^base|one|sub$/) {
		$scope = $Options{'S'};
	} else {
		print STDERR "-S must be one of 'base', 'one' or 'sub'.\n";
                exit 1;
	}
}
if (defined($Options{'p'})){ $pass       = $Options{'p'};}
if ($Options{'H'}){ $host                = $Options{'H'};}
if (defined($Options{'b'})){ $searchbase = $Options{'b'};}
if ($Options{'v'}){ $verbose             = 1;}
if ($Options{'f'}){ $filter              = $Options{'f'};}
if (defined($Options{'m'})){ $mvsep      = $Options{'m'};}
if (defined($Options{'q'})){ $fieldquot  = $Options{'q'};}
if (defined($Options{'s'})){ $fieldsep   = $Options{'s'};}
if ($Options{'1'}){ $singleval           = 1;}
if (defined($Options{'l'})){ $pagesize   = $Options{'l'};}


#
# Connect and bind to server
#
if ($verbose) { print STDERR "connecting to $host...\n"; }
my $ldap = Net::LDAP->new($host);   # LDAP-Verbindung aufbauen
if (!$ldap){
        print STDERR "Could not connect to $host!\n(Server says: $@)\n\n";
        exit 1;
}
if ($user) {
        my $mesg = $ldap->bind($user, 'password' => $pass);
        if($mesg->code){
                print STDERR "Authentication failed!\n(Server says: ".$mesg->error.")\n\n";
                exit 1;
        }
} else {
        my $mesg = $ldap->bind();
}


#
# Set up CONTROL for paged results
#
my $page = Net::LDAP::Control::Paged->new( size => $pagesize );
my $cookie = undef;
my @searchArgs = (
	base    => $searchbase, 
	filter  => $filter, 
	attrs   => \@attributes,
	scope   => $scope,
	control => [ $page ] 
);

# prepare and print CSV header line:
my $csv_header;
foreach my $a (@attributes) {
	$csv_header = "$csv_header$fieldquot$a$fieldquot$fieldsep";
}
$csv_header =~ s/\Q$fieldsep\E$//; # eat last $fieldsep

# set helper variables
my $csv_header_printed = 0;
my $exitVal = undef;
my $totalcount = 0;

do{
	#
	# Perform search and print data
	#
	if ($verbose) { print STDERR "performing search (filter='$filter'; searchbase='$searchbase')... "; }
	my $mesg = $ldap->search(@searchArgs);
	if ($mesg->code) {
		print STDERR "LDAP search failed!\n(Server says: ".$mesg->error."\n\n";
		$exitVal = 2;
	}
	if (!defined($cookie) && $mesg->count() == 0){
		print STDERR "No ppl found. Check searchparameters.\n";
		$exitVal = 0;
	} else {
		if ($verbose) { print STDERR $mesg->count()." entries found\n"; }
		$totalcount += $mesg->count();
		# search was ok
		# if no header was printed so far, do it now
		unless ($csv_header_printed == 1) {
			print "$csv_header\n";
			$csv_header_printed = 1;
		}
		
		# get control element for paged result set and save it to the cookie
		my($response) = $mesg->control( LDAP_CONTROL_PAGED ) or $exitVal = 3;
		$cookie = $response->cookie or $exitVal = 3;

		# Now dump all found entries
		while (my $entry = $mesg->shift_entry()){
			# Retrieve each fields value and print it
			# if attr is multivalued, separate each value
			my $current_line = ""; #prepare fresh line
			foreach my $a (@attributes) {
				if ($entry->exists($a)) {
					my $attr    = $entry->get_value($a, 'asref' => 1);
					my @values  = @$attr;
					my $val_str = "";
					if (!$singleval) {
						# retrieve all values and separate them via $mvsep
						foreach my $val (@values) {
							$val_str = "$val_str$val$mvsep"; # add all values to field
						}
						$val_str =~ s/\Q$mvsep\E$//; # eat last MV-Separator
					} else {
						$val_str = shift(@values); # user wants only the first value
					}

					$current_line .= $fieldquot.$val_str.$fieldquot; # add field data to current line

				} else {
					# no value found: just add fieldquotes
					$current_line .= $fieldquot.$fieldquot;
				}
				$current_line .= $fieldsep; # close field and add to current line
			}
			$current_line =~ s/\Q$fieldsep\E$//; # eat last $fieldsep
			print "$current_line\n"; # print line
		}
		# set cookie of the 
		$page->cookie($cookie);
	}
} until (defined($exitVal));

if ($verbose) { print STDERR "A total of $totalcount entries were found.\n"; }

if( defined( $cookie ) ){
	$page->cookie($cookie);
	$page->size(0);
	$ldap->search(@searchArgs);
}

# all fine, go home
$ldap->disconnect();
if ($verbose) {
	my $runtime = time - $time_start;
	print STDERR "done in $runtime s\n"
}
exit $exitVal;


# Usage information for help screen
sub usage {
	print "Export LDAP entries into csv format\n";
	print "Synopsis:\n";
	print "  ./ldap-csvexport.pl -a attr-list -H Host -b searchbase\n";
	print "                      [-1] [-m mv-sep] [-q quotechar] [-s field-sep]\n";
	print "                      [-u user-dn] [-p password] [-f filter] [-v]\n";
	print "  ./ldap-csvexport.pl -h\n";
	print "\nMandatory options:\n";
	print "  -a  Attribute list specifiying the attributes to export. Attributes\n";
	print "      are to be separated by space, commata or escaped semicolon (\"\\;\").\n";
	print "  -b  LDAP searchbase\n";
	print "\nOptional options:\n";
	print "  -f  LDAP filter (default: '$filter')\n";
	print "  -h  Show more help than this usage information\n";
	print "  -H  Hostname (DNS or IP) of LDAP server (default: '$host')\n";
	print "  -l  LDAP page size limit (default: '$pagesize', depends on your server)\n";
	print "  -m  String that is used to separate multiple values inside csv-fields (default: '$mvsep')\n";
	print "  -p  Password of user for binding (see -u)\n";
	print "  -q  String that is used to quote entire csv fields (default: '$fieldquot')\n";
	print "  -s  String that separates csv-fields (default: '$fieldsep')\n";
	print "  -S  Scope of LDAP search (default: '$scope')\n";
	print "  -1  Prints only the first retrieved value for an attribute (instead of MV)\n";
        print "  -u  DN of user for binding (anonymous if not given)\n";
	print "  -v  Show at STDERR what the program does\n";
}

# Prints extendet help
sub help {
	print "\n\nAdditional information:\n";
	print "  Exit codes are as following:\n";
	print "    0 = everything was ok\n";
	print "    1 = connection or bind error\n";
	print "    2 = operational error\n";
	print "\nA word on the -a parameter with semicolon\n";
	print "    As of release 1.1, the semicolon MUST be escaped to be used as attribute\n";
	print "    selection separator, because LDAP allows \"attribute flavors\":\n";
	print "      -a 'sn,givenName,description;lang-en'  => sn, givenName, description;lang-en\n";
	print "      -a 'sn,givenName,description\\;lang-en' => sn, givenName, description, lang-en\n";
	print "\nUsage Examples: (parameters -H and -b are ommitted for readability)\n";
	print "  $0 -a 'attr1,attr2,attr3' > foofile.csv\n";
	print "    -> export attr1, attr2 and attr3 to foofile.csv\n";
	print "  $0 -1 -a 'attr3 attr4' > foofile.csv\n";
	print "    -> export attr3 and attr4 but print only the first retrieved attribute\n";
	print "       value (this is not always the first value in the server!)\n";
	print "  $0 -a 'attr5\\;attr6' -m '-' -q '/' > foofile.csv\n";
	print "    -> export attr5 and attr6. If one has multiple values, they will be separated by\n";
	print "       the minus character. Additionally, quote entire csv fields with a\n";
	print "       forward slash. resulting cvs line like: \"/val1-val2-val3/attr6v1\"\n";
	print "\nTroubleshooting:\n";
	print "  If you have problems with special characters (e.g. german umlauts),\n";
	print "  use recode to change the encoding of the resulting file.\n";
	print "\n  If you find bugs, please report them to the SF bugtracker:\n";
	print "    https://sourceforge.net/projects/ldap-csvexport/\n";
}
