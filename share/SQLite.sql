CREATE TABLE [% tree %] (
    treeid INTEGER PRIMARY KEY,
    parent [% type %] NOT NULL,
    child  [% type %] NOT NULL,
    depth  INTEGER NOT NULL,
    UNIQUE (parent, child)
    FOREIGN KEY(parent) REFERENCES [% table %]([% pk %]) ON DELETE CASCADE,
    FOREIGN KEY(child) REFERENCES [% table %]([% pk %]) ON DELETE CASCADE
);

--SPLIT--
/*
 Triggers in SQLite run in the reverse order to which they are defined.
 Actions happen from the bottom up.
 */

[%- IF path -%]
CREATE TRIGGER
    ai_[% table %]_path_2
AFTER INSERT ON
    [% table %]
FOR EACH ROW WHEN
    NEW.[% parent %] IS NOT NULL
BEGIN
    UPDATE
        [% table %]
    SET
        [% path %] = (
            SELECT
                [% path %] || '/' || NEW.[% path_from %]
            FROM
                [% table %]
            WHERE
                [% pk %] = NEW.[% parent %]
        )
    WHERE
        [% pk %] = NEW.[% pk %]
    ;

END;

--SPLIT--
CREATE TRIGGER
    ai_[% table %]_path_1
AFTER INSERT ON
    [% table %]
FOR EACH ROW WHEN
    NEW.[% parent %] IS NULL
BEGIN

    UPDATE
        [% table %]
    SET
        [% path %] = [% path_from %]
    WHERE
        [% pk %] = NEW.[% pk %]
    ;
END;

[%- END -%]

--SPLIT--
CREATE TRIGGER
    ai_[% table %]_tree_1
AFTER INSERT ON
    [% table %]
FOR EACH ROW 
BEGIN

    /*
     Insert a matching row in [% tree %] where both parent and child
     are set to the id of the newly inserted object. Depth is set to 0
     as both child and parent are on the same level.
     */

    INSERT INTO
        [% tree %] (
            parent,
            child,
            depth
        )
    VALUES (
        NEW.[% pk %],
        NEW.[% pk %],
        0
    );

    /*
     Copy all rows that our parent had as its parents, but we modify
     the child id in these rows to be the id of currently inserted row,
     and increase depth by one.
     */

    INSERT INTO
        [% tree %] (
            parent,
            child,
            depth
        )
    SELECT
        x.parent,
        NEW.[% pk %],
        x.depth + 1
    FROM
        [% tree %] x
    WHERE
        x.child = NEW.[% parent %]
    ;
END;

[%- IF path -%]
--SPLIT--
-- Paths - update all affected rows with the new parent path
CREATE TRIGGER
    au_[% table %]_path_2
AFTER UPDATE ON
    [% table %]
FOR EACH ROW WHEN
    NEW.[% parent %] IS NOT NULL
BEGIN
    UPDATE
        [% table %]
    SET
        [% path %] = (
            SELECT
                [% path %]
            FROM
                [% table %]
            WHERE
                [% pk %] = NEW.[% parent %]
        ) || '/' || [% path %]
    WHERE
        [% pk %] IN (
            SELECT
                child
            FROM
                [% tree %]
            WHERE parent = NEW.[% parent %] AND depth > 0
        )
    ;
END;
[%- END -%]


--SPLIT--
-- Finally, insert tree data relating to the new parent
CREATE TRIGGER au_[% table %]_tree_5
AFTER UPDATE ON [% table %]
FOR EACH ROW WHEN NEW.[% parent %] IS NOT NULL
BEGIN
    INSERT INTO [% tree %] (parent, child, depth)
    SELECT r1.parent, r2.child, r1.depth + r2.depth + 1
    FROM
        [% tree %] r1
    INNER JOIN
        [% tree %] r2
    ON
        r2.parent = NEW.[% pk %]
    WHERE
        r1.child = NEW.[% parent %]
    ;
END;

--SPLIT--
-- Remove the tree data relating to the old parent
CREATE TRIGGER au_[% table %]_tree_4
AFTER UPDATE ON [% table %]
FOR EACH ROW WHEN OLD.[% parent %] IS NOT NULL
BEGIN
    DELETE FROM [% tree %] WHERE treeid in (
        SELECT r2.treeid
        FROM
            [% tree %] r1
        INNER JOIN
            [% tree %] r2
        ON
            r1.child = r2.child AND r2.depth > r1.depth
        WHERE r1.parent = NEW.[% pk %]
    );
END;
-- FIXME: Also trigger when column 'path_from' changes. For the
-- moment, the user work-around is to temporarily re-parent the row.


[%- IF path -%]
--SPLIT--
-- path changes - Remove the leading paths of the old parent. This has
-- to happen before we make changes to [% tree %].
CREATE TRIGGER au_[% table %]_path_1
AFTER UPDATE ON [% table %]
FOR EACH ROW WHEN OLD.[% parent %] IS NOT NULL
BEGIN
    UPDATE [% table %]
    SET [% path %] = substr([% path %], (
        SELECT length([% path %] || '/') + 1
        FROM [% table %]
        WHERE [% pk %] = OLD.[% parent %]
    ))
    WHERE [% pk %] IN (
        SELECT child
        FROM [% tree %]
        WHERE parent = OLD.[% parent %] AND depth > 0
    );
END;
[%- END -%]

--SPLIT--
-- If there was no change to the parent then we can skip the rest of
-- the triggers
CREATE TRIGGER au_[% table %]_tree_2
AFTER UPDATE ON [% table %]
FOR EACH ROW WHEN
    (OLD.[% parent %] IS NULL AND NEW.[% parent %] IS NULL) OR
    ((OLD.[% parent %] IS NOT NULL and NEW.[% parent %] IS NOT NULL) AND
     (OLD.[% parent %] = NEW.[% parent %]))
BEGIN
    SELECT RAISE (IGNORE);
END;

[%- IF path -%]
--SPLIT--
-- If the from_path column has changed then update the path
CREATE TRIGGER au_[% table %]_tree_x2
AFTER UPDATE ON [% table %]
FOR EACH ROW WHEN OLD.[% path_from %] != NEW.[% path_from %]
BEGIN
    UPDATE [% table %]
    SET
        [% path %] = (SELECT [% path %] FROM [% table %] WHERE [% pk %] = OLD.[% pk %]) ||
            SUBSTR([% path %], LENGTH(OLD.[% path %])+1)
    WHERE
        [% pk %] IN (
            SELECT child
            FROM [% tree %]
            WHERE parent = OLD.[% pk %] AND depth > 0
        )
    ;
END;

--SPLIT--
/*
 If the from_path column has changed then update the path
*/

CREATE TRIGGER
    au_[% table %]_tree_x
AFTER UPDATE ON
    [% table %]
FOR EACH ROW WHEN
    OLD.[% path_from %] != NEW.[% path_from %]
BEGIN
    UPDATE
        [% table %]
    SET
        [% path %] = 
            CASE WHEN
                NEW.[% parent %] IS NOT NULL
            THEN
                (SELECT
                    [% path %]
                 FROM
                    [% table %]
                 WHERE
                    [% pk %] = NEW.[% parent %]
                ) || '/' || [% path_from %]
            ELSE
                [% path_from %]
            END
    WHERE
        [% pk %] = OLD.[% pk %]
    ;
END;
[%- END -%]


--SPLIT--
/*
 As for moving data around in [% table %] freely, we should forbid
 moves that would create loops:
*/

CREATE TRIGGER
    bu_[% table %]_tree_2
BEFORE UPDATE ON
    [% table %]
FOR EACH ROW WHEN
    NEW.[% parent %] IS NOT NULL AND
    (SELECT
        COUNT(child) > 0
     FROM
        [% tree %]
     WHERE
        child = NEW.[% parent %] AND parent = NEW.[% pk %]
    )
BEGIN
    SELECT RAISE (ABORT,
        'Update blocked, because it would create loop in tree.');
END;

--SPLIT--
/*
 This implementation forbids changes to the primary key
*/

CREATE TRIGGER
    bu_[% table %]_tree_1
BEFORE UPDATE ON
    [% table %]
FOR EACH ROW WHEN
    OLD.[% pk %] != NEW.[% pk %]
BEGIN
    SELECT RAISE (ABORT, 'Changing ids is forbidden.');
END;
