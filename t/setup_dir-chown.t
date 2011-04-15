#!perl

use 5.010;
use strict;
use warnings;

use FindBin '$Bin';
use lib $Bin, "$Bin/t";

use File::Slurp;
use Test::More 0.96;
require "testlib.pl";

plan skip_all => "must run as root to test changing ownership/group" if $>;

setup();

#test_setup_dir(...);

DONE_TESTING:
teardown();
