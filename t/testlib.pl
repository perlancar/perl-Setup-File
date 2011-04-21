use 5.010;
use strict;
use warnings;

use File::chdir;
use File::Path qw(remove_tree);
use File::Spec;
use File::Slurp;
use File::Temp qw(tempdir);
use Setup::Dir  qw(setup_dir);
use Setup::File qw(setup_file);
use Test::More 0.96;

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
    my ($which, %args) = @_;
    subtest "$args{name}" => sub {

        if ($args{presetup}) {
            $args{presetup}->();
        }

        my $path = $::root_dir . $args{path};
        my %setup_args = (path => $path);
        if ($args{other_args}) {
            while (my ($k, $v) = each %{$args{other_args}}) {
                $setup_args{$k} = $v;
            }
        }
        my $res;
        eval {
            if ($which eq 'file') {
                $res = setup_file(%setup_args);
            } else {
                $res = setup_dir(%setup_args);
            }
        };
        my $eval_err = $@;

        if ($args{dies}) {
            ok($eval_err, "dies");
        } else {
            ok(!$eval_err, "doesn't die") or diag $eval_err;
        }

        #diag explain $res;
        if ($args{status}) {
            is($res->[0], $args{status}, "status $args{status}")
                or diag explain($res);
        }

        my $is_symlink = (-l $path);
        my $exists     = (-e _);
        my @st         = stat($path);
        my $is_file    = (-f _);
        my $is_dir     = (-d _);

        if ($args{exists} // 1) {
            ok($exists, "exists") or return;

            if (defined $args{is_symlink}) {
                if ($args{is_symlink}) {
                    ok($is_symlink, "is symlink");
                } else {
                    ok(!$is_symlink, "not symlink");
                }
            }

            if (defined $args{is_file}) {
                if ($args{is_file}) {
                    ok($is_file, "is file");
                } else {
                    ok(!$is_file, "not file");
                }
            }

            if (defined $args{is_dir}) {
                if ($args{is_dir}) {
                    ok($is_dir, "is dir");
                } else {
                    ok(!$is_dir, "not dir");
                }
            }

            if (defined $args{mode}) {
                my $mode = $st[2] & 07777;
                is($mode, $args{mode}, sprintf("mode is %04o", $args{mode}));
            }

            if (defined $args{owner}) {
                my $owner = $st[4];
                my $wanted = $args{owner};
                if ($wanted !~ /^\d+$/) {
                    my @gr = getpwnam($wanted)
                        or die "Can't getpwnam($wanted): $!";
                    $wanted = $gr[2];
                }
                is($owner, $wanted, "owner");
            }

            if (defined $args{group}) {
                my $group = $st[5];
                my $wanted = $args{group};
                if ($wanted !~ /^\d+$/) {
                    my @gr = getgrnam($wanted)
                        or die "Can't getgrnam($wanted): $!";
                    $wanted = $gr[2];
                }
                is($group, $wanted, "group");
            }

            if (defined $args{content}) {
                my $content = read_file($path);
                is($content, $args{content}, "content");
            }

        } else {
            ok(!$exists, "does not exist");
        }

        if ($args{posttest}) {
            $args{posttest}->($res, $path);
        }

        remove_tree($path) if $args{cleanup} // 1;
    };
}

1;
