package Setup::Dir;
# ABSTRACT: Ensure dir (non-)existence & mode/permission

use 5.010;
use strict;
use warnings;
use Log::Any '$log';

use Setup::File;

require Exporter;
our @ISA       = qw(Exporter);
our @EXPORT_OK = qw(setup_dir);

our %SPEC;

$SPEC{setup_dir} = {
    summary  => "Ensure directory (non-)existence and mode/permission",
    description => <<'_',

If given, -undo_hint should contain {tmp_dir=>...} to specify temporary
directory to save replaced file/dir. Temporary directory defaults to ~/.setup,
it will be created if not exists.

_
    args     => {
        path => ['str*' => {
            summary => 'Path to dir',
            description => <<'_',

Dir path needs to be absolute so it's normalized.

_
            arg_pos => 1,
            match   => qr!^/!,
        }],
        should_exist => ['bool' => {
            summary => 'Whether dir should exist',
            description => <<'_',

If undef, dir need not exist. If set to 0, dir must not exist and will be
deleted if it does. If set to 1, dir must exist and will be created if it
doesn't.

_
        }],
        mode => ['str' => {
            summary => 'Expected permission mode',
        }],
        owner => ['str' => {
            summary => 'Expected owner',
        }],
        group => ['str' => {
            summary => 'Expected group',
        }],
        allow_symlink => ['bool*' => {
            summary => 'Whether symlink is allowed',
            description => <<'_',

If existing dir is a symlink then if allow_symlink is false then it is an
unacceptable condition (the symlink will be replaced if replace_symlink is
true).

Note: if you want to setup symlink instead, use Setup::Symlink.

_
            default => 0,
        }],
        replace_symlink => ['bool*' => {
            summary => "Replace existing symlink if it needs to be replaced",
            default => 1,
        }],
        replace_file => ['bool*' => {
            summary => "Replace existing file if it needs to be replaced",
            default => 1,
        }],
        replace_dir => ['bool*' => {
            summary => "Replace existing dir if it needs to be replaced",
            default => 1,
        }],
    },
    features => {undo=>1, dry_run=>1},
};
sub setup_dir  { Setup::File::_setup_file_or_dir('dir' , @_) }

1;
__END__

=head1 SYNOPSIS

 use Setup::Dir 'setup_dir';

 # simple usage (doesn't save undo info)
 $res = setup_dir path => '/etc/myapp',
                  should_exist => 1,
                  owner => 'root', group => 0, mode => 0755;
 die unless $res->[0] == 200;

 # perform setup and save undo info (undo info should be serializable)
 $res = setup_dir ..., -undo_action => 'do';
 die unless $res->[0] == 200;
 my $undo_info = $res->[3]{undo_info};

 # perform undo
 $res = setup_dir ..., -undo_action => "undo", -undo_info=>$undo_info;
 die unless $res->[0] == 200;

 # state that dir must not exist
 setup_dir path => '/foo/bar', should_exist => 0;


=head1 DESCRIPTION

This module provides one function: B<setup_dir>.

This module is part of the Setup modules family.

This module uses L<Log::Any> logging framework.

This module's functions have L<Sub::Spec> specs.


=head1 THE SETUP MODULES FAMILY

I use the C<Setup::> namespace for the Setup modules family, typically used in
installers (or other applications). The modules in Setup family have these
characteristics:

=over 4

=item * used to reach some desired state

For example, Setup::Symlink::setup_symlink makes sure a symlink exists to the
desired target. Setup::File::setup_file makes sure a file exists with the
correct content/ownership/permission.

=item * do nothing if desired state has been reached

=item * support dry-run (simulation) mode

=item * support undo to restore state to previous/original one

=back


=head1 FUNCTIONS

None are exported by default, but they are exportable.


=head1 SEE ALSO

L<Sub::Spec>, specifically L<Sub::Spec::Clause::features> on dry-run/undo.

Other modules in Setup:: namespace.

=cut
