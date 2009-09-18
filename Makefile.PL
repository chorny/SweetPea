use strict;
use warnings;
use inc::Module::Install;
 
WriteMakefile(
    NAME => 'SweetPea',
    AUTHOR => q{Al Newkirk <al.newkirk@awnstudio.com>},
    VERSION_FROM => 'lib/SweetPea.pm',
    ABSTRACT_FROM => 'lib/SweetPea.pm',
    LICENSE => 'perl',
    PL_FILES => {},
    PREREQ_PM => {
        'Test::More' => 0,
        'CGI' => 0,
        'CGI::Cookie' => 0,
        'CGI::Session' => 0,
    },
    dist => { COMPRESS => 'gzip -9f', SUFFIX => 'gz', },
    clean => { FILES => 'SweetPea-*' },
);