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
    name          => "create",
    path          => "/f",
    other_args    => {should_exist=>1},
    check_unsetup => {exists=>0},
    check_setup   => {exists=>1, is_file=>1},
    cleanup       => sub { unlink "f" },
);
test_setup_file(
    name          => "create with arg gen_content_sub",
    path          => "/f",
    other_args    => {should_exist=>1, gen_content_code=>sub {\"foo"}},
    check_unsetup => {exists=>0},
    check_setup   => {exists=>1, is_file=>1, content=>"foo"},
    cleanup       => sub { unlink "f" },
);
test_setup_file(
    name          => "create w/ arg gen_content_sub #2 (scalar also accepted)",
    path          => "/f",
    other_args    => {should_exist=>1, gen_content_code=>sub {"foo"}},
    check_unsetup => {exists=>0},
    check_setup   => {exists=>1, is_file=>1, content=>"foo"},
    cleanup       => sub { unlink "f" },
);
test_setup_file(
    name          => "create with arg content",
    path          => "/f",
    other_args    => {should_exist=>1, content=>"foo"},
    check_unsetup => {exists=>0},
    check_setup   => {exists=>1, is_file=>1, content=>"foo"},
    cleanup       => sub { unlink "f" },
);
test_setup_file(
    name          => "create (arg content + gen_content_code -> conflict)",
    path          => "/f",
    other_args    => {should_exist=>1, content=>"foo",
                      gen_content_code=>sub{\"foo"}},
    dry_do_error  => 400,
    check_unsetup => {exists=>0},
);
test_setup_file(
    name          => "create (arg content + check_content_code -> conflict)",
    path          => "/f",
    other_args    => {should_exist=>1, content=>"foo",
                      check_content_code=>sub{ ${$_[0]} eq "foo" }},
    dry_do_error  => 400,
    check_unsetup => {exists=>0},
);
test_setup_file(
    name          => "create (state changed before undo)",
    path          => "/f",
    other_args    => {should_exist=>1, gen_content_code=>sub{\"old"}},
    check_unsetup => {exists=>0},
    check_setup   => {exists=>1, is_file=>1, content=>"old"},
    set_state1    => sub { write_file "f", "new" },
    check_state1  => {exists=>1, is_file=>1, content=>"new"},
    cleanup       => sub { unlink "f" },
);
test_setup_file(
    name          => "create (state changed before redo)",
    path          => "/f",
    other_args    => {should_exist=>1, gen_content_code=>sub{\"old"}},
    check_unsetup => {exists=>0},
    check_setup   => {exists=>1, is_file=>1, content=>"old"},
    set_state2    => sub { write_file "f", "new" },
    check_state2  => {exists=>1, is_file=>1, content=>"new"},
    cleanup       => sub { unlink "f" },
);
test_setup_file(
    name          => "replace symlink",
    prepare       => sub { symlink "x", "f" },
    path          => "/f",
    other_args    => {should_exist=>1, allow_symlink=>0},
    check_unsetup => {exists=>1, is_symlink=>1, },
    check_setup   => {exists=>1, is_file=>1, is_symlink=>0},
    cleanup       => sub { unlink "f" },
);
test_setup_file(
    name          => "allow_symlink=1, but target doesn't exist",
    prepare       => sub { symlink "x", "f" },
    path          => "/f",
    other_args    => {should_exist=>1, allow_symlink=>1},
    check_unsetup => {exists=>1, is_symlink=>1, },
    check_setup   => {exists=>1, is_file=>1, is_symlink=>0},
    cleanup       => sub { unlink "f" },
);
test_setup_file(
    name          => "allow_symlink=1",
    prepare       => sub { symlink "$Bin/$FindBin::Script", "f" },
    path          => "/f",
    other_args    => {should_exist=>1, allow_symlink=>1},
    check_unsetup => {exists=>1, is_symlink=>1, },
    check_setup   => {exists=>1, is_symlink=>1, },
    cleanup       => sub { unlink "f" },
);
test_setup_file(
    name          => "replace file content (mode not preserved)",
    prepare       => sub { write_file "f", "old"; chmod 0646, "f" },
    path          => "/f",
    other_args    => {should_exist=>1,
                      check_content_code=>sub { ${$_[0]} eq 'new' },
                      gen_content_code => sub { \'new' } },
    check_unsetup => {exists=>1, content=>'old'},
    check_setup   => {exists=>1, content=>'new'},
    cleanup       => sub { unlink "f" },
);
test_setup_file(
    name          => "replace file (arg mode)",
    prepare       => sub { write_file "f", "old"; chmod 0646, "f" },
    path          => "/f",
    other_args    => {should_exist=>1, mode=>0664,
                      check_content_code=>sub { ${$_[0]} eq 'new' },
                      gen_content_code => sub { \'new' } },
    check_unsetup => {exists=>1, mode=>0646, content=>'old'},
    check_setup   => {exists=>1, mode=>0664, content=>'new'},
    cleanup       => sub { unlink "f" },
);
test_setup_file(
    name          => "replace dir",
    prepare       => sub { mkdir "f"; chmod 0715, "f" },
    path          => "/f",
    other_args    => {should_exist=>1, mode=>0664,
                      check_content_code=>sub { ${$_[0]} eq 'new' },
                      gen_content_code => sub { \'new' } },
    check_unsetup => {exists=>1, is_dir=>1},
    check_setup   => {exists=>1, is_file=>1, mode=>0664, content=>'new'},
    cleanup       => sub { rmdir "f" },
);

goto DONE_TESTING;

# XXX: test symbolic mode
# XXX: test should_exist = undef

DONE_TESTING:
teardown();
