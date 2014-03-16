package Mojolicious::Plugin::FeedReader;
use Mojo::Base 'Mojolicious::Plugin';

our $VERSION = '0.01';
use Mojo::Util qw(decode slurp trim);
use Mojo::DOM;
use Mojo::IOLoop;
use HTTP::Date;

sub register {
  my ($self, $app) = @_;
  foreach my $method (
    qw(process_feed parse_rss parse_rss_dom parse_rss_channel parse_rss_item find_feeds set_req_headers req_info)
    )
  {
    $app->helper($method => \&{$method});
  }
}

sub parse_rss {
  my ($c, $xml, $cb) = @_;
  my $dom;
  if (!ref $xml) { # assume file
    my $rss_str  = decode 'UTF-8', slurp $xml;
    die "Failed to read file $xml (as UTF-8): $!" unless ($rss_str);
    $dom = Mojo::DOM->new->parse($rss_str);
  }
  elsif (ref $xml eq 'SCALAR') { # assume string
    $dom = Mojo::DOM->new->parse($$xml);
  }
  elsif ($xml->can('slurp')) { # assume Mojo::Asset
    my $rss_str  = decode 'UTF-8', $xml->slurp;
    die "Failed to read asset $xml (as UTF-8): $!" unless ($rss_str);
    $dom = Mojo::DOM->new->parse($rss_str);
  }
  elsif ($xml->isa('Mojo::DOM')) {
    $dom = $xml;
  }
  elsif ($xml->isa('Mojo::URL')) {
    # this is the only case where we might go non-blocking:
    if ($cb) {
      $c->ua->get($xml, sub {
          my ($ua, $tx) = @_;
          my $feed;
          if ($tx->success) {
            eval {
              $feed = $c->parse_rss_dom($tx->res->dom);
            };
          }
          $c->$cb($feed);
       });
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
  my $feed = $self->parse_rss_channel($dom); # Feed properties
  my $items = $dom->find('item');
  my $entries = $dom->find('entry'); # Atom
  my $res = [];
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
  foreach my $k (qw{title subtitle description tagline link:not([rel]) link[rel=alternate]}) {
    my $p = $dom->at("channel > $k") || $dom->at("feed > $k"); # direct child
    if ($p) {
      $info{$k} = $p->text || $p->content || $p->attr('href');
    }
  }
  my ($htmlUrl) = grep { defined $_ } map { delete $info{$_} } ('link:not([rel])','link[rel=alternate]');
  my ($description) = grep { defined $_ } map { exists $info{$_} ? $info{$_} : undef } ( qw(description tagline subtitle) );
  $info{htmlUrl} = $htmlUrl if ($htmlUrl);
  $info{description} = $description if ($description);

  return ( keys %info) ? \%info : undef;
}

sub parse_rss_item {
    my ($self, $item) = @_;
    my %h;
    foreach my $k (qw(title id summary guid content description content\:encoded xhtml\:body pubDate published updated dc\:date)) {
      my $p = $item->at($k);
      if ($p) {
        # skip namespaced items - like itunes:summary - unless explicitly
        # searched:
        next if ($p->type =~ /\:/ && $k ne 'content\:encoded' && $k ne 'xhtml\:body' && 'dc\:date');
        $h{$k} = $p->text || $p->content;
        if ($k eq 'pubDate' || $k eq 'published' || $k eq 'updated' || $k eq 'dc\:date') {
          $h{$k} = str2time($h{$k});
        }
      }
    }
    # let's handle links seperately, because ATOM loves these buggers:
    $item->find('link')->each( sub {
      my $l = shift;
      if ($l->attr('href')) {
        if (!$l->attr('rel') || $l->attr('rel') eq 'alternate') {
          $h{'link'} = $l->attr('href');
        }
      }
      else {
        if ($l->text =~ /\w+/) {
          $h{'link'} = $l->text; # simple link
        }
#         else { # we have an empty link element with no 'href'. :-(
#           $h{'link'} = $1 if ($l->next->text =~ m/^(http\S+)/);
#         }
       }
    });
    # find tags:
    my @tags;
    $item->find('category, dc\:subject')->each(sub { push @tags, $_[0]->text || $_[0]->attr('term') } );
    if (@tags) {
      $h{'tags'} = \@tags;
    }
    #
    # normalize fields:
                my %replace = (
                    'content\:encoded' => 'content',
                    'xhtml\:body'      => 'content',
                    'pubDate'          => 'published',
                    'dc\:date'         => 'published',
                    'summary'          => 'description',
                    'updated'          => 'published',
                #    'guid'             => 'link'
                );
    while (my ($old, $new) = each %replace) {
    if ($h{$old} && ! $h{$new}) {
      $h{$new} = delete $h{$old};
    }
    }
    my %copy = ('description' => 'content', link => 'id',  guid => 'id');
    while (my ($fill, $required) = each %copy) {
      if ($h{$fill} && ! $h{$required}) {
        $h{$required} = $h{$fill};
      }
    }
    $h{"_raw"} = $item->to_string;
    return \%h;
}

sub req_info {
  my ($tx) = pop;
  my %info = ( url => $tx->req->url );
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
        $info{'error'} = $tx->res->message; # for not modified etc.
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
  $headers{'If-None-Match'} = $h->{etag} if ($h->{etag});
  return %headers;
}
# find_feeds - get RSS/Atom feed URL from argument.
# Code adapted to use Mojolcious from Feed::Find by Benjamin Trott
# Any stupid mistakes are my own
sub find_feeds {
  my $self = shift;
  my $url  = shift;
  my $cb   = ( ref $_[-1] eq 'CODE' ) ? pop @_ : sub { return @_; };
  $self->ua->max_redirects(5)->connect_timeout(30);
  my $delay = Mojo::IOLoop->delay(
    sub {
      $self->ua->get($url, $_[0]->begin(0));
    },
    sub {
      my ($del, $ua, $tx ) = @_;
      my $req_info = req_info($tx);
      my @feeds;
      if ( $req_info->{code} == 200 ) {
        eval {
          @feeds = _find_feed_links( $self, $tx->req->url, $tx->res );
        };
        if ($@) {
          $req_info->{'error'} = $@;
        }
        if (@feeds == 0) {
          $req_info->{'error'} = 'no feeds found';
        }
      }
      $del->pass($req_info, @feeds);
    },
    sub { $cb->(@_); }
  );
  $delay->wait unless Mojo::IOLoop->is_running;
}

sub _find_feed_links {
  my ( $self, $url, $res ) = @_;
  my %is_feed = map { $_ => 1 } (

    # feed mime-types:
    'application/x.atom+xml',
    'application/atom+xml',
    'application/xml',
    'text/xml',
    'application/rss+xml',
    'application/rdf+xml',
  );
  state $feed_ext = qr/\.(?:rss|xml|rdf)$/;
  my @feeds;

  # use split to remove charset attribute from content_type
  my ($content_type) = split( /[; ]+/, $res->headers->content_type );
  if ( $is_feed{$content_type} ) {
    push @feeds, Mojo::URL->new($url)->to_abs;
  }
  else {
  # we are in a web page. PHEAR.
    my $base = Mojo::URL->new( $res->dom->find('head base')->pluck( 'attr', 'href' )->join('') || $url );
    my $title = $res->dom->find('head > title')->pluck('text')->join('') || $url;
    $res->dom->find('head link')->each(
      sub {
        my $attrs = $_->attr();
        return unless ( $attrs->{'rel'} );
        my %rel = map { $_ => 1 } split /\s+/, lc( $attrs->{'rel'} );
        my $type = ( $attrs->{'type'} ) ? lc trim $attrs->{'type'} : '';
        if ( $is_feed{$type}
          && ( $rel{'alternate'} || $rel{'service.feed'} ) )
        {
          push @feeds,
            Mojo::URL->new( $attrs->{'href'} )->to_abs( $base );
        }
      }
    );
    $res->dom->find('a')->grep(
      sub {
        $_->attr('href')
          && Mojo::URL->new( $_->attr('href') )->path =~ /$feed_ext/io;
      }
      )->each(
      sub {
        push @feeds,
          Mojo::URL->new( $_->attr('href') )->to_abs( $base );
      }
      );
    unless (@feeds) { # call me crazy, but maybe this is just a feed served as HTML?
      if ( parse_rss_dom($self, $res->dom)->{items} > 0) {
        push @feeds, Mojo::URL->new($url)->to_abs;
      }
    }
  }
  return @feeds;
}


sub process_feed {
  my ($self, $tx) = @_;
  my $req_info = req_info($tx);
  my $feed;
  if (!defined $req_info->{error} && $req_info->{'code'} == 200) {
    eval {
      $feed = $self->parse_rss( $tx->res->dom );
    };
    if ($@) { # assume no error from tx, because code is 200
      $req_info->{'error'} = $@;
    }
    if (!$feed && ! defined $req_info->{'error'}) {
      $req_info->{'error'} = 'url no longer points to a feed';
    }
  }
 return ($feed, $req_info);
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

=head1 DESCRIPTION

B<Experimental / Toy code !!! use at your own risk!!!>

B<Mojolicious::Plugin::FeedReader> implements helpers for identifying, fetching and parsing RSS and Atom Feeds.
It has minimal dependencies, relying as much as possible on Mojo:: components (Mojo::UserAgent, Mojo::DOM).
It therefore is probably pretty fragile.

=head1 METHODS

L<Mojolicious::Plugin::FeedReader> inherits all methods from
L<Mojolicious::Plugin> and implements the following new ones.

=head2 register

  $plugin->register(Mojolicious->new);

Register plugin in L<Mojolicious> application. This method will install the helpers
listed below in your Mojolicious application.

=head1 HELPERS

B<Mojolicious::Plugin::FeedReader> adds the following helpers.

=head2 find_feeds

=head2 parse_rss

=head1 SEE ALSO

L<Mojolicious>, L<Mojolicious::Guides>, L<http://mojolicio.us>.

=cut
