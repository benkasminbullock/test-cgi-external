use warnings;
use strict;
use FindBin;
use Test::More;

if ($^O eq 'MSWin32') {
    plan skip_all => "These tests not adapted for Microsoft Windows";
}
use Test::CGI::External;

my $tester = Test::CGI::External->new ();
$tester->set_verbosity (1);
$tester->set_cgi_executable ("$FindBin::Bin/test.cgi", '--gzip');
$tester->do_compression_test (1);
$tester->expect_charset ('utf-8');
my %options;
$options{REQUEST_METHOD} = 'GET';

$tester->run (\%options);
#$tester->plan ();
done_testing ();

# Local variables:
# mode: perl
# End:
