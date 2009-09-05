#!perl -T

use Test::More tests => 1;

BEGIN {
    use_ok( 'SweetPea' );
}

diag( "Testing SweetPea $SweetPea::VERSION, Perl $], $^X" );
