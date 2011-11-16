use inc::Module::Install;
license 'Gpl_3';
name 'SQL-Tree';
all_from 'lib/SQL/Tree.pm';

requires 'Getopt::Long::Descriptive' => 0;

test_requires 'Test::More'      => 0;
test_requires 'Test::Exception' => 0;
test_requires 'Test::Database'  => 0;
test_requires 'DBI'             => 0;
test_requires 'DBD::SQLite'     => 0;

install_script 'bin/sqltree';

resources repository => 'git://github.com/mlawren/sql-tree.git';

WriteAll;
