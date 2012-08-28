#!perl

use 5.010;
use strict;
use warnings;
use FindBin '$Bin';
use lib "$Bin/lib";

use File::chdir;
use File::Slurp;
use File::Temp qw(tempdir);
use Setup::File;
use Test::More 0.98;
use Test::Perinci::Tx::Manager qw(test_tx_action);

my $tmpdir = tempdir(CLEANUP=>1);
$CWD = $tmpdir;

test_tx_action(
    name        => "empty dir",
    tmpdir      => $tmpdir,
    f           => 'Setup::File::rmdir',
    args        => {path=>"dir1"},
    reset_state => sub { mkdir "dir1" },
);

test_tx_action(
    name        => "non-empty dir, w/o confirm",
    tmpdir      => $tmpdir,
    f           => 'Setup::File::rmdir',
    args        => {path=>"dir1"},
    reset_state => sub { mkdir "dir1"; write_file("dir1/file", "") },
    status      => 331,
);

test_tx_action(
    name        => "non-empty dir, w/ confirm",
    tmpdir      => $tmpdir,
    f           => 'Setup::File::rmdir',
    args        => {path=>"dir1"},
    confirm     => 1,
    reset_state => sub { mkdir "dir1"; write_file("dir1/file", "") },
);

test_tx_action(
    name        => "non-empty dir, delete_nonempty_dir=0",
    tmpdir      => $tmpdir,
    f           => 'Setup::File::rmdir',
    args        => {path=>"dir1", delete_nonempty_dir=>0},
    confirm     => 1,
    reset_state => sub { mkdir "dir1"; write_file("dir1/file", "") },
    status      => 412,
);

test_tx_action(
    name        => "non-empty dir, delete_nonempty_dir=1",
    tmpdir      => $tmpdir,
    f           => 'Setup::File::rmdir',
    args        => {path=>"dir1", delete_nonempty_dir=>1},
    reset_state => sub { mkdir "dir1"; write_file("dir1/file", "") },
);

subtest "symlink tests" => sub {
    plan skip_all => "symlink() not available" unless eval { symlink "",""; 1 };

    test_tx_action(
        name        => "allow_symlink=0 (the default)",
        tmpdir      => $tmpdir,
        f           => 'Setup::File::rmdir',
        args        => {path=>"sym1"},
        reset_state => sub { mkdir "dir1"; symlink "dir1", "sym1" },
        status      => 412,
    );

    test_tx_action(
        name        => "allow_symlink=1",
        tmpdir      => $tmpdir,
        f           => 'Setup::File::rmdir',
        args        => {path=>"sym1", allow_symlink=>1},
        reset_state => sub { mkdir "dir1"; symlink "dir1", "sym1" },
    );

    test_tx_action(
        name        => "allow_symlink=1, symlink points to non-dir",
        tmpdir      => $tmpdir,
        f           => 'Setup::File::rmdir',
        args        => {path=>"sym1", allow_symlink=>1},
        reset_state => sub {
            mkdir "dir1"; write_file("file", ""); symlink "file", "sym1";
        },
        status      => 412,
    );
};

DONE_TESTING:
done_testing();
if (Test::More->builder->is_passing) {
    #diag "all tests successful, deleting test data dir";
    $CWD = "/";
} else {
    diag "there are failing tests, not deleting test data dir $tmpdir";
}
