#!perl
use Test::More tests => 3;
BEGIN {
    use_ok('SweetPea');
}

# 

my $s = sweet->routes({

    '/*' => sub {
        my $s = shift;
        ok(1, 'route mapped');
        is($s->param('*'), 'download/files.fosswire.com/2007/08/fwunixref.txt/via/pdf', 'random url w/wildcard param 1');
        
        # prevent printing headers
        $s->debug('ran adv routing tests a...');
        $s->output('debug', 'cli');
    },
    '/test/*' => sub {
        my $s = shift;
        ok(1, 'route mapped');
        is($s->param('*'), 'files.fosswire.com/2007/08/fwunixref.txt/via/pdf', 'random url w/wildcard param 1');
        
        # prevent printing headers
        $s->debug('ran adv routing tests b...');
        $s->output('debug', 'cli');
    }

})->test('/test/files.fosswire.com/2007/08/fwunixref.txt/via/pdf');