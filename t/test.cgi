#!/usr/bin/env perl
use warnings;
use strict;
use CGI::Compress::Gzip;
my $cgi = CGI::Compress::Gzip->new();
print $cgi->header (-charset => 'UTF-8'), $cgi->start_html (), "\n";
