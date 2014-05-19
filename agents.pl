#!/usr/bin/perl -w

use strict;

use lib ".";
use Player;

Player->fillData('data');

my @Owners = ($Player::Me, grep { $_ ne $Player::Me } Player->allOwners());

#foreach my $Owner (@Owners) {
foreach my $Owner ($Owners[0]) {
    print " === $Owner ===\n";
    warn("Analyzing $Owner ...\n");
    my @Players = Player->byOwner($Owner);
    my ($BaseTeamScore, $BestTeamRef) = Player->makeBestTeam(@Players);
    my $LeastValue = undef;
    
    $BaseTeamScore = 0 unless(defined($BaseTeamScore));
    foreach(@Players) {
        my $PlayerValue = $_->fptsWtd();
        if(!defined($LeastValue)
           || $PlayerValue < $LeastValue) {
            $LeastValue = $PlayerValue;
        }
    }
    
    if(grep {!($_->isActive())} @$BestTeamRef) {
        $LeastValue = 0;
    }
    
    my @EveryoneElse = sort {
        $b->fptsWtd() <=> $a->fptsWtd()
    } ( grep { !defined($_->owner()) && $_->fptsWtd() >= $LeastValue } Player->allPlayers() );
    
    next unless @EveryoneElse;
    
    my @TradeTgtSet = sort {
        $b->fptsWtd() <=> $a->fptsWtd()
    } (grep { $_->fptsWtd <= $EveryoneElse[0]->fptsWtd() } @Players);
    
    for(my $TradeIdx = 0; $TradeIdx != @TradeTgtSet; ++$TradeIdx) {
        my $TradeTgt = $TradeTgtSet[$TradeIdx];
        
        warn("Considering ", $TradeTgt->name(), " (", sprintf('%5.2f', $TradeIdx / @TradeTgtSet * 100), "%)...\n");
        
        my $TradeTgtValue = $TradeTgt->fptsWtd();
        my $ActiveTgtValue = $TradeTgt->isActive() ? $TradeTgtValue : 0.0;
        my @TruncatedTeam = grep { $_ != $TradeTgt } @Players;
        
        ## Player->clearMBTCache();
        for(my $TradeForIdx = 0; $TradeForIdx != @EveryoneElse; ++$TradeForIdx) {
            my $TradeFor = $EveryoneElse[$TradeForIdx];
            
            next unless(($TradeTgt->isActive() || 0) == ($TradeFor->isActive() || 0));
            next unless($TradeTgt->isCompatable($TradeFor));
            
            warn("  for ", $TradeFor->name(), " (", sprintf('%5.2f', ($TradeForIdx / @EveryoneElse + $TradeIdx) / @TradeTgtSet * 100),  "%)\n");
            my $TradeForValue = $TradeFor->fptsWtd();
            next unless $TradeForValue > 0.0;
            my $ActiveForValue = $TradeFor->isActive() ? $TradeForValue : 0.0;
            my ($TradeTeamScore) = Player->makeBestTeam($TradeFor, @TruncatedTeam);
            $TradeTeamScore = 0.0 unless(defined($TradeTeamScore));
            
            next unless($TradeTeamScore > $BaseTeamScore ||
                        $TradeTeamScore == $BaseTeamScore &&
                        ($ActiveForValue > $ActiveTgtValue ||
                         $ActiveForValue == $ActiveTgtValue &&
                         $TradeForValue > $TradeTgtValue));
            
            printf("[%7.2f] %-25s for [%7.2f] %-25s [%+7.3f] [%+7.3f] [%+7.3f]\n", 
                   $TradeForValue,
                   $TradeFor->name(),
                   $TradeTgtValue,
                   $TradeTgt->name(),
                   $TradeTeamScore - $BaseTeamScore,
                   $ActiveForValue - $ActiveTgtValue,
                   $TradeForValue - $TradeTgtValue);
        }
    }
    print "\n\n";
    
}
exit 0;
