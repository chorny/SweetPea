#!perl
use Test::More tests => 3;
BEGIN {
    use_ok('SweetPea');
}

my $s = sweet->routes({

    '/' => sub {
        # prevent printing headers
        my $s = shift;
        ok($s->session->param('name', 'sweetpea'), 'session set');
        is($s->session->param('name'), 'sweetpea', 'session param retrieved');
        
        $s->debug('ran session tests...');
        $s->output('debug', 'cli');
    }

})->test('/');