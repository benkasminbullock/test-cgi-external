use strict;
use warnings;
use ExtUtils::MakeMaker;

WriteMakefile (
    NAME => 'Test::CGI::External',
    VERSION_FROM => 'lib/Test/CGI/External.pm',
    PREREQ_PM => {
        'Test::More' => 0,
        'IPC::Run3' => 0,
        'IO::Uncompress::Gunzip' => 0,
        'autodie' => 0,
    },
);
