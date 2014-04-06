use Mojo::Base -strict;

use Test::More;
use Test::Mojo;

use Mojolicious::Lite;

plugin 'FeedReader';

my $sample_dir = File::Spec->catdir($FindBin::Bin, 'samples');
push @{app->static->paths}, $sample_dir;
my $t = Test::Mojo->new(app);

# test files:
my %files = (
  google_reader => File::Spec->catdir($sample_dir, 'subscriptions.xml'),
  sputnik       => File::Spec->catdir($sample_dir, 'sputnik-feeds.opml.xml'),
  rssowl        => File::Spec->catdir($sample_dir, 'rssowl.opml')
);

for my $type (qw(google_reader sputnik rssowl)) {
  my $opml = $files{$type};
  diag("testing with $type export");
  my @feeds = app->parse_opml( $opml );
  is(scalar @feeds, 294, 'got 294 feeds');
  ok(defined $feeds[0]{xmlUrl}, "xmlUrl defined");
  ok(defined $feeds[293]{xmlUrl}, "xmlUrl defined");
  my $feedcount = scalar grep { defined $_->{xmlUrl} } @feeds;
  is($feedcount, 294, 'all feeds defined');
  ok(defined $feeds[0]{$_}, "$_ defined") for (qw(htmlUrl text));
  ok(defined $feeds[293]{$_}, "$_ defined") for (qw(htmlUrl text));
  my ($frew) = grep { $_->{xmlUrl} =~ /Foolish/ } @feeds;
  say $frew->{xmlUrl} , " is sub I will test";
  my @cats = sort @{$frew->{categories}};
  is($cats[0], 'perl', $frew->{xmlUrl} . ' is in category perl');
  is(scalar @cats, 1, $frew->{xmlUrl} . ' is in one category');
  my ($abn) = grep { $_->{xmlUrl} =~ /wrongquest/ } @feeds;
  say $abn->{xmlUrl} , " is sub I will test";
  @cats = sort @{$abn->{categories}};
  is($cats[0], 'a-list', $abn->{xmlUrl} . ' is in category a-list');
  is($cats[1], 'books', $abn->{xmlUrl} . ' is in category books');
  is($cats[2], 'friends', $abn->{xmlUrl} . ' is in category friends');
  is(scalar @cats, 3, $abn->{xmlUrl} . ' is in three categories');
}

done_testing();
