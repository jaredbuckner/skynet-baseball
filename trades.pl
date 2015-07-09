#!/usr/bin/perl -w

use strict;

use lib ".";
use Player;

use constant CONSIDERATION => 2;
use constant MUSTBECOMPAT => 0;

Player->fillData('data');

my %Force;

for my $PName (map { ( split(':', $_)) } @ARGV) {
    my @PMatches = Player->byMatch($PName);
    
    if(@PMatches == 0) {
        die("No player matches '$PName'\n");
    } elsif(@PMatches != 1) {
        die("Multiple matches for '$PName':  ",
            join(', ', map {$_->name()} @PMatches),
            "\n");
    } else {
        $Force{$PMatches[0]} = 0;
    }
}

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
        
        use_force(\%Force, $_) foreach(@TradeTgtSet);
        
        warn("   Offering ", join(" ", map { $_->name } @TradeTgtSet), " ...\n");
        
        my @TruncatedWe = @We;
        splice(@TruncatedWe, $_, 1) foreach(reverse(@TradeTgtIdxSet));
        
        
        
        my @TradeForIdxSet = ();
        while(nextIndexSet(\@TradeForIdxSet, scalar(@They), CONSIDERATION)) {
            my @TradeForSet = @They[@TradeForIdxSet];            
            next unless(allActive(\@TradeForSet));
            
            
            use_force(\%Force, $_) foreach(@TradeForSet);
            
            next unless(clear_force(\%Force) &&
                        (!MUSTBECOMPAT || tradeCompatable(\@TradeTgtSet, \@TradeForSet)));
            
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
    
    for my $TradeRef ($TradeTgtRef, $TradeForRef) {
        for my $Entry (@$TradeRef) {
            my $Name = $Entry->name();
            $BNSize = length($Name) if(length($Name) > $BNSize);
            
            my $Pos = join(':', (sort $Entry->pos()));
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
    $TradeDeltaForOther += $_->fptsWtd() foreach(@$TradeTgtRef);
    $TradeDeltaForOther -= $_->fptsWtd() foreach(@$TradeForRef);
    
    printf("==== from %-26s [%+7.3f] vs [%+7.3f] %s (tdfo=%+7.3f) ====\n",
           $TradeForRef->[0]->owner(),
           $WeBTSNew - $WeBTSBase,
           $TheyBTSNew - $TheyBTSBase,
           $IsPareto ? 'P' : ' ',
           $TradeDeltaForOther);
    
    for(my $I = 0; $I < @$TradeTgtRef || $I < @$TradeForRef; ++$I) {
        my $TgtEntry = $TradeTgtRef->[$I];
        my $ForEntry = $TradeForRef->[$I];
        
        print("  ");
        print_side($TgtEntry, 1, 0, $BNSize, $POSize);
        print(" <=> ");
        print_side($ForEntry, 0, defined($ForEntry) && exists($Besties{$ForEntry}), $BNSize, $POSize);
        print("\n");
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

## Returns <0 if the first trade is pareto-sub-optimal
## Returns >0 if the second trade is pareto-sub-optimal
## Returns =0 if both trades are pair-wise pareto
sub paretoCompare {
    my ($RefA, $RefB) = @_;
    
    my ($TgtRefA, $TgtForA, $WeBtsNewA, undef, $TheyBtsNewA) = @$RefA;
    my ($TgtRefB, $TgtForB, $WeBtsNewB, undef, $TheyBtsNewB) = @$RefB;
    
    my $WeBtsCmp = ($WeBtsNewA <=> $WeBtsNewB);
    my $TheyBtsCmp = ($TheyBtsNewA <=> $TheyBtsNewB);
    
    if($WeBtsCmp < 0 && $TheyBtsCmp <= 0 ||
       $WeBtsCmp <= 0 && $TheyBtsCmp < 0) {
        return(-1);
    } elsif($WeBtsCmp > 0 && $TheyBtsCmp >= 0 ||
            $WeBtsCmp >= 0 && $TheyBtsCmp > 0) {
        return(1);
    } elsif($WeBtsCmp == 0 && $TheyBtsCmp == 0) {
        my $TgtRefCmp = (@$TgtRefA <=> @$TgtRefB);
        my $TgtForCmp = (@$TgtForA <=> @$TgtForB);
        if($TgtRefCmp > 0 && $TgtForCmp >=0 ||
           $TgtRefCmp >= 0 && $TgtForCmp > 0) {
            return(-1);
        } elsif($TgtRefCmp < 0 && $TgtForCmp <=0 ||
                $TgtRefCmp <=0 && $TgtForCmp <0) {
            return(-1);
        }
    }
    
    return(0);
}

sub updateParetoOptimal {
    my ($TradesRef) = @_;
    my $LastIdx = @$TradesRef - 1;
    
    my (undef, $LastTradeForRef) = @{$TradesRef->[$LastIdx]};
    
    my $Player = $LastTradeForRef->[0]->owner();
    
    for(my $Idx = 0; $Idx != $LastIdx; ++$Idx) {
        my (undef, $ThisTradeForRef,
            undef, undef, undef, $IsPareto) = @{$TradesRef->[$Idx]};
        next unless($IsPareto);
        next unless($ThisTradeForRef->[0]->owner() eq $Player);
        
        my $CmpVal = paretoCompare($TradesRef->[$LastIdx], $TradesRef->[$Idx]);
        if($CmpVal < 0) {
            $TradesRef->[$LastIdx]->[5] = 0;
            last;
        } elsif($CmpVal > 0) {
            $TradesRef->[$Idx]->[5] = 0;
        }
    }
}

sub allActive {
    my ($SeqRef) = @_;
    
    foreach(@$SeqRef) { return(0) unless $_->isActive(); }
    return(1);
}

sub print_side {
    my ($Entry, $IsLH, $IsBest, $BNSize, $POSize) = @_;
    
    if($Entry) {
        my $POS = join(':', (sort $Entry->pos()));
        
        printf("%-*s%s[%7.2f] %s %-*s%s%*s",
               $IsLH ? 0 : $POSize,
               $IsLH ? '' : $POS,
               $IsLH ? '' : ' ',
               $Entry->fptsWtd(),
               $IsBest ? '!' : $Entry->isActive() ? '*' : ' ',
               $BNSize,
               $Entry->name(),
               $IsLH ? '' : ' ',
               $IsLH ? $POSize : 0,
               $IsLH ? $POS : '');        
    } else {
        printf("%*s",
               5 + 7 + $BNSize + $POSize,
               '');
    }
}

sub clear_force {
    my ($FRef) = @_;
    
    my $WasAllForced = 1;
    
    for my $Key (keys %$FRef) {
        my $VRef = \ ($FRef->{$Key});
        $WasAllForced &&= $$VRef;
        $$VRef = 0;
    }
    
    return($WasAllForced);
}

sub use_force {
    my ($FRef, $Player) = @_;
    
    if(exists($FRef->{$Player})) {
        $FRef->{$Player} = 1;
    }
}

