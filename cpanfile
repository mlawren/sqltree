#!perl

on configure => sub {
    requires 'ExtUtils::MakeMaker::CPANfile';
};

on runtime => sub {
    requires 'Getopt::Long::Descriptive' => 0;
};

on test => sub {
    requires 'Test::More'      => 0;
    requires 'Test::Exception' => 0;
    requires 'Test::Database'  => 0;
    requires 'DBI'             => 0;
    requires 'DBD::SQLite'     => 0;
};

on develop => sub {

    #    requires 'Class::Inline' => 0;
};

