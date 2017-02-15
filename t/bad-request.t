#!/home/ben/software/install/bin/perl
use warnings;
use strict;
use utf8;
use FindBin '$Bin';
use Test::More;
use Test::CGI::External;
my $tester = Test::CGI::External->new ();
$tester->set_cgi_executable ("$Bin/bad-method.cgi");
$tester->bad_request_method ();
done_testing ();
