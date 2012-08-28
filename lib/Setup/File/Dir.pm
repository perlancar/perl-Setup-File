package Setup::File::Dir;

use 5.010;
use strict;
use warnings;
use Log::Any '$log';

#use Setup::File;

require Exporter;
our @ISA       = qw(Exporter);
our @EXPORT_OK = qw(setup_dir);

# VERSION

our %SPEC;

$SPEC{setup_dir} = {
    v           => 1.1,
    summary     => "Setup directory (existence, mode, permission)",
    description => <<'_',

On do, will create directory (if it doesn't already exist) and fix its
mode/permission.

On undo, will restore old mode/permission (and delete directory if it is empty
and was created by this function). If directory was created by this function but
is not empty, will return status 331 to ask for confirmation (`-confirm`). If
confirmation is set to true, will delete non-empty directory.

Will *not* create intermediate directories like "mkdir -p". Create intermediate
directories using several setup_dir() invocation.

_
    args     => {
        path => {
            schema      => ['str*' => {match => qr!^/!}],
            pos         => 0,
            summary     => 'Path to dir',
            description => <<'_',

Dir path needs to be absolute so it's normalized.

_
        },
        should_exist => {
            schema      => ['bool' => {}],
            summary     => 'Whether dir should exist',
            description => <<'_',

If undef, dir need not exist. If set to 0, dir must not exist and will be
deleted if it does. If set to 1, dir must exist and will be created if it
doesn't.

_
        },
        mode => {
            schema  => ['str' => {}],
            summary => 'Expected permission mode',
        },
        owner => {
            schema  => ['str' => {}],
            summary => 'Expected owner',
        },
        group => {
            schema   => ['str' => {}],
            summary => 'Expected group',
        },
        allow_symlink => {
            schema      => ['bool*' => {default=>1}],
            summary     => 'Whether symlink is allowed',
            description => <<'_',

If existing dir is a symlink then if allow_symlink is false then it is an
unacceptable condition (the symlink will be replaced if replace_symlink is
true).

Note: if you want to setup symlink instead, use Setup::Symlink.

_
        },
        replace_symlink => {
            schema  => ['bool*' => {default=>1}],
            summary => "Replace existing symlink if it needs to be replaced",
        },
        replace_file => {
            schema  => ['bool*' => {default=>1}],
            summary => "Replace existing file if it needs to be replaced",
        },
        replace_dir => {
            schema  => ['bool*' => {default=>1}],
            summary => "Replace existing dir if it needs to be replaced",
        },
    },
    features => {
        tx         => {v=>2},
        idempotent => 1,
    },
};
sub setup_dir  {
    my %args = @_;
    Setup::File::_setup_file_or_dir('dir' , %args);
}

1;
# ABSTRACT: Setup directory (existence, mode, permission)

=head1 SEE ALSO

L<Setup>

L<Setup::File>

=cut
