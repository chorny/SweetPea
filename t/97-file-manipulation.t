#!perl
use Test::More tests => 3;
BEGIN {
    use_ok('SweetPea');
}

my $s = sweet->routes({

    '/' => sub {
        # prevent printing headers
        my $s = shift;
        ok($s->file('>', $s->path('sweetpea.test.txt'), 'This is a test'), 'file creation');
        is($s->file('<', $s->path('sweetpea.test.txt')), 'This is a test', 'read file contents');
        $s->file('x', $s->path('sweetpea.test.txt'));
        $s->debug('ran session tests...');
        $s->output('debug', 'cli');
    }

})->test('/');