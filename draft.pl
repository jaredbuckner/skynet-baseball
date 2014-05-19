#!/usr/bin/perl -w

use strict;

use lib '.';
use Player;

Player->fillData('data');

## How many owners will draft this season?
my $DraftingOwners = 18;

## How many total players will be drafted for each position?
my %PositionDepth;
my %PositionFill;
my %PositionPlayers;  ## Empty position contains all players chosen

for my $Pos (Player->allSlots()) {
    $PositionDepth{$Pos} += $DraftingOwners;
    $PositionFill{$Pos} = 0;
}

print(join('  ', Player->allSlots()), "\n\n");

## Sort the players by fptsWtd
my @AllPlayers = sort { $b->fptsWtd() <=> $a->fptsWtd() } Player->allPlayers();

my @PositionsRemaining = keys %PositionFill;

for my $Player (@AllPlayers) {
    my @AvailPos = grep { $Player->plays($_) } @PositionsRemaining;
    next unless(@AvailPos);
    
    my $AddedToEmptyPos = 0;
    my $UpdateRemaining = 0;
    for my $Pos (@AvailPos) {
        push(@{$PositionPlayers{$Pos}}, $Player);
        unless($AddedToEmptyPos) {
            push(@{$PositionPlayers{''}}, $Player);
            $AddedToEmptyPos = 1;
        }
        next unless $Player->isActive();
        
        $PositionFill{$Pos} += 1.0 / @AvailPos;
        if($PositionFill{$Pos} - $PositionDepth{$Pos} >= -0.0001) {
            $UpdateRemaining = 1;
        }
    }
    
    if($UpdateRemaining) {
        @PositionsRemaining = grep { $PositionFill{$_} - $PositionDepth{$_} < -0.0001 } keys %PositionFill;
    }
    
    last unless(@PositionsRemaining);
}

my @ValuablePlayers = sort { $a->name() cmp $b->name() } @{$PositionPlayers{''}};

my @PlayersPos;
for my $Pos (Player->allPositions()) {
    for my $Player (@{$PositionPlayers{$Pos}}) {
        push(@PlayersPos, [$Player, $Pos]);
    }
}

@PlayersPos = sort { slack(@$b) <=> slack(@$a) } @PlayersPos;


print "===== Position Order =====\n";
for my $PPRef (@PlayersPos) {
    my ($Player, $Pos) = @$PPRef;
    
    printPlayer($Player, $Pos);
}

print "\n\n===== Name Order\n";
for my $Player (@ValuablePlayers) {
    printPlayer($Player);
}

exit(0);

sub slack {
    my ($Player, $Pos) = @_;
    my $SlackBase = $PositionPlayers{$Pos}->[-1]->fptsWtd();
    return($Player->fptsWtd() - $SlackBase);
}

sub printPlayer {
    my ($Player, $Pos) = @_;
    
    if(defined($Pos)) {
        printf("%-2s %6.2f  ",
               $Pos,
               slack($Player, $Pos));
    } else {
        printf("%-2s %6s  ",
               '',
               '');
    }
    printf("[%6.2f] %s %-27s",
           $Player->fptsWtd(),
           ($Player->isActive() ? '*' : ' ' ),
           $Player->name());
    for my $OtherPos (sort { slack($Player, $b) <=> slack($Player, $a) }
                      $Player->pos()) {
        if(!defined($Pos) || $OtherPos ne $Pos) {
            printf("  %2s:%7.2f",
                   $OtherPos, slack($Player, $OtherPos));
        }
    }
    
    print("\n");
}
