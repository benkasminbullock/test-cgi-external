use warnings;
use strict;
use FindBin '$Bin';
use Test::More;
use Test::CGI::External;

my $tester = Test::CGI::External->new ();
$tester->set_verbosity (1);
$tester->set_cgi_executable ("$Bin/test.cgi", '--gzip');
$tester->do_compression_test (1);
$tester->expect_charset ('utf-8');

my %options;

$options{REQUEST_METHOD} = 'GET';
$tester->run (\%options);

$options{REQUEST_METHOD} = 'HEAD';
$tester->run (\%options);

$options{REQUEST_METHOD} = 'POST';
$options{input} = 'hallo baby.';
$tester->run (\%options);

done_testing ();
