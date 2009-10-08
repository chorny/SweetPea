#!perl
use Test::More tests => 3;
BEGIN {
    use_ok('SweetPea');
}

# 

my $s = sweet->routes({

    '/http/:data/60299' => sub {
        my $s = shift;
        ok(1, 'route mapped');
        is($s->param('data'), 'item/levitation-business-4-in-1', 'random url w/wildcard param 1');
        
        # prevent printing headers
        $s->debug('ran adv routing tests a...');
        $s->output('debug', 'cli');
    },
    '/http/:data/60299' => sub {
        my $s = shift;
        ok(1, 'route mapped');
        is($s->param('data'), 'item/levitation-business-4-in-1', 'random url w/wildcard param 1');
        
        # prevent printing headers
        $s->debug('ran adv routing tests b...');
        $s->output('debug', 'cli');
    }

})->test('/http/item/levitation-business-4-in-1/60299');