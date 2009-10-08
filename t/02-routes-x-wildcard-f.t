#!perl
use Test::More tests => 2;
BEGIN {
    use_ok('SweetPea');
}

# 

my $s = sweet->routes({

    '/http/:data/60299' => sub {
        my $s = shift;
        ok(1, 'route mapped');
        
        # prevent printing headers
        $s->debug('ran adv routing tests b...');
        $s->output('debug', 'cli');
    }

})->test('/http/item/$#%^&*****(&)7809*&(&)(*&)(*&)*(&(.*)/levitation-business-4-in-1/60299');