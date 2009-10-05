#!perl
use Test::More tests => 2;
BEGIN {
    use_ok('SweetPea');
}

# testing inline url params at root-level e.g. /:param

my $s = undef;

$s = sweet->routes({

    '/test/:a' => sub {
        my $s = shift;
        ok(1, 'route mapped');
        
        # prevent printing headers
        $s->debug('ran adv routing tests...');
        $s->output('debug', 'cli');
    }

})->test('/test/;!@$%^&*()_%22%22{}[;eval{exit};');

undef $s;