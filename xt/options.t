#!/home/ben/software/install/bin/perl
use warnings;
use strict;
use Test::More;
use Test::CGI::External;
my $cgi = '/home/ben/projects/kanji/c/minidic-1.cgi';
if (! -x $cgi) {
    plan skip_all => "No $cgi to test against";
}
my $tester = Test::CGI::External->new ();
$tester->set_cgi_executable ($cgi);
$tester->test_options ();
done_testing ();
