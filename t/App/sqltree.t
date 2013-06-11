use strict;
use warnings;
use App::sqltree;
use Cwd;
use Data::Dumper;
use File::Temp;
use Path::Tiny;
use Test::Database;
use Test::Fatal qw/exception/;
use Test::More;

$Data::Dumper::Indent   = 0;
$Data::Dumper::Maxdepth = 2;

$Test::App::sqltree::SHARE_DIR =
  path(__FILE__)->parent(3)->child('share')->absolute;

diag "\nshare is $Test::App::sqltree::SHARE_DIR";

my $table = 'items';
my $tree  = 'items_tree';

my $home = getcwd;
my $dir  = File::Temp->newdir;

chdir($dir) || die "chdir: $!";

END {
    chdir $home;
    $dir = undef;
}

my $dbh;

sub check {
    my $sql    = shift;
    my $args   = shift;
    my $struct = shift;
    my $name   = shift;

    my $result = $dbh->selectall_arrayref( $sql, undef, @$args );

    #        diag $sql;
    #        diag 'Wanted: '. Dumper( $struct );
    #        diag 'Got   : '. Dumper( $result );
    if ( !is_deeply( $result, $struct, $name ) ) {
        diag $sql;
        diag 'Wanted: ' . Dumper($struct);
        diag 'Got   : ' . Dumper($result);
    }
}

sub check_tree {
    my $sql    = shift;
    my $args   = shift;
    my $struct = shift;
    my $name   = shift;

    $dbh->do( $sql, undef, @$args );

    my $result = $dbh->selectall_arrayref( "
            select
                child,
                parent,
                depth
            from
                $tree
            order by
                depth,
                child,
                parent"
    );

    #        diag $sql;
    #        diag 'Wanted: '. Dumper( $struct );
    #        diag 'Got   : '. Dumper( $result );
    if ( !is_deeply( $result, $struct, $name ) ) {
        diag $sql;
        diag "Select: [child,parent,depth]";
        diag 'Wanted: ' . Dumper($struct);
        diag 'Got   : ' . Dumper($result);
    }
}

sub check_path {
    my $sql    = shift;
    my $args   = shift;
    my $struct = shift;
    my $name   = shift;

    eval { $dbh->do( $sql, undef, @$args ) };
    if ($@) {
        diag $sql;
        die $@;
    }
    my $result = $dbh->selectall_arrayref(
        "SELECT id,codename,parent,path
            FROM $table
            ORDER BY id
        "
    );

    if ( !is_deeply( $result, $struct, $name ) ) {
        diag $sql;
        diag "Select: [id,codename,parent,path]";
        diag 'Wanted: ' . Dumper($struct);
        diag 'Got   : ' . Dumper($result);
    }
}

my @handles = Test::Database->handles( 'SQLite', );    # { driver => 'Pg' } );

plan skip_all => 'No supported database drivers available'
  unless @handles;

foreach my $handle (@handles) {
    diag "Testing " . $handle->dbd();

    $dbh = DBI->connect(
        $handle->connection_info,
        {
            RaiseError         => 1,
            PrintError         => 0,
            PrintWarn          => 1,
            ShowErrorStatement => 1
        }
    );

    my %opts = (
        driver   => $handle->dbd,
        table    => $table,
        pk       => 'id',
        parent   => 'parent',
        type     => 'INTEGER',
        no_print => 1,
    );

    if ( $handle->dbd eq 'SQLite' ) {
        $dbh->do('PRAGMA foreign_keys = 1;');
        $dbh->do("PRAGMA recursive_triggers = ON;");
        $dbh->do('PRAGMA temp_store = MEMORY;');
        $dbh->do('PRAGMA synchronous = OFF;');
        $dbh->do("DROP TABLE IF EXISTS $table;");
    }
    elsif ( $handle->dbd eq 'Pg' ) {
        $dbh->do('SET client_min_messages = warning;');
        $dbh->do("DROP TABLE IF EXISTS $table CASCADE;");
    }

    $dbh->do( "
        CREATE TABLE $table(
            $opts{pk} $opts{type} primary key,
            $opts{parent} $opts{type} references $table($opts{pk}),
            codename text
        );" );

    $dbh->do($_) for App::sqltree::run( \%opts );

    check_tree(
        "INSERT INTO $table (id, codename) VALUES (?, ?);",
        [ 1, 'a' ],
        [ [ 1, 1, 0 ], ],
        'insert 1'
    );

    check_tree(
        "INSERT INTO $table (id, codename) VALUES (?, ?);",
        [ 2, 'b' ],
        [ [ 1, 1, 0 ], [ 2, 2, 0 ], ],
        'insert 2'
    );

    check_tree(
        "INSERT INTO $table (id, codename,parent) VALUES (?, ?, ?);",
        [ 3, 'c', 1 ],
        [ [ 1, 1, 0 ], [ 2, 2, 0 ], [ 3, 3, 0 ], [ 3, 1, 1 ], ],
        'insert 3'
    );

    check_tree(
        "INSERT INTO $table (id, codename,parent) VALUES (?, ?, ?);",
        [ 4, 'd', 2 ],
        [
            [ 1, 1, 0 ],
            [ 2, 2, 0 ],
            [ 3, 3, 0 ],
            [ 4, 4, 0 ],
            [ 3, 1, 1 ],
            [ 4, 2, 1 ],
        ],
        'insert 4'
    );

    check_tree(
        "INSERT INTO $table (id, codename,parent) VALUES (?, ?, ?);",
        [ 5, 'e', 3 ],
        [
            [ 1, 1, 0 ],
            [ 2, 2, 0 ],
            [ 3, 3, 0 ],
            [ 4, 4, 0 ],
            [ 5, 5, 0 ],
            [ 3, 1, 1 ],
            [ 4, 2, 1 ],
            [ 5, 3, 1 ],
            [ 5, 1, 2 ],
        ],
        'insert 5'
    );

    # Moving some child object to become top-level object
    check_tree(
        "UPDATE $table SET parent=NULL WHERE id=?;",
        [3],
        [
            [ 1, 1, 0 ],
            [ 2, 2, 0 ],
            [ 3, 3, 0 ],
            [ 4, 4, 0 ],
            [ 5, 5, 0 ],
            [ 4, 2, 1 ],
            [ 5, 3, 1 ],
        ],
        'update 1'
    );

    # Move some top-level object to become child object:
    check_tree(
        "UPDATE $table SET parent=5 WHERE id=?;",
        [2],
        [
            [ 1, 1, 0 ],
            [ 2, 2, 0 ],
            [ 3, 3, 0 ],
            [ 4, 4, 0 ],
            [ 5, 5, 0 ],
            [ 2, 5, 1 ],
            [ 4, 2, 1 ],
            [ 5, 3, 1 ],
            [ 2, 3, 2 ],
            [ 4, 5, 2 ],
            [ 4, 3, 3 ],
        ],
        'update 2'
    );

    # And the last way to update: move some child object under
    # new parent:

    check_tree(
        "UPDATE $table SET parent = 1 WHERE id = ?;",
        [5],
        [
            [ 1, 1, 0 ],
            [ 2, 2, 0 ],
            [ 3, 3, 0 ],
            [ 4, 4, 0 ],
            [ 5, 5, 0 ],
            [ 2, 5, 1 ],
            [ 4, 2, 1 ],
            [ 5, 1, 1 ],
            [ 2, 1, 2 ],
            [ 4, 5, 2 ],
            [ 4, 1, 3 ],
        ],
        'update 3'
    );

    check_tree(
        "UPDATE $table SET parent = 1 WHERE id = ?;",
        [5],
        [
            [ 1, 1, 0 ],
            [ 2, 2, 0 ],
            [ 3, 3, 0 ],
            [ 4, 4, 0 ],
            [ 5, 5, 0 ],
            [ 2, 5, 1 ],
            [ 4, 2, 1 ],
            [ 5, 1, 1 ],
            [ 2, 1, 2 ],
            [ 4, 5, 2 ],
            [ 4, 1, 3 ],
        ],
        'update 3'
    );

    check( "
        SELECT codename
        FROM $table o
        INNER JOIN $tree t
        ON o.id = t.parent
        WHERE t.child = ?
        ORDER BY t.depth DESC
    ", [1],
        [
            ['a'],
        ], 'select path as rows' );

    check( "
        SELECT codename
        FROM $table o
        INNER JOIN $tree t
        ON o.id = t.parent
        WHERE t.child = ?
        ORDER BY t.depth DESC
    ", [2],
        [
            ['a'],
            ['e'],
            ['b'],
        ], 'select path as rows 2' );

    like exception {
        $dbh->do( "UPDATE $table SET parent = 4 WHERE id = ?;", undef, 1 );
    }, qr/would create loop/, 'loop';

    like exception {
        $dbh->do( "UPDATE $table SET id = 9 WHERE id = ?;", undef, 2 );
    }, qr/Changing ids is forbidden/, 'id change';

    # path implementation
    if ( $handle->dbd eq 'SQLite' ) {
        $dbh->do("DROP TABLE IF EXISTS $table;");
        $dbh->do("DROP TABLE IF EXISTS $tree;");
    }

    if ( $handle->dbd eq 'Pg' ) {
        $dbh->do("DROP TABLE IF EXISTS $table CASCADE;");
    }

    $opts{path}      = 'path';
    $opts{path_from} = 'codename';

    $dbh->do( "
        CREATE TABLE $table(
            $opts{pk} $opts{type} primary key,
            $opts{parent} $opts{type} references $table($opts{pk}),
            codename text,
            path text
        );
    " );

    $dbh->do($_) for App::sqltree::run( \%opts );

    foreach my $vals (
        [ 1, 'a', undef ],
        [ 2, 'b', undef ],
        [ 3, 'c', 1 ],
        [ 4, 'd', 2 ],
        [ 5, 'e', 3 ]
      )
    {
        $dbh->do( "insert into $table(id,codename,parent) values(?,?,?)",
            {}, @$vals );
    }

    check( "
        SELECT id,codename,parent,path
        FROM $table
        ORDER BY id
    ",
        [],
        [
            [ 1, 'a', undef, 'a' ],
            [ 2, 'b', undef, 'b' ],
            [ 3, 'c', 1,     'a/c' ],
            [ 4, 'd', 2,     'b/d' ],
            [ 5, 'e', 3,     'a/c/e' ],
        ],
        'select auto generated path' );

    check_path(
        "UPDATE $table SET parent = NULL WHERE id = ?",
        [3],
        [
            [ 1, 'a', undef, 'a' ],
            [ 2, 'b', undef, 'b' ],
            [ 3, 'c', undef, 'c' ],
            [ 4, 'd', 2,     'b/d' ],
            [ 5, 'e', 3,     'c/e' ],
        ],
        'update path 1'
    );

    check_path(
        "UPDATE $table SET parent = 5 WHERE id = ?",
        [2],
        [
            [ 1, 'a', undef, 'a' ],
            [ 2, 'b', 5,     'c/e/b' ],
            [ 3, 'c', undef, 'c' ],
            [ 4, 'd', 2,     'c/e/b/d' ],
            [ 5, 'e', 3,     'c/e' ],
        ],
        'update path 2'
    );
    check_path(
        "UPDATE $table SET parent = 1 WHERE id = ?",
        [5],
        [
            [ 1, 'a', undef, 'a' ],
            [ 2, 'b', 5,     'a/e/b' ],
            [ 3, 'c', undef, 'c' ],
            [ 4, 'd', 2,     'a/e/b/d' ],
            [ 5, 'e', 1,     'a/e' ],
        ],
        'update path 3'
    );

    check( "
        select
          s.id,s.codename,s.path,max(t.depth) as depth
        from
          $table s
        inner join
          $tree t
        on
          s.id=t.child
        group by
          s.id,s.codename,s.path
        order by
          path; 
    ",
        [],
        [
            [ 1, 'a', 'a',       0 ],
            [ 5, 'e', 'a/e',     1 ],
            [ 2, 'b', 'a/e/b',   2 ],
            [ 4, 'd', 'a/e/b/d', 3 ],
            [ 3, 'c', 'c',       0 ]
        ],
        'select indented/hierarchical comments' );

    like exception {
        $dbh->do( "DELETE FROM $table WHERE id = ?;", undef, 5 );
    }, qr/constraint/, 'delete constraint - which one?';

    check_path(
        "DELETE FROM $table WHERE id = ?",
        [4],
        [
            [ 1, 'a', undef, 'a' ],
            [ 2, 'b', 5,     'a/e/b' ],
            [ 3, 'c', undef, 'c' ],
            [ 5, 'e', 1,     'a/e' ],
        ],
        'delete end node'
    );

    check_path(
        "UPDATE $table SET codename=? WHERE id = ?",
        [ 'x', 3 ],
        [
            [ 1, 'a', undef, 'a' ],
            [ 2, 'b', 5,     'a/e/b' ],
            [ 3, 'x', undef, 'x' ],
            [ 5, 'e', 1,     'a/e' ],
        ],
        'path rename single'
    );

    check_path(
        "UPDATE $table SET codename=? WHERE id = ?",
        [ 'y', 1 ],
        [
            [ 1, 'y', undef, 'y' ],
            [ 2, 'b', 5,     'y/e/b' ],
            [ 3, 'x', undef, 'x' ],
            [ 5, 'e', 1,     'y/e' ],
        ],
        'path rename top'
    );

    check_path(
        "UPDATE $table SET codename=? WHERE id = ?",
        [ 'z', 5 ],
        [
            [ 1, 'y', undef, 'y' ],
            [ 2, 'b', 5,     'y/z/b' ],
            [ 3, 'x', undef, 'x' ],
            [ 5, 'z', 1,     'y/z' ],
        ],
        'path rename middle'
    );

    check_path(
        "UPDATE $table SET codename=? WHERE id = ?",
        [ 't', 2 ],
        [
            [ 1, 'y', undef, 'y' ],
            [ 2, 't', 5,     'y/z/t' ],
            [ 3, 'x', undef, 'x' ],
            [ 5, 'z', 1,     'y/z' ],
        ],
        'path rename end'
    );

}

done_testing();
