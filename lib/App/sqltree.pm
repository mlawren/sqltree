package App::sqltree;
use strict;
use warnings;
use File::ShareDir qw/dist_dir/;
use IO::Prompt::Tiny qw/prompt/;
use OptArgs qw/arg opt optargs/;
use Path::Tiny qw/path/;
use Template::Tiny;

our $VERSION = '0.0.5_1';

arg driver => (
    isa     => 'Str',
    comment => 'database driver type (SQLite | Pg)',
);

arg table => (
    isa     => 'Str',
    comment => 'the table name',
);

arg pk => (
    isa     => 'Str',
    comment => 'the primary key column name',
);

arg parent => (
    isa     => 'Str',
    comment => 'the parent column name',
);

arg type => (
    isa     => 'Str',
    comment => 'the SQL type of the primary key and parent columns',
);

opt help => (
    isa     => 'Bool',
    comment => 'print a usage message and exit',
    alias   => 'h',
    ishelp  => 1,
);

opt path => (
    isa     => 'Str',
    comment => 'the path column name',
    alias   => 'p',
);

opt path_from => (
    isa     => 'Str',
    comment => 'the source of the path column calculation',
    alias   => 'f',
);

opt order => (
    isa     => 'Str',
    comment => 'the order column name',
    alias   => 'o',
);

opt no_print => (
    isa     => 'Bool',
    comment => 'do not print the output, just return it',
    hidden  => 1,
);

sub run {
    my $opts = shift;
    my $share_dir =
      path( $Test::App::sqltree::SHARE_DIR || dist_dir('SQL-Tree') );

    $opts->{driver} ||= prompt( 'Driver:', 'SQLite' );
    my $template = $share_dir->child( $opts->{driver} . '.sql' );
    die "Unsupported driver type: $opts->{driver}\n" unless -f $template;

    $opts->{table}  ||= prompt( 'Table:',                 'items' );
    $opts->{pk}     ||= prompt( 'Primary Key Column:',    'id' );
    $opts->{parent} ||= prompt( 'Parent Column:',         'parent_id' );
    $opts->{type}   ||= prompt( 'PK/Parent Column Type:', 'integer' );

    $opts->{tree} = $opts->{table} . '_tree';

    my $tt  = Template::Tiny->new;
    my $src = $template->slurp_utf8;
    my $sql;

    $tt->process( \$src, $opts, \$sql );

    if ( $opts->{no_print} ) {
        return split( /^--SPLIT--$/m, $sql );
    }
    else {
        $sql =~ s/^--SPLIT--$//mg;
        print $sql;
    }
}

1;
__END__


=head1 NAME

App::sqltree - implementation of the sqltree command

=head1 VERSION

0.0.5_1 (2013-06-12)

=head1 SYNOPSIS

    # Via OptArgs
    use OptArgs 'dispatch';
    dispatch(qw/run App::sqltree/);

    # Or directly
    use App::sqltree;

    my @sql = App::sqltree::run(
        {
            no_print => 1,
            driver   => 'SQLite',
            table    => 'items',
            pk       => 'id',
            parent   => 'parent_id',
            type     => 'integer',
        }
    );

=head1 DESCRIPTION

This is the implementation module for the L<sqltree> command.

=head1 SEE ALSO

L<OptArgs>, L<sqltree>

=head1 AUTHOR

Mark Lawrence E<lt>nomad@null.netE<gt>

=head1 COPYRIGHT AND LICENSE

Copyright (C) 2010,2013 Mark Lawrence E<lt>nomad@null.netE<gt>

This program is free software; you can redistribute it and/or modify it
under the terms of the GNU General Public License as published by the
Free Software Foundation; either version 3 of the License, or (at your
option) any later version.

