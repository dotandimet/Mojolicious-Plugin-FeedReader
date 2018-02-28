# Adapted from a failing test in hadashot:
use Mojolicious::Lite;

use Test::More;
use Test::Mojo;

plugin 'FeedReader';

plan tests => 1; # but a good one

get '/' => sub { shift->render(text => "Hello!") };

my $t = Test::Mojo->new()->app(app);
$t->app->ua->max_redirects(5);
my ($feed) = Mojo::URL->new('http://www.haaretz.co.il/cmlink/1.1617539'); # Haaretz Headlines
my $res = $t->app->parse_feed($feed);
is($res->{title}, 'כותרות ראשיות');
