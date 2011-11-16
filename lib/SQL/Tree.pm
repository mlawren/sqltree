package SQL::Tree;
use strict;
use warnings;
use base qw/Exporter/;
use Carp qw/confess/;

our $VERSION   = '0.03';
our @EXPORT_OK = qw/generate_sql_tree/;

sub generate_sql_tree {
    my %opts = ( @_, );

    my $dbtype = delete $opts{dbtype};

    if ( $dbtype =~ m/SQLite/ ) {
        return generate_SQLite(%opts);
    }
    elsif ( $dbtype =~ m/Pg/ ) {
        return generate_Pg(%opts);
    }

    confess 'dbtype must be SQLite or Pg';
}

sub generate_SQLite {
    my %opts = ( @_, );

    my $table  = $opts{table}  || confess 'usage: generate needs table';
    my $pk     = $opts{pk}     || confess 'usage: generate needs pk';
    my $pktype = $opts{pktype} || confess 'usage: generate needs pktype';
    my $parent = $opts{parent} || confess 'usage: generate needs parent';
    my $path   = $opts{path};
    my $path_from = $opts{path_from};

    if ( $path and !$path_from ) {
        confess 'usage: generate needs both path and path_from';
    }

    my $tree_table = $table . '_tree';

    my @SQL;

    $opts{drop} && push(
        @SQL, split /\n\n+/, qq[
DROP TABLE IF EXISTS $tree_table;

DROP TRIGGER IF EXISTS ${tree_table}_insert_trigger_1;

DROP TRIGGER IF EXISTS ${tree_table}_update_trigger_1;

DROP TRIGGER IF EXISTS ${tree_table}_update_trigger_2;

DROP TRIGGER IF EXISTS ${tree_table}_update_trigger_3;

DROP TRIGGER IF EXISTS ${tree_table}_update_trigger_4;

DROP TRIGGER IF EXISTS ${tree_table}_update_trigger_r5;
]
    );

    push(
        @SQL, split /\n\n+/, qq[
CREATE TABLE $tree_table (
    treeid    INTEGER PRIMARY KEY,
    parent    $pktype NOT NULL REFERENCES $table($pk) ON DELETE CASCADE,
    child     $pktype NOT NULL REFERENCES $table($pk) ON DELETE CASCADE,
    depth     INTEGER NOT NULL,
    UNIQUE (parent, child)
);
-- --------------------------------------------------------------------
-- INSERT:
-- 1. Insert a matching row in $tree_table where both parent and child
-- are set to the id of the newly inserted object. Depth is set to 0 as
-- both child and parent are on the same level.
--
-- 2. Copy all rows that our parent had as its parents, but we modify
-- the child id in these rows to be the id of currently inserted row,
-- and increase depth by one.
-- --------------------------------------------------------------------
]
    );

    $path && push(
        @SQL, split /\n\n+/, qq[
CREATE TRIGGER ai_${table}_path_2 AFTER INSERT ON $table
FOR EACH ROW WHEN NEW.$parent IS NULL
BEGIN
    UPDATE $table
    SET $path = $path_from
    WHERE $pk = NEW.$pk;
END;

CREATE TRIGGER ai_${table}_path_1 AFTER INSERT ON $table
FOR EACH ROW WHEN NEW.$parent IS NOT NULL
BEGIN
    UPDATE $table
    SET $path = (
        SELECT $path || '/' || NEW.$path_from
        FROM $table
        WHERE $pk = NEW.$parent
    )
    WHERE $pk = NEW.$pk;
END;
]
    );

    push(
        @SQL, split /\n\n+/, qq[
CREATE TRIGGER ai_${table}_tree_1 AFTER INSERT ON $table
FOR EACH ROW 
BEGIN
    INSERT INTO $tree_table (parent, child, depth)
        VALUES (NEW.$pk, NEW.$pk, 0);
    INSERT INTO $tree_table (parent, child, depth)
        SELECT x.parent, NEW.$pk, x.depth + 1
            FROM $tree_table x
            WHERE x.child = NEW.$parent;
END;
-- --------------------------------------------------------------------
-- UPDATE:
--
-- Triggers in SQLite are apparently executed LIFO, so you need to read
-- these trigger statements from the bottom up.
-- --------------------------------------------------------------------
]
    );

    $path && push(
        @SQL, split /\n\n+/, qq[
-- Paths - update all affected rows with the new parent path
CREATE TRIGGER au_${table}_path_2 AFTER UPDATE ON $table
FOR EACH ROW WHEN NEW.$parent IS NOT NULL
BEGIN
    UPDATE $table
    SET $path = (
        SELECT $path
        FROM $table
        WHERE $pk = NEW.$parent
    ) || '/' || $path
    WHERE $pk IN (
        SELECT child
        FROM $tree_table
        WHERE parent = NEW.$parent AND depth > 0
    );
END;
]
    );

    push(
        @SQL, split /\n\n+/, qq[
-- Finally, insert tree data relating to the new parent
CREATE TRIGGER au_${table}_tree_5 AFTER UPDATE ON $table
FOR EACH ROW WHEN NEW.$parent IS NOT NULL
BEGIN
    INSERT INTO $tree_table (parent, child, depth)
    SELECT r1.parent, r2.child, r1.depth + r2.depth + 1
    FROM
        $tree_table r1
    INNER JOIN
        $tree_table r2
    ON
        r2.parent = NEW.$pk
    WHERE
        r1.child = NEW.$parent
    ;
END;

-- Remove the tree data relating to the old parent
CREATE TRIGGER au_${table}_tree_4 AFTER UPDATE ON $table
FOR EACH ROW WHEN OLD.$parent IS NOT NULL
BEGIN
    DELETE FROM $tree_table WHERE treeid in (
        SELECT r2.treeid
        FROM
            $tree_table r1
        INNER JOIN
            $tree_table r2
        ON
            r1.child = r2.child AND r2.depth > r1.depth
        WHERE r1.parent = NEW.$pk
    );
END;
-- FIXME: Also trigger when column 'path_from' changes. For the
-- moment, the user work-around is to temporarily re-parent the row.
]
    );

    $path && push(
        @SQL, split /\n\n+/, qq[
-- path changes - Remove the leading paths of the old parent. This has
-- to happen before we make changes to $tree_table.
CREATE TRIGGER au_${table}_path_1 AFTER UPDATE ON $table
FOR EACH ROW WHEN OLD.$parent IS NOT NULL
BEGIN
    UPDATE $table
    SET $path = substr($path, (
        SELECT length($path || '/') + 1
        FROM $table
        WHERE $pk = OLD.$parent
    ))
    WHERE $pk IN (
        SELECT child
        FROM $tree_table
        WHERE parent = OLD.$parent AND depth > 0
    );
END;
]
    );

    push(
        @SQL, split /\n\n+/, qq[
-- If there was no change to the parent then we can skip the rest of
-- the triggers
CREATE TRIGGER au_${table}_tree_2 AFTER UPDATE ON $table
FOR EACH ROW WHEN
    (OLD.$parent IS NULL AND NEW.$parent IS NULL) OR
    ((OLD.$parent IS NOT NULL and NEW.$parent IS NOT NULL) AND
     (OLD.$parent = NEW.$parent))
BEGIN
    SELECT RAISE (IGNORE);
END;

-- As for moving data around in $table freely, we should forbid
-- moves that would create loops:
CREATE TRIGGER bu_${table}_tree_2 BEFORE UPDATE ON $table
FOR EACH ROW WHEN NEW.$parent IS NOT NULL AND
    (SELECT
        COUNT(child)
     FROM $tree_table
     WHERE child = NEW.$parent AND parent = NEW.$pk) > 0
BEGIN
    SELECT RAISE (ABORT,
        'Update blocked, because it would create loop in tree.');
END;

-- This implementation forbids changes to the primary key
CREATE TRIGGER bu_${table}_tree_1 BEFORE UPDATE ON $table
FOR EACH ROW WHEN OLD.$pk != NEW.$pk
BEGIN
    SELECT RAISE (ABORT, 'Changing ids is forbidden.');
END;
]
    );

    return @SQL;
}

sub generate_Pg {
    my %opts = ( @_, );

    my $table  = $opts{table}  || confess 'usage: generate needs table';
    my $pk     = $opts{pk}     || confess 'usage: generate needs pk';
    my $pktype = $opts{pktype} || confess 'usage: generate needs pktype';
    my $parent = $opts{parent} || confess 'usage: generate needs parent';
    my $path   = $opts{path};
    my $path_from = $opts{path_from};

    if ( $path and !$path_from ) {
        confess 'usage: generate needs both path and path_from';
    }

    my $tree_table = $table . '_tree';

    my @SQL;

    $opts{drop} && push(
        @SQL, split /\n\n+/, qq[
DROP TABLE IF EXISTS $tree_table;

DROP TRIGGER IF EXISTS ${tree_table}_insert_trigger_1 ON $table;

DROP TRIGGER IF EXISTS ${tree_table}_before_update_trigger_1 ON $table;

DROP TRIGGER IF EXISTS ${tree_table}_after_update_trigger_1 ON $table;

DROP TRIGGER IF EXISTS ${tree_table}_path_before_update_trigger ON $table;
]
    );

    push(
        @SQL, split /\n\n+/, qq[
CREATE OR REPLACE FUNCTION make_plpgsql()
RETURNS VOID
LANGUAGE SQL
AS \$\$
CREATE LANGUAGE plpgsql;
\$\$;

SELECT
    CASE
    WHEN EXISTS(
        SELECT 1
        FROM pg_catalog.pg_language
        WHERE lanname='plpgsql'
    )
    THEN NULL
    ELSE make_plpgsql()
    END;
 
DROP FUNCTION make_plpgsql();

CREATE TABLE $tree_table (
    treeid    SERIAL PRIMARY KEY,
    parent    $pktype NOT NULL REFERENCES $table($pk) ON DELETE CASCADE,
    child     $pktype NOT NULL REFERENCES $table($pk) ON DELETE CASCADE,
    depth     INTEGER NOT NULL,
    UNIQUE (parent, child)
);

-- --------------------------------------------------------------------
-- INSERT:
-- 1. Insert a matching row in $tree_table where both parent and child
-- are set to the id of the newly inserted object. Depth is set to 0 as
-- both child and parent are on the same level.
--
-- 2. Copy all rows that our parent had as its parents, but we modify
-- the child id in these rows to be the id of currently inserted row,
-- and increase depth by one.
-- --------------------------------------------------------------------
CREATE OR REPLACE FUNCTION ai_${table}_tree_1() RETURNS TRIGGER AS
\$BODY\$
DECLARE
BEGIN
    INSERT INTO $tree_table (parent, child, depth)
        VALUES (NEW.$pk, NEW.$pk, 0);
    INSERT INTO $tree_table (parent, child, depth)
        SELECT x.parent, NEW.$pk, x.depth + 1
            FROM $tree_table x
            WHERE x.child = NEW.$parent;
    RETURN NEW;
END;
\$BODY\$
LANGUAGE 'plpgsql';

CREATE TRIGGER ai_${table}_tree_1 AFTER INSERT ON $table
FOR EACH ROW EXECUTE PROCEDURE ai_${table}_tree_1();

-- --------------------------------------------------------------------
-- UPDATE:
-- --------------------------------------------------------------------
-- As for moving data around in $table freely, we should forbid
-- moves that would create loops:
CREATE OR REPLACE FUNCTION bu_${table}_tree_1() RETURNS TRIGGER AS
\$BODY\$
DECLARE
BEGIN
    IF NEW.$pk <> OLD.$pk THEN
        RAISE EXCEPTION 'Changing ids is forbidden.';
    END IF;
    IF OLD.$parent IS NOT DISTINCT FROM NEW.$parent THEN
        RETURN NEW;
    END IF;
    IF NEW.$parent IS NULL THEN
        RETURN NEW;
    END IF;
    PERFORM 1 FROM $tree_table
        WHERE ( parent, child ) = ( NEW.$pk, NEW.$parent );
    IF FOUND THEN
        RAISE EXCEPTION 'Update blocked, because it would create loop in tree.';
    END IF;
    RETURN NEW;
END;
\$BODY\$
LANGUAGE 'plpgsql';

CREATE TRIGGER bu_${table}_tree_1 BEFORE UPDATE ON $table
FOR EACH ROW EXECUTE PROCEDURE bu_${table}_tree_1();

CREATE OR REPLACE FUNCTION au_${table}_tree_1() RETURNS TRIGGER AS
\$BODY\$
DECLARE
BEGIN
    IF OLD.$parent IS NOT DISTINCT FROM NEW.$parent THEN
        RETURN NEW;
    END IF;
    IF OLD.$parent IS NOT NULL THEN
        DELETE FROM $tree_table WHERE treeid in (
            SELECT r2.treeid
            FROM $tree_table r1
            JOIN $tree_table r2 ON r1.child = r2.child
            WHERE r1.parent = NEW.$pk AND r2.depth > r1.depth
        );
    END IF;
    IF NEW.$parent IS NOT NULL THEN
        INSERT INTO $tree_table (parent, child, depth)
            SELECT r1.parent, r2.child, r1.depth + r2.depth + 1
            FROM
                $tree_table r1,
                $tree_table r2
            WHERE
                r1.child = NEW.$parent AND
                r2.parent = NEW.$pk;
    END IF;
    RETURN NEW;
END;
\$BODY\$
LANGUAGE 'plpgsql';

CREATE TRIGGER au_${table}_tree_1 AFTER UPDATE ON $table
FOR EACH ROW EXECUTE PROCEDURE au_${table}_tree_1();
]
    );

    $path && push(
        @SQL, split /\n\n+/, qq[
-- Generate path urls based on $path_from and position in
-- the tree. 
CREATE OR REPLACE FUNCTION bi_${table}_path_1()
RETURNS TRIGGER AS
\$BODY\$
DECLARE
BEGIN
    IF NEW.$parent IS NULL THEN
        NEW.$path := NEW.$path_from;
    ELSE
        SELECT $path || '/' || NEW.$path_from INTO NEW.$path
        FROM $table
        WHERE $pk = NEW.$parent;
    END IF;
    RETURN NEW;
END;
\$BODY\$
LANGUAGE 'plpgsql';

CREATE TRIGGER bi_${table}_path_1 BEFORE INSERT ON $table
FOR EACH ROW EXECUTE PROCEDURE bi_${table}_path_1();

CREATE OR REPLACE FUNCTION bu_${table}_path_1()
RETURNS TRIGGER AS
\$BODY\$
DECLARE
    replace_from TEXT := '^';
    replace_to   TEXT := '';
BEGIN
    IF OLD.$parent IS NOT DISTINCT FROM NEW.$parent THEN
        RETURN NEW;
    END IF;
    IF OLD.$parent IS NOT NULL THEN
        SELECT '^' || $path || '/' INTO replace_from
        FROM $table
        WHERE $pk = OLD.$parent;
    END IF;
    IF NEW.$parent IS NOT NULL THEN
        SELECT $path || '/' INTO replace_to
        FROM $table
        WHERE $pk = NEW.$parent;
    END IF;
    NEW.$path := regexp_replace( NEW.$path, replace_from, replace_to );
    UPDATE $table
    SET $path = regexp_replace($path, replace_from, replace_to )
    WHERE $pk in (
        SELECT child
        FROM $tree_table
        WHERE parent = NEW.$pk AND depth > 0
    );
    RETURN NEW;
END;
\$BODY\$
LANGUAGE 'plpgsql';

CREATE TRIGGER bu_${table}_path_1 BEFORE UPDATE ON $table
FOR EACH ROW EXECUTE PROCEDURE bu_${table}_path_1();
]
    );

    return @SQL;

}

1;
__END__

-- Now, I promised that I will tell you why we need record with depth 0 and why we need depth column.
-- Let's assume our $table are categories. And we have some products in these categories. Like this:

CREATE TABLE products (
    id          $pktype PRIMARY KEY,
    category_id $pktype NOT NULL REFERENCES $table (id),
    ...
);

-- It is quite common to ask database for all products in given category and it's subcategories.
-- Now, I can simply:

SELECT
    p.*
FROM
    products p
    join $tree_table c on p.category_id = c.id
WHERE
    c.parent = <SOME_ID>;

-- And why do we need depth column?
-- Let's stay with this categories example. When user is <i>in</i> some category, we would like to show him <i>path</i> to this category. So he could easily move to some parent category.
-- Now, it's pretty simple:

SELECT
    o.*
FROM
    $table o
    join $tree_table t on o.id = t.parent
WHERE
    t.id = 4
ORDER BY
    t.depth DESC;


-- Now. Another task for our tree. Let's say we want to generate urls for categories based on their codenames and position in tree.
-- For this I will need another field in $table table. This field will never be null, but I can't make it 'not null', as this would force application to put some data there.

ALTER TABLE $table add column tree_path TEXT;

CREATE OR REPLACE FUNCTION tree_path_${table}_bi() RETURNS TRIGGER AS
$BODY$
DECLARE
BEGIN
    IF NEW.$parent IS NULL THEN
        NEW.tree_path := NEW.codename;
    ELSE
        SELECT tree_path || '/' || NEW.codename INTO NEW.tree_path FROM $table WHERE id = NEW.$parent;
    END IF;
    RETURN NEW;
END;
$BODY$
LANGUAGE 'plpgsql';
CREATE TRIGGER tree_path_${table}_bi BEFORE INSERT ON $table FOR EACH ROW EXECUTE PROCEDURE tree_path_${table}_bi();

CREATE OR REPLACE FUNCTION tree_path_${table}_bu() RETURNS TRIGGER AS
$BODY$
DECLARE
    replace_from TEXT := '^';
    replace_to   TEXT := '';
BEGIN
    IF NOT OLD.$parent IS distinct FROM NEW.$parent THEN
        RETURN NEW;
    END IF;
    IF OLD.$parent IS NOT NULL THEN
        SELECT '^' || tree_path || '/' INTO replace_from FROM $table WHERE id = OLD.$parent;
    END IF;
    IF NEW.$parent IS NOT NULL THEN
        SELECT tree_path || '/' INTO replace_to FROM $table WHERE id = NEW.$parent;
    END IF;
    NEW.tree_path := regexp_replace( NEW.tree_path, replace_from, replace_to );

    UPDATE $table SET tree_path = regexp_replace(tree_path, replace_from, replace_to ) WHERE id in (SELECT id FROM $tree_table WHERE parent = NEW.$pk AND depth > 0);

    RETURN NEW;
END;
$BODY$
LANGUAGE 'plpgsql';
CREATE TRIGGER tree_path_${table}_bu BEFORE UPDATE ON $table FOR EACH ROW EXECUTE PROCEDURE tree_path_${table}_bu();


DELETE FROM $table;
INSERT INTO $table (id, codename, parent) VALUES (1, 'a', NULL), (2, 'b', NULL), (3, 'c', 1), (4, 'd', 2), (5, 'e', 3);

SELECT * FROM $table;
--  id | codename | printable_name | some_property | parent | tree_path
-- ----+----------+----------------+---------------+-----------+-----------
--   1 | a        | [null]         |        [null] |    [null] | a
--   2 | b        | [null]         |        [null] |    [null] | b
--   3 | c        | [null]         |        [null] |         1 | a/c
--   4 | d        | [null]         |        [null] |         2 | b/d
--   5 | e        | [null]         |        [null] |         3 | a/c/e

UPDATE $table SET parent = NULL WHERE id = 3;
UPDATE $table SET parent = 5 WHERE id = 2;
UPDATE $table SET parent = 1 WHERE id = 5;
SELECT * FROM $table;
--  id | codename | printable_name | some_property | parent | tree_path
-- ----+----------+----------------+---------------+-----------+-----------
--   1 | a        | [null]         |        [null] |    [null] | a
--   3 | c        | [null]         |        [null] |    [null] | c
--   2 | b        | [null]         |        [null] |         5 | a/e/b
--   4 | d        | [null]         |        [null] |         2 | a/e/b/d
--   5 | e        | [null]         |        [null] |         1 | a/e

SELECT id, tree_path, codename, parent FROM $table ORDER BY tree_path;
--  id | tree_path | codename | parent
-- ----+-----------+----------+-----------
--   1 | a         | a        |    [null]
--   5 | a/e       | e        |         1
--   2 | a/e/b     | b        |         5
--   4 | a/e/b/d   | d        |         2
--   3 | c         | c        |    [null]

INSERT INTO $table (id, codename, parent) VALUES (6, 'f', 3), (7, 'g', 3), (8, 'h', 6), (9, 'i', 7), (10, 'j', 8);

SELECT id, tree_path, codename, parent FROM $table ORDER BY tree_path;
--  id | tree_path | codename | parent
-- ----+-----------+----------+-----------
--   1 | a         | a        |    [null]
--   5 | a/e       | e        |         1
--   2 | a/e/b     | b        |         5
--   4 | a/e/b/d   | d        |         2
--   3 | c         | c        |    [null]
--   6 | c/f       | f        |         3
--   8 | c/f/h     | h        |         6
--  10 | c/f/h/j   | j        |         8
--   7 | c/g       | g        |         3
--   9 | c/g/i     | I        |         7

(10 rows)
-- Nice. But what if I'd like to have c/g <b>before</b> c/f ?
-- This will require input from user/application &#8211; saying what order should we have.
-- Now. We'd like to keep it as simple as possible, both in selects and in writes. To make it as simple we will make this field unique. We could make it unique in pair (parent, ordering), but then moving $table in tree would become difficult.
-- So, next modification of our table:

ALTER TABLE $table add ordering $pktype UNIQUE;

-- Now. This field really shouldn't be null &#8211; otherwise we could get 2 elements with null ordering, and we wouldn't be able to unambiguously order them.
-- So, let's:

UPDATE $table SET ordering = id;
ALTER TABLE $table ALTER column ordering SET NOT NULL;

Now. It's great that we have this field, but sorting with it will be at the very least tedious.
What I mean. While getting all children of given object, ordered, is simple:
select * from $table where parent = 3 order by ordering;
There is next-to-no way to get it properly sorted for whole tree at once.
To allow sorting of whole tree (or just some branch) we need to add new column, also trigger-filled, which will be used for sorting. This field will be globally unique (just like tree_path):

ALTER TABLE $table add column ordering_path TEXT UNIQUE;
-- This field will be filled by these triggers:
CREATE OR REPLACE FUNCTION tree_ordering_path_${table}_bi() RETURNS TRIGGER AS
$BODY$
DECLARE
BEGIN
    IF NEW.$parent IS NULL THEN
        NEW.ordering_path := to_char(NEW.ordering, '000000000000');

    ELSE
        SELECT ordering_path || '/' || to_char(NEW.ordering, '000000000000') INTO NEW.ordering_path FROM $table WHERE id = NEW.$parent;
    END IF;
    RETURN NEW;
END;
$BODY$
LANGUAGE 'plpgsql';
CREATE TRIGGER tree_ordering_path_${table}_bi BEFORE INSERT ON $table FOR EACH ROW EXECUTE PROCEDURE tree_ordering_path_${table}_bi();

CREATE OR REPLACE FUNCTION tree_ordering_path_${table}_bu() RETURNS TRIGGER AS
$BODY$
DECLARE
BEGIN
    IF OLD.ordering = NEW.ordering THEN
        RETURN NEW;
    END IF;
    IF NEW.$parent IS NULL THEN
        NEW.ordering_path := to_char(NEW.ordering, '000000000000');

    ELSE
        SELECT ordering_path || '/' || to_char(NEW.ordering, '000000000000') INTO NEW.ordering_path FROM $table WHERE id = NEW.$parent;
    END IF;
    UPDATE $table SET ordering_path = regexp_replace(ordering_path, '^' || OLD.ordering_path, NEW.ordering_path )
        WHERE id in (SELECT id FROM $tree_table WHERE parent = NEW.$pk AND depth > 0);

    RETURN NEW;
END;
$BODY$
LANGUAGE 'plpgsql';
CREATE TRIGGER tree_ordering_path_${table}_bu BEFORE UPDATE ON $table FOR EACH ROW EXECUTE PROCEDURE tree_ordering_path_${table}_bu();

DELETE FROM $table;
INSERT INTO $table (id, codename, parent, ordering) VALUES
    (1, 'a', NULL, 100),
    (2, 'b', NULL, 200),
    (3, 'c', 1, 300),
    (4, 'd', 2, 400),
    (5, 'e', 3, 500),
    (6, 'f', 3, 600),
    (7, 'g', 3, 700),
    (8, 'h', 6, 800),
    (9, 'i', 7, 900),
    (10, 'j', 8, 1000);

SELECT id, tree_path, ordering_path, ordering FROM $table ORDER BY ordering_path;
--  id | tree_path |                             ordering_path                             | ordering
-- ----+-----------+-----------------------------------------------------------------------+----------
--   1 | a         |  000000000100                                                         |      100
--   3 | a/c       |  000000000100/ 000000000300                                           |      300
--   5 | a/c/e     |  000000000100/ 000000000300/ 000000000500                             |      500
--   6 | a/c/f     |  000000000100/ 000000000300/ 000000000600                             |      600
--   8 | a/c/f/h   |  000000000100/ 000000000300/ 000000000600/ 000000000800               |      800
--  10 | a/c/f/h/j |  000000000100/ 000000000300/ 000000000600/ 000000000800/ 000000001000 |     1000
--   7 | a/c/g     |  000000000100/ 000000000300/ 000000000700                             |      700
--   9 | a/c/g/i   |  000000000100/ 000000000300/ 000000000700/ 000000000900               |      900
--   2 | b         |  000000000200                                                         |      200
--   4 | b/d       |  000000000200/ 000000000400                                           |      400

UPDATE $table SET ordering = 550 WHERE id = 7;
SELECT id, tree_path, ordering_path, ordering FROM $table ORDER BY ordering_path;
--  id | tree_path |                             ordering_path                             | ordering
-- ----+-----------+-----------------------------------------------------------------------+----------
--   1 | a         |  000000000100                                                         |      100
--   3 | a/c       |  000000000100/ 000000000300                                           |      300
--   5 | a/c/e     |  000000000100/ 000000000300/ 000000000500                             |      500
--   7 | a/c/g     |  000000000100/ 000000000300/ 000000000550                             |      550
--   9 | a/c/g/i   |  000000000100/ 000000000300/ 000000000550/ 000000000900               |      900
--   6 | a/c/f     |  000000000100/ 000000000300/ 000000000600                             |      600
--   8 | a/c/f/h   |  000000000100/ 000000000300/ 000000000600/ 000000000800               |      800
--  10 | a/c/f/h/j |  000000000100/ 000000000300/ 000000000600/ 000000000800/ 000000001000 |     1000
--   2 | b         |  000000000200                                                         |      200
--   4 | b/d       |  000000000200/ 000000000400                                           |      400

UPDATE $table SET ordering = 50 WHERE id = 2;
SELECT id, tree_path, ordering_path, ordering FROM $table ORDER BY ordering_path;
--  id | tree_path |                             ordering_path                             | ordering
-- ----+-----------+-----------------------------------------------------------------------+----------
--   2 | b         |  000000000050                                                         |       50
--   4 | b/d       |  000000000050/ 000000000400                                           |      400
--   1 | a         |  000000000100                                                         |      100
--   3 | a/c       |  000000000100/ 000000000300                                           |      300
--   5 | a/c/e     |  000000000100/ 000000000300/ 000000000500                             |      500
--   7 | a/c/g     |  000000000100/ 000000000300/ 000000000550                             |      550
--   9 | a/c/g/i   |  000000000100/ 000000000300/ 000000000550/ 000000000900               |      900
--   6 | a/c/f     |  000000000100/ 000000000300/ 000000000600                             |      600
--   8 | a/c/f/h   |  000000000100/ 000000000300/ 000000000600/ 000000000800               |      800
--  10 | a/c/f/h/j |  000000000100/ 000000000300/ 000000000600/ 000000000800/ 000000001000 |     1000

UPDATE $table SET ordering = 5 WHERE id = 1;
SELECT id, tree_path, ordering_path, ordering FROM $table ORDER BY ordering_path;
-- id | tree_path |                             ordering_path                             | ordering
------+-----------+-----------------------------------------------------------------------+----------
--  1 | a         |  000000000005                                                         |        5
--  3 | a/c       |  000000000005/ 000000000300                                           |      300
--  5 | a/c/e     |  000000000005/ 000000000300/ 000000000500                             |      500
--  7 | a/c/g     |  000000000005/ 000000000300/ 000000000550                             |      550
--  9 | a/c/g/i   |  000000000005/ 000000000300/ 000000000550/ 000000000900               |      900
--  6 | a/c/f     |  000000000005/ 000000000300/ 000000000600                             |      600
--  8 | a/c/f/h   |  000000000005/ 000000000300/ 000000000600/ 000000000800               |      800
-- 10 | a/c/f/h/j |  000000000005/ 000000000300/ 000000000600/ 000000000800/ 000000001000 |     1000
--  2 | b         |  000000000050                                                         |       50
--  4 | b/d       |  000000000050/ 000000000400                                           |      400

-- That basically concludes this post, as a last thing.
-- At one of companies I worked for we had this problem of getting 2nd level element in tree, that would be parent of given object.
-- For example, let's assume you have geographical tree. Top-level elements are countries, 2nd level are states, 3rd level are cities, 4th level are districts, and 5th level are streets.
-- Now, somebody tells you &#8211; I have this street with id 123, and I want to know in which state (or city or whatever) it is.
-- With standard adjacency-list way &#8211; oops, welcome loops. With nested sets &#8211; it's simpler, but you will be looking at some subselects.
-- And here? It's pretty simple:
-- select o.*
-- from $table o join $tree_table t on o.id = t.parent
-- where t.id = 123
-- order by t.depth desc
-- limit 1 offset 1;
-- If I would add 'tree_level' (also calculated on triggers of course) to $tree_table table, I could even do it without order/limit.
-- Now. At the end &#8211; you might be scared by amount of triggers in this code. Yes. There are some. You could easily get rid of some of them by simply bundling functionalities in single trigger.




__END__

=head1 NAME

SQL::Tree - Generate a trigger-based SQL tree implementation

=head1 SYNOPSIS

  use SQL::Tree qw/generate_sql_tree/;
  use DBI;

  my %opts = (
    dbtype    => $dbtype,
    drop      => $bool,
    table     => $table,
    pk        => $pk_column,
    pktype    => $pktype,
    parent    => $parent_column,
    path      => $path_column,
    path_from => $visual_column,
  );

  my $dbh = DBI->connect(...);
  foreach my $sql ( generate_sql_tree( %opts ) ) {
    $dbh->do( $sql );
  }

=head1 DESCRIPTION

B<SQL::Tree> generates a herarchical data (tree) implementation for
SQLite and PostgreSQL using triggers, as described here:

    http://www.depesz.com/index.php/2008/04/11/my-take-on-trees-in-sql/

A single subroutine is exported (on demand) that returns a list of SQL
statements:

=over 4

=item * generate_sql_tree( %opts ) -> @str

=back

See the L<sqltree> documentation for the list of arguments and their
meanings.

=head1 SEE ALSO

L<sqltree>(1) - command line access to B<SQL::Tree>

=head1 AUTHOR

Mark Lawrence E<lt>nomad@null.netE<gt>

=head1 COPYRIGHT AND LICENSE

Copyright 2010 Mark Lawrence <nomad@null.net>

This program is free software; you can redistribute it and/or modify it
under the terms of the GNU General Public License as published by the
Free Software Foundation; either version 3 of the License, or (at your
option) any later version.

=cut
