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
    name       => "create (dry run)",
    path       => "/d",
    other_args => {should_exist=>1, -dry_run=>1},
    status     => 304,
    exists     => 0,
);
test_setup_dir(
    name       => "create",
    path       => "/d",
    other_args => {should_exist=>1},
    status     => 200,
    is_dir     => 1,
);
test_setup_dir(
    name       => "create (with undo)",
    path       => "/d",
    other_args => {should_exist=>1,
                   -undo_action=>"do", -undo_hint=>{tmp_dir=>$tmp_dir}},
    status     => 200,
    is_dir     => 1,
    posttest   => sub {
        my $res = shift;
        $undo_data = $res->[3]{undo_data};
        ok($undo_data, "there is undo info");
    },
    cleanup    => 0,
);
test_setup_dir(
    name       => "create (undo, dry_run)",
    path       => "/d",
    other_args => {should_exist=>1, -dry_run=>1,
                   -undo_action=>"undo", -undo_data=>$undo_data},
    status     => 304,
    is_dir     => 1,
    cleanup    => 0,
);
test_setup_dir(
    name       => "create (undo)",
    path       => "/d",
    other_args => {should_exist=>1,
                   -undo_action=>"undo", -undo_data=>$undo_data},
    status     => 200,
    exists     => 0,
    cleanup    => 0,
);

test_setup_dir(
    name       => "replace symlink (dry_run)",
    presetup   => sub { symlink "x", "d" },
    path       => "/d",
    other_args => {-dry_run=>1, should_exist=>1, allow_symlink=>0},
    status     => 304,
    is_symlink => 1,
);
test_setup_dir(
    name       => "allow_symlink = 1 (target doesn't exist)",
    presetup   => sub { symlink "x", "d" },
    path       => "/d",
    other_args => {should_exist=>1, allow_symlink=>1, mode=>0755},
    status     => 200,
    posttest   => sub {
        my ($res, $path) = @_;
        ok((-d $path) && !(-l $path), "symlink replaced with dir");
    },
);
test_setup_dir(
    name       => "allow_symlink = 1",
    presetup   => sub { symlink $Bin, "d" },
    path       => "/d",
    other_args => {should_exist=>1, allow_symlink=>1},
    status     => 304,
    is_symlink => 1,
    is_dir     => 1,
);
test_setup_dir(
    name       => "replace symlink",
    presetup   => sub { symlink "x", "d" },
    path       => "/d",
    other_args => {should_exist=>1, allow_symlink=>0},
    status     => 200,
    is_symlink => 0,
    is_dir     => 1,
);
test_setup_dir(
    name       => "replace symlink (with undo)",
    presetup   => sub { symlink "x", "d" },
    path       => "/d",
    other_args => {should_exist=>1, allow_symlink=>0,
                   -undo_action=>"do", -undo_hint=>{tmp_dir=>$tmp_dir}},
    status     => 200,
    is_symlink => 0,
    is_dir     => 1,
    posttest   => sub {
        my $res = shift;
        $undo_data = $res->[3]{undo_data};
        ok($undo_data, "there is undo info");
        my $step = $undo_data->[0];
    },
    cleanup    => 0,
);
test_setup_dir(
    name       => "replace symlink (undo, dry_run)",
    path       => "/d",
    other_args => {should_exist=>1, allow_symlink=>0, -dry_run=>1,
                   -undo_action=>"undo", -undo_data=>$undo_data},
    status     => 304,
    is_symlink => 0,
    is_dir     => 1,
);
test_setup_dir(
    name       => "replace symlink (undo)",
    path       => "/d",
    other_args => {should_exist=>1, allow_symlink=>0,
                   -undo_action=>"undo", -undo_data=>$undo_data},
    status     => 200,
    is_symlink => 1,
    posttest   => sub {
        my ($res, $path) = @_;
        my $step = $undo_data->[0];
        ok(!(-l $step->[1]), "undo_data: step[0]: temp file moved");
        is(readlink($path), "x",
           "undo_data: step[0]: original symlink restored");
    },
);

test_setup_dir(
    name       => "replace dir (dry_run)",
    presetup   => sub { mkdir "d", 0751 },
    path       => "/d",
    other_args => {-dry_run=>1, should_exist=>1, mode => 0715},
    status     => 304,
    is_symlink => 0, is_dir => 1, mode => 0751,
    cleanup    => 0,
);
test_setup_dir(
    name       => "replace dir (arg mode)",
    path       => "/d",
    other_args => {should_exist=>1, mode => 0715,
                   check_content_code=>sub { $_[0] eq 'new' },
                   gen_content_code=>sub { 'new' }, },
    status     => 200,
    is_symlink => 0, is_dir => 1, mode => 0715,
);
test_setup_dir(
    name       => "replace dir (with undo)",
    presetup   => sub { mkdir "d", 0751 },
    path       => "/d",
    other_args => {should_exist=>1, mode => 0715,
                   -undo_action=>"do", -undo_hint=>{tmp_dir=>$tmp_dir}},
    status     => 200,
    is_symlink => 0, is_dir => 1, mode => 0715,
    posttest   => sub {
        my $res = shift;
        $undo_data = $res->[3]{undo_data};
        ok($undo_data, "there is undo info");
    },
    cleanup    => 0,
);
test_setup_dir(
    name       => "replace dir (undo, dry_run)",
    path       => "/d",
    other_args => {-dry_run=>1, should_exist=>1, mode => 0715,
                   -undo_action=>"undo", -undo_data=>$undo_data},
    status     => 304,
    is_symlink => 0, is_dir => 1, mode => 0715,
    cleanup    => 0,
);
test_setup_dir(
    name       => "replace dir (undo)",
    path       => "/d",
    other_args => {should_exist=>1, mode => 0715,
                   -undo_action=>"undo", -undo_data=>$undo_data},
    status     => 200,
    is_symlink => 0, is_dir => 1, mode => 0751,
);

test_setup_dir(
    name       => "replace file (dry_run)",
    presetup   => sub { write_file "d", "orig"; chmod 0664, "d" },
    path       => "/d",
    other_args => {-dry_run=>1, should_exist=>1, mode => 0775},
    status     => 304,
    is_symlink => 0, is_file => 1, mode => 0664, content => "orig",
    cleanup    => 0,
);
test_setup_dir(
    name       => "replace file",
    path       => "/d",
    other_args => {should_exist=>1, mode => 0775},
    status     => 200,
    is_symlink => 0, is_dir => 1, mode => 0775,
);
test_setup_dir(
    name       => "replace file (with undo)",
    presetup   => sub { write_file "d", "orig"; chmod 0664, "d" },
    path       => "/d",
    other_args => {should_exist=>1, mode => 0664,
                   -undo_action=>"do", -undo_hint=>{tmp_dir=>$tmp_dir}},
    status     => 200,
    is_symlink => 0, is_dir => 1, mode => 0775,
    posttest   => sub {
        my $res = shift;
        $undo_data = $res->[3]{undo_data};
        ok($undo_data, "there is undo info");
    },
    cleanup    => 0,
);
test_setup_dir(
    name       => "replace file (undo, dry_run)",
    path       => "/d",
    other_args => {-dry_run=>1, should_exist=>1, mode => 0775,
                   -undo_action=>"undo", -undo_data=>$undo_data},
    status     => 304,
    is_symlink => 0, is_dir => 1, mode => 0775,
    cleanup    => 0,
);
test_setup_dir(
    name       => "replace file (undo)",
    path       => "/d",
    other_args => {should_exist=>1, mode => 0775,
                   -undo_action=>"undo", -undo_data=>$undo_data},
    status     => 200,
    is_symlink => 0, is_file => 1, mode => 0664, content => "orig",
);

# XXX: test symbolic mode
# XXX: test should_exist = undef

DONE_TESTING:
teardown();
