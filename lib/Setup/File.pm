package Setup::File;

use 5.010;
use strict;
use warnings;
use Log::Any '$log';

use Digest::MD5 qw(md5_hex);
use File::chmod;
use File::Copy::Recursive qw(rmove);
use File::Path qw(remove_tree);
use File::Slurp;
use File::Temp qw(tempfile tempdir);
use Perinci::Sub::Gen::Undoable 0.22 qw(gen_undoable_func);
use UUID::Random;

require Exporter;
our @ISA       = qw(Exporter);
our @EXPORT_OK = qw(setup_file);

# VERSION

our %SPEC;

my $res;

$res = gen_undoable_func(
    v           => 2,
    name        => 'rm_r',
    summary     => 'Delete file/dir',
    trash_dir   => 1,
    description => <<'_',

It actually moves the file/dir to a unique name in trash and save the unique
name as undo data.

Fixed state: path does not exist.

Fixable state: path exists.

_
    args        => {
        path => {
            schema => 'str*',
        },
    },
    check_args => sub {
        # TMP, schema
        my $args = shift;
        defined($args->{path}) or return [400, "Please specify path"];
        [200, "OK"];
    },
    check_or_fix_state => sub {
        my ($which, $args, $undo) = @_;

        my $path = $args->{path};
        my $exists = (-l $path) || (-e _);
        my $save = "$args->{-undo_trash_dir}/". UUID::Random::generate;
        my @u;
        if ($which eq 'check') {
            push @u, ['Setup::File::mv', {from => $save, to => $path}]
                if $exists;
            return @u ? [200,"OK",undef,{undo_data=>\@u}]:[304,"Nothing to do"];
        }
        $save = $undo->[0][1]{from};
        if (rmove $path, $save) {
            return [200, "OK"];
        } else {
            return [500, "Can't move $path -> $save: $!"];
        }
    },
);
die "Can't generate rm_r: $res->[0] - $res->[1]" unless $res->[0] == 200;

$res = gen_undoable_func(
    v           => 2,
    name        => 'mv',
    summary     => 'Move file/dir',
    description => <<'_',

Fixed state: none.

Fixable state: `from` exists and `to` doesn't exist.

_
    args        => {
        from => {
            schema => 'str*',
        },
        to => {
            schema => 'str*',
        },
    },
    check_args => sub {
        # TMP, schema
        my $args = shift;
        defined($args->{from}) or return [400, "Please specify from"];
        defined($args->{to})   or return [400, "Please specify to"];
        [200, "OK"];
    },
    check_or_fix_state => sub {
        my ($which, $args, $undo) = @_;

        my $from = $args->{from};
        my $to   = $args->{to};
        my $from_exists = (-l $from) || (-e _);
        my $to_exists   = (-l $to)   || (-e _);
        my @u;
        if ($which eq 'check') {
            return [412, "Source ($from) does not exist"] unless $from_exists;
            return [412, "Target ($to) exists"] if $to_exists;
            push @u, ['Setup::File::mv', {
                from => $to,
                to   => $from,
            }];
            return @u ? [200,"OK",undef,{undo_data=>\@u}]:[304,"Nothing to do"];
        }
        if (rmove $from, $to) {
            return [200, "OK"];
        } else {
            return [500, "Can't move $from -> $to: $!"];
        }
    },
);
die "Can't generate mv: $res->[0] - $res->[1]" unless $res->[0] == 200;

1;

__END__

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

sub __build_steps {
    my $which = shift; # file for Setup::File, or dir for Setup::File::Dir
    my $args = shift;

    my $path = $args->{path};

    my $is_symlink     = (-l $path);
    my $exists         = (-e _);
    # -l does lstat, we need stat
    #my @st = stat($is_symlink ? $path : _);
    my @st             = stat($path); # stricture complains about _
    return [500, "Can't stat (1): $!"] if $exists && !$is_symlink && !@st;
    my $is_file        = (-f _);
    my $is_dir         = (-d _);

    # exists means whether *target* exists, if symlink is allowed. while
    # symlink_exists means the symlink itself exists.
    my $symlink_exists;
    if ($allow_symlink && $is_symlink) {
        $symlink_exists = $exists;
        $exists = (-e _) if $symlink_exists;
    }

    my @steps;
    {
        if (defined($args->{should_exist}) && !$args->{should_exist}
                && $exists) {
            $log->info("nok: $which $path should not exist but does");
            push @steps, [$is_dir ? "rm_r" : "rmfile"];
            last;
        }
        if ($args->{should_exist} && !$exists) {
            $log->info("nok: $which $path should exist but doesn't");
            push @steps, ["rmsym"] if $symlink_exists;
            push @steps, ["create"];
            last;
        }
        if (!$args->{allow_symlink} && $is_symlink) {
            $log->info("nok: $which $path should not be symlink but is");
            if (!$args->{replace_symlink}) {
                return [412, "must replace symlink but instructed not to"];
            }
            push @steps, ["rmsym"], ["create"];
            last;
        }
        last unless $exists;
        if ($is_dir && $which eq 'file') {
            $log->info("nok: $path is expected to be file but is dir");
            if (!$args->{replace_dir}) {
                return [412, "must replace dir but instructed not to"];
            }
            push @steps, ["rm_r"], ["create"];
            last;
        } elsif (!$is_dir && $which eq 'dir') {
            $log->info("nok: $path is expected to be dir but is file");
            if (!$args->{replace_file}) {
                return [412, "must replace file but instructed not to"];
            }
            push @steps, ["rm_r"], ["create"];
            last;
        }
        if (defined $args->{mode}) {
            my $cur_mode = $st[2] & 07777;
            my $mode = $args->{mode} =~ /[+=-]/ ? # resolve symbolic mode
                getchmod($args->{mode}, $cur_mode) : $args->{mode};
            if ($mode != $cur_mode) {
                $log->infof("nok: $which $path mode is %04o, ".
                                "but it should be %04o",
                            $cur_mode, $mode);
                push @steps, ["chmod", $mode];
            }
        }
        if (defined $args->{owner}) {
            my $cur_uid = $st[4];
            my $uid;
            my @pw;
            if ($args->{owner} !~ /\A\d+\z/) { # resolve username -> uid
                @pw = getpwnam($args->{owner});
                return [412, "Can't find user with name $args->{owner}"]
                    unless @pw;
                $uid = $pw[2];
            } else {
                $uid = $args->{owner};
            }
            if ($uid != $cur_uid) {
                my @pwc = getpwuid($cur_uid);
                $log->infof("nok: $which $path owner is %s ".
                                "but it should be %s",
                            @pwc ? $pwc[0] : $cur_uid,
                            @pw  ? $pw[0]  : $uid);
                push @steps, ["chown", $uid];
            }
        }
        if (defined $args->{group}) {
            my $cur_gid = $st[5];
            my $gid;
            my @gr;
            if ($args->{group} !~ /^\d+$/) {
                my @gr = getgrnam($args->{group});
                return [412, "Can't find group with name $args->{group}"]
                    unless @gr;
                $gid = $gr[2];
            } else {
                $gid = $args->{group};
            }
            if ($gid != $cur_gid) {
                my @grc = getgrgid($cur_gid);
                $log->infof("nok: $which $path group is %s ".
                                "but it should be %s",
                            @grc ? $grc[0] : $cur_gid,
                            @gr  ? $gr[0]  : $gid);
                push @steps, ["chown", undef, $gid];
            }
        }
        if ($args->{check_content_code} || defined($args->{content})) {
            my $cur_content = read_file($path, err_mode=>'quiet');
            return [500, "Can't read file content: $!"]
                unless defined($cur_content);
            my $res = $args->{check_content_code} ?
                $args->{check_content_code}->(\$cur_content) :
                    $cur_content eq $args->{content};
            unless ($res) {
                $log->infof("nok: file $path content incorrect");
                my $ref_ct = $args->{gen_content_code}->(\$cur_content);
                $ref_ct = \$ref_ct unless ref($ref_ct);
                push @steps, ["set_content", $$ref_ct]; # JSON doesnt do \scalar
            }
        }
    } # block
}

our $steps = {
    rmsym => {
        summary => "Delete symlink at 'path'",
        description => <<'_',

Syntax: `["rmsym"]`

Will fail if 'path' argument is not a symlink.

The original symlink target is saved as undo data.

See also: ln.

_
        check => sub {
            my ($args, $step) = @_;
            my $path = $args->{path};
            if (-l $path) {
                my $t = readlink($path) // "";
                return [200, "OK", ["ln", $t]];
            } elsif (-e _) {
                return [412, "Can't rmsym $path: not a symlink"];
            }
            return [200, "OK"];
        },
        fix => sub {
            my ($args, $step) = @_;
            my $path = $args->{path};
            if (unlink $s) {
                return [200, "OK"];
            }
            return [500, "Can't unlink $path: $!"];
        },
    },

    ln => {
        summary => 'Create symlink',
        description => <<'_',

Syntax: `["ln", $t]`.

Create symlink which points to $t.

See also: rmsym.

_
        check => sub {
            my ($args, $step) = @_;
            my $path = $args->{path};
            my $t = $step->[1];
            if (-l $path) {
                if (readlink($path) eq $t) {
                    return [200, "OK"];
                } else {
                    return [200, "OK", ["ln"]];
                }
            } elsif (-e _) {
                return [412, "Can't ln: already exists"];
            }
                return [200, "OK", ["rmsym"]];
            }
            return [200, "OK"];

        elsif ($step->[0] eq 'ln') {
            my $t = $step->[1];
            $log->info("Creating symlink $path -> $t ...");
            unless ((-l $path) && readlink($path) eq $t) {
                if (symlink $t, $path) {
                    unshift @$undo_steps, ["rmsym"];
                } else {
                    $err = "Can't symlink $path -> $t: $!";
                }
             }
        } elsif ($step->[0] eq 'rm_r') {
            $log->info("Removing file/dir $path ...");
            if ((-l $path) || (-e _)) {
                # do not bother to save file/dir if not asked
                if ($save_undo) {
                    if (rmove $path, $save_path) {
                        unshift @$undo_steps, ["restore", $save_path];
                    } else {
                        $err = "Can't move file/dir $path -> $save_path: $!";
                    }
                } else {
                    remove_tree($path, {error=>\my $e});
                    if (@$e) {
                        $err = "Can't remove file/dir $path: ".dumpp($e);
                    }
                }
            }
        } elsif ($step->[0] eq 'rmfile') {
            $log->info("Removing file $path ...");
            # will only delete if content is unchanged from time of create,
            # content is represented by hash
            if ((-l $path) || (-e _)) {
                my $ct = read_file($path, err_mode=>'quiet');
                if (!defined($ct)) {
                    $err = "Can't read file: $!";
                } else {
                    my $ct_hash = md5_hex($ct);
                    if (defined($step->[1]) && $ct_hash ne $step->[1]) {
                        $log->warn("File content has changed, not removing");
                    } else {
                        if (unlink $path) {
                            unshift @$undo_steps, ["create", \$ct];
                        } else {
                            $err = "Can't unlink $path: $!";
                        }
                    }
                }
            }
        } elsif ($step->[0] eq 'rmdir') {
            $log->info("Removing dir $path ...");
            if ((-l $path) || (-e _)) {
                if (rmdir $path) {
                    unshift @$undo_steps, ["create"];
                } else {
                    $err = "Can't rmdir $path: $!";
                }
            }
        } elsif ($step->[0] eq 'restore') {
            $log->info("Restoring $step->[1] -> $path ...");
            if ((-l $path) || (-e _)) {
                $err = "Can't restore $step->[1] -> $path: already exists";
            } elsif (rmove $step->[1], $path) {
                unshift @$undo_steps, ["rm_r"];
            } else {
                $err = "Can't restore $step->[1] -> $path: $!";
            }
        } elsif ($step->[0] eq 'create') {
            $log->info("Creating $path ...");
            if ((-l $path) || (-e _)) {
                if ((-f _)) {
                    my $cur_content = read_file($path, err_mode=>'quiet');
                    return [500, "Can't read file content: $!"]
                        unless defined($cur_content);
                    if ($cur_content ne ${$step->[1]}) {
                        $err = "Can't create $path: file already exists but ".
                            "with different content";
                    }
                } else {
                    $err = "Can't create $path: already exists but not a file";
                }
            } else {
                {
                    if ($which eq 'dir') {
                        mkdir $path
                            or do { $err = "Can't mkdir: $!"; last };
                        chown $owner//-1, $group//-1, $path
                            or do { $err = "Can't chown: $!"; last };
                        defined($mode) and chmod $mode, $path ||
                            do { $err = "Can't chmod: $!"; last };
                        unshift @$undo_steps, ["rmdir"];
                    } else {
                        my $ct;
                        if (defined $step->[1]) {
                            $ct = ${$step->[1]};
                        } else {
                            if ($gen_ct) {
                                my $ref_ct = $gen_ct->(\$cur_content);
                                $ct = ref($ref_ct) ? $$ref_ct : $ref_ct;
                            } else {
                                $ct = $content;
                            }
                            $ct //= "";
                        }
                        my $ct_hash = md5_hex($ct);
                        write_file($path, {err_mode=>'quiet', atomic=>1}, $ct)
                            or do { $err = "Can't write file: $!"; last };
                        chown $owner//-1, $group//-1, $path
                            or do { $err = "Can't chown: $!"; last };
                        defined($mode) and chmod $mode, $path ||
                            do { $err = "Can't chmod: $!"; last };
                        unshift @$undo_steps, ["rmfile", $ct_hash];
                    }
                }
            }
        } elsif ($step->[0] eq 'set_content') {
            $log->info("Setting content ...");
            {
                my $cur_content = read_file($path, err_mode=>'quiet');
                defined($cur_content)
                    or do { $err = "Can't read file: $!"; last };
                write_file($path, {err_mode=>'quiet', atomic=>1}, ${$step->[1]})
                    or do { $err = "Can't write file: $!"; last };
                unshift @$undo_steps, ["set_content", \$cur_content];
                # need to chown + chmod temporary file again
                chown $owner//-1, $group//-1, $path
                    or do { $log->warn("Can't chown: $!") };
                defined($mode) and chmod $mode, $path ||
                    do { $log->warn("Can't chmod: $!") };
            }
        } elsif ($step->[0] eq 'chmod') {
            $log->info("Chmod $path ...");
            my @st = lstat($path);
            if (!@st) {
                $log->warn("Can't stat, skipping chmod");
            } else {
                if (chmod $step->[1], $path) {
                    unshift @$undo_steps, ["chmod", $st[2] & 07777];
                } else {
                    $err = $!;
                }
            }
        } elsif ($step->[0] eq 'chown') {
            $log->info("Chown $path ...");
            my @st = lstat($path);
            if (!@st) {
                $log->warn("Can't stat, skipping chmod");
            } else {
                if (chown $step->[1]//-1, $step->[2]//-1, $path) {
                    unshift @$undo_steps,
                        ["chown",
                         defined($step->[1]) ? $st[4] : undef,
                         defined($step->[2]) ? $st[5] : undef];
                } else {
                    $err = $!;
                }
            }
        } else {
            die "BUG: Unknown step command: $step->[0]";
        }
        if ($err) {
            if ($rollback) {
                die "Failed rollback step $i of 0..".(@$steps-1).": $err";
            } else {
                $log->tracef("Step failed: $err, performing rollback (%s)...",
                             $undo_steps);
                $rollback = $err;
                $steps = $undo_steps;
                goto STEP; # perform steps all over again
            }
        }
    }
    };

my $res = gen_undoable_func(
    name     => 'setup_file',
    summary  => "Setup file (existence, mode, permission, content)",
    description => <<'_',

On do, will create file (if it doesn't already exist) and correct
mode/permission as well as content.

On undo, will restore old mode/permission/content, or delete the file again if
it was created by this function *and* its content hasn't changed since.

If given, -undo_hint should contain {tmp_dir=>...} to specify temporary
directory to save replaced file/dir. Temporary directory defaults to ~/.setup,
it will be created if not exists.

_
    args     => {
        path => {
            schema  => ['str*' => { match => qr!^/! }],
            summary => 'Path to file',
            description => <<'_',

File path needs to be absolute so it's normalized.

_
            req => 1,
            pos => 0,
        },
        should_exist => {
            schema  => 'bool',
            summary => 'Whether file should exist',
            description => <<'_',

If undef, file need not exist. If set to 0, file must not exist and will be
deleted if it does. If set to 1, file must exist and will be created if it
doesn't.

_
        },
        mode => {
            schema => 'str',
            summary => 'Expected permission mode',
            description => <<'_',

Mode is as supported by File::chmod. Either an octal string (e.g. '0755') or a
symbolic mode (e.g. 'u+rw').

_
        },
        owner => {
            schema  => 'str',
            summary => 'Expected owner',
        },
        group => {
            schema  => 'str',
            summary => 'Expected group',
        },
        content => {
            schema  => 'str',
            summary => 'Desired file content',
            description => <<'_',

Alternatively you can also use check_content_code & gen_content_code.

_
        },
        check_content_code => {
            schema  => 'code',
            summary => 'Code to check content',
            description => <<'_',

If unset, file will not be checked for its content. If set, code will be called
whenever file content needs to be checked. Code will be passed the reference to
file content and should return a boolean value indicating whether content is
acceptable. If it returns a false value, content is deemed unacceptable and
needs to be fixed.

Alternatively you can use the simpler 'content' argument.

_
        },
        gen_content_code => {
            schema  => 'code',
            summary => 'Code to generate content',
            description => <<'_',

If set, whenever a new file content is needed (e.g. when file is created or file
content reset), this code will be called to provide it. If unset, empty string
will be used instead.

Code will be passed the reference to the current content (or undef) and should
return the new content.

Alternatively you can use the simpler 'content' argument.

_
        },
        allow_symlink => {
            schema  => [bool => {default=>1}],
            summary => 'Whether symlink is allowed',
            description => <<'_',

If existing file is a symlink then if allow_symlink is false then it is an
unacceptable condition (the symlink will be replaced if replace_symlink is
true).

Note: if you want to setup symlink instead, use Setup::Symlink.

_
        },
        replace_symlink => {
            schema  => [bool => {default=>1}],
            summary => "Replace existing symlink if it needs to be replaced",
        },
        replace_file => {
            schema  => [bool => {default=>1}],
            summary => "Replace existing file if it needs to be replaced",
        },
        replace_dir => {
            schema  => [bool => {default=>1}],
            summary => "Replace existing dir if it needs to be replaced",
        },
    },

    check_args => sub {
        my $args = shift;
        $args->{path} or return [400, "Please specify path"];
        $args->{path} =~ m!^/!
            or return [400, "Please specify an absolute path"];
        $args->{allow_symlink}   //= 1;
        $args->{replace_file}    //= 1;
        $args->{replace_dir}     //= 1;
        $args->{replace_symlink} //= 1;

        my $ct       = $args->{content};
        my $check_ct = $args->{check_content_code};
        my $gen_ct   = $args->{gen_content_code};
        return [400, "If check_content_code is specified, ".
                    "gen_content_code must also be specified"]
            if defined($check_ct) && !defined($gen_ct);
        return [400, "If content is specified, then check_content_code/".
                    "gen_content_code must not be specified (and vice versa)"]
            if defined($ct) && (defined($check_ct) || defined($gen_ct));
        [200, "OK"];
    },

    build_steps => sub {
        __build_steps('file', @_);
    },

    steps => $steps,
);

1;
# ABSTRACT: Setup file (existence, mode, permission, content)

=head1 SYNOPSIS

 use Setup::File 'setup_file';

 # simple usage (doesn't save undo data)
 my $res = setup_file path => '/etc/rc.local',
                      should_exist => 1,
                      gen_content_code => sub { \("#!/bin/sh\n") },
                      owner => 'root', group => 0,
                      mode => '+x';
 die unless $res->[0] == 200 || $res->[0] == 304;

 # perform setup and save undo data (undo data should be serializable)
 $res = setup_file ..., -undo_action => 'do';
 die unless $res->[0] == 200 || $res->[0] == 304;
 my $undo_data = $res->[3]{undo_data};

 # perform undo
 $res = setup_file ..., -undo_action => "undo", -undo_data=>$undo_data;
 die unless $res->[0] == 200 || $res->[0] == 304;


=head1 SEE ALSO

L<Setup>

=cut
