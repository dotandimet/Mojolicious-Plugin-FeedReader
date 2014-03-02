use Mojo::Base -strict;

use Test::More;
use Test::Mojo;
use Mojo::URL;
use FindBin;

use Mojolicious::Lite;
plugin 'FeedReader';

get '/goto' => sub { shift->redirect_to('/atom.xml'); };
push @{app->static->paths}, File::Spec->catdir($FindBin::Bin, 'samples');
my $t = Test::Mojo->new(app);


# block a non-blocking thing boilerplate. Ugh.
$t->app->helper(
  get_feed => sub {
    my ($self, $url, $headers) = @_;
    my %headers = $self->set_req_headers($headers) if ($headers);
    $t->app->ua->max_redirects(5)->connect_timeout(30); # for redirects
    my ($tx) = $t->app->ua->get($url, \%headers);
    return $self->process_feed($tx);
  }
);

my $sub = '/atom.xml';
$t->get_ok($sub)->status_is(200);
my ($f, $r) = $t->app->get_feed($sub);
is(ref $f,        'HASH');
is($r->{error},            undef);
is($r->{code},            200);
is(scalar @{$f->{items}}, 2);
is($f->{items}[0]{title}, 'Entry Two');

# see how not-modified will work:
($f, $r) = $t->app->get_feed($sub, $r);
is($f,     undef);
is($r->{error},     'Not Modified');
is($r->{code},     304);

# now let's do error tests:
($f, $r) = $t->app->get_feed('/floo');
is($f,     undef);
is($r->{error},     'Not Found');
is($r->{code},     404);

($f, $r) = $t->app->get_feed('/link1.html');
is($f,     undef);
is($r->{error},    'url no longer points to a feed');
is($r->{code},     200);


# check the processing of a set of feeds

my @set = (
  '/atom.xml', '/link1.html',    # feed will be undef
  '/nothome',                    # 404
  '/goto',                       # redirect
  '/rss10.xml', '/rss20.xml',
);

my %set_tests = (
  '/atom.xml' => sub {
    is($_[1]{title}, 'First Weblog');    # title in feed
  },
  '/link1.html' =>                       # feed will be undef
    sub {
    is($_[1], undef);
    },
  '/nothome' =>                          # 404
    sub {
    is($_[1], undef);
    is($_[2]{error}, 'Not Found');
    is($_[2]{code}, 404);
    },
  '/goto' =>                             # redirect
    sub {
    is(scalar @{$_[1]{items}}, 2);
    is($_[2]{code},                  200);     # no sign of the re-direct...
    },
  '/rss10.xml' => sub {
    is(scalar @{$_[1]{items}}, 2);
    is($_[1]{title},           'First Weblog');
    is($_[2]{error},                  undef);
    is($_[2]{code},                  200);              # no sign of the re-direct...
  },
  '/rss20.xml' => sub {
    is(scalar @{$_[1]{items}}, 2);
    is($_[1]{title},           'First Weblog');
    is($_[2]{error},                  undef);
    is($_[2]{code},                  200);              # no sign of the re-direct...
  }
);

foreach my $s (@set) {
  my ($feed, $req_info) = $t->app->get_feed($s);
  my $req_url = $req_info->{url}->path;
  eval {
    if ($set_tests{$req_url}) {
      $set_tests{$req_url}->($s, $feed, $req_info);
    }
  };
  if ($@) {
    die "Something horrible: ", $@;
  }
};

done_testing();

