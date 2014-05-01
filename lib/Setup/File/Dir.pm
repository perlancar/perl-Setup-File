package Setup::File::Dir;

use Setup::File;

require Exporter;
our @ISA       = qw(Exporter);
our @EXPORT_OK = qw(setup_dir);

# VERSION

# now moved to Setup::File

sub setup_dir {
    [501, "Moved to Setup::File"];
}

1;
# ABSTRACT: Setup directory (existence, mode, permission)

=for Pod::Coverage ^(setup_dir)$

=head1

Moved to

=head1 SEE ALSO

L<Setup>

L<Setup::File>

=cut
