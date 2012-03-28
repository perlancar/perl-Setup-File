use 5.010;
use strict;
use warnings;

use File::chdir;
use File::Path qw(remove_tree);
use File::Spec;
use File::Slurp;
use File::Temp qw(tempdir);
use Setup::File::Dir qw(setup_dir);
use Setup::File qw(setup_file);
use Test::More 0.96;
use Test::Setup qw(test_setup);

sub setup {
    plan skip_all => "Not Unix-y enough (absolute path doesn't start with /)"
        unless File::Spec->rel2abs("") =~ m!^/!;

    $::root_dir = tempdir(CLEANUP=>1);
    $::tmp_dir  = "$::root_dir/.undo";
    mkdir $::tmp_dir or die "Can't make tmp_dir `$::tmp_dir`: $!";
    $CWD = $::root_dir;
    diag "test data dir is $::root_dir";
}

sub teardown {
    done_testing();
    if (Test::More->builder->is_passing) {
        #diag "all tests successful, deleting test data dir";
        $CWD = "/" unless $ENV{NO_CLEANUP};
    } else {
        diag "there are failing tests, not deleting test data dir";
        #diag "tmp dir is $::tmp_dir";
    }
}

sub test_setup_file {
    _test_setup_file_or_dir('file', @_);
}

sub test_setup_dir {
    _test_setup_file_or_dir('dir', @_);
}

sub _test_setup_file_or_dir {
    my ($which, %tsfargs) = @_;

    my %tsargs;

    for (qw/name dry_do_error do_error set_state1 set_state2 prepare cleanup/) {
        $tsargs{$_} = $tsfargs{$_};
    }
    $tsargs{function}    = $which eq 'file' ? \&setup_file : \&setup_dir;

    my $path = $::root_dir . $tsfargs{path};
    my %fargs = (path => $path,
                 -undo_hint=>{tmp_dir=>$::tmp_dir},
                 %{$tsfargs{other_args} // {}});
    $tsargs{args} = \%fargs;

    my $check = sub {
        my %cargs = @_;

        my $is_symlink = (-l $path);
        my $exists     = (-e _);
        my @st         = stat($path);
        my $is_file    = (-f _);
        my $is_dir     = (-d _);

        if ($cargs{exists} // 1) {
            ok($exists, "exists") or return;

            if (defined $cargs{is_symlink}) {
                if ($cargs{is_symlink}) {
                    ok($is_symlink, "is symlink");
                } else {
                    ok(!$is_symlink, "not symlink");
                }
            }

            if (defined $cargs{is_file}) {
                if ($cargs{is_file}) {
                    ok($is_file, "is file");
                } else {
                    ok(!$is_file, "not file");
                }
            }

            if (defined $cargs{is_dir}) {
                if ($cargs{is_dir}) {
                    ok($is_dir, "is dir");
                } else {
                    ok(!$is_dir, "not dir");
                }
            }

            if (defined $cargs{mode}) {
                my $mode = $st[2] & 07777;
                is($mode, $cargs{mode}, sprintf("mode is %04o", $cargs{mode}));
            }

            if (defined $cargs{owner}) {
                my $owner = $st[4];
                my $wanted = $cargs{owner};
                if ($wanted !~ /^\d+$/) {
                    my @gr = getpwnam($wanted)
                        or die "Can't getpwnam($wanted): $!";
                    $wanted = $gr[2];
                }
                is($owner, $wanted, "owner");
            }

            if (defined $cargs{group}) {
                my $group = $st[5];
                my $wanted = $cargs{group};
                if ($wanted !~ /^\d+$/) {
                    my @gr = getgrnam($wanted)
                        or die "Can't getgrnam($wanted): $!";
                    $wanted = $gr[2];
                }
                is($group, $wanted, "group");
            }

            if (defined $cargs{content}) {
                my $content = read_file($path);
                is($content, $cargs{content}, "content");
            }
        } else {
            ok(!$exists, "does not exist");
        }
    };

    $tsargs{check_setup}   = sub { $check->(%{$tsfargs{check_setup}}) };
    $tsargs{check_unsetup} = sub { $check->(%{$tsfargs{check_unsetup}}) };
    if ($tsfargs{check_state1}) {
        $tsargs{check_state1} = sub { $check->(%{$tsfargs{check_state1}}) };
    }
    if ($tsfargs{check_state2}) {
        $tsargs{check_state2} = sub { $check->(%{$tsfargs{check_state2}}) };
    }

    test_setup(%tsargs);
}

1;
