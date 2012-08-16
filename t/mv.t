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

write_file "$rootdir/from", "content";
test_mv(
    name          => "fixable",
    from          => "/from",
    to            => "/to",
    check_unsetup => {exists=>[qw/from/], not_exists=>[qw/to/]},
    check_setup   => {exists=>[qw/to/]  , not_exists=>[qw/from/]},
);

write_file "$rootdir/from", "content";
write_file "$rootdir/to"  , "content";
test_mv(
    name          => "unfixable: target exists",
    from          => "/from",
    to            => "/to",
    check_unsetup => {exists=>[qw/from to/]},
    dry_do_error  => 412,
);

unlink "$rootdir/from";
unlink "$rootdir/to";
test_mv(
    name          => "unfixable: source not exists",
    from          => "/from",
    to            => "/to",
    check_unsetup => {exists=>[qw//], not_exists=>[qw/to from/]},
    dry_do_error  => 412,
);

DONE_TESTING:
done_testing();
if (Test::More->builder->is_passing) {
    #diag "all tests successful, deleting test data dir";
    $CWD = "/";
} else {
    diag "there are failing tests, not deleting test data dir $rootdir";
}

sub test_mv {
    my (%targs) = @_;

    my %tsargs;

    for (qw/name dry_do_error do_error set_state1 set_state2 prepare cleanup/) {
        $tsargs{$_} = $targs{$_};
    }
    $tsargs{function} = \&Setup::File::mv;

    my $from = $rootdir . $targs{from};
    my $to   = $rootdir . $targs{to};
    my %fargs = (from => $from, to => $to, %{$targs{other_args} // {}});
    $tsargs{args} = \%fargs;

    my $check = sub {
        my %cargs = @_;

        for (@{ $cargs{exists} // [] }) {
            ok((-l $_) || (-e _), "$_ exists");
        }
        for (@{ $cargs{not_exists} // [] }) {
            ok(!((-l $_) || (-e _)), "$_ not exists");
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
