#!/usr/bin/perl -w

use strict;

use lib ".";
use Player;

Player->fillData('data');

use constant CONSIDERATION => 2;

## By owner

my @We = Player->byOwner($Player::Me);
my ($WeBTSBase) = Player->makeBestTeam(@We);
$WeBTSBase = 0.0 unless(defined($WeBTSBase));
my @Trades;

my @Owners = sort Player->allOwners();

for(my $OwnerIdx = 0; $OwnerIdx != @Owners; ++$OwnerIdx) {
    my $Owner = $Owners[$OwnerIdx];
    next if($Owner eq $Player::Me);
    
    warn("Picking the pockets of $Owner (",
         sprintf('%5.2f', $OwnerIdx / @Owners * 100), ") ...\n");
    
    my @They = Player->byOwner($Owner);
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
    
    printf("==== from %-26s [%+7.3f] vs [%+7.3f] %s ====\n",
           $TradeForRef->[0]->owner(),
           $WeBTSNew - $WeBTSBase,
           $TheyBTSNew - $TheyBTSBase,
           $IsPareto ? 'P' : ' ' );
    
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
               $TradeForRef->[$I]->isActive() ? '*' : ' ',
               $BNSize,
               $TradeForRef->[$I]->name());
    }
}


exit(0);

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
