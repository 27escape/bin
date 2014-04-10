#!/usr/bin/env perl
# get some geo info
#
# (c) kevin Mulholland 2012, moodfarm@cpan.org
# this code is released under the Perl Artistic License

# v0.1 moodfarm@cpan.org, initial work

use 5.14.0 ;
use strict ;
use warnings ;
use App::Basis ;
use Data::Printer ;

use Geo::Coder::Google;

sub other_debug
{
  my $debug = shift ;
  say localtime() . " app " . $debug ;
}

# -----------------------------------------------------------------------------
# main

my $program = get_program() ;

my %opt = init_app(
  help_text => "Boiler plate code for an App::Basis app"
  , help_cmdline => "other things",
  options => { 'verbose|v' => 'Dump extra useful information', 
    'test=s'  => {
        desc => 'test item',
        # depends => 'item',
        default => 'testing 123',
        # required => 1,
    },
    'item=s' => {
      # required  => 1,
      default => '123',
      desc => 'another item',
      # validate => sub { my $val = shift ; return $val eq 'item'}
    }
  }
) ;

set_debug( \&other_debug ) ;

if ( $opt{verbose} ) {
  my $prog = get_program() ;
  debug("prog is '$prog'") ;
}

  my $geocoder = Geo::Coder::Google->new(apiver => 3);
  my $location = $geocoder->geocode( location => 'Hollywood and Highland, Los Angeles, CA' );

