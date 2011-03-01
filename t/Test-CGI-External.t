use warnings;
use strict;
use FindBin;
use Test::More tests => 1;
BEGIN { use_ok('Test::CGI::External') };
use Test::CGI::External;

my $tester = Test::CGI::External->new ();
$tester->set_verbosity (1);
$tester->set_cgi_executable ("$FindBin::Bin/test.cgi");
$tester->do_compression_test (1);
$tester->expect_charset ('utf-8');
my %options;
$options{REQUEST_METHOD} = 'GET';

$tester->run (\%options);

# Local variables:
# mode: perl
# End:
