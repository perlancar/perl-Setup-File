package Spanel::Setup::Common::Dir;

use 5.010;
use strict;
use warnings;
use Log::Any '$log';

require Exporter;
our @ISA       = qw(Exporter);
our @EXPORT_OK = qw(setup_dir);

our %SPEC;

# return 1 if dir exists and empty
sub dir_is_empty {
    my ($dir) = @_;
    return unless (-d $dir);
    return unless opendir my($dh), $dir;
    my @d = grep {$_ ne '.' && $_ ne '..'} readdir($dh);
    my $res = !@d;
    $log->tracef("dir_is_empty(%s)? %d", $dir, $res);
    $res;
}

$SPEC{setup_dir} = {
    summary  => "Create dir and remove it in reverse mode (if dir is empty)",
    args     => {
        dir  => ['str*' => {
            summary => 'Path of directory, ',
            match   => qr!^/!,
        }],
        mode => ['int' => {
            summary => 'Mode',
            default => 0755,
            ge      => 0,
        }],
    },
    features => {reverse=>1, dry_run=>1},
};
sub setup_dir {
    my %args    = @_;
    my $dry_run = $args{dry_run};
    my $reverse = $args{-reverse};

    my $dir     = $args{dir};
    return [400, "Please specify absolute path for dir"]
        unless $dir =~ m!^/!;
    my $perm    = $args{perm} // 0755;

    my ($ok, $nok_msg, $bail);
    my $empty  = _dir_is_empty($dir);
    my $exists = (-d _);
    if ($reverse) {
        $ok = !$empty;
        $bail = $exists;
        if (!$ok) {
            if ($bail) {
                $nok_msg = "Directory $dir exists but not empty, ".
                    "we will not be deleting it in undo";
            } else {
                $nok_msg = "Directory $dir exists and is empty";
            }
        }
    } else {
        $ok = $exists;
        $nok_msg = "Directory $dir doesn't exist" if !$ok;
    }

    return [304, "OK"] if $ok;
    return [412, $nok_msg] if $dry_run || $bail;

    use autodie;
    if ($reverse) {
        $log->debug("deleting dir $dir");
        rmdir $dir;
    } else {
        $log->debugf("creating dir %s (%s)", $dir, sprintf("%04o", $perm));
        mkdir $dir;
    }
    [200, "Fixed"];
}

1;
