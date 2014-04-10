#!/bin/bash
# moodfarm@cpan.org

PROGRAM=`basename $1`
PROFILE_DIR="/tmp/nytprof"
PROFILE_FILE="$PROFILE_DIR/$PROGRAM.$$.nytprof"
mkdir $PROFILE_DIR 2>/dev/null

# setup options to make sure we output into someplace nice
export NYTPROF="trace=2:start=init:sigexit=1:posix_exit=1:file=$PROFILE_FILE"
PERL5OPT=-d:NYTProf

# run the passed script and parameters
$*

# print to STDERR
echo "now use nytprofhtml -o /tmp/nytprof -f $PROFILE_FILE --open to view the data" 1>&2