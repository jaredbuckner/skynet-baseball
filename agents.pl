#!/usr/bin/perl -w

use strict;

use lib ".";
use Player;

my $Epsilon = 1e-6;

Player->fillData('data');

my @Owners = ($Player::Me, grep { $_ ne $Player::Me } Player->allOwners());

## [ $Agent, [ [$Player, $PlayableGain, $ActiveGain, $TeamGain], [...] ]]
my @WorthyAgents;
foreach my $Player (Player->allPlayers()) {
    if(!defined($Player->owner()) && $Player->fptsWtd() > $Epsilon) {
        push(@WorthyAgents, [ $Player, [] ]);
    }
}

@WorthyAgents = sort { $b->[0]->fptsWtd() <=> $a->[0]->fptsWtd() } @WorthyAgents;

my @AllTrades;

#foreach my $Owner ($Owners[0]) {
foreach my $Owner (@Owners) {
    warn("Analyzing $Owner ...\n");
    my @Players = Player->byOwner($Owner);
    my ($PlayableBase) = Player->makeBestTeam(@Players);
    
    $PlayableBase = 0 unless(defined($PlayableBase));
    
    for(my $Idx = 0; $Idx != @Players; ++$Idx) {
        my @RemainingPlayers = @Players;
        my $TgtPlayer = splice(@RemainingPlayers, $Idx, 1);
        
        for my $AgentDataRef (@WorthyAgents) {
            my ($Agent, $TradeListRef) = @$AgentDataRef;
            
            next unless($Agent->isCompatable($TgtPlayer));
            
            my $TeamGain = $Agent->fptsWtd() - $TgtPlayer->fptsWtd();
            my $ActiveGain;
            my $PlayableGain;
            
            if($Agent->isActive()) {
                if($TgtPlayer->isActive()) {
                    $ActiveGain = $Agent->fptsWtd() - $TgtPlayer->fptsWtd();
                } else {
                    $ActiveGain = $Agent->fptsWtd();
                }
            } else {
                if($TgtPlayer->isActive()) {
                    next;  ## Never exchange an active player for an inactive one
                } else {
                    $ActiveGain = 0.0;
                }
            }
            
            my ($NewPlayable) = Player->makeBestTeam($Agent, @RemainingPlayers);
            next unless($NewPlayable);
            
            $PlayableGain = $NewPlayable - $PlayableBase;
            
            if($PlayableGain < -$Epsilon ||
               ($PlayableGain < $Epsilon &&
                ($ActiveGain < -$Epsilon ||
                 $TeamGain < -$Epsilon ||
                 ($ActiveGain < $Epsilon && $TeamGain < $Epsilon)))) {
                next;
            }
            
            my $TradeRef = [$Agent, $TgtPlayer, $PlayableGain, $ActiveGain, $TeamGain];
            push(@$TradeListRef, $TradeRef);
            push(@AllTrades, $TradeRef);
        }
    }
}

printByTradeValue();

exit 0;

sub printByAgent {
    for my $AgentDataRef (@WorthyAgents) {
        my ($Agent, $TradeListRef) = @$AgentDataRef;
        
        next unless(@$TradeListRef);
        
        printAgent($Agent);
        print("\n");
        
        for my $TradeDataRef (sort { sortTradeData($a, $b) } @$TradeListRef) {
            print "   ";
            printTrade($TradeDataRef);
            print "\n";
        }    
    }    
}

sub printByTradeValue {
    my $LastAgent;
    for my $TradeRef (sort { sortTradeData($a, $b) } @AllTrades) {
        if(defined($LastAgent) && $LastAgent != $TradeRef->[0]) {
            print "\n";
        }
        
        printAgent($TradeRef->[0]);
        printTrade($TradeRef);
        print "\n";
        
        $LastAgent = $TradeRef->[0];
    }
}


sub printAgent {
    my ($Agent) = @_;
    printf("[%7.2f] %s %-25s",
           $Agent->fptsWtd(),
           ($Agent->isActive() ? '*' : ' '),
           $Agent->name());    
}

sub printTrade {
    my ($TradeDataRef) = @_;
    my ($Agent, $TgtPlayer, $PlayableGain, $ActiveGain, $TeamGain) = @$TradeDataRef;
    printf(" => [%7.2f] %s %-25s %+7.2f (%+7.2f, %+7.2f) %s",
           $TgtPlayer->fptsWtd(),
           ($TgtPlayer->isActive() ? '*' : ' '),
           $TgtPlayer->name(),
           $PlayableGain,
           $ActiveGain,
           $TeamGain,
           $TgtPlayer->owner());  
}

sub sortTradeData {
    return(($b->[2] <=> $a->[2]) ||
           ($b->[3] <=> $a->[3]) ||
           ($b->[4] <=> $a->[4]) ||
           ($b->[0]->fptsWtd() <=> $a->[0]->fptsWtd()) ||
           ($a->[1]->fptsWtd() <=> $b->[1]->fptsWtd()));
}
