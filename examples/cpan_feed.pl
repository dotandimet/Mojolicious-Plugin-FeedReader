#!/usr/bin/env perl

use Mojolicious::Lite;
use FindBin;
use lib $FindBin::Bin . '/../lib';

plugin 'FeedReader';

get '/' => sub {
  my $self = shift;
  $self->render_later;
  my $delay = Mojo::IOLoop->delay(
    sub {
      my $delay = shift;
      $self->find_feeds("search.cpan.org", $delay->begin(0));
    },
    sub {
      my $delay = shift;
      my $feed = pop;
      $self->parse_rss($feed, $delay->begin);
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
