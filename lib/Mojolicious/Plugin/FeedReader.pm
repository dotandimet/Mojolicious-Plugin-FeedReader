package Mojolicious::Plugin::FeedReader;
use Mojo::Base 'Mojolicious::Plugin';

our $VERSION = '0.01';
use Mojo::Util qw(decode slurp trim);
use Mojo::DOM;
use Mojo::IOLoop;
use HTTP::Date;
use Carp "croak";

our @time_fields
  = (qw(pubDate published created issued updated modified dc\:date));
our %is_time_field = map { $_ => 1 } @time_fields;

# feed mime-types:
our @feed_types = (
  'application/x.atom+xml', 'application/atom+xml',
  'application/xml',        'text/xml',
  'application/rss+xml',    'application/rdf+xml'
);
our %is_feed = map { $_ => 1 } @feed_types;

sub register {
  my ($self, $app) = @_;
  foreach my $method (
    qw( find_feeds parse_rss parse_rss_dom parse_rss_channel parse_rss_item ))
  {
    $app->helper($method => \&{$method});
  }
}

sub parse_rss {
  my ($c, $xml, $cb) = @_;
  my $dom;
  if (!ref $xml) {    # assume file
    my $rss_str = decode 'UTF-8', slurp $xml;
    die "Failed to read file $xml (as UTF-8): $!" unless ($rss_str);
    $dom = Mojo::DOM->new->parse($rss_str);
  }
  elsif (ref $xml eq 'SCALAR') {    # assume string
    $dom = Mojo::DOM->new->parse($$xml);
  }
  elsif ($xml->can('slurp')) {      # assume Mojo::Asset
    my $rss_str = decode 'UTF-8', $xml->slurp;
    die "Failed to read asset $xml (as UTF-8): $!" unless ($rss_str);
    $dom = Mojo::DOM->new->parse($rss_str);
  }
  elsif ($xml->isa('Mojo::DOM')) {
    $dom = $xml;
  }
  elsif ($xml->isa('Mojo::URL')) {

    # this is the only case where we might go non-blocking:
    if ($cb) {
      $c->ua->get(
        $xml,
        sub {
          my ($ua, $tx) = @_;
          my $feed;
          if ($tx->success) {
            eval { $feed = $c->parse_rss_dom($tx->res->dom); };
          }
          $c->$cb($feed);
        }
      );
    }
    else {
      $dom = $c->ua->get($xml)->res->dom;
    }
  }
  return ($dom) ? $c->parse_rss_dom($dom) : 1;
}

sub parse_rss_dom {
  my ($self, $dom) = @_;
  die "Argument $dom is not a Mojo::DOM" unless ($dom->isa('Mojo::DOM'));
  my $feed    = $self->parse_rss_channel($dom);    # Feed properties
  my $items   = $dom->find('item');
  my $entries = $dom->find('entry');               # Atom
  my $res     = [];
  foreach my $item ($items->each, $entries->each) {
    push @$res, $self->parse_rss_item($item);
  }
  if (@$res) {
    $feed->{'items'} = $res;
  }
  return $feed;
}

sub parse_rss_channel {
  my ($self, $dom) = @_;
  my %info;
  foreach my $k (
    qw{title subtitle description tagline link:not([rel]) link[rel=alternate] dc\:creator author webMaster},
    @time_fields
    )
  {
    my $p = $dom->at("channel > $k") || $dom->at("feed > $k");   # direct child
    if ($p) {
      $info{$k} = $p->text || $p->content || $p->attr('href');
      if ($k eq 'author' && $p->at('name')) {
         $info{$k} = $p->at('name')->text || $p->at('name')->content;
      }
      if ($is_time_field{$k}) {
        $info{$k} = str2time($info{$k});
      }
    }
  }
  my ($htmlUrl)
    = grep { defined $_ }
    map { delete $info{$_} } ('link:not([rel])', 'link[rel=alternate]');
  my ($description)
    = grep { defined $_ }
    map { exists $info{$_} ? $info{$_} : undef }
    (qw(description tagline subtitle));
  $info{htmlUrl}     = $htmlUrl     if ($htmlUrl);
  $info{description} = $description if ($description);

  # normalize fields:
  my @replace = (
    'pubDate'  => 'published',
    'dc\:date' => 'published',
    'created'  => 'published',
    'issued'   => 'published',
    'updated'  => 'published',
    'modified' => 'published',
    'dc\:creator' => 'author',
    'webMaster' => 'author'
  );
  while (my ($old, $new) = splice(@replace, 0, 2)) {
    if ($info{$old} && !$info{$new}) {
      $info{$new} = delete $info{$old};
    }
  }
  return (keys %info) ? \%info : undef;
}

sub parse_rss_item {
  my ($self, $item) = @_;
  my %h;
  foreach my $k (
    qw(title id summary guid content description content\:encoded xhtml\:body dc\:creator author),
    @time_fields
    )
  {
    my $p = $item->at($k);
    if ($p) {

      # skip namespaced items - like itunes:summary - unless explicitly
      # searched:
      next
        if ($p->type =~ /\:/
        && $k ne 'content\:encoded'
        && $k ne 'xhtml\:body'
        && $k ne 'dc\:date'
        && $k ne 'dc\:creator');
      $h{$k} = $p->text || $p->content;
      if ($k eq 'author' && $p->at('name')) {
        $h{$k} = $p->at('name')->text;
      }
      if ($is_time_field{$k}) {
        $h{$k} = str2time($h{$k});
      }
    }
  }

  # let's handle links seperately, because ATOM loves these buggers:
  $item->find('link')->each(
    sub {
      my $l = shift;
      if ($l->attr('href')) {
        if (!$l->attr('rel') || $l->attr('rel') eq 'alternate') {
          $h{'link'} = $l->attr('href');
        }
      }
      else {
        if ($l->text =~ /\w+/) {
          $h{'link'} = $l->text;    # simple link
        }

#         else { # we have an empty link element with no 'href'. :-(
#           $h{'link'} = $1 if ($l->next->text =~ m/^(http\S+)/);
#         }
      }
    }
  );

  # find tags:
  my @tags;
  $item->find('category, dc\:subject')
    ->each(sub { push @tags, $_[0]->text || $_[0]->attr('term') });
  if (@tags) {
    $h{'tags'} = \@tags;
  }
  #
  # normalize fields:
  my @replace = (
    'content\:encoded' => 'content',
    'xhtml\:body'      => 'content',
    'summary'          => 'description',
    'pubDate'          => 'published',
    'dc\:date'         => 'published',
    'created'          => 'published',
    'issued'           => 'published',
    'updated'          => 'published',
    'modified'         => 'published',
    'dc\:creator'      => 'author'

    #    'guid'             => 'link'
  );
  while (my ($old, $new) = splice(@replace, 0, 2)) {
    if ($h{$old} && !$h{$new}) {
      $h{$new} = delete $h{$old};
    }
  }
  my %copy = ('description' => 'content', link => 'id', guid => 'id');
  while (my ($fill, $required) = each %copy) {
    if ($h{$fill} && !$h{$required}) {
      $h{$required} = $h{$fill};
    }
  }
  $h{"_raw"} = $item->to_string;
  return \%h;
}

sub req_info {
  my ($tx) = pop;
  my %info = (url => $tx->req->url);
  if (my $res = $tx->success) {
    $info{'code'} = $res->code;
    if ($res->code == 200) {
      my $headers = $res->headers;
      my ($last_modified, $etag) = ($headers->last_modified, $headers->etag);
      if ($last_modified) {
        $info{last_modified} = $last_modified;
      }
      if ($etag) {
        $info{etag} = $etag;
      }
    }
    else {
      $info{'error'} = $tx->res->message;    # for not modified etc.
    }
  }
  else {
    my ($err, $code) = $tx->error;
    $info{'code'} = $code if ($code);
    $info{'error'} = $err;
  }
  return \%info;
}

# set request conditional headers from saved last_modified and etag headers
sub set_req_headers {
  my $h = pop;
  my %headers;
  $headers{'If-Modified-Since'} = $h->{last_modified} if ($h->{last_modified});
  $headers{'If-None-Match'}     = $h->{etag}          if ($h->{etag});
  return %headers;
}

# find_feeds - get RSS/Atom feed URL from argument.
# Code adapted to use Mojolicious from Feed::Find by Benjamin Trott
# Any stupid mistakes are my own
sub find_feeds {
  my $self = shift;
  my $url  = shift;
  my $cb   = (ref $_[-1] eq 'CODE') ? pop @_ : undef;
  $self->ua->max_redirects(5)->connect_timeout(30);
  my $main = sub {
    my ($tx) = @_;
    my @feeds;
    return unless ($tx->success && $tx->res->code == 200);
    eval { @feeds = _find_feed_links($self, $tx->req->url, $tx->res); };
    if ($@) {
      croak "Exception in find_feeds - ", $@;
    }
    return (@feeds);
  };
  if ($cb) {    # non-blocking:
    $self->ua->get(
      $url,
      sub {
        my ($ua, $tx) = @_;
        my (@feeds) = $main->($tx);
        $cb->(@feeds);
      }
    );
  }
  else {
    my $tx = $self->ua->get($url);
    return $main->($tx);
  }
}

sub _find_feed_links {
  my ($self, $url, $res) = @_;

  state $feed_ext = qr/\.(?:rss|xml|rdf)$/;
  my @feeds;

  # use split to remove charset attribute from content_type
  my ($content_type) = split(/[; ]+/, $res->headers->content_type);
  if ($is_feed{$content_type}) {
    push @feeds, Mojo::URL->new($url)->to_abs;
  }
  else {
    # we are in a web page. PHEAR.
    my $base = Mojo::URL->new(
      $res->dom->find('head base')->pluck('attr', 'href')->join('') || $url);
    my $title
      = $res->dom->find('head > title')->pluck('text')->join('') || $url;
    $res->dom->find('head link')->each(
      sub {
        my $attrs = $_->attr();
        return unless ($attrs->{'rel'});
        my %rel = map { $_ => 1 } split /\s+/, lc($attrs->{'rel'});
        my $type = ($attrs->{'type'}) ? lc trim $attrs->{'type'} : '';
        if ($is_feed{$type} && ($rel{'alternate'} || $rel{'service.feed'})) {
          push @feeds, Mojo::URL->new($attrs->{'href'})->to_abs($base);
        }
      }
    );
    $res->dom->find('a')->grep(
      sub {
        $_->attr('href')
          && Mojo::URL->new($_->attr('href'))->path =~ /$feed_ext/io;
      }
      )->each(
      sub {
        push @feeds, Mojo::URL->new($_->attr('href'))->to_abs($base);
      }
      );
    unless (@feeds)
    {    # call me crazy, but maybe this is just a feed served as HTML?
      if (parse_rss_dom($self, $res->dom)) {
        push @feeds, Mojo::URL->new($url)->to_abs;
      }
    }
  }
  return @feeds;
}


1;

=encoding utf-8

=head1 NAME

Mojolicious::Plugin::FeedReader - Mojolicious Plugin to fetch and parse RSS & Atom feeds

=head1 SYNOPSIS

        # Mojolicious
         $self->plugin('FeedReader');

         # Mojolicious::Lite
         plugin 'FeedReader';

        # Blocking:
        get '/b' => sub {
          my $self = shift;
          my ($info, $feed) = $self->find_feeds(q{search.cpan.org});
          my $out = $self->parse_rss($feed);
          $self->render(template => 'uploads', items => $out->{items});
        };

        # Non-blocking:
        get '/nb' => sub {
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
                $self->render(template => 'uploads', items => $data->{items});
            });
          $delay->wait unless Mojo::IOLoop->is_running;
        };

        app->start;

        __DATA__

        @@ uploads.html.ep
        <ul>
        % for my $item (@$items) {
          <li><%= link_to $item->{title} => $item->{link} %> - <%= $item->{description} %></li>
        % }
        </ul>

=head1 DESCRIPTION

B<Mojolicious::Plugin::FeedReader> implements minimalistic helpers for identifying,
fetching and parsing RSS and Atom Feeds.  It has minimal dependencies, relying as
much as possible on Mojolicious components - Mojo::UserAgent for fetching feeds and
checking URLs, Mojo::DOM for XML/HTML parsing.
It is therefore rather fragile and naive, and should be considered Experimental/Toy
code - B<use at your own risk>.


=head1 METHODS

L<Mojolicious::Plugin::FeedReader> inherits all methods from
L<Mojolicious::Plugin> and implements the following new ones.

=head2 register

  $plugin->register(Mojolicious->new);

Register plugin in L<Mojolicious> application. This method will install the helpers
listed below in your Mojolicious application.

=head1 HELPERS

B<Mojolicious::Plugin::FeedReader> implements the following helpers.

=head2 find_feeds

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

A Mojolicious port of L<Feed::Find> by Benjamin Trott. This helper implements feed auto-discovery for finding syndication feeds, given a URI.
If given a callback function as an additional argument, execution will be non-blocking.

=head2 parse_rss

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

Dates are parsed using L<HTTP::Date>.

If parsing fails (for example, the parser was given an HTML page), the helper will return undef.

On success, the result returned is a hashref with the following keys:

=over 4

=item * title

=item * description

=item * htmlUrl - web page URL associated with the feed

=item * items - array ref of feed news items

=item * subtitle (optional)

=item * tagline (optional)

=item * author (optional)

=item * published (optional)

=back

Each item in the items array is a hashref with the following keys:

=over 4

=item * title

=item * link

=item * content

=item * id

=item * description (optional) - usually a shorter form of the content

=item * guid (optional)

=item * published (optional)

=item * author (optional)

=item * tags (optional) - array ref of tags or categories.

=item * _raw - XML serialized text of the item's Mojo::DOM node. Note that this can be different from the original XML text in the feed.

=back

=head1 CREDITS

Some tests adapted from L<Feed::Find> and L<XML::Feed>. Feed autodiscovery adapted from l<Feed::Find>.

Test data (web pages, feeds and excerpts) included in this package is intended for testing purposes only, and is not meant in anyway
to infringe on the rights of the respective authors.

=head1 COPYRIGHT AND LICENSE

Copyright (C) 2014, Dotan Dimet.

This program is free software, you can redistribute it and/or modify it
under the terms of the Artistic License version 2.0.

=head1 SEE ALSO

L<Mojolicious>, L<Mojolicious::Guides>, L<http://mojolicio.us>

L<XML::Feed>, L<Feed::Find>, L<HTTP::Date>

=cut
