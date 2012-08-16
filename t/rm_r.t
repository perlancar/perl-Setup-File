#!perl

use 5.010;
use strict;
use warnings;
use Test::More 0.96;

use File::chdir;
use File::Slurp;
use File::Temp qw(tempdir);
use Setup::File;
use Test::Setup qw(test_setup);

#plan skip_all => "symlink() not available"
#    unless eval { symlink "", ""; 1 };

my $rootdir = tempdir(CLEANUP=>1);
$CWD = $rootdir;

write_file "$rootdir/p", "";
test_rm_r(
    name          => "fixable",
    path          => "/p",
    check_unsetup => {exists=>1},
    check_setup   => {exists=>0},
);
unlink "$rootdir/p";
test_rm_r(
    name          => "fixed: already removed",
    path          => "/p",
    check_unsetup => {exists=>0},
    dry_do_error  => 304,
);

DONE_TESTING:
done_testing();
if (Test::More->builder->is_passing) {
    #diag "all tests successful, deleting test data dir";
    $CWD = "/";
} else {
    diag "there are failing tests, not deleting test data dir $rootdir";
}

sub test_rm_r {
    my (%targs) = @_;

    my %tsargs;
    $tsargs{tmpdir} = $rootdir;

    for (qw/name dry_do_error do_error set_state1 set_state2 prepare cleanup/) {
        $tsargs{$_} = $targs{$_};
    }
    $tsargs{function} = \&Setup::File::rm_r;

    my $path = $rootdir . $targs{path};
    my %fargs = (path => $path,
                 -undo_trash_dir=>$rootdir, %{$targs{other_args} // {}},
             );
    $tsargs{args} = \%fargs;

    my $check = sub {
        my %cargs = @_;

        my $exists     = (-l $path) || (-e _);

        my $te = $cargs{exists} // 1;
        if ($te) {
            ok($exists, "exists");
        } else {
            ok(!$exists, "does not exist");
        }
        if ($cargs{extra}) {
            $cargs{extra}->();
        }
    };

    $tsargs{check_setup}   = sub { $check->(%{$targs{check_setup}}) };
    $tsargs{check_unsetup} = sub { $check->(%{$targs{check_unsetup}}) };
    if ($targs{check_state1}) {
        $tsargs{check_state1} = sub { $check->(%{$targs{check_state1}}) };
    }
    if ($targs{check_state2}) {
        $tsargs{check_state2} = sub { $check->(%{$targs{check_state2}}) };
    }

    test_setup(%tsargs);
}
