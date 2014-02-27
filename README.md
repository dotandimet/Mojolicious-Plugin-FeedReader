# NAME

Mojolicious::Plugin::FeedReader - Mojolicious Plugin to fetch and parse RSS & Atom feeds

# SYNOPSIS

        # Mojolicious
         $self->plugin('FeedReader');

         # Mojolicious::Lite
         plugin 'FeedReader';

# DESCRIPTION

__Experimental / Toy code !!! use at your own risk!!!__

__Mojolicious::Plugin::FeedReader__ implements helpers for identifying, fetching and parsing RSS and Atom Feeds.
It has minimal dependencies, relying as much as possible on Mojo:: components (Mojo::UserAgent, Mojo::DOM).
It therefore is probably pretty fragile.

# METHODS

[Mojolicious::Plugin::FeedReader](http://search.cpan.org/perldoc?Mojolicious::Plugin::FeedReader) inherits all methods from
[Mojolicious::Plugin](http://search.cpan.org/perldoc?Mojolicious::Plugin) and implements the following new ones.

## register

    $plugin->register(Mojolicious->new);

Register plugin in [Mojolicious](http://search.cpan.org/perldoc?Mojolicious) application. This method will install the helpers
listed below in your Mojolicious application.

# HELPERS

__Mojolicious::Plugin::FeedReader__ adds the following helpers.

## find\_feeds

## parse\_rss

## process\_feeds

# SEE ALSO

[Mojolicious](http://search.cpan.org/perldoc?Mojolicious), [Mojolicious::Guides](http://search.cpan.org/perldoc?Mojolicious::Guides), [http://mojolicio.us](http://mojolicio.us).
