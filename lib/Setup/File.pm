package Setup::File;
# ABSTRACT: Ensure file (non-)existence, mode/permission, and content

use 5.010;
use strict;
use warnings;
use Log::Any '$log';

use File::chmod;
use File::Copy::Recursive qw(rmove);
use File::Path qw(remove_tree);
use File::Slurp;
use File::Temp qw(tempfile tempdir);
use UUID::Random;

require Exporter;
our @ISA       = qw(Exporter);
our @EXPORT_OK = qw(setup_file);

our %SPEC;

$SPEC{setup_file} = {
    summary  => "Ensure file (non-)existence, mode/permission, and content",
    description => <<'_',

If given, -undo_hint should contain {tmp_dir=>...} to specify temporary
directory to save replaced file/dir. Temporary directory defaults to ~/.setup,
it will be created if not exists.

_
    args     => {
        path => ['str*' => {
            summary => 'Path to file',
            description => <<'_',

File path needs to be absolute so it's normalized.

_
            arg_pos => 1,
            match   => qr!^/!,
        }],
        should_exist => ['bool' => {
            summary => 'Whether file should exist',
            description => <<'_',

If undef, file need not exist. If set to 0, file must not exist and will be
deleted if it does. If set to 1, file must exist and will be created if it
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
        check_content_code => ['code' => {
            summary => 'Code to check content',
            description => <<'_',

If unset, file will not be checked for its content. If set, code will be called
whenever file content needs to be checked. Code will be passed the file content
and should return a boolean value indicating whether content is acceptable.

_
        }],
        gen_content_code => ['code' => {
            summary => 'Code to generate content',
            description => <<'_',

If set, whenever a new file content is needed (e.g. when file is created or file
content reset), this code will be called to provide it. If unset, empty string
will be used instead.

Code will be passed the current content (or undef) and should return the new
content.

_
        }],
        allow_symlink => ['bool*' => {
            summary => 'Whether symlink is allowed',
            description => <<'_',

If existing file is a symlink then if allow_symlink is false then it is an
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
sub setup_file { _setup_file_or_dir('file', @_) }

# return 1 if dir exists and empty
sub _dir_is_empty {
    my ($dir) = @_;
    return unless (-d $dir);
    return unless opendir my($dh), $dir;
    my @d = grep {$_ ne '.' && $_ ne '..'} readdir($dh);
    my $res = !@d;
    #$log->tracef("dir_is_empty(%s)? %d", $dir, $res);
    $res;
}

sub _setup_file_or_dir {
    my ($which, %args) = @_;
    die "BUG: which should be file/dir"
        unless $which eq 'file' || $which eq 'dir';

    my $dry_run        = $args{-dry_run};
    my $undo_action    = $args{-undo_action} // "";

    # check args
    my $path           = $args{path};
    $log->tracef("=> setup_file(path=%s)", $path);
    $path              =~ m!^/!
        or return [400, "Please specify an absolute path"];
    my $should_exist   = $args{should_exist};
    my $allow_symlink  = $args{allow_symlink} // 1;
    my $replace_file   = $args{replace_file} // 1;
    my $replace_dir    = $args{replace_dir} // 1;
    my $replace_sym    = $args{replace_symlink} // 1;
    my $owner          = $args{owner};
    my $group          = $args{group};
    my $mode           = $args{mode};
    my $check_ct       = $args{check_content_code};
    my $gen_ct         = $args{gen_content_code};
    return [400, "If check_content_code is specified, ".
                "gen_content_code must also be specified"]
        if defined($check_ct) && !defined($gen_ct);

    # check current state
    my $is_symlink     = (-l $path);
    my $exists         = (-e _);
    my $state_ok       = 1;
    # -l does lstat, we need stat
    #my @st = stat($is_symlink ? $path : _);
    my @st             = stat($path); # stricture complains about _
    return [500, "Can't stat (1): $!"] if $exists && !$is_symlink && !@st;
    my $is_file        = (-f _);
    my $is_dir         = (-d _);

    # exists means whether target exists, if symlink is allowed
    my $symlink_exists;
    if ($allow_symlink && $is_symlink) {
        $symlink_exists = $exists;
        $exists = (-e _) if $symlink_exists;
    }

    {
        if (defined($should_exist) && !$should_exist) {
            $log->trace("nok: $which should not exist but does") if $exists;
            $state_ok = !$exists;
            last;
        }
        if ($should_exist && !$exists) {
            $log->trace("nok: $which should exist but doesn't");
            $state_ok = 0;
            last;
        }
        if (!$allow_symlink && $is_symlink) {
            $log->trace("nok: $which should not be symlink but is");
            $state_ok = 0;
            last;
        }
        if ($exists) {
            if ($is_dir && $which eq 'file') {
                $log->trace("nok: file expected but is dir");
                $state_ok = 0;
                last;
            } elsif (!$is_dir && $which eq 'dir') {
                $log->trace("nok: dir expected but is file");
                $state_ok = 0;
                last;
            }
            if (defined $mode) {
                my $cur_mode = $st[2] & 07777;
                $mode = getchmod($mode, $cur_mode)
                    if $mode =~ /[+=-]/; # symbolic mode
                if ($mode != $cur_mode) {
                    $log->tracef("nok: $which mode is %04o, ".
                                     "but it should be %04o",
                                 $cur_mode, $mode);
                    $state_ok = 0;
                    last;
                }
            }
            if (defined $owner) {
                my $cur_owner = $st[4];
                my @pw;
                if ($owner !~ /^\d+$/) {
                    @pw = getpwnam($owner);
                    $owner = $pw[2];
                } else {
                    @pw = getpwuid($owner);
                }
                if ($owner != $cur_owner) {
                    my @pwc = getpwuid($cur_owner);
                    $log->tracef("nok: $which owner is %s but it should be %s",
                                 @pwc ? $pwc[0] : $cur_owner,
                                 @pw ? $pw[0] : $owner);
                    $state_ok = 0;
                    last;
                }
            }
            if (defined $group) {
                my $cur_group = $st[5];
                my @gr;
                if ($group !~ /^\d+$/) {
                    @gr = getgrnam($group);
                    $group = $gr[2];
                } else {
                    @gr = getgrgid($group);
                }
                if ($group != $cur_group) {
                    my @grc = getgrgid($cur_group);
                    $log->tracef("nok: $which group is %s but it should be %s",
                                 @grc ? $grc[0] : $cur_group,
                                 @gr ? $gr[0] : $group);
                    $state_ok = 0;
                    last;
                }
            }
            if (defined $check_ct) {
                my $content = read_file($path, err_mode=>'quiet');
                return [500, "Can't read file content: $!"]
                    unless defined($content);
                my $res = $check_ct->($content);
                unless ($res) {
                    $log->tracef("nok: file content fails check_content_code");
                    $state_ok = 0;
                    last;
                }
            }

        } else {
            $state_ok = 0;
        }
    }

    if ($undo_action eq 'undo') {
        return [412, "Can't undo: $which has vanished/changed"]
            unless $state_ok;
        return [412, "Can't undo: dir is not empty"]
            if $which eq 'dir' && !_dir_is_empty($path);
        return [304, "dry run"] if $dry_run;
        my $undo_data = $args{-undo_data};
        my $res = _undo(\%args, $undo_data);
        if ($res->[0] == 200) {
            return [200, "OK", undef, {}];
        } else {
            return $res;
        }
    }

    my $undo_hint = $args{-undo_hint} // {};
    return [400, "Invalid -undo_hint, please supply a hashref"]
        unless ref($undo_hint) eq 'HASH';
    my $tmp_dir = $undo_hint->{tmp_dir} // "$ENV{HOME}/.setup";
    unless (-d $tmp_dir) {
        mkdir $tmp_dir, 0777
            or return [500, "Can't make temp dir `$tmp_dir`: $!"];
    }

    my $save_undo = $undo_action ? 1:0;
    my @undo;
    return [304, "Already ok"] if $state_ok;
    return [304, "dry run"] if $dry_run;
    return [412, "dir should be replaced with file but I'm instructed not to"]
        if $which eq 'file' && $is_dir && !$replace_dir;
    return [412, "file should be replaced with dir but I'm instructed not to"]
        if $which eq 'dir' && !$is_dir && !$replace_file;
    return [412, "symlink should be replaced but I'm instructed not to"]
        if $is_symlink && !$allow_symlink && !$replace_sym;
    if (($exists || $is_symlink) && defined($should_exist) && !$should_exist ||
            $is_symlink && !$allow_symlink ||
                $which eq 'file' && $is_dir ||
                    $which eq 'dir' && $exists && !$is_dir) {
        my $uuid = UUID::Random::generate;
        my $save_path = "$tmp_dir/$uuid";
        if ($save_undo) {
            $log->tracef("fix: saving original to $save_path ...");
            rmove $path, $save_path
                or return [500, "Can't move $path -> $save_path: $!"];
            push @undo, ['move', $save_path];
        } else {
            $log->tracef("fix: removing original ...");
            remove_tree $path
                or return [500, "Can't remove $path: $!"];
        }
        $exists = 0;
    }

    if ($should_exist && !$exists) {
        if ($is_symlink && $symlink_exists) {
            $log->tracef("fix: removing symlink first ...");
            my $sym_target = readlink($path);
            unless (unlink $path) {
                _undo(\%args, \@undo, 1);
                return [500, "Can't remove symlink: $!"];
            }
            push @undo, ['mksym', $sym_target];
        }

        if ($which eq 'file') {
            $log->tracef("fix: creating file ...");
            my $res = write_file($path,
                                 {atomic=>1, err_mode=>'quiet'},
                                 $args{gen_content_code} ?
                                     $args{gen_content_code}->() : "");
            my $err = $!;
            if (!$res) {
                _undo(\%args, \@undo, 1);
                return [500, "Can't create file: $err"];
            }
            if (defined($mode) && $mode =~ /[+=-]/) { # symbolic mode
                # XXX: should use umask?
                $mode = getchmod($mode, 0644);
            }
            push @undo, ['mkfile'];
        } else {
            $log->tracef("fix: creating dir ...");
            unless (mkdir $path, 0755) {
                _undo(\%args, \@undo, 1);
                return [500, "Can't mkdir: $!"];
            }
            if (defined($mode) && $mode =~ /[+=-]/) { # symbolic mode
                # XXX: should use umask?
                $mode = getchmod($mode, 0755);
            }
            push @undo, ['mkdir'];
        }
        $exists = 1;
    }

    if ($exists) {

        my @st = stat($path) or return [500, "Can't stat (2): $!"];
        my $cur_mode = $st[2] & 07777;
        my $cur_owner = $st[4];
        my $cur_group = $st[5];

        if (defined $check_ct) {
            my $content = read_file($path, err_mode=>'quiet');
            defined($content) or do {
                _undo(\%args, \@undo, 1);
                return [500, "Can't read file content: $!"];
            };
            if (!$check_ct->($content)) {
                $log->tracef("fix: resetting file content to ".
                                 "expected content ...");
                my $res = write_file($path,
                                     {atomic=>1, err_mode=>'quiet'},
                                     $gen_ct->($content));
                my $err = $!;
                if (!$res) {
                    _undo(\%args, \@undo, 1);
                    return [500, "Can't set file content: $!"];
                }
                push @undo, ['content', \$content];
            }
        }

        if (defined($mode) && $mode != $cur_mode) {
            $log->tracef("fix: setting mode to %04o ...", $mode);
            unless (chmod $mode, $path) {
                _undo(\%args, \@undo, 1);
                return [500, "Can't chmod: $!"];
            }
            push @undo, ['chmod', $cur_mode];
        }

        if (defined($owner) && $cur_owner != $owner ||
                defined($group) && $cur_group != $group) {
            $log->tracef("fix: setting owner/group to %s/%s ...",
                         $owner, $group);
            unless (chown $owner//-1, $group//-1, $path) {
                _undo(\%args, \@undo, 1);
                return [500, "Can't chown: $!"];
            }
            push @undo, ['chown', $cur_owner, $cur_group];
        }

    }
    my $meta = {};
    $meta->{undo_data} = \@undo if $save_undo;
    return [200, "OK", undef, $meta];
}

sub _undo {
    my ($args, $undo_data, $is_rollback) = @_;
    return [200, "Nothing to do"] unless defined($undo_data);
    die "BUG: Invalid undo data, must be arrayref"
        unless ref($undo_data) eq 'ARRAY';

    my $path = $args->{path};

    my $i = 0;
    for my $undo_step (reverse @$undo_data) {
        $log->tracef("undo[%d of 0..%d]: %s",
                     $i, scalar(@$undo_data)-1, $undo_step);
        die "BUG: Invalid undo_step[$i], must be arrayref"
            unless ref($undo_step) eq 'ARRAY';
        my ($cmd, @arg) = @$undo_step;
        my $err;
        if ($cmd eq 'move') {
            rmove $arg[0], $path or $err = "$! ($arg[0])";
        } elsif ($cmd eq 'mkfile') {
            unlink $path or $err = $!;
        } elsif ($cmd eq 'mkdir') {
            rmdir $path or $err = $!;
        } elsif ($cmd eq 'mksym') {
            symlink $arg[0], $path or $err = $!;
        } elsif ($cmd eq 'content') {
            # XXX doesn't do atomic write here, for simplicity (doesn't have to
            # set owner and mode again). but we probably should.
            #write_file($path, {err_mode=>'quiet', atomic=>1}, ${$arg[0]})
            #    or $err = $!;
            open my($fh), ">", $path;
            print $fh ${$arg[0]};
            close $fh or $err = $!;
        } elsif ($cmd eq 'chmod') {
            chmod $arg[0], $path or $err = $!;
        } elsif ($cmd eq 'chown') {
            chown $arg[0]//-1, $arg[1]//-1, $path or $err = $!;
        } else {
            die "BUG: Invalid undo_step[$i], unknown command: $cmd";
        }
        if ($err) {
            if ($is_rollback) {
                die "Can't rollback step[$i] ($cmd): $err";
            } else {
                return [500, "Can't undo step[$i] ($cmd): $err"];
            }
        }
        $i++;
    }
    [200, "OK"];
}

1;
__END__

=head1 SYNOPSIS

 use Setup::File 'setup_file';

 # simple usage (doesn't save undo data)
 my $res = setup_file path => '/etc/rc.local',
                      should_exist => 1,
                      gen_content_code => sub { "#!/bin/sh\n" },
                      owner => 'root', group => 0,
                      mode => '+x';
 die unless $res->[0] == 200;

 # perform setup and save undo data (undo data should be serializable)
 $res = setup_file ..., -undo_action => 'do';
 die unless $res->[0] == 200;
 my $undo_data = $res->[3]{undo_data};

 # perform undo
 $res = setup_file ..., -undo_action => "undo", -undo_data=>$undo_data;
 die unless $res->[0] == 200;

 # state that file must not exist
 setup_file path => '/foo/bar', should_exist => 0;


=head1 DESCRIPTION

This module provides one function: B<setup_file>.

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
