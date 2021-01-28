package SQL::Tree;
use strict;
use warnings;
use Carp ();
use File::Basename;
use File::ShareDir::Dist 'dist_share';
use File::Spec;
use Template::Tiny;

our $VERSION = '0.05';
our $INLINE  = {
    comments      => {},
    driver        => { required => 1, },
    drop          => {},
    id            => { required  => 1, },
    name          => { predicate => 1, },
    parent_id     => { required  => 1, },
    path          => { predicate => 1, },
    postfix       => { required  => 1, },
    separator     => { predicate => 1, },
    table         => { required  => 1, },
    template_file => {
        lazy    => 0,
        default => sub {
            my $self = shift;
            my $file =
              File::Spec->catfile( dist_share('SQL-Tree'),
                $self->driver . '.sqlt' );
            Carp::croak 'unsupported driver: ' . $self->driver unless -f $file;

            $file;
        },
    },
    type => { required => 1, },
    ref  => {
        default => sub {
            my $self = shift;
            my $ref  = {
                id        => $self->id,
                drop      => $self->drop,
                localtime => scalar localtime(),
                name      => $self->name,
                parent_id => $self->parent_id,
                path      => $self->path,
                program   => __PACKAGE__,
                separator => $self->has_separator
                ? $self->separator =~ s/'/''/gr
                : undef,
                table      => $self->table,
                table_tree => $self->table . $self->postfix,
                type       => $self->type,
                version    => $VERSION,
            };
        },
    },
};

sub BUILD {
    my $self = shift;
    Carp::croak 'path requires a name'
      if $self->has_path and not $self->has_name;
}

sub generate {
    my $self = shift;

    open my $fh, '<', $self->template_file or die 'open: ' . $!;
    my $sqlt = do { local $/; <$fh> };
    close $fh;

    my $tt = Template::Tiny->new( TRIM => 0, );
    $tt->process( \$sqlt, $self->ref, \my $output );
    $output;
}

### DO NOT EDIT BELOW! (generated by Class::Inline v0.0.1)
#<<<
  require Carp;our@ATTRS_UNEX=(undef);sub _dump {my$self=shift;require
  Data::Dumper;no warnings 'once';local$Data::Dumper::Indent=1;local
  $Data::Dumper::Maxdepth=1;my$x=Data::Dumper::Dumper($self);$x =~
  s/^.*?\n(.*)\n.*?\n/$1/s;Carp::carp$self ."\n".$x ."\n "}sub new {my$class=
  shift;my$self={@_ ? @_ > 1 ? @_ : %{$_[0]}: ()};map {local$Carp::CarpLevel=(
  $Carp::CarpLevel//0)+ 1;Carp::croak(
  "missing attribute SQL::Tree::$_ is required")unless exists$self->{$_}}
  'driver','id','parent_id','postfix','table','type';if (@ATTRS_UNEX){map {
  local$Carp::CarpLevel=$Carp::CarpLevel + 1;Carp::carp(
  "SQL::Tree attribute '$_' unexpected");delete$self->{$_ }}sort grep {not
  exists$INLINE->{$_ }}keys %$self}else {@ATTRS_UNEX=map {delete$self->{$_ };
  $_}grep {not exists$INLINE->{$_ }}keys %$self}bless$self,ref$class || $class
  ;$self->{'template_file'}//= $INLINE->{'template_file'}->{'default'}->($self
  );my@check=('SQL::Tree');my@parents;while (@check){no strict 'refs';my$c=
  shift@check;push@parents,@{$c .'::ISA'};push@check,@{$c .'::ISA'}}map {$_->
  BUILD()if exists &{$_.'::BUILD'}}reverse@parents;$self->BUILD()if exists &{
  'BUILD'};$self}sub __ro {my (undef,undef,undef,$sub)=caller(1);local
  $Carp::CarpLevel=$Carp::CarpLevel + 1;Carp::croak(
  "attribute $sub is read-only (value: '" .($_[1]// 'undef')."')")}sub
  comments {$_[0]->__ro($_[1])if @_ > 1;$_[0]{'comments'}// undef}sub driver {
  $_[0]->__ro($_[1])if @_ > 1;$_[0]{'driver'}}sub drop {$_[0]->__ro($_[1])if
  @_ > 1;$_[0]{'drop'}// undef}sub id {$_[0]->__ro($_[1])if @_ > 1;$_[0]{'id'}
  }sub name {$_[0]->__ro($_[1])if @_ > 1;$_[0]{'name'}// undef}sub has_name {
  exists $_[0]{'name'}};sub parent_id {$_[0]->__ro($_[1])if @_ > 1;$_[0]{
  'parent_id'}}sub path {$_[0]->__ro($_[1])if @_ > 1;$_[0]{'path'}// undef}sub
  has_path {exists $_[0]{'path'}};sub postfix {$_[0]->__ro($_[1])if @_ > 1;$_[
  0]{'postfix'}}sub ref {$_[0]->__ro($_[1])if @_ > 1;$_[0]{'ref'}//= $INLINE->
  {'ref'}->{'default'}->($_[0])}sub separator {$_[0]->__ro($_[1])if @_ > 1;$_[
  0]{'separator'}// undef}sub has_separator {exists $_[0]{'separator'}};sub
  table {$_[0]->__ro($_[1])if @_ > 1;$_[0]{'table'}}sub template_file {$_[0]->
  __ro($_[1])if @_ > 1;$_[0]{'template_file'}}sub type {$_[0]->__ro($_[1])if
  @_ > 1;$_[0]{'type'}}
#>>>
### DO NOT EDIT ABOVE! (generated by Class::Inline v0.0.1)

1;

__END__

=head1 NAME

SQL::Tree - Generate a trigger-based SQL tree implementation

=head1 VERSION

0.05 (2021-01-28)

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
