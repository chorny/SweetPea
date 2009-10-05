#!perl
use Test::More tests => 2;
BEGIN {
    use_ok('SweetPea');
}

my $s = sweet->routes({

    '/' => sub {
        # prevent printing headers
        my $s = shift;
        ok(1, 'route mapped');
        
        $s->debug('ran routing tests...');
        $s->output('debug', 'cli');
    }

})->test('/');