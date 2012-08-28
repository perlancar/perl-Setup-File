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

test_setup_file(
    name          => "create",
    path          => "/f",
    other_args    => {should_exist=>1, owner=>2, group=>3},
    check_unsetup => {exists=>0},
    check_setup   => {exists=>1, is_file=>1, owner=>2, group=>3},
    cleanup       => sub { unlink "f" },
);

# XXX: test using group name (instead of gid)
# XXX: test using user name (instead of uid)
# XXX: test fixing existing file's owner/group
# XXX: test undo (restore existing file's previous owner/group)

DONE_TESTING:
teardown();
