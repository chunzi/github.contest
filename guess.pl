#!/usr/bin/perl
# github.com/chunzi

use strict;
use File::Slurp;
use Math::Complex;
use Class::Date qw/date/;

my $repos = {};
my $user = {};
local $|=1;

#-------------------------------------------
print "loading data...\n";
for ( grep { chomp } read_file('repos.txt') ){
    my ( $rid, $rest ) = split(':', $_);
    my ( $path, $created, $frid ) = split(',', $rest);
    my ( $owner, $name ) = split('/', $path);

    my @keywords = split(/\W/, $name);
    $repos->{$rid} = {
        rid => $rid,
        name => $name,
        keywords => \@keywords,
        owner => $owner,
        created => int(date($created)->epoch/86400),
        forked => $frid,
    };
}
for ( grep { chomp } read_file('lang.txt') ){
    my ( $rid, $rest ) = split(':', $_);
    my @parts = split(',', $rest);
    map {
        my ( $lang, $lines ) = split(';', $_);
        $repos->{$rid}{'lang'}{$lang} = length $lines;
    } @parts;
}
for ( grep { chomp } read_file('data.txt') ){
    my ( $uid, $rid ) = split(':', $_);
    push @{$repos->{$rid}{'followed'}}, $uid;
    push @{$user->{$uid}}, $rid;
}
my @test = grep { chomp } read_file('test.txt');
my $left = scalar @test;


#-------------------------------------------
print "caculating popular repos topten...\n";
my @popular_repos = sort { scalar @{$repos->{$b}{'followed'}} <=> scalar @{$repos->{$a}{'followed'}} } 
                    grep { exists $repos->{$_}{'followed'} } keys %$repos;
my @popular_repos_topten = splice( @popular_repos, 0, 10);


#-------------------------------------------
printf "caculating tastes for all the %d repos...\n", scalar keys %$repos;
for my $rid ( keys %$repos ){
    my $repo = $repos->{$rid};
    my $taste = {};
    $taste->{'owner'}{$repo->{'owner'}}++; 
    map { $taste->{'followed'}{$_}++ } @{$repo->{'followed'}};
    map { $taste->{'keywords'}{$_}++ } @{$repo->{'keywords'}};
    map { $taste->{$rid}{'lang'}{$_} += $repo->{'lang'}{$_} } keys %{$repo->{'lang'}};
    $repo->{'taste'} = $taste;
}


#-------------------------------------------
printf "walking through the %d tests users...\n", scalar @test;
write_file( 'results.txt', join('',
    map{ sprintf "%s:%s\n", $_, join(',', guess($_)) } @test
));
exit;




#-------------------------------------------
sub guess {
    my $uid = shift;
    return @popular_repos_topten unless exists $user->{$uid};
    printf "%d) uid %s watching %s repos, guessing...\n", --$left, $uid, scalar @{$user->{$uid}};
     
    my $taste = {};
    my $skip = {};

    my $followed = {};
    my $keywords = {};
    for ( @{$user->{$uid}} ){
        my $repo = $repos->{$_};
        $taste->{'owner'}{$repo->{'owner'}}++;
        map { $followed->{$_}++ } @{$repo->{'followed'}};
        map { $keywords->{$_}++ } @{$repo->{'keywords'}};
        map { $taste->{'lang'}{$_} += $repo->{'lang'}{$_} } keys %{$repo->{'lang'}};
        $skip->{$_}++;
    }
    my @followed_sorted = sort { $followed->{$b} <=> $followed->{$a} } keys %$followed;
    map { $taste->{'followed'}{$_} = $followed->{$_} } splice( @followed_sorted, 0, 10 );
    my @keywords_sorted = sort { $keywords->{$b} <=> $keywords->{$a} } keys %$keywords;
    map { $taste->{'keywords'}{$_} = $keywords->{$_} } splice( @keywords_sorted, 0, 10 );

    my @other = grep { ! $skip->{$_} } keys %$repos;

    my $score = {};
    for my $rid ( @other ){
        my @scores = map { score_for_tastes( $_, $taste, $repos->{$rid}{'taste'} ) }
            (qw/ owner followed keywords lang /);
        $score->{$rid} = $scores[0]*0.2 + $scores[1]*0.5 + $scores[2]*0.2 + $scores[3]*0.1;
    }

    my @sorted = ( sort { $score->{$b} <=> $score->{$a} } keys %$score )[0..20];
    my @topten = ( sort { $score->{$b} <=> $score->{$a} || $repos->{$b}{'created'} <=> $repos->{$a}{'created'} } @sorted )[0..9];

    map { 
        printf " - %-7s %.6f %-10s  %s\n", 
        $_->{'rid'}, $score->{$_->{'rid'}}, $_->{'owner'}, $_->{'name'}
    } map { $repos->{$_} } @topten;

    return @topten;
}

sub score_for_tastes {
    my ( $item, $tu, $tr ) = @_;
    my $sum = 0;
    my $count = 0;
    for my $key ( keys %{$tu->{$item}} ){
        if ( exists $tr->{$item}{$key} ){
            my $rc = $tu->{$item}{$key};
            my $oc = $tr->{$item}{$key};
            $sum += ($rc-$oc)**2;
            $count++;
        }
    }
    return 0 if $count == 0;
    my $score = 1 / ( 1 + sqrt($sum) );
    return $score;
} 

