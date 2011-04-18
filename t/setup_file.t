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

test_setup_file(
    name       => "create (dry run)",
    path       => "/f",
    other_args => {should_exist=>1, -dry_run=>1},
    status     => 304,
    exists     => 0,
);
test_setup_file(
    name       => "create",
    path       => "/f",
    other_args => {should_exist=>1},
    status     => 200,
    is_file    => 1,
);
test_setup_file(
    name       => "create (arg gen_content_sub)",
    path       => "/f",
    other_args => {should_exist=>1, gen_content_code=>sub {"foo"}},
    status     => 200,
    is_file    => 1,
    content    => "foo",
);
test_setup_file(
    name       => "create (with undo)",
    path       => "/f",
    other_args => {should_exist=>1,
                   -undo_action=>"do", -undo_hint=>{tmp_dir=>$tmp_dir}},
    status     => 200,
    is_file    => 1,
    posttest   => sub {
        my $res = shift;
        $undo_data = $res->[3]{undo_data};
        ok($undo_data, "there is undo info");
    },
    cleanup    => 0,
);
test_setup_file(
    name       => "create (undo, dry_run)",
    path       => "/f",
    other_args => {should_exist=>1, -dry_run=>1,
                   -undo_action=>"undo", -undo_data=>$undo_data},
    status     => 304,
    is_file    => 1,
    cleanup    => 0,
);
test_setup_file(
    name       => "create (undo)",
    path       => "/f",
    other_args => {should_exist=>1,
                   -undo_action=>"undo", -undo_data=>$undo_data},
    status     => 200,
    exists     => 0,
    cleanup    => 0,
);

test_setup_file(
    name       => "replace symlink (dry_run)",
    presetup   => sub { symlink "x", "f" },
    path       => "/f",
    other_args => {-dry_run=>1, should_exist=>1, allow_symlink=>0},
    status     => 304,
    is_symlink => 1,
);
test_setup_file(
    name       => "allow_symlink = 1 (target doesn't exist)",
    presetup   => sub { symlink "x", "f" },
    path       => "/f",
    other_args => {should_exist=>1, allow_symlink=>1,
                   -undo_action=>"do", -undo_hint=>{tmp_dir=>$tmp_dir}},
    status     => 200,
    posttest   => sub {
        my ($res, $path) = @_;
        ok((-f $path) && !(-l $path), "symlink replaced with file");
        $undo_data = $res->[3]{undo_data};
    },
    cleanup    => 0,
);
test_setup_file(
    name       => "allow_symlink = 1 (target doesn't exist, undo)",
    path       => "/f",
    other_args => {should_exist=>1, allow_symlink=>1,
                   -undo_action=>"undo", -undo_data=>$undo_data},
    status     => 200,
    posttest   => sub {
        my ($res, $path) = @_;
        ok((-l $path) && !(-e $path), "symlink restored");
    },
);
test_setup_file(
    name       => "allow_symlink = 1",
    presetup   => sub { symlink "$Bin/$FindBin::Script", "f" },
    path       => "/f",
    other_args => {should_exist=>1, allow_symlink=>1},
    status     => 304,
    is_symlink => 1,
    is_file    => 1,
);
test_setup_file(
    name       => "replace symlink",
    presetup   => sub { symlink "x", "f" },
    path       => "/f",
    other_args => {should_exist=>1, allow_symlink=>0},
    status     => 200,
    is_symlink => 0,
    is_file    => 1,
);
test_setup_file(
    name       => "replace symlink (with undo)",
    presetup   => sub { symlink "x", "f" },
    path       => "/f",
    other_args => {should_exist=>1, allow_symlink=>0,
                   -undo_action=>"do", -undo_hint=>{tmp_dir=>$tmp_dir}},
    status     => 200,
    is_symlink => 0,
    is_file    => 1,
    posttest   => sub {
        my $res = shift;
        $undo_data = $res->[3]{undo_data};
        ok($undo_data, "there is undo info");
        my $step = $undo_data->[0];
    },
    cleanup    => 0,
);
test_setup_file(
    name       => "replace symlink (undo, dry_run)",
    path       => "/f",
    other_args => {should_exist=>1, allow_symlink=>0, -dry_run=>1,
                   -undo_action=>"undo", -undo_data=>$undo_data},
    status     => 304,
    is_symlink => 0,
    is_file    => 1,
    cleanup    => 0,
);
test_setup_file(
    name       => "replace symlink (undo)",
    path       => "/f",
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

test_setup_file(
    name       => "replace file (dry_run)",
    presetup   => sub { write_file "f", "old"; chmod 0646, "f" },
    path       => "/f",
    other_args => {-dry_run=>1, should_exist=>1, mode => 0664,
                   check_content_code=>sub { $_[0] eq 'new' },
                   gen_content_code=>sub { 'new' }, },
    status     => 304,
    is_symlink => 0, is_file => 1, content => 'old', mode => 0646,
    cleanup    => 0,
);
test_setup_file(
    name       => "replace file (arg mode)",
    path       => "/f",
    other_args => {should_exist=>1, mode => 0664,
                   check_content_code=>sub { $_[0] eq 'new' },
                   gen_content_code=>sub { 'new' }, },
    status     => 200,
    is_symlink => 0, is_file => 1, content => 'new', mode => 0664,
);
test_setup_file(
    name       => "replace file (with undo)",
    presetup   => sub { write_file "f", "old"; chmod 0646, "f" },
    path       => "/f",
    other_args => {should_exist=>1, mode => 0664,
                   check_content_code=>sub { $_[0] eq 'new' },
                   gen_content_code=>sub { 'new' },
                   -undo_action=>"do", -undo_hint=>{tmp_dir=>$tmp_dir}},
    status     => 200,
    is_symlink => 0, is_file => 1, content => 'new', mode => 0664,
    posttest   => sub {
        my $res = shift;
        $undo_data = $res->[3]{undo_data};
        ok($undo_data, "there is undo info");
    },
    cleanup    => 0,
);
test_setup_file(
    name       => "replace file (undo, dry_run)",
    path       => "/f",
    other_args => {-dry_run=>1, should_exist=>1, mode => 0664,
                   check_content_code=>sub { $_[0] eq 'new' },
                   gen_content_code=>sub { 'new' },
                   -undo_action=>"undo", -undo_data=>$undo_data},
    status     => 304,
    is_symlink => 0, is_file => 1, content => 'new', mode => 0664,
    cleanup    => 0,
);
test_setup_file(
    name       => "replace file (undo)",
    path       => "/f",
    other_args => {should_exist=>1, mode => 0664,
                   check_content_code=>sub { $_[0] eq 'new' },
                   gen_content_code=>sub { 'new' },
                   -undo_action=>"undo", -undo_data=>$undo_data},
    status     => 200,
    is_symlink => 0, is_file => 1, content => 'old', mode => 0646,
);

test_setup_file(
    name       => "replace dir (dry_run)",
    presetup   => sub { mkdir "f"; chmod 0715, "f" },
    path       => "/f",
    other_args => {-dry_run=>1, should_exist=>1, mode => 0664,
                   check_content_code=>sub { $_[0] eq 'new' },
                   gen_content_code=>sub { 'new' }, },
    status     => 304,
    is_symlink => 0, is_dir => 1, mode => 0715,
    cleanup    => 0,
);
test_setup_file(
    name       => "replace dir",
    path       => "/f",
    other_args => {should_exist=>1, mode => 0664,
                   check_content_code=>sub { $_[0] eq 'new' },
                   gen_content_code=>sub { 'new' }, },
    status     => 200,
    is_symlink => 0, is_file => 1, content => 'new', mode => 0664,
);
test_setup_file(
    name       => "replace dir (with undo)",
    presetup   => sub { mkdir "f"; chmod 0715, "f" },
    path       => "/f",
    other_args => {should_exist=>1, mode => 0664,
                   check_content_code=>sub { $_[0] eq 'new' },
                   gen_content_code=>sub { 'new' },
                   -undo_action=>"do", -undo_hint=>{tmp_dir=>$tmp_dir}},
    status     => 200,
    is_symlink => 0, is_file => 1, content => 'new', mode => 0664,
    posttest   => sub {
        my $res = shift;
        $undo_data = $res->[3]{undo_data};
        ok($undo_data, "there is undo info");
    },
    cleanup    => 0,
);
test_setup_file(
    name       => "replace dir (undo, dry_run)",
    path       => "/f",
    other_args => {-dry_run=>1, should_exist=>1, mode => 0664,
                   check_content_code=>sub { $_[0] eq 'new' },
                   gen_content_code=>sub { 'new' },
                   -undo_action=>"undo", -undo_data=>$undo_data},
    status     => 304,
    is_symlink => 0, is_file => 1, content => 'new', mode => 0664,
    cleanup    => 0,
);
test_setup_file(
    name       => "replace dir (undo)",
    path       => "/f",
    other_args => {should_exist=>1, mode => 0664,
                   check_content_code=>sub { $_[0] eq 'new' },
                   gen_content_code=>sub { 'new' },
                   -undo_action=>"undo", -undo_data=>$undo_data},
    status     => 200,
    is_symlink => 0, is_dir => 1, mode => 0715,
);

# XXX: test symbolic mode
# XXX: test should_exist = undef

DONE_TESTING:
teardown();
