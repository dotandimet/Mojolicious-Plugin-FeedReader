use strict;
use warnings;

use ExtUtils::MakeMaker;

WriteMakefile(
    NAME         => 'Mojolicious::Plugin::FeedReader',
    VERSION_FROM => 'lib/Mojolicious/Plugin/FeedReader.pm',
    AUTHOR       => 'Dotan Dimet <dotan@corky.net>',
    PREREQ_PM    => {
        'Mojolicious' => '4.85',
        'HTTP::Date'  => '6.02',
        'Time::Zone'  => '2.2'
    },
    test => { TESTS => 't/*.t' }
);
