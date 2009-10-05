#!perl
use Test::More tests => 3;
BEGIN {
    use_ok('SweetPea');
}

# testing inline url params at the 2nd-level e.g. /:param

my $s = sweet->routes({

    '/test/:a' => sub {
        my $s = shift;
        ok(1, 'route mapped');
        is($s->param('a'), '123', 'level-2 inline url parameter');
        
        # prevent printing headers
        $s->debug('ran adv routing tests...');
        $s->output('debug', 'cli');
    }

})->test('/test/123');