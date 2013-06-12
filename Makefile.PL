use inc::Module::Install;
license 'Gpl_3';
name 'App-sqltree';
all_from 'lib/App/sqltree.pm';
readme_from 'lib/App/sqltree.pm';

requires 'File::ShareDir'   => 0;
requires 'IO::Prompt::Tiny' => 0;
requires 'OptArgs'          => 0;
requires 'Path::Tiny'       => 0;
requires 'Template::Tiny'   => 0;

test_requires 'Data::Dumper'   => 0;
test_requires 'File::Temp'     => 0;
test_requires 'Test::Database' => 0;
test_requires 'Test::Fatal'    => 0;
test_requires 'Test::More'     => 0;

tests_recursive 't';

install_script 'bin/sqltree';
install_share 'share';

resources repository => 'git://github.com/mlawren/sqltree.git';

WriteAll;

# Create the test scripts if we are a developer
exit unless -d '.git';

require Cwd;
my $dir = Cwd::abs_path;
open( FH, '>', 't/sqltree' ) or die "open: $!";
print FH <<"END";
#!$^X
use strict;
use FindBin qw/\$Bin/;
use lib "\$Bin/../lib";
use Path::Tiny;
use OptArgs qw/dispatch/;

\$Test::App::sqltree::SHARE_DIR = path('$dir', 'share');

dispatch(qw/run App::sqltree/);
END
close FH;
chmod 0755, 't/sqltree' or warn "chmod: $!";
