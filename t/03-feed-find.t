use Mojo::Base -strict;

use Test::More;
use Test::Mojo;
use Mojo::URL;
use FindBin;

use Mojolicious::Lite;
plugin 'FeedReader';

get '/floo' => sub { shift->redirect_to('/link1.html'); };

push @{app->static->paths}, File::Spec->catdir($FindBin::Bin, 'samples');

my $t = Test::Mojo->new(app);

# feed
$t->get_ok('/atom.xml')->status_is(200);
my @feeds = $t->app->find_feeds('/atom.xml');
like( $feeds[0],  qr{http://localhost:\d+/atom.xml$} ); # abs url!

# link
$t->get_ok('/link1.html')->status_is(200);
@feeds = $t->app->find_feeds('/link1.html');
like( $feeds[0],  qr{http://localhost:\d+/atom.xml$} ); # abs url!

# html page with multiple feed links
$t->get_ok('/link2_multi.html')->status_is(200);
@feeds = $t->app->find_feeds('/link2_multi.html');
is ( scalar @feeds, 3, 'got 3 possible feed links');
is( $feeds[0],  'http://www.example.com/?feed=rss2' ); # abs url!
is( $feeds[1],  'http://www.example.com/?feed=rss' ); # abs url!
is( $feeds[2],  'http://www.example.com/?feed=atom' ); # abs url!

# feed is in link:
# also, use base tag in head - for pretty url
$t->get_ok('/link3_anchor.html')->status_is(200);
@feeds = $t->app->find_feeds('/link3_anchor.html');
is( $feeds[0],  'http://example.com/foo.rss' );
is( $feeds[1],  'http://example.com/foo.xml' );

# Does it work the same non-blocking?
my $delay = Mojo::IOLoop->delay(sub{ shift; is(scalar(@_), 3); });
my $end = $delay->begin(0);
$t->app->find_feeds('/link2_multi.html', sub {
  my ($c, $req_info, @feeds) = @_;
  is ($req_info->{code}, 200 );
  ok (not defined $req_info->{error});
  is( scalar @feeds, 3);
is( $feeds[0],  'http://www.example.com/?feed=rss2' ); # abs url!
is( $feeds[1],  'http://www.example.com/?feed=rss' ); # abs url!
is( $feeds[2],  'http://www.example.com/?feed=atom' ); # abs url!
  $end->(@feeds);
});
$delay->wait();

# Let's try something with redirects:
$t->get_ok('/floo')->status_is(302);
@feeds = $t->app->find_feeds('/floo');
like( $feeds[0],  qr{http://localhost:\d+/atom.xml$} ); # abs url!

# what do we do on a page with no feeds?

@feeds = $t->app->find_feeds('/no_link.html');
is(scalar @feeds, 0, 'no feeds');

# we should get more info with non-blocking:

$delay = Mojo::IOLoop->delay();

$t->app->find_feeds('/no_link.html', sub {
  my($c, $req_info, @feeds) = @_;
  isa_ok($c, 'Mojolicious::Controller', 'called with controller');
  is(scalar @feeds, 0, 'no feeds');
  ok(defined $req_info->{'error'}, 'error is defined');
  $delay->begin(0)->();
});

$delay->wait unless (Mojo::IOLoop->is_running);



done_testing();
