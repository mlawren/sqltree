use inc::Module::Install;
license         'Gpl_3';
name            'SQL-Tree';
all_from        'lib/SQL/Tree.pm';

build_requires  'Test::More'        => 0;
build_requires  'Test::Exception'   => 0;
build_requires  'Test::Database'    => 0;
build_requires  'DBI'               => 0;
build_requires  'DBD::SQLite'       => 0;

requires        'Getopt::Long::Descriptive'   => 0;

install_script  'bin/sqltree';

resources
    repository => 'git://github.com/mlawren/sql-tree.git';
    bugtracker => 'git://github.com/mlawren/sql-tree-bugs.git',

WriteAll;

