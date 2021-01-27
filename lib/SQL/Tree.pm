package SQL::Tree;
use strict;
use warnings;
use File::Basename;
use File::ShareDir::Dist 'dist_share';
use File::Spec;
use Template::Tiny;

our $VERSION = '0.05_1';

my $tt = Template::Tiny->new( TRIM => 0, );

sub generate {
    my $ref = shift;

    $ref->{table_tree} = $ref->{table} . $ref->{postfix};
    $ref->{program}    = __PACKAGE__;
    $ref->{localtime}  = scalar localtime;
    $ref->{version}    = $VERSION;

    local $ref->{separator} = $ref->{separator} =~ s/'/''/gr;

    die 'path requires a name'
      if exists $ref->{path} and not exists $ref->{name};

    my $dist_share = dist_share('SQL-Tree');
    my $template = File::Spec->catfile( $dist_share, $ref->{driver} . '.sqlt' );

    open my $fh, '<', $template or die 'unsupported driver: ' . $ref->{driver};
    my $sqlt = do { local $/; <$fh> };

    $tt->process( \$sqlt, $ref, \my $output );
    $output;
}

1;

__END__

=head1 NAME

SQL::Tree - Generate a trigger-based SQL tree implementation

=head1 VERSION

0.05_1 (2021-01-27)

=head1 SYNOPSIS

    use SQL::Tree;

    my $sql = SQL::Tree::generate({
        driver    => $DBI_driver_name,
        drop      => $bool,
        id        => $primary_key_name,
        name      => $source_column_name_for_path,
        parent    => $parent_column_name,
        path      => $path_column_name,
        table     => $table_name,
        type      => $primary_key_type,
    });


=head1 DESCRIPTION

B<SQL::Tree> generates a herarchical data (tree) implementation for
SQLite and PostgreSQL using triggers, as described here:

    http://www.depesz.com/index.php/2008/04/11/my-take-on-trees-in-sql/

A single subroutine is provided that returns a list of SQL
statements:

=over 4

=item * generate( \%opts ) -> $str

=back

See the L<sqltree> documentation for the list of arguments and their
meanings.

=head1 SEE ALSO

L<sqltree>(1) - command line access to B<SQL::Tree>

=head1 AUTHOR

Mark Lawrence E<lt>nomad@null.netE<gt>

=head1 COPYRIGHT AND LICENSE

Copyright 2010-2021 Mark Lawrence <nomad@null.net>

This program is free software; you can redistribute it and/or modify it
under the terms of the GNU General Public License as published by the
Free Software Foundation; either version 3 of the License, or (at your
option) any later version.
