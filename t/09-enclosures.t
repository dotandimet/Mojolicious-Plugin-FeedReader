use Mojo::Base -strict;

use Test::More;
use Mojo::File 'path';
use Mojolicious::Plugin::FeedReader;

use FindBin;

my $samples = path($FindBin::Bin)->child('all_samples');

my $reader = Mojolicious::Plugin::FeedReader->new;

for my $file ( 'atom-enclosure.xml', 'rss20-enclosure.xml' ) {
    my $feed = $reader->parse_rss( $samples->child($file) );
    is_deeply(
        $feed->{items}->[0]->{enclosure},
        {
            'length' => '2478719',
            'type'   => 'audio/mpeg',
            'url'    => 'http://example.com/sample_podcast.mp3'
        }
    );
}

done_testing();
