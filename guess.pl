#!/usr/bin/perl
# github.com/chunzi

use strict;
use File::Slurp;
use Math::Complex;
use Data::Dumper;
use Time::Progress;
local $|=1;

my $simrepos_cache = {};
my $score_cache = {};
my $repos = {};
my $repos_name_keys = {};

# load
print "loading data...\n";
for ( grep { chomp } read_file('repos.txt') ){
    my ( $rid, $rest ) = split(':', $_);
    my ( $path, $date, $frid ) = split(',', $rest);
    my ( $owner, $name ) = split('/', $path);

    my @name_keys = split(/\W/, $name);
    map { push @{$repos_name_keys->{$_}}, $rid } @name_keys;

    $repos->{$rid} = {
        id => $rid,
        name => $name,
        name_keys => \@name_keys,
        owner => $owner,
        created => $date,
        forked => $frid,
    };
}
for ( grep { chomp } read_file('lang.txt') ){
    my ( $rid, $rest ) = split(':', $_);
    my @parts = split(',', $rest);
    map {
        my ( $lang, $lines ) = split(';', $_);
        $repos->{$rid}{'lang'}{$lang} = $lines;
    } @parts;
}
my $user = {};
for ( grep { chomp } read_file('data.txt') ){
    my ( $uid, $rid ) = split(':', $_);
    push @{$repos->{$rid}{'watched_by'}}, $uid;
    push @{$user->{$uid}}, $rid;
}


# prepare
print "caculating pref...\n";
my $pref = {};
for my $rid ( keys %$repos ){
    my $rep = $repos->{$rid};

    $pref->{$rid}{'owner'}{$repos->{'owner'}}++; 
    for my $uid ( @{$repos->{$rid}{'watched_by'}} ){
        $pref->{$rid}{'watched_by'}{$uid}++;
    }

    for my $key ( @{$repos->{$rid}{'name_keys'}} ){
        $pref->{$rid}{'repos_name'}{$key}++;
    }

    for my $lang ( keys %{$repos->{$rid}{'lang'}} ){
        $pref->{$rid}{'lang'}{$lang} += $repos->{$rid}{'lang'}{$lang};
    }
}
my @popular_repos = sort { scalar @{$repos->{$b}{'watched_by'}} <=> scalar @{$repos->{$a}{'watched_by'}} } keys %$repos;
my @popular_topten = splice(@popular_repos, 0, 10);


# output
print "walking for the tests...\n";
my @test = grep { chomp } read_file('test.txt');


my $results;
for ( @test ){
    $results .= sprintf "%s:%s\n", $_, join(',', guess($_));
}
write_file( 'results.txt', $results);
exit;






sub guess {
    my $uid = shift;
    print "uid: $_\n";
    return @popular_topten unless exists $user->{$uid};
    printf "watching: %s repos\n", scalar @{$user->{$uid}};
    
    my @similar;
    map { push @similar, @$_ } map { similar_reposes( $_ ) } @{$user->{$uid}};
    my @topten = map { $_->{'rid'} } sort { $b->{'score'} <=> $a->{'score'} } @similar;
    return @topten;
}

sub similar_reposes {
    my $rid = shift;
    printf "finding similar repos for rid: %s\n", $rid;
    return $simrepos_cache->{$rid} if exists $simrepos_cache->{$rid};

    my $distance = {};
    my $p = new Time::Progress;
    $p->restart( min => 1, max => scalar keys %$pref );
    my $ct = 0;
    for my $oid ( keys %$pref ){
        $ct++;
        next if $oid == $rid; # skip self
        $distance->{$oid} = get_score( $rid, $oid );
        print $p->report( "%60b %p\r", $ct );
    }
    $p->stop;
    print "\n";

    my @similar = sort { $distance->{$b} <=> $distance->{$a} } keys %$distance;
    my @topten = splice( @similar, 0, 10 );
    my @ret = map { { rid => $_, name => $repos->{$_}{'name'}, score => $distance->{$_} } } @topten;
    $simrepos_cache->{$rid} = \@ret;

    return \@ret;
} 

sub get_score {
    my ( $rid, $oid ) = @_;
    my $ck1 = join('.',$rid,$oid);
    my $ck2 = join('.',$oid,$rid);
    return $score_cache->{$ck1} if exists $score_cache->{$ck1};
    return $score_cache->{$ck2} if exists $score_cache->{$ck2};
    my $score_owner = distance_for_item( 'owner', $rid, $oid );
    my $score_watched_by = distance_for_item( 'watched_by', $rid, $oid );
    #my $score_repos_name = distance_for_item( 'repos_name', $rid, $oid );
    my $score_lang = distance_for_item( 'lang', $rid, $oid );
    #my $score = $score_owner*0.3 + $score_watched_by*0.4 + $score_repos_name*0.2 + $score_lang*0.1;
    my $score = $score_owner*0.4 + $score_watched_by*0.5 + $score_lang*0.1;
    $score_cache->{$ck1} = $score;
    $score_cache->{$ck2} = $score;
    return $score;
}

sub distance_for_item {
    my ( $item, $rid, $oid ) = @_;
    my $sum = 0;
    my $count = 0;
    for my $key ( keys %{$pref->{$rid}{$item}} ){
        if ( exists $pref->{$rid}{$item}{$key} ){
            my $rc = $pref->{$rid}{$item}{$key};
            my $oc = $pref->{$oid}{$item}{$key};
            $sum += ($rc-$oc)**2;
            $count++;
        }
    }
    return 0 if $count == 0;
    my $score = 1 / ( 1 + sqrt($sum) );
    return $score;
} 
