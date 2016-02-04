use warnings;
use strict;
use FindBin '$Bin';
use Test::More;
use Test::CGI::External;

# Edit the test script to give it the right path.
# http://stackoverflow.com/questions/10390173/getting-absolute-path-to-perl-executable-for-the-current-process#10393492

use Config;
my $perlpath = $Config{perlpath};
my $cgi = "$Bin/test.cgi";
open my $in, "<", $cgi or die "Cannot open $cgi: $!";
my @lines;
while (<$in>) {
s/^#!.*perl.*$/#!$perlpath/;
push @lines, $_;
}
close $in or die "Cannot close $cgi: $!";
open my $out, ">", $cgi or die "Cannot open $cgi: $!";
for (@lines) {
print $out $_;
}
close $out or die "Cannot close $cgi: $!";

# Now start the tests.


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

$options{mime_type} = 'text/html';
$tester->run (\%options);

done_testing ();
