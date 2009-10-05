#!perl
use Test::More tests => 3;
BEGIN {
    use_ok('SweetPea');
}

# testing inline url params at root-level e.g. /:param

my $s = sweet->routes({

    '/:a' => sub {
        my $s = shift;
        ok(1, 'route mapped');
        is($s->param('a'), '123', 'inline url parameter');
        
        # prevent printing headers
        $s->debug('ran adv routing tests...');
        $s->output('debug', 'cli');
    }

})->test('/123');