#!/usr/bin/env perl
use SQL::Tree;
use Test2::V0;

my $args = {
    driver    => 'SQLite',
    table     => 'test',
    postfix   => '_tree',
    type      => 'integer',
    id        => 'id',
    parent_id => 'parent_id',
};

like( SQL::Tree::generate($args), qr/CREATE TABLE test_tree/, 'basic use' );

done_testing();
