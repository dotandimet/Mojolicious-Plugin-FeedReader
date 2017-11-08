# Adapted from a failing test in hadashot:
use Mojolicious::Lite;

use Test::More;
use Test::Mojo;

plugin 'FeedReader';

plan tests => 1; # but a good one

get '/' => sub { shift->render(text => "Hello!") };

my $t = Test::Mojo->new()->app(app);
$t->app->ua->max_redirects(5);
my ($feed) = $t->app->find_feeds("http://corky.net");
my $res = $t->app->parse_feed($feed);
is($res->{title}, 'קורקי.נט aggregator');
