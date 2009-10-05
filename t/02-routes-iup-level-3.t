#!perl
use Test::More tests => 3;
BEGIN {
    use_ok('SweetPea');
}

# testing inline url params at the 3rd-level e.g. /:param

my $s = sweet->routes({

    '/test/three/:a' => sub {
        my $s = shift;
        ok(1, 'route mapped');
        is($s->param('a'), '123', 'level-3 inline url parameter');
        
        # prevent printing headers
        $s->debug('ran adv routing tests...');
        $s->output('debug', 'cli');
    }

})->test('/test/three/123');