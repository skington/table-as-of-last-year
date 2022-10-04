#!/usr/bin/env perl
# Loads last year's results, and this year's results so far, and combines the two.

use strict;
use warnings;

use English qw(-no_match_vars);

use JSON::MaybeXS;

# Load last year's results, and this year's results.
my %game_results = (
    last_year => _read_json_file('2021-2022'),
    this_year => _read_json_file('2022-2023'),
);

# Replace last year's relegated teams with this year's promoted teams.
_replace_last_year_team('Burnley' => 'Fulham');
_replace_last_year_team('Watford' => 'Bournemouth');
_replace_last_year_team('Norwich' => q{Nott'm Forest});

# Derive the results.
my %team_results = (map { $_ => _tally_game_results($game_results{$_}) } qw(last_year this_year));

# And work out the table.
my @table = generate_table();

# And print it.
print_table(@table);

# Supplied with a season spec - e.g. "2021-2022" - reads its results from JSON.

sub _read_json_file {
    my ($season_spec) = @_;

    open my $fh, '<', "data/$season_spec.json" or die "Couldn't read $season_spec: $OS_ERROR";
    my $json;
    {
        local $/ = undef;
        $json = <$fh>;
    }
    return JSON::MaybeXS->new->decode($json);
}

# Supplied with the name of a relegated team, and a promoted team, replaces the relegated team in
# last year's results with the promoted team.

sub _replace_last_year_team {
    my ($relegated_team, $promoted_team) = @_;

    for my $date (keys %{ $game_results{last_year} }) {
        for my $game_result (@{ $game_results{last_year}{$date} }) {
            for my $team_field (qw(home_team away_team)) {
                if ($game_result->{$team_field} eq $relegated_team) {
                    $game_result->{$team_field} = $promoted_team;
                    $game_result->{relegation}++;
                }
            }
        }
    }
}

# Supplied with a hashref of date => [ game results], return a hash of
# { team => { opposing_team => { home => ..., away => ... } } }

sub _tally_game_results {
    my ($yearly_game_results) = @_;

    my %team_results;
    for my $date (keys %$yearly_game_results) {
        for my $game_result (@{ $yearly_game_results->{$date} }) {
            $team_results{ $game_result->{home_team} }{ $game_result->{away_team} }{home}
                = { %$game_result, _game_wld(side => 'home', %$game_result) };
            $team_results{ $game_result->{away_team} }{ $game_result->{home_team} }{away}
                = { %$game_result, _game_wld(side => 'away', %$game_result) };
        }
    }
    return \%team_results;
}

sub _game_wld {
    my (%args) = @_;

    my ($subjective_result, $goal_difference);
    if ($args{home_score} == $args{away_score}) {
        $subjective_result = 0;
        $goal_difference = 0;
    } else {
        my $home_result = $args{home_score} > $args{away_score} ? 1 : -1;
        my $home_goal_difference = $args{home_score} - $args{away_score};
        $subjective_result = $args{side} eq 'home' ? $home_result : -$home_result;
        $goal_difference = $args{side} eq 'home' ? $home_goal_difference : -$home_goal_difference;
    }
    return (
        wld             => { 1 => 'W', 0 => 'D', -1 => 'L' }->{$subjective_result},
        goal_difference => $goal_difference
    );
}

# Works out the table for this year, using this year's results if we have them, and otherwise
# assuming last year's. Returns a list of hashrefs, from most points to fewest.

sub generate_table {
    my %team_stats;

    for my $team (keys %{$team_results{this_year}}) {
        for my $opposing_team (grep { $_ ne $team } keys %{ $team_results{this_year} }) {
            for my $fixture (qw(home away)) {
                my $game_result = $team_results{this_year}{$team}{$opposing_team}{$fixture}
                    || $team_results{last_year}{$team}{$opposing_team}{$fixture};
                $team_stats{$team}{played}++;
                $team_stats{$team}{$game_result->{wld}}++;
                $team_stats{$team}{goal_difference} += $game_result->{goal_difference};
                $team_stats{$team}{points} += { W => 3, D => 1, L => 0}->{$game_result->{wld}};
            }
        }
    }
    return
        map  { { team => $_, %{$team_stats{$_}} } }
        sort {
               $team_stats{$b}{points} <=> $team_stats{$a}{points}
            || $team_stats{$b}{goal_difference} <=> $team_stats{$a}{goal_difference}
        }
        keys %team_stats;
}

# Supplied with a list of hashrefs, prints a football table of them.

sub print_table {
    my (@table) = @_;

    my $position = 1;
    printf("P  %30s P  W  D  L  GD  Pts\n", 'Team');
    for my $team_stats (@table) {
        printf("%-2d %-30s %2d %2d %2d %2d %3d %2d\n",
            $position++, @$team_stats{qw(team played W D L goal_difference points)});
    }
}
