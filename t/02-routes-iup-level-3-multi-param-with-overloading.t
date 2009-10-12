#!perl
use Test::More tests => 5;
BEGIN {
    use_ok('SweetPea');
}

# testing inline url params at the 3rd-level e.g. /:param

my $s = sweet->routes({

    '/test/three/:a/:b/:c' => sub {
        my $s = shift;
        ok(1, 'route mapped');
        is($s->param('a'), '123/456/789/abc/def/eig/hij', 'level-3.1 inline url parameter');
        is($s->param('b'), 'klm', 'level-3.2 inline url parameter');
        is($s->param('c'), 'nop', 'level-3.3 inline url parameter');
        
        # prevent printing headers
        $s->debug('ran adv routing tests...');
        $s->output('debug', 'cli');
    }

})->test('/test/three/123/456/789/abc/def/eig/hij/klm/nop');