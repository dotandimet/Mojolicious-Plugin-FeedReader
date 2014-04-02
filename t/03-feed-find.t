use Mojo::Base -strict;

use Test::More;
use Test::Mojo;
use Mojo::URL;
use FindBin;
use Mojo::Util qw(slurp);

use Mojolicious::Lite;
plugin 'FeedReader';

get '/floo' => sub { shift->redirect_to('/link1.html'); };

my $samples = File::Spec->catdir($FindBin::Bin, 'samples');
push @{app->static->paths}, $samples;
get '/olaf' =>sub { shift->render(data => slurp(File::Spec->catfile($samples, 'atom.xml')), format => 'html'); };

my $t = Test::Mojo->new(app);

# feed
$t->get_ok('/atom.xml')->status_is(200);
my @feeds = $t->app->find_feeds('/atom.xml');
like( $feeds[0],  qr{http://localhost:\d+/atom.xml$} ); # abs url!

# can we consume a Mojo::URL ?
my @feeds_a = $t->app->find_feeds($feeds[0]);
is_deeply($feeds_a[0], $feeds[0], 'argument is a Mojo::URL');

# link
$t->get_ok('/link1.html')->status_is(200);
(@feeds) = $t->app->find_feeds('/link1.html');
like( $feeds[0],  qr{http://localhost:\d+/atom.xml$} ); # abs url!

# html page with multiple feed links
$t->get_ok('/link2_multi.html')->status_is(200);
(@feeds) = $t->app->find_feeds('/link2_multi.html');
is ( scalar @feeds, 3, 'got 3 possible feed links');
is( $feeds[0],  'http://www.example.com/?feed=rss2' ); # abs url!
is( $feeds[1],  'http://www.example.com/?feed=rss' ); # abs url!
is( $feeds[2],  'http://www.example.com/?feed=atom' ); # abs url!

# feed is in link:
# also, use base tag in head - for pretty url
$t->get_ok('/link3_anchor.html')->status_is(200);
(@feeds) = $t->app->find_feeds('/link3_anchor.html');
is( $feeds[0],  'http://example.com/foo.rss' );
is( $feeds[1],  'http://example.com/foo.xml' );

# Does it work the same non-blocking?
my $delay = Mojo::IOLoop->delay( sub {
  shift;
  my (@feeds) = @_;
  is( scalar @feeds, 3);
is( $feeds[0],  'http://www.example.com/?feed=rss2' ); # abs url!
is( $feeds[1],  'http://www.example.com/?feed=rss' ); # abs url!
is( $feeds[2],  'http://www.example.com/?feed=atom' ); # abs url!
} );
$t->app->find_feeds('/link2_multi.html', $delay->begin(0));
$delay->wait unless (Mojo::IOLoop->is_running);
# Let's try something with redirects:
$t->get_ok('/floo')->status_is(302);
(@feeds) = $t->app->find_feeds('/floo');
is( $feeds[0],  undef, 'default UA does not follow redirects'); # default UA doesn't follow redirects!
$t->app->ua->max_redirects(3);
(@feeds) = $t->app->find_feeds('/floo');
like( $feeds[0],  qr{http://localhost:\d+/atom.xml$}, 'found with redirect' ); # abs url!

# what do we do on a page with no feeds?
$t->get_ok('/no_link.html')->status_is(200);
(@feeds) = $t->app->find_feeds('/no_link.html');
is(scalar @feeds, 0, 'no feeds');
say "feed: $_" for (@feeds);

# a feed with an incorrect mime-type:
$t->get_ok('/olaf')->status_is(200)->content_type_like(qr/^text\/html/, 'feed served as html');
(@feeds) = $t->app->find_feeds('/olaf');
is(scalar @feeds, 1);
is(Mojo::URL->new($feeds[0])->path, '/olaf', 'feed served as html');

# we should get more info with non-blocking:

$delay = Mojo::IOLoop->delay(sub {
  shift;
  my (@feeds) = @_;
  is(scalar @feeds, 0, 'no feeds');
});

$t->app->find_feeds('/no_link.html', $delay->begin(0) );
$delay->wait unless (Mojo::IOLoop->is_running);



done_testing();
