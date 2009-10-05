#!perl -T

use Test::More tests => 4;

BEGIN {
    use_ok ('CGI');
    use_ok ('CGI::Cookie');
    use_ok ('CGI::Session');
    use_ok ('SweetPea');
}

diag( "Testing SweetPea $SweetPea::VERSION, Perl $], $^X" );
