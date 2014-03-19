# NAME

Mojolicious::Plugin::FeedReader - Mojolicious Plugin to fetch and parse RSS & Atom feeds

# SYNOPSIS

        # Mojolicious
         $self->plugin('FeedReader');

         # Mojolicious::Lite
         plugin 'FeedReader';

        my ($info, $feed) = app->find_feeds(q{search.cpan.org});
        my $out = app->parse_rss($feed);
        say $_->{title} for (@{$out->{items}});

        # In a route handler:
        get '/' => sub {
          my $self = shift;
          $self->render_later;
          my $delay = Mojo::IOLoop->delay(
            sub {
              $self->find_feeds("search.cpan.org", shift->begin(0));
            },
            sub {
              my $feed = pop;
              $self->parse_rss($feed, shift->begin);
            },
            sub {
                my $data = pop;
                $self->render(items => $data->{items});
            });
          $delay->wait unless Mojo::IOLoop->is_running;
        } => 'uploads';



        app->start;

        __DATA__

        @@ uploads.html.ep
        <ul>
        % for my $item (@$items) {
          <li><%= link_to $item->{title} => $item->{link} %> - <%= $item->{description} %></li>
        % }
        </ul>

# DESCRIPTION

__Mojolicious::Plugin::FeedReader__ implements minimalistic helpers for identifying,
fetching and parsing RSS and Atom Feeds.  It has minimal dependencies, relying as
much as possible on Mojolicious components - Mojo::UserAgent for fetching feeds and
checking URLs, Mojo::DOM for XML/HTML parsing.
It is therefore rather fragile and naive, and should be considered Experimental/Toy
code - __use at your own risk__.



# METHODS

[Mojolicious::Plugin::FeedReader](http://search.cpan.org/perldoc?Mojolicious::Plugin::FeedReader) inherits all methods from
[Mojolicious::Plugin](http://search.cpan.org/perldoc?Mojolicious::Plugin) and implements the following new ones.

## register

    $plugin->register(Mojolicious->new);

Register plugin in [Mojolicious](http://search.cpan.org/perldoc?Mojolicious) application. This method will install the helpers
listed below in your Mojolicious application.

# HELPERS

__Mojolicious::Plugin::FeedReader__ implements the following helpers.

## find\_feeds

    # Call blocking
    my ($info, @feeds) = app->find_feeds('search.cpan.org');
    # $info is a hash ref
    # @feeds is a list of Mojo::URL objects

    # Call non-blocking
    $self->find_feeds('http://example.com', sub {
      my ($info, @feeds) = @_;
      unless (@feeds) {
        $self->render_exception("no feeds found, " . $info->{error});
      }
      else {
        ....
      }
    });

A Mojolicious port of [Feed::Find](http://search.cpan.org/perldoc?Feed::Find) by Benjamin Trott. This helper implements feed auto-discovery for finding syndication feeds, given a URI.
If given a callback function as an additional argument, execution will be non-blocking.

## parse\_rss

    # parse an RSS feed
    # blocking
    my $url = Mojo::URL->new('http://rss.slashdot.org/Slashdot/slashdot');
    my $feed = $self->parse_rss($url);
    for my $item (@{$feed->{items}}) {
      say $_ for ($item->{title}, $item->{description}, 'Tags: ' . join q{,}, @{$item->{tags}});
    }

    # non-blocking
    $self->parse_rss($url, sub {
      my ($c, $feed) = @_;
      $c->render(text => "Feed tagline: " . $feed->{tagline});
    });

    # parse a file
    $feed2 = $self->parse_rss('/downloads/foo.rss');

    # parse response DOM
    $self->ua->get($feed_url, sub {
      my ($ua, $tx) = @_;
      my $feed = $self->parse_rss($tx->res->dom);
    });

A minimalist liberal RSS/Atom parser, using Mojo::DOM queries.

Dates are parsed using [HTTP::Date](http://search.cpan.org/perldoc?HTTP::Date).

If parsing fails (for example, the parser was given an HTML page), the helper will return undef.

On success, the result returned is a hashref with the following keys:

- title
- description
- htmlUrl - web page URL associated with the feed
- items - array ref of feed news items
- subtitle (optional)
- tagline (optional)

Each item in the items array is a hashref with the following keys:

- title
- link
- content
- id
- description (optional) - usually a shorter form of the content
- guid (optional)
- published (optional)
- tags (optional) - array ref of tags or categories.
- \_raw - XML serialized text of the item's Mojo::DOM node. Note that this can be different from the original XML text in the feed.

# SEE ALSO

[Mojolicious](http://search.cpan.org/perldoc?Mojolicious), [Mojolicious::Guides](http://search.cpan.org/perldoc?Mojolicious::Guides), [http://mojolicio.us](http://mojolicio.us).
