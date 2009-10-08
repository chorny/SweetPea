#!perl
use Test::More tests => 3;
BEGIN {
    use_ok('SweetPea');
}

# testing inline url params at the 3rd-level e.g. /:param

my $s = sweet->routes({

    '/download/*/via/pdf' => sub {
        my $s = shift;
        ok(1, 'route mapped');
        is($s->param('*'), 'files.fosswire.com/2007/08/fwunixref.txt', 'random url w/wildcard');
        
        # prevent printing headers
        $s->debug('ran adv routing tests...');
        $s->output('debug', 'cli');
    }

})->test('/download/files.fosswire.com/2007/08/fwunixref.txt/via/pdf');