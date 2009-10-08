#!perl
use Test::More tests => 3;
BEGIN {
    use_ok('SweetPea');
}

# testing inline url params at the 3rd-level e.g. /:param

my $s = sweet->routes({

    '/test/*/three' => sub {
        my $s = shift;
        ok(1, 'route mapped');
        is($s->param('*'), '123', 'level-3 variable parameter placement');
        
        # prevent printing headers
        $s->debug('ran adv routing tests...');
        $s->output('debug', 'cli');
    }

})->test('/test/123/three');