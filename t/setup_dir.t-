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

setup();

test_setup_dir(
    name          => "create",
    path          => "/d",
    other_args    => {should_exist=>1},
    check_unsetup => {exists=>0},
    check_setup   => {is_dir=>1},
    cleanup       => sub { rmdir "d" },
);
test_setup_dir(
    name          => "replace symlink",
    path          => "/d",
    prepare       => sub { symlink "x", "d" },
    other_args    => {should_exist=>1},
    check_unsetup => {is_symlink=>1},
    check_setup   => {is_dir=>1},
    cleanup       => sub { rmdir "d" },
);
test_setup_dir(
    name          => "allow_symlink=1, but target doesn't exist -> replace",
    path          => "/d",
    prepare       => sub { symlink "x", "d" },
    other_args    => {should_exist=>1, allow_symlink=>1},
    check_unsetup => {is_symlink=>1},
    check_setup   => {is_dir=>1},
    cleanup       => sub { rmdir "d" },
);
test_setup_dir(
    name          => "allow_symlink=1",
    path          => "/d",
    prepare       => sub { symlink $Bin, "d" },
    other_args    => {should_exist=>1, allow_symlink=>1},
    check_unsetup => {is_symlink=>1},
    check_setup   => {is_dir=>1},
    cleanup       => sub { unlink "d" },
);
test_setup_dir(
    name          => "chmod",
    path          => "/d",
    prepare       => sub { mkdir "d"; chmod 0751, "d" },
    other_args    => {should_exist=>1, mode=>0715},
    check_unsetup => {is_dir=>1, mode=>0751},
    check_setup   => {is_dir=>1, mode=>0715},
    cleanup       => sub { rmdir "d" },
);
test_setup_dir(
    name          => "replace file",
    path          => "/d",
    prepare       => sub { write_file "d", "orig"; chmod 0664, "d" },
    other_args    => {should_exist=>1, mode=>0775},
    check_unsetup => {is_file=>1, mode=>0664},
    check_setup   => {is_dir=>1, mode=>0775},
    cleanup       => sub { rmdir "d" },
);
goto DONE_TESTING;

# XXX: test symbolic mode
# XXX: test should_exist = undef

DONE_TESTING:
teardown();
