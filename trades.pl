#!/usr/bin/perl -w

use strict;

use lib ".";
use Player;

Player->fillData('data');

use constant CONSIDERATION => (defined($ARGV[0]) ? $ARGV[0] : 2);

## By owner

my @We = Player->byOwner($Player::Me);
my ($WeBTSBase) = Player->makeBestTeam(@We);
$WeBTSBase = 0.0 unless(defined($WeBTSBase));
my @Trades;

my @Owners = sort Player->allOwners();
my %OwnerTrades;
my %Besties;

for(my $OwnerIdx = 0; $OwnerIdx != @Owners; ++$OwnerIdx) {
    my $Owner = $Owners[$OwnerIdx];
    next if($Owner eq $Player::Me);
    
    warn("Picking the pockets of $Owner (",
         sprintf('%5.2f', $OwnerIdx / @Owners * 100), ") ...\n");
    
    my @They = Player->byOwner($Owner);
    
    ## Determine their favorite players
    {
        my $TheyBestU;
        my $TheyBestP;
        for my $TheyPlay (@They) {
            next unless($TheyPlay->isActive());
            if($TheyPlay->plays('U')) {
                if(!defined($TheyBestU) || $TheyBestU->fptsWtd() < $TheyPlay->fptsWtd()) {
                    $TheyBestU = $TheyPlay;
                }
            } elsif($TheyPlay->plays('SP') || $TheyPlay->plays('RP')) {
                if(!defined($TheyBestP) || $TheyBestP->fptsWtd() < $TheyPlay->fptsWtd()) {
                    $TheyBestP = $TheyPlay;
                }
            }
        }
        
        $Besties{$TheyBestU} = 1 if(defined($TheyBestU));
        $Besties{$TheyBestP} = 1 if(defined($TheyBestP));
    }
    
    my ($TheyBTSBase) = Player->makeBestTeam(@They);
    $TheyBTSBase = 0.0 unless(defined($TheyBTSBase));
    
    my @TradeTgtIdxSet = ();
    while(nextIndexSet(\@TradeTgtIdxSet, scalar(@We), CONSIDERATION)) {
        my @TradeTgtSet = @We[@TradeTgtIdxSet];
        next unless(allActive(\@TradeTgtSet));
        
        warn("   Offering ", join(" ", map { $_->name } @TradeTgtSet), " ...\n");
        
        my @TruncatedWe = @We;
        splice(@TruncatedWe, $_, 1) foreach(reverse(@TradeTgtIdxSet));
        
        
        
        my @TradeForIdxSet = ();
        while(nextIndexSet(\@TradeForIdxSet, scalar(@They), CONSIDERATION)) {
            my @TradeForSet = @They[@TradeForIdxSet];            
            next unless(allActive(\@TradeForSet));
            
            next unless(tradeCompatable(\@TradeTgtSet, \@TradeForSet));
            
            # warn("     for ", join(" ", map { $_->name } @TradeForSet), " ...\n");
            
            my @TruncatedThey = @They;
            splice(@TruncatedThey, $_, 1) foreach(reverse(@TradeForIdxSet));
            
            my ($WeBTSNew) = Player->makeBestTeam(@TradeForSet, @TruncatedWe);
            next unless(defined($WeBTSNew) && $WeBTSNew > $WeBTSBase);
            
            my ($TheyBTSNew) = Player->makeBestTeam(@TradeTgtSet, @TruncatedThey);
            next unless(defined($TheyBTSNew) && $TheyBTSNew > $TheyBTSBase);
            
            push(@Trades, [\@TradeTgtSet, \@TradeForSet, $WeBTSNew, $TheyBTSBase, $TheyBTSNew, 1]);
            warn("      Found:  ", scalar(@Trades), "\n");
            updateParetoOptimal(\@Trades);
        }
    }
}

@Trades = sort {
    $b->[5] <=> $a->[5] ||
        ($b->[2] - $WeBTSBase) <=> ($a->[2] - $WeBTSBase) ||
        ($a->[4] - $a->[3]) <=> ($b->[4] - $b->[3])
} @Trades;

my $BNSize = 8;
my $POSize = 2;
for my $TradeRef (@Trades) {
    my ($TradeTgtRef, $TradeForRef) = @$TradeRef;
    for (my $I = 0; $I < @$TradeTgtRef; ++$I) {
        for my $Name ($TradeTgtRef->[$I]->name(), $TradeForRef->[$I]->name()) {
            $BNSize = length($Name) if(length($Name) > $BNSize);
        }
        for my $Pos (join(':', (sort $TradeTgtRef->[$I]->pos())),
                     join(':', (sort $TradeForRef->[$I]->pos()))) {
            $POSize = length($Pos) if (length($Pos) > $POSize);
        }
    }
}


for my $TradeRef (@Trades) {
    my ($TradeTgtRef, $TradeForRef, $WeBTSNew, $TheyBTSBase, $TheyBTSNew, $IsPareto) = @$TradeRef;
    
    if($IsPareto && $WeBTSNew - $WeBTSBase >= 10.0 &&
       ($TheyBTSNew - $TheyBTSBase) / ($WeBTSNew - $WeBTSBase) <= 1.6) {
        my $IsSpecial = 1;
        ## Check to see if any of the players are 'special'
        for my $MaybeSpecialPlayer (@$TradeForRef) {
            if(exists($Besties{$MaybeSpecialPlayer})) {
                $IsSpecial = 0;
                last;
            }
        }
        push(@{$OwnerTrades{$TradeForRef->[0]->owner()}}, $TradeRef) if($IsSpecial);
    }
    
    my $TradeDeltaForOther = 0.0;
    for(my $I = 0; $I < @$TradeTgtRef; ++$I) {
        $TradeDeltaForOther += $TradeTgtRef->[$I]->fptsWtd();
        $TradeDeltaForOther -= $TradeForRef->[$I]->fptsWtd();
    }
    
    printf("==== from %-26s [%+7.3f] vs [%+7.3f] %s (tdfo=%+7.3f) ====\n",
           $TradeForRef->[0]->owner(),
           $WeBTSNew - $WeBTSBase,
           $TheyBTSNew - $TheyBTSBase,
           $IsPareto ? 'P' : ' ',
           $TradeDeltaForOther);
    
    for(my $I = 0; $I < @$TradeTgtRef; ++$I) {
        printf("  [%7.2f] %s %-*s %*s <=> %-*s [%7.2f] %s %-*s\n",
               $TradeTgtRef->[$I]->fptsWtd(),
               $TradeTgtRef->[$I]->isActive() ? '*' : ' ',
               $BNSize,
               $TradeTgtRef->[$I]->name(),
               $POSize,
               join(':', (sort $TradeTgtRef->[$I]->pos())),
               $POSize,
               join(':', (sort $TradeForRef->[$I]->pos())),
               $TradeForRef->[$I]->fptsWtd(),
               exists($Besties{$TradeForRef->[$I]})
                      ? '!'
                      : $TradeForRef->[$I]->isActive()
                      ? '*'
                      : ' ',
               $BNSize,
               $TradeForRef->[$I]->name());
    }
}

print "\n\n";

for my $Owner (sort keys %OwnerTrades) {
    print " ***** To $Owner *****\n";
    my $OTSeqRef = $OwnerTrades{$Owner};
    
    my $Seen = 0;
    while($Seen < 7 && @$OTSeqRef) {
        ++$Seen;
        my $Idx = int(rand(@$OTSeqRef));
        my $TradeRef = splice(@$OTSeqRef, $Idx, 1);
        
        print(join(', ', map {playerNameAndPos($_)} @{$TradeRef->[0]}), "   for   ",
              join(', ', map {playerNameAndPos($_)} @{$TradeRef->[1]}), "\n");
    }
    
    print "\n";
}

exit(0);

sub playerNameAndPos {
    my ($Player) = @_;
    return(sprintf("%s [%s]",
                   $Player->name(),
                   join(':', $Player->pos())));
}

## This counts through indices as follows, for max-size of 3
##   (0)
##   (0, 1)
##   (0, 1, 2)
##   (0, 1, 3)
##   ...
##   (0, 1, N-1)
##   (0, 2)
##   (0, 2, 3)
##   ...
##   (0, 2, N-1)
##   ...
##   (0, N-1)
##   (1)
##   (1, 2)
##   (1, 2, 3)
##   ...
##   (1, N-1)
##   ...
##   (N-1)
##   ()
sub nextIndexSet {
    my ($SetRef, $EndIndex, $MaxSize) = @_;
    
    if(@$SetRef == 0) {
        push(@$SetRef, 0);
        return(1);
    }
    
    my $NextIndex = $SetRef->[-1] + 1;
    if($NextIndex < $EndIndex) {
        if(@$SetRef < $MaxSize) {
            push(@$SetRef, $NextIndex);
            return(1);
        } else {
            $SetRef->[-1] = $NextIndex;
            return(1);
        }
    }
    
    pop(@$SetRef);
    if(@$SetRef) {
        $SetRef->[-1] += 1;
        return(1);
    }
    
    return(0);
}


## A trade is compatable if we can find a one-to-one mapping of compatable
## players.
sub tradeCompatable {
    my ($OfferSetRef, $RequestSetRef) = @_;
    
    ## If the sets are not the same size, it's definitely not compatible
    if(@$OfferSetRef != @$RequestSetRef) { return(0); }
    
    ## If the sets are empty, it is compatible
    if(@$OfferSetRef == 0) { return(1); }
    
    ## Find one compatible pair, splice them out, see if the remainder is
    ## compatible
    for(my $OfferIdx = 0; $OfferIdx != @$OfferSetRef; ++$OfferIdx) {
        my $OfferPlayer = $OfferSetRef->[$OfferIdx];
        
        for(my $RequestIdx = 0; $RequestIdx != @$RequestSetRef; ++$RequestIdx) {
            my $RequestPlayer = $RequestSetRef->[$RequestIdx];
            
            if($OfferPlayer->isCompatable($RequestPlayer)) {
                my @OfferCpy = @$OfferSetRef;
                my @RequestCpy = @$RequestSetRef;
                splice(@OfferCpy, $OfferIdx, 1);
                splice(@RequestCpy, $RequestIdx, 1);
                if(tradeCompatable(\@OfferCpy, \@RequestCpy)) {
                    return(1);
                }
            }
        }
    }

    return(0);
}

sub updateParetoOptimal {
    my ($TradesRef) = @_;
    my $LastIdx = @$TradesRef - 1;
    
    my ($LastTradeTgtRef, $LastTradeForRef,
        $LastWeBTSNew, $LastTheyBTSBase, $LastTheyBTSNew) = @{$TradesRef->[$LastIdx]};
    
    my $Player = $LastTradeForRef->[0]->owner();
    
    for(my $Idx = 0; $Idx != $LastIdx; ++$Idx) {
        my ($ThisTradeTgtRef, $ThisTradeForRef,
            $ThisWeBTSNew, $ThisTheyBTSBase, $ThisTheyBTSNew, $IsPareto) = @{$TradesRef->[$Idx]};
        next unless($IsPareto);
        next unless($ThisTradeForRef->[0]->owner() eq $Player);

        if($ThisWeBTSNew >= $LastWeBTSNew && $ThisTheyBTSNew > $LastTheyBTSNew ||
           $ThisWeBTSNew > $LastWeBTSNew && $ThisTheyBTSNew >= $LastTheyBTSNew ) {
            $TradesRef->[$LastIdx]->[5] = 0;
            last;
        }
        if($ThisWeBTSNew <= $LastWeBTSNew && $ThisTheyBTSNew < $LastTheyBTSNew ||
           $ThisWeBTSNew < $LastWeBTSNew && $ThisTheyBTSNew <= $LastTheyBTSNew ) {
            $TradesRef->[$Idx]->[5] = 0;
        }
    }
}

sub allActive {
    my ($SeqRef) = @_;
    
    foreach(@$SeqRef) { return(0) unless $_->isActive(); }
    return(1);
}
