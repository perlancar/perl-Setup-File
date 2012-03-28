#!perl

use 5.010;
use strict;
use warnings;

use FindBin '$Bin';
use lib $Bin, "$Bin/t";

use File::Slurp;
use Test::More 0.96;
require "testlib.pl";

use vars qw($tmp_dir $undo_data);

plan skip_all => "must run as root to test changing ownership/group" if $>;

setup();

test_setup_dir(
    name          => "create",
    path          => "/d",
    other_args    => {should_exist=>1, owner=>2, group=>3},
    check_unsetup => {exists=>0},
    check_setup   => {exists=>1, is_dir=>1, owner=>2, group=>3},
    cleanup       => sub { rmdir "d" },
);

# XXX: test using group name (instead of gid)
# XXX: test using user name (instead of uid)
# XXX: test fixing existing dir's owner/group
# XXX: test undo (restore existing dir's previous owner/group)

DONE_TESTING:
teardown();
