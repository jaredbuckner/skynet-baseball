#!/usr/bin/perl -w

use Getopt::Long;

use strict;

use lib '.';
use Player;

my $StrikeFile = "data/strike.list";

my @StrikeThese;
my @UnstrikeThese;
my @HideThese;

unless(GetOptions("hide=s" => \@HideThese,
                  "strike=s" => \@StrikeThese,
                  "unstrike=s" => \@UnstrikeThese)) {
    die("Error while reading options.\n");
}

@HideThese = map { (split(':', $_)) } @HideThese;

my %HideMap;
for my $Hidden (@HideThese) {
    unless(grep {uc ($Hidden) eq $_} Player->allPositions()) {
        die("Unknown position:  $Hidden\n");
    }
    $HideMap{uc($Hidden)} = 1;
}

@StrikeThese = map { (split(':', $_)) } @StrikeThese;
@UnstrikeThese = map { (split(':', $_)) } @UnstrikeThese;

if(@ARGV) {
    die("Unknown options:  ", join(', ', @ARGV), "\n");
}

Player->fillData('data');

my %AlreadyStruck;
my $UpdatedStrike = loadStrike($StrikeFile, \%AlreadyStruck);

foreach(@StrikeThese) {
    my $DidStrike = strikePlayer($_, \%AlreadyStruck);
    $UpdatedStrike ||= $DidStrike;
}

foreach(@UnstrikeThese) {
    my $DidUnstrike = unstrikePlayer($_, \%AlreadyStruck);
    $UpdatedStrike ||= $DidUnstrike;
}

saveStrike($StrikeFile, \%AlreadyStruck) if($UpdatedStrike);

## How many owners will draft this season?
my $DraftingOwners = 12;

## How many total players will be drafted for each position?
my %PositionDepth;
my %PositionFill;
my %PositionPlayers;  ## Empty position contains all players chosen

#my @FillSlots = Player->allSlots();
my @FillSlots = Player->playSlots();

for my $Pos (@FillSlots) {
    $PositionDepth{$Pos} += $DraftingOwners;
    $PositionFill{$Pos} = 0;
}

## For striking...
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

@PlayersPos = sort { 
    (slack(@$b) <=> slack(@$a))
        || ($b->[0]->fptsWtd() <=> $a->[0]->fptsWtd())
} @PlayersPos;


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
    return if(exists($AlreadyStruck{$Player}) ||
              (defined($Pos) && exists($HideMap{$Pos})));
    
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

sub strikePlayer {
    my ($Expr, $StrikeMapRef) = @_;
    my $Player = matchPlayer($Expr);
    unless(exists($StrikeMapRef->{$Player})) {
        $StrikeMapRef->{$Player} = $Player;
        return(1);
    }

    warn("Cannot overstrike player ", $Player->name(), "\n");
    return(0);
}

sub unstrikePlayer {
    my ($Expr, $StrikeMapRef) = @_;
    my $Player = matchPlayer($Expr);
    if(exists($StrikeMapRef->{$Player})) {
        delete $StrikeMapRef->{$Player};
        return(1);
    }

    warn("Cannot understrike player ", $Player->name(), "\n");
    return(0);
}

sub loadStrike {
    my ($File, $StrikeMapRef) = @_;
    my $Rewrite = 0;
    
    if(open(SF, "<$File")) {
        while(defined(my $Line = <SF>)) {
            my $Result = strikePlayer($Line, $StrikeMapRef);
            $Rewrite ||= !$Result;
        }
        
        close(SF);
    } else {
        warn("Unable to read $File : $!\n");
        $Rewrite = 1;
    }

    return($Rewrite);
}

sub saveStrike {
    my ($File, $StrikeMapRef) = @_;
    if(open(SF, ">$File")) {
        for my $Player (values %$StrikeMapRef) {
            print SF ($Player->name(), "\n");
        }
        close(SF);
    } else {
        die("Unable to write $File : $!\n");
    }
}
