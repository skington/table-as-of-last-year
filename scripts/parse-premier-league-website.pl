#!/usr/bin/env perl
# Data is the contents of e.g. https://www.premierleague.com/results?co=1&se=489&cl=-1
# cut and pasted from a web browser (after manually scrolling down and waiting for all data to load
# in Javascript; this is why I haven't just scraped the website).

use strict;
use warnings;

use Date::Parse qw(strptime);
use JSON::MaybeXS;

my %result_by_date;
my %state;
my @game_stats = qw(home_team home_score away_team away_score);
line:
while (<>) {
    chomp;
    # A date means "all games after this the list were played on this date"
    /^ \S+ \s \d{1,2} \s \S+ \s \d{4} $/x and do {
        my (undef, undef, undef, $day, $month, $year) = strptime($_);
        $state{date} = sprintf('%04d-%02d-%02d', $year + 1900, $month, $day);
        next line;
    };
    
    # Blank lines, "Premier League" or "Highlights availale" are useless furniture.
    next line if !/\S/ || /Premier League/ || /Highlights available/i;

    # A score is obvious (old format).
    /^ \s* (?<home_score> \d+ ) - (?<away_score> \d+ ) /x and do {
        %state = (%state, %+);
        next line;
    };

    # Just a number, or "A" for abandoned, is part of a score. The - between is furniture.
    if (my ($score_value) = /^ ( \d+ | A ) $/x) {
        my $score_name = exists $state{home_score} ? 'away_score' : 'home_score';
        $state{$score_name} = $score_value;
        next line;
    }
    next line if $_ eq '-';

    # Anything else is a team name.
    if (!$state{home_team}) {
        $state{home_team} = $_;
        next line;
    }

    # If this is the second name we've seen, we've got all the information we need about this game
    # now.
    $state{away_team} = $_;
    unless ($state{home_score} eq 'A' && $state{away_score} eq 'A') {
        push @{ $result_by_date{$state{date}} }, { %state{@game_stats} };
    }
    delete @state{@game_stats};
}

my $json = JSON::MaybeXS->new(pretty => 1, canonical => 1);
print $json->encode(\%result_by_date);


