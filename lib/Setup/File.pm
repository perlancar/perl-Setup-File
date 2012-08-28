package Setup::File;

use 5.010;
use strict;
use warnings;
use Log::Any '$log';

use File::Trash::Undoable;
use SHARYANTO::File::Util qw(dir_empty);

require Exporter;
our @ISA       = qw(Exporter);
our @EXPORT_OK = qw(setup_file);

# VERSION

our %SPEC;

my $res;

$SPEC{rmdir} = {
    v           => 1.1,
    summary     => 'Delete directory',
    description => <<'_',

Fixed state: `path` doesn't exist.

Fixable state: `path` exists and is a directory (or, a symlink to a directory,
if `allow_symlink` option is enabled).

Unfixable state: `path` exists but is not a directory.

_
    args        => {
        path => {
            schema => 'str*',
            req    => 1,
            pos    => 0,
        },
        allow_symlink => {
            schema => [bool => {default => 0}],
            summary => 'Whether to assume symlink to a directory as directory',
        },
        delete_nonempty_dir => {
            schema => [bool => {}],
            summary => 'Whether to delete non-empty directory',
            description => <<'_',

If set to true, will delete non-empty directory.

If set to false, will never delete non-empty directory.

If unset (default), will ask for confirmation first by returning status 331.
Caller can confirm by passing special argument `-confirm`.

_
        },
    },
    features => {
        tx => {v=>2},
        idempotent => 1,
    },
};
sub rmdir {
    my %args = @_;

    # TMP, schema
    my $tx_action = $args{-tx_action} // '';
    my $path      = $args{path};
    defined($path) or return [400, "Please specify path"];
    my $allow_sym = $args{allow_symlink} // 0;

    my $is_sym    = (-l $path);
    my $exists    = $is_sym || (-e _);
    my $is_dir    = (-d _);
    my $is_sym_to_dir = $is_sym && (-d $path);
    my $empty     = $exists && dir_empty($path);

    my @undo;

    #$log->tracef("path=%s, exists=%s, is_dir=%s, allow_sym=%s, is_sym_to_dir=%s", $path, $exists, $is_dir, $allow_sym, $is_sym_to_dir);
    if ($tx_action eq 'check_state') {
        return [412, "Not a dir"] if $exists &&
            !($is_dir || $allow_sym && $is_sym_to_dir);
        if ($exists) {
            if (!$empty) {
                my $d = $args{delete_nonempty_dir};
                if (defined($d) && !$d) {
                    return [412, "Dir $path is not empty, but instructed ".
                                "never to remove non-empty dir"];
                } elsif (!defined($d)) {
                    if (!$args{-confirm}) {
                        return [331, "Dir $path not empty, confirm delete?"];
                    }
                }
            }
            $log->info("nok: Dir $path should be removed");
            push @undo, (
                ['File::Trash::Undoable::untrash' => {path=>$path}],
            );
        }
        if (@undo) {
            return [200, "Fixable", undef, {undo_actions=>\@undo}];
        } else {
            return [304, "Fixed"];
        }
    } elsif ($tx_action eq 'fix_state') {
        return File::Trash::Undoable::trash(
            -tx_action=>'fix_state', path=>$path);
    }
    [400, "Invalid -tx_action"];
}

$SPEC{mkdir} = {
    v           => 1.1,
    summary     => 'Create directory',
    description => <<'_',

Fixed state: `path` exists and is a directory.

Fixable state: `path` doesn't exist.

Unfixable state: `path` exists and is not a directory.

_
    args        => {
        path => {
            summary => 'Path to directory',
            schema  => 'str*',
            req     => 1,
            pos     => 0,
        },
        allow_symlink => {
            summary => 'Whether to assume symlink to a directory as directory',
            schema => 'str*',
        },
    },
    features => {
        tx => {v=>2},
        idempotent => 1,
    },
};
sub mkdir {
    my %args = @_;

    # TMP, schema
    my $tx_action = $args{-tx_action} // '';
    my $path      = $args{path};
    defined($path) or return [400, "Please specify path"];
    my $allow_sym = $args{allow_symlink} // 0;

    my $is_sym    = (-l $path);
    my $exists    = $is_sym || (-e _);
    my $is_dir    = (-d _);
    my $is_sym_to_dir = $is_sym && (-d $path);

    if ($tx_action eq 'check_state') {
        my @undo;
        return [412, "Not a dir"] if $exists &&
            !($is_dir || $allow_sym && $is_sym_to_dir);
        if (!$exists) {
            $log->info("nok: Dir $path should be created");
            push @undo, [rmdir => {path => $path}];
        }
        if (@undo) {
            return [200, "Fixable", undef, {undo_actions=>\@undo}];
        } else {
            return [304, "Fixed"];
        }
    } elsif ($tx_action eq 'fix_state') {
        if (CORE::mkdir($path)) {
            return [200, "Fixed"];
        } else {
            return [500, "Can't symlink: $!"];
        }
    }
    [400, "Invalid -tx_action"];
}

$SPEC{chmod} = {
    v           => 1.1,
    summary     => "Set file's permission mode",
    description => <<'_',

Fixed state: `path` exists and mode is already correct.

Fixable state: `path` exists but mode is not correct.

Unfixable state: `path` doesn't exist.

_
    args        => {
        path => {
            summary => 'Path to file/directory',
            schema  => 'str*',
            req     => 1,
            pos     => 0,
        },
        mode => {
            summary => 'Permission mode, either numeric or symbolic (e.g. a+w)',
            schema  => 'str*',
            req     => 1,
            pos     => 1,
        },
        follow_symlink => {
            summary => 'Whether to follow symlink',
            schema => [bool => {default=>0}],
        },
        orig_mode => {
            summary=>'If set, confirm if current mode is not the same as this',
            schema => 'int',
        },
    },
    features => {
        tx => {v=>2},
        idempotent => 1,
    },
};
sub chmod {
    require File::chmod;

    my %args = @_;

    local $File::chmod::UMASK = 0;

    # TMP, schema
    my $tx_action  = $args{-tx_action} // '';
    my $path       = $args{path};
    defined($path) or return [400, "Please specify path"];
    my $follow_sym = $args{follow_symlink} // 0;
    my $orig_mode  = $args{orig_mode};
    my $want_mode  = $args{mode};
    defined($want_mode) or return [400, "Please specify mode"];

    my $is_sym    = (-l $path);
    return [412, "$path is a symlink"] if !$follow_sym && $is_sym;
    my $exists    = $is_sym || (-e _);
    my @st        = stat($path);
    my $cur_mode  = $st[2] & 07777 if $exists;
    if (!$args{-tx_recovery} && defined($orig_mode) && defined($cur_mode) &&
            $cur_mode != $orig_mode && !$args{-confirm}) {
        return [331, "$path: File mode has changed, chmod?"];
    }
    if ($want_mode =~ /\D/) {
        return [412, "Symbolic mode requires path to exist"] unless $exists;
        $want_mode = File::chmod::getchmod($want_mode, $path);
    }

    #$log->tracef("path=%s, cur_mode=%04o, want_mode=%04o", $path, $cur_mode, $want_mode);
    if ($tx_action eq 'check_state') {
        my @undo;
        return [412, "Doesn't exist"] if !$exists;
        if ($cur_mode != $want_mode) {
            $log->infof("nok: Should chmod $path to %04o", $want_mode);
            push @undo, [chmod => {
                path => $path, mode=>$cur_mode, orig_mode=>$want_mode,
                follow_symlink => $follow_sym,
            }];
        }
        if (@undo) {
            return [200, "Fixable", undef, {undo_actions=>\@undo}];
        } else {
            return [304, "Fixed"];
        }
    } elsif ($tx_action eq 'fix_state') {
        if (CORE::chmod($want_mode, $path)) {
            return [200, "Fixed"];
        } else {
            return [500, "Can't chmod $path: $!"];
        }
    }
    [400, "Invalid -tx_action"];
}

$SPEC{chown} = {
    v           => 1.1,
    summary     => "Set file's ownership",
    description => <<'_',

Fixed state: `path` exists and ownership is already correct.

Fixable state: `path` exists but ownership is not correct.

Unfixable state: `path` doesn't exist.

_
    args        => {
        path => {
            summary => 'Path to file/directory',
            schema  => 'str*',
            req     => 1,
            pos     => 0,
        },
        owner => {
            summary => 'Numeric UID or username',
            schema  => 'str*',
        },
        group => {
            summary => 'Numeric GID or group',
            schema  => 'str*',
        },
        follow_symlink => {
            summary => 'Whether to follow symlink',
            schema => [bool => {default=>0}],
        },
        orig_owner => {
            summary=>'If set, confirm if current owner is not the same as this',
            schema => 'str',
        },
        orig_group => {
            summary=>'If set, confirm if current group is not the same as this',
            schema => 'str',
        },
    },
    features => {
        tx => {v=>2},
        idempotent => 1,
    },
};
sub chown {
    require Lchown;
    return [412, "lchown() is not available on this system"] unless
        Lchown::LCHOWN_AVAILABLE();

    my %args = @_;

    # TMP, schema
    my $tx_action  = $args{-tx_action} // '';
    my $path       = $args{path};
    defined($path) or return [400, "Please specify path"];
    my $follow_sym = $args{follow_symlink} // 0;
    my $orig_owner = $args{orig_owner};
    my $orig_group = $args{orig_group};
    my $want_owner = $args{owner};
    my $want_group = $args{group};
    defined($want_owner) || defined($want_group)
        or return [400, "Please specify at least either owner/group"];

    my ($orig_uid, $orig_uname);
    if (defined $orig_owner) {
        if ($orig_owner =~ /\A\d+\z/) {
            $orig_uid = $orig_owner;
            my @ent = getpwuid($orig_uid);
            $orig_uname = $ent[0] if @ent;
        } else {
            $orig_uname = $orig_owner;
            my @ent = getpwnam($orig_uname);
            return [412, "User doesn't exist: $orig_uname"] unless @ent;
            $orig_uid = $ent[2];
        }
    }

    my ($want_uid, $want_uname);
    if (defined $want_owner) {
        if ($want_owner =~ /\A\d+\z/) {
            $want_uid = $want_owner;
            my @ent = getpwuid($want_uid);
            $want_uname = $ent[0] if @ent;
        } else {
            $want_uname = $want_owner;
            my @ent = getpwnam($want_uname);
            return [412, "User doesn't exist: $want_uname"] unless @ent;
            $want_uid = $ent[2];
        }
    }

    my ($orig_gid, $orig_gname);
    if (defined $orig_group) {
        if ($orig_group =~ /\A\d+\z/) {
            $orig_gid = $orig_group;
            my @grent = getgrgid($orig_gid);
            $orig_gname = $grent[0] if @grent;
        } else {
            $orig_gname = $orig_group;
            my @grent = getgrnam($orig_gname);
            return [412, "Group doesn't exist: $orig_gname"] unless @grent;
            $orig_gid = $grent[2];
        }
    }

    my ($want_gid, $want_gname);
    if (defined $want_group) {
        if ($want_group =~ /\A\d+\z/) {
            $want_gid = $want_group;
            my @grent = getgrgid($want_gid);
            $want_gname = $grent[0] if @grent;
        } else {
            $want_gname = $want_group;
            my @grent = getgrnam($want_gname);
            return [412, "Group doesn't exist: $want_gname"] unless @grent;
            $want_gid = $grent[2];
        }
    }

    my @st        = lstat($path);
    my $is_sym    = (-l _);
    return [412, "$path is a symlink"] if !$follow_sym && $is_sym;
    my $exists    = $is_sym || (-e _);
    if ($follow_sym && $exists) {
        @st = stat($path);
        return [500, "Can't stat $path (2): $!"] unless @st;
    }
    my $cur_uid   = $st[4];
    my $cur_gid   = $st[5];
    if (!$args{-tx_recovery} && !$args{-confirm}) {
        my $changed = defined($orig_uid) && $orig_uid != $cur_uid ||
            defined($orig_gid) && $orig_gid != $cur_gid;
        return [331, "$path: File mode has changed, chmod?"] if $changed;
    }

    #$log->tracef("path=%s, cur_uid=%s, cur_gid=%s, want_uid=%s, want_uname=%s, want_gid=%s, want_gname=%s", $cur_uid, $cur_gid, $want_uid, $want_uname, $want_gid, $want_gname);
    if ($tx_action eq 'check_state') {
        my @undo;
        return [412, "Doesn't exist"] if !$exists;
        if (defined($want_uid) && $cur_uid != $want_uid ||
                defined($want_gid) && $cur_gid != $want_gid) {
            $log->infof("nok: Should chown $path to (%s, %s)",
                        $want_owner, $want_group);
            push @undo, [chown => {
                path  => $path,
                owner => (defined($want_uid) &&
                              $cur_uid != $want_uid ? $cur_uid : undef),
                group => (defined($want_gid) &&
                              $cur_gid != $want_gid ? $cur_gid : undef),
                orig_owner => $want_owner, orig_group => $want_group,
                follow_symlink => $follow_sym,
            }];
        }
        if (@undo) {
            return [200, "Fixable", undef, {undo_actions=>\@undo}];
        } else {
            return [304, "Fixed"];
        }
    } elsif ($tx_action eq 'fix_state') {
        my $res;
        if ($follow_sym) {
            $res = CORE::chown   ($want_uid // -1, $want_gid // -1, $path);
        } else {
            $res = Lchown::lchown($want_uid // -1, $want_gid // -1, $path);
        }
        if ($res) {
            return [200, "Fixed"];
        } else {
            return [500, "Can't chown $path: $!"];
        }
    }
    [400, "Invalid -tx_action"];
}

1;

__END__

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
            $log->info("nok: $which $path should not exist but does") if $do_log;
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

# OLD

our $steps = {
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

use Digest::MD5 qw(md5_hex);
use File::Slurp;

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
