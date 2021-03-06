#!/usr/bin/perl -w

use strict;

use lib ".";
use Player;

my $SwapFrom;
my @PlayersFrom;
my @PlayersTo;

Player->fillData('data');

my @PlayerList = map { (split(':', $_)) } @ARGV;

for my $Expr (@PlayerList) {
    my $Player = matchPlayer($Expr);
    
    my $Owner = $Player->owner();
    if(defined($Owner)) {
        if($Owner eq $Player::Me) {
            push(@PlayersTo, $Player);
        } else {
            if(defined($SwapFrom)) {
                if($SwapFrom ne $Owner) {
                    die("Can't steal players from two different teams:  \"$SwapFrom\" and \"$Owner\"\n");
                }
            } else {
                $SwapFrom = $Owner;
            }
            push(@PlayersFrom, $Player);
        }
    } else {
        push(@PlayersFrom, $Player);
    }
}

for my $Player (@PlayersFrom) { $Player->chown($Player::Me); }
for my $Player (@PlayersTo)   { $Player->chown($SwapFrom); }

my %OwnerTeam;
my %OwnerTeamScore;
my %OwnerActiveScore;
my %OwnerTotalScore;

my %PlayerIsPlaying;

for my $Owner ( Player->allOwners() ) {
    warn("Generating team data for $Owner...\n");
    my @Players = Player->byOwner($Owner);
    my @ActivePlayers = grep { $_->isActive() } @Players;
    my ($TeamScore, $BestTeamRef) = Player->makeBestTeam(@Players);
    my $ActiveScore = 0;
    my $TotalScore = 0;
    
    if(defined($TeamScore)) {
        my @PlaySlots = Player->playSlots();
        
        for(my $Idx = 0; $Idx != @PlaySlots; ++$Idx) {
            $PlayerIsPlaying{$BestTeamRef->[$Idx]} = $PlaySlots[$Idx];
        }
    }
    
    $ActiveScore += $_->fptsWtd() foreach(@ActivePlayers);
    $TotalScore += $_->fptsWtd() foreach(@Players);
    
    $OwnerTeam{$Owner} = $BestTeamRef;
    $OwnerTeamScore{$Owner} = defined($TeamScore) ? $TeamScore : 0;
    $OwnerActiveScore{$Owner} = $ActiveScore;
    $OwnerTotalScore{$Owner} = $TotalScore;
}

my @Owners = sort { 
    $OwnerTeamScore{$b} <=> $OwnerTeamScore{$a}
    || $OwnerTotalScore{$b} <=> $OwnerTotalScore{$a}
} keys %OwnerTeam;

for(my $OwnerIdx = 0; $OwnerIdx != @Owners; ++$OwnerIdx) {
    my $Owner = $Owners[$OwnerIdx];
    printf("===== #%-2d  %-28s %7.2f (%7.2f, %7.2f) =====\n",
           $OwnerIdx + 1,
           $Owner,
           $OwnerTeamScore{$Owner},
           $OwnerActiveScore{$Owner},
           $OwnerTotalScore{$Owner});
    
    my @Players = sort { $b->fptsWtd() <=> $a->fptsWtd() } Player->byOwner($Owner);
    
    for my $Player (@Players) {
        printf("%-30s %11s %1s %-2s %7.2f\n",
               $Player->name(),
               join(':', (sort $Player->pos())),
               ($Player->isActive() ? '*' : ''),
               (defined($PlayerIsPlaying{$Player}) ? $PlayerIsPlaying{$Player} : ''),
               $Player->fptsWtd());
    }
    
    print("[ ", (defined($OwnerTeam{$Owner}) ?
                 join(', ', (map { $_->name() } @{$OwnerTeam{$Owner}})) :
                 'illegal roster'),
          " ]\n\n");
}

exit 0;

sub matchPlayer {
    my ($Expr) = @_;

    $Expr =~ s/^\s+//;
    $Expr =~ s/\s+$//;
    
    my @PMatches = Player->byMatch($Expr);
    
    if(@PMatches == 0) {
        die("No player matches name '$Expr'\n");
    } elsif(@PMatches == 1) {
        return($PMatches[0]);
    } else {
        die("Multiple matches for expression '$Expr': ",
            join(', ', map {$_->name()} @PMatches),
            "\n");
    }
}

