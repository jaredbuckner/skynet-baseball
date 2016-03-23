## -*- perl -*-
##
## Common routines for handling player data
##

use strict;

use Text::CSV_XS;
use Time::Local;

package Player;

use constant I_NAME     => 0;  ## Currently "Name (TEAM)"
use constant I_TEAM     => 1;  ## Not Currently Used
use constant I_POS      => 2;
use constant I_ACTIVE   => 3;
use constant I_FPTS_YTD => 4;
use constant I_FPTS_21D => 5;
use constant I_FPTS_7DY => 6;
use constant I_FPTS_ROS => 7;
use constant I_FPTS_WTD => 8;
use constant I_OWNER    => 9;
use constant I_END      => 10;

use constant SEASON_PA  => 694.5;

my %Players;
my %ActivePlayers;
my %OwnerPlayers;  ## ( owner => [PlayerRef, PlayerRef] )
my %MBTCache;
my @MBTCacheSeq;
my $MBTCacheMax = 2000000;

## Fraction of the season completed
my $SeasonFrac;

our $Me = "Skynet...";
#our $Me = "Dewey Cheatham and Howe";

sub new {
    my ($Class, $Name, $Team) = @_;
    
    my $Self = [ $Name, $Team, {} ];
    bless($Self, $Class);
    $Players{$Name} = $Self;
    return($Self);
}

sub allNames { return(keys %Players); }
sub allPlayers { return(values %Players); }
sub activeNames { return(keys %ActivePlayers); }
sub activePlayers { return(values %ActivePlayers); }
sub allOwners { return(keys %OwnerPlayers); }

sub byName {
    my ($Class, $Name) = @_;
    return($Players{$Name});
}

## Returns list of matches given a partial string
sub byMatch {
    my ($Class, $Expr) = @_;
    
    my $Player = Player->byName($Expr);
    
    return($Player) if defined($Player);
    
    my @PMatches;
    my $QMExpr = quotemeta($Expr);
    for my $TryPlayer (Player->allPlayers()) {
        if($TryPlayer->name() =~ /$QMExpr/i) {
            push(@PMatches, $TryPlayer);
        }
    }
    
    return(@PMatches);
}

sub byOwner {
    my ($Class, $Owner) = @_;
    return(@{$OwnerPlayers{$Owner}});
}

sub allPositions { return(qw (C 1B 2B SS 3B OF U SP RP)); }
sub allSlots     { return(qw (C 1B 2B SS 3B OF OF OF U SP SP SP RP U SP SP)); }
sub playSlots    { return(qw (C 1B 2B SS 3B OF OF OF U SP SP SP RP)); }

sub name     { my ($Self) = @_; return($Self->[I_NAME]); }
sub team     { my ($Self) = @_; return($Self->[I_TEAM]); }
sub pos      { my ($Self) = @_; return(keys %{$Self->[I_POS]}); }
sub isActive { my ($Self) = @_; return($Self->[I_ACTIVE]); }
sub fptsYtd  { my ($Self) = @_; return($Self->[I_FPTS_YTD] || 0.0); }
sub fpts21d  { my ($Self) = @_; return($Self->[I_FPTS_21D] || 0.0); }
sub fpts7dy  { my ($Self) = @_; return($Self->[I_FPTS_7DY] || 0.0); }
sub fptsRoS  { my ($Self) = @_; return($Self->[I_FPTS_ROS] || 0.0); }
sub fptsWtd  { my ($Self) = @_; return($Self->[I_FPTS_WTD] || 0.0); }
sub owner    { my ($Self) = @_; return($Self->[I_OWNER]); }

sub plays    { my ($Self, $Pos) = @_; return(exists $Self->[I_POS]->{$Pos}); }
sub addPos   { my ($Self, $Pos) = @_; $Self->[I_POS]->{$Pos} = 1; }

sub isCompatable {
    my ($Self, $Other) = @_;
    for my $SelfPos ($Self->pos()) {
        if($Other->plays($SelfPos)) {
            return(1);
        }
    }
    
    return(0);
}

sub activate {
    my ($Self) = @_;
    $Self->[I_ACTIVE] = 1;
    $ActivePlayers{$Self->[I_NAME]} = $Self;
}

sub deactivate {
    my ($Self) = @_;
    $Self->[I_ACTIVE] = 0;
    delete $ActivePlayers{$Self->[I_NAME]};
}

sub chown {
    my ($Self, $Owner) = @_;
    
    if(defined(my $OldOwner = $Self->[I_OWNER])) {
        @{$OwnerPlayers{$OldOwner}} = grep { $_ != $Self } @{$OwnerPlayers{$OldOwner}};
    }
    $Self->[I_OWNER] = $Owner;
    if(defined($Owner)) {
        if(exists($OwnerPlayers{$Owner})) {
            @{$OwnerPlayers{$Owner}} = sort { $b->fptsWtd() <=> $a->fptsWtd() } (@{$OwnerPlayers{$Owner}}, $Self);
        } else {
            $OwnerPlayers{$Owner} = [$Self];
        }
    }
}

sub setFptsYtd {
    my ($Self, $Fpts) = @_;
    $Self->[I_FPTS_YTD] = $Fpts;
    $Self->_reweight();
}

sub setFpts21d {
    my ($Self, $Fpts) = @_;
    $Self->[I_FPTS_21D] = $Fpts;
    $Self->_reweight();
}

sub setFpts7dy {
    my ($Self, $Fpts) = @_;
    $Self->[I_FPTS_7DY] = $Fpts;
    $Self->_reweight();
}

sub setFptsRoS {
    my ($Self, $Fpts) = @_;
    $Self->[I_FPTS_ROS] = $Fpts;
    $Self->_reweight();
}

sub _reweight {
    my ($Self) = @_;
#    $Self->[I_FPTS_WTD] = 0.67 * $Self->fpts21d() + 0.33 * $Self->fptsYtd();
#    $Self->[I_FPTS_WTD] = $Self->fptsRoS() + $Self->fpts7dy();
    $Self->[I_FPTS_WTD]
        = (1.0 - $Self->seasonFrac()) * $Self->fptsRoS()
        + $Self->fptsYtd()
        - 0.6 * $Self->fpts7dy()
        + 0.2 * $Self->fpts21d();
    
    my $Owner = $Self->owner();
    if(defined($Owner) && exists($OwnerPlayers{$Owner})) {
        @{$OwnerPlayers{$Owner}} = sort { $b->fptsWtd() <=> $a->fptsWtd() } @{$OwnerPlayers{$Owner}};
    }
}

sub seasonFrac {
    unless(defined($SeasonFrac)) {
        my (undef, undef, undef,
            $MDay, $Mon, $Year) = localtime();
        my $SeasonStart = Time::Local::timelocal(0, 0, 0, 1, 3, $Year);
        my $SeasonNow = Time::Local::timelocal(0, 0, 0, $MDay, $Mon, $Year);
        my $SeasonEnd = Time::Local::timelocal(0, 0, 0, 1, 9, $Year);
        $SeasonFrac = ($SeasonNow - $SeasonStart) / ($SeasonEnd - $SeasonStart);
        $SeasonFrac = 0.0 if($SeasonFrac < 0.0);
        $SeasonFrac = 1.0 if($SeasonFrac > 1.0);
    }
    return($SeasonFrac);
}

sub loadYtdStats { _loadStats(@_, I_FPTS_YTD); }
sub load21dStats { _loadStats(@_, I_FPTS_21D); }
sub load7dyStats { _loadStats(@_, I_FPTS_7DY); }
sub loadRoSStats { _loadStats(@_, I_FPTS_ROS); }

sub _loadStats {
    my ($Class, $FileHandle, $Position, $PTSIDX, $Rebalance) = @_;
    
    my $CSVParser = Text::CSV_XS->new();
    my $FPTSIdx;
    my $PlayerIdx;
    my $TeamIdx;
    my $ABIdx;
    my $BBIdx;

    while(defined(my $DatRef = $CSVParser->getline($FileHandle))) {
        unless(defined($FPTSIdx) &&
               defined($PlayerIdx) &&
               defined($TeamIdx)) {
            for(my $Idx = 0; $Idx != @$DatRef; ++$Idx) {
                my $HeaderVal = $DatRef->[$Idx];
                if($HeaderVal eq 'FPTS') {
                    $FPTSIdx = $Idx;
                } elsif($HeaderVal eq 'Player') {
                    $PlayerIdx = $Idx;
                } elsif($HeaderVal eq 'Team' || $HeaderVal eq 'Avail') {
                    $TeamIdx = $Idx;
                } elsif($HeaderVal eq 'AB') {
                    $ABIdx = $Idx;
                } elsif($HeaderVal eq 'BB') {
                    $BBIdx = $Idx;
                }
            }
            next;
        }
        
        my ($Name, $Team, $FPTS) = @{$DatRef}[$PlayerIdx, $TeamIdx, $FPTSIdx];
        next unless(defined($Name) && defined($Team) && defined($FPTS));
        
        my $AB = (defined $ABIdx ? $DatRef->[$ABIdx] : undef);
        my $BB = (defined $BBIdx ? $DatRef->[$BBIdx] : undef);
        
        $Name = Player->_modName($Name);
        
        my $Player = $Class->byName($Name);
        unless(defined($Player)) {
            $Player = $Class->new($Name);
        }
        
        $Player->addPos($Position);
        
        if($Rebalance) {
            if(defined($AB) && defined($BB)) {
                $Player->[$PTSIDX] = $FPTS * SEASON_PA / ($AB + $BB + 1);
            } else {
                $Player->[$PTSIDX] = $FPTS;
            }
        } else {
            $Player->[$PTSIDX] = $FPTS;
        }
        $Player->_reweight();
        
        if($Team ne 'Free Agent' && $Team ne 'W ') {
            $Player->chown($Team);
        }
    }
}

sub _modName {
    my ($Class, $Name) = @_;
    
    my $WordsRx = qr/\S+(?:\s+\S+)*/;
    $Name =~ s/^\s*(${WordsRx})\s+\S+\s+\|\s+(\S+)\s*$/$1 ($2)/;
    $Name =~s/^\s*(${WordsRx})\s*,\s*(${WordsRx})\s+\S+\s+(\S+)\s*$/$2 $1 ($3)/;
    
    return($Name);
}

sub loadDepth {
    my ($Class, $FileHandle) = @_;

    my $CSVParser = Text::CSV_XS->new();
    my $MLBTeamIdx;
    my @IdxOfInterest;
    
    while(defined(my $DatRef = $CSVParser->getline($FileHandle))) {
        unless(defined($MLBTeamIdx)) {
            for(my $Idx = 0; $Idx != @$DatRef; ++$Idx) {
                my $HeaderVal = $DatRef->[$Idx];
                if($HeaderVal eq 'Team') {
                    $MLBTeamIdx = $Idx;
                } elsif($HeaderVal eq 'Starter' ||
                        $HeaderVal eq 'Starters' ||
                        $HeaderVal eq 'Closer' ||
                        $HeaderVal eq 'Set-up Man' ||
                        $HeaderVal eq 'SP #1' ||
                        $HeaderVal eq 'SP #2' ||
                        $HeaderVal eq 'SP #3' ||
                        $HeaderVal eq 'SP #4' ||
                        $HeaderVal eq 'SP #5') {
                    push(@IdxOfInterest, $Idx);
                }
            }
            next;
        }
        
        my ($MLBTeam,
            @Players) = @{$DatRef}[$MLBTeamIdx,
                                   @IdxOfInterest];
        
        next if($MLBTeam eq 'NL Teams' ||
                $MLBTeam eq 'AL Teams' ||
                $MLBTeam eq 'Team');

        for my $PlayerString (@Players) {
            next unless defined($PlayerString);
            
            $PlayerString = $Class->_fixPlayerString($PlayerString);
            
            for my $Player (split(/\s{2,}/, $PlayerString)) {
                my @AllNamePieces = split(' ', $Player);
                my @ThisNamePieces;
                while(defined(my $Piece = shift(@AllNamePieces))) {
                    push(@ThisNamePieces, $Piece);
                    
                    my $ThisPlayer = $Class->_modName(join(' ', @ThisNamePieces));
                    $ThisPlayer .= " ($MLBTeam)";
                    my $PRef = $Class->byName($ThisPlayer);
                    if(defined($PRef)) {
                        $PRef->activate();
                        @ThisNamePieces = ();
                    }
                }
                
                if(@ThisNamePieces) {
                    my @ReallyTryHardPieces = ();
                  SL: while(defined(my $Piece = shift(@ThisNamePieces))) {
                        for(my $Idx = 1; $Idx <= length($Piece); ++$Idx) {
                            my $AlphaPiece = substr($Piece, 0, $Idx);
                            my $BetaPiece = substr($Piece, $Idx);
                            
                            my $ThisPlayer = $Class->_modName(join(' ', @ReallyTryHardPieces, $AlphaPiece));
                            $ThisPlayer .= " ($MLBTeam)";
                            my $PRef = $Class->byName($ThisPlayer);
                            if(defined($PRef)) {
                                $PRef->activate();
                                @ReallyTryHardPieces = ();
                                if($BetaPiece ne '') {
                                    unshift(@ThisNamePieces, $BetaPiece);
                                }
                                next SL;
                            }                            
                        }
                        push(@ReallyTryHardPieces, $Piece);
                    }
                    
                    if(@ReallyTryHardPieces) {
                        die("Given playerstring $PlayerString, cannot activate $Player using ",
                            join(' ', @ReallyTryHardPieces), "\n");
                        next;
                    }
                }
            }
        }
    }
}

sub _fixPlayerString {
    my ($Class, $PlayerString) = @_;
    
    $PlayerString =~ s/ (ARI|ATL|CHC|CIN|COL|HOU|LAD|MIA|MIL|NYM|PHI|PIT|SD|SF|STL|WAS|BAL|BOS|CHW|CLE|DET|KC|LAA|MIN|NYY|OAK|SEA|TB|TEX|TOR)/ $1  /g;
    $PlayerString =~ s/\s?\*\s|\s\(\d\)/  /g;
    $PlayerString =~ s/\d+//g;
    $PlayerString =~ s/^\s+//;
    $PlayerString =~ s/\s+$//;
    
    return($PlayerString);
}

sub loadInjury {
    my ($Class, $FileHandle) = @_;
    
    my $CSVParser = Text::CSV_XS->new();
    my $PlayerIdx;
    my $StatusIdx;
    
    while(defined(my $DatRef = $CSVParser->getline($FileHandle))) {
        unless(defined($PlayerIdx)) {
            for(my $Idx = 0; $Idx != @$DatRef; ++$Idx) {
                my $HeaderVal = $DatRef->[$Idx];
                if($HeaderVal eq 'Player') {
                    $PlayerIdx = $Idx;
                } elsif($HeaderVal eq 'Status') {
                    $StatusIdx = $Idx;
                }
            }
            next;
        }
        
        my ($PlayerString, $Status) = @{$DatRef}[$PlayerIdx, $StatusIdx];
        
        next unless($Status eq 'DL' ||
                    $Status eq 'Suspended' ||
                    $Status eq 'Out');
        next unless(defined($PlayerString));
        $PlayerString = $Class->_modName($Class->_fixPlayerString($PlayerString));
        my $Player = $Class->byName($PlayerString);
        unless(defined($Player)) {
            die("Given playerstring ",
                 $DatRef->[$PlayerIdx],
                 ", cannot deactivate $PlayerString\n");
            next;
        }
        $Player->deactivate();
    }
}

sub fillData {
    my ($Class, $DataDir) = @_;
    
    for my $Position ($Class->allPositions()) {
         open(DAT, "<$DataDir/$Position.ytd.csv") || die $!;
         Player->loadYtdStats(*DAT, $Position);
         close(DAT);
         
         open(DAT, "<$DataDir/$Position.21d.csv") || die $!;
         Player->load21dStats(*DAT, $Position);
         close(DAT);
         
         open(DAT, "<$DataDir/$Position.7d.csv") || die $!;
         Player->load7dyStats(*DAT, $Position);
         close(DAT);
         
         open(DAT, "<$DataDir/$Position.restofseason.csv") || die $!;
         Player->loadRoSStats(*DAT, $Position);
         close(DAT);
    }
    
    ## Must load all players before attempting depth
    for my $Position ($Class->allPositions()) {
        open(DAT, "<$DataDir/$Position.depth.csv") || die $!;
        Player->loadDepth(*DAT, $Position);
        close(DAT);
        
    }
    
    open(DAT, "<$DataDir/injuries.csv") || die $!;
    Player->loadInjury(*DAT);
    close(DAT);
}

sub makeBestTeam {
    my ($Class, @Players) = @_;
    
    ## In a bit to increase cache hits, sort players.
#    @Players = sort @Players;
    
    return($Class->_mbt(\@Players, [$Class->playSlots()]));
}

#  sub clearMBTCache {
#      undef %MBTCache;
#      warn("(Cache cleared)\n");
#      $MBTCacheSize = 0;
#  }

sub _mbt {
    my ($Class, $PlayersRef, $SlotsRef) = @_;
    
    return(0, []) unless(@$SlotsRef);
    
    my $MBTCacheKey = _mbtCacheKey($Class, $PlayersRef, $SlotsRef);
    if(exists($MBTCache{$MBTCacheKey})) {
        return(@{$MBTCache{$MBTCacheKey}});
    }
    
    my ($Player, @UnusedPlayers) = @$PlayersRef;
    my $BestScore;
    my @BestTeam;
    
    ## Can we bench him?  If so, let's try that
    if(@$PlayersRef > @$SlotsRef) {
        my ($Score, $RetRef) = $Class->_mbt(\@UnusedPlayers, $SlotsRef);
        
        if(!defined($BestScore) ||
           $Score > $BestScore) {
            $BestScore = $Score;
            @BestTeam = @$RetRef;
            
        }
    }
    
    for(my $Idx = 0; $Idx != @$SlotsRef; ++$Idx) {
        my $Position = $SlotsRef->[$Idx];
        next unless $Player->plays($Position);
        
        my @Remainder = @$SlotsRef;
        splice(@Remainder, $Idx, 1);
        my ($Score, $RetRef) = $Class->_mbt(\@UnusedPlayers, \@Remainder);
        next unless(defined($Score));
        
        my $PlayerScore = $Player->isActive()
            ? $Player->fptsWtd()
            : 0.0;
        
        $Score += $PlayerScore;
        if(!defined($BestScore) ||
           $Score > $BestScore) {
            $BestScore = $Score;
            @BestTeam = @$RetRef;
            splice(@BestTeam, $Idx, 0, $Player);
        }
    }
    
    $MBTCache{$MBTCacheKey} = [ $BestScore, \@BestTeam ];
    push(@MBTCacheSeq, $MBTCacheKey);
    
    if(@MBTCacheSeq > $MBTCacheMax) {
        delete($MBTCache{shift(@MBTCacheSeq)});
    }
    
    return($BestScore, \@BestTeam);
}

## A unique value for the given entries.
## These are designed to never collide.
sub _mbtCacheKey {
    my ($Class, $PlayersRef, $SlotsRef) = @_;
    
    return(join(',', @$PlayersRef, @$SlotsRef));
}


## sub generate_teams {
##     my ($TeamsRef, $HashRef, $PosRef, $Period) = @_;
##     
##     $TeamsRef = {} unless(defined($TeamsRef));
##     
##     for my $PlayerName (keys %$HashRef) {
##         my $Team = $HashRef->{$PlayerName}->{'team'};
##         next if($Team eq 'Free Agent');
##         
##         my $FPTS = $HashRef->{$PlayerName}->{'period'}->{$Period}->{'fpts'};
##         push(@{$TeamsRef->{$Team}->{'players'}}, $PlayerName);
##         $TeamsRef->{$Team}->{'sum'} += $FPTS;
##         if($HashRef->{$PlayerName}->{'active'}) {
##             $TeamsRef->{$Team}->{'active'} += $FPTS;
##         }
##     }
##     
##     for my $Team (keys %$TeamsRef) {
##         my @PNames = grep
##         { $HashRef->{$_}->{'active'} } @{$TeamsRef->{$Team}->{'players'}};
##         ($TeamsRef->{$Team}->{'rpts'},
##          $TeamsRef->{$Team}->{'roster'}) = Player::best_team($HashRef,
##                                                              \@PNames,
##                                                              $PosRef,
##                                                              $Period);
##         $TeamsRef->{$Team}->{'rpts'} = 0 unless(defined($TeamsRef->{$Team}->{'rpts'}));
##     }
##     
##     return($TeamsRef);
## }

## sub generate_trades {
##     my ($TeamsRef, $BaseTeam, $HashRef, $PosRef, $Period, $AllowNeg) = @_;
##     
##     my @Trades;
##     
##     my @OtherTeams = grep { $_ ne $BaseTeam } keys %$TeamsRef;
##     
##     my @BasePlayers = sort @{$TeamsRef->{$BaseTeam}->{'players'}};
##     my ($BaseRPTS) = Player::best_team($HashRef,
##                                        \@BasePlayers,
##                                        $PosRef, $Period);
##     $BaseRPTS = 0 unless(defined($BaseRPTS));
##     
##     for my $OtherTeam (sort @OtherTeams) {
##         my @OtherPlayers = sort @{$TeamsRef->{$OtherTeam}->{'players'}};
##         my ($OtherRPTS) = Player::best_team($HashRef,
##                                             \@OtherPlayers,
##                                             $PosRef, $Period);
##         $OtherRPTS = 0 unless(defined($OtherRPTS));
##         
##         for(my $BaseIdx = 0; $BaseIdx != @BasePlayers; ++$BaseIdx) {
##             my $BasePlayer = $BasePlayers[$BaseIdx];
##             warn("Offering $BasePlayer to $OtherTeam ...\n");
##             my $BaseFPTS = $HashRef->{$BasePlayer}->{'period'}->{$Period}->{'fpts'};
##             for(my $OtherIdx = 0; $OtherIdx != @OtherPlayers; ++$OtherIdx) {
##                 my $OtherPlayer = $OtherPlayers[$OtherIdx];
##                 warn("  Considering $OtherPlayer ...\n");
##                 my $OtherFPTS = $HashRef->{$OtherPlayer}->{'period'}->{$Period}->{'fpts'};
##                 
##                 my $DelOtherFPTS = $BaseFPTS - $OtherFPTS;
##                 next unless($AllowNeg || $DelOtherFPTS > 0);
##                 
##                 my @NewBasePlayers = @BasePlayers;
##                 splice(@NewBasePlayers, $BaseIdx, 1, $OtherPlayer);
##                 my ($NewBaseRPTS) = Player::best_team($HashRef,
##                                                       \@NewBasePlayers,
##                                                       $PosRef, $Period);
##                 next unless(defined($NewBaseRPTS));
## 
##                 my $DelBaseRPTS = $NewBaseRPTS - $BaseRPTS;
##                 next unless($DelBaseRPTS >= 0);
##                 
##                 my @NewOtherPlayers = @OtherPlayers;
##                 splice(@NewOtherPlayers, $OtherIdx, 1, $BasePlayer);
##                 my ($NewOtherRPTS) = Player::best_team($HashRef,
##                                                        \@NewOtherPlayers,
##                                                        $PosRef, $Period);
##                 next unless(defined($NewOtherRPTS));
##                 
##                 my $DelOtherRPTS = $NewOtherRPTS - $OtherRPTS;
##                 
##                 next unless($DelOtherFPTS > 0 || $DelOtherRPTS > 0);
##                 
##                 my $AdvantageRPTS = $DelBaseRPTS - $DelOtherRPTS;
##                 
##                 next unless($AdvantageRPTS > $DelOtherFPTS);
##                 
##                 push(@Trades, [ $BasePlayer, $OtherPlayer, $OtherTeam, $DelBaseRPTS, $DelOtherFPTS, $AdvantageRPTS ]);
##             }
##         }
##     }
##     
##     return(sort { $b->[3] <=> $a->[3] ||
##                       $a->[4] <=> $b->[4] ||
##                       $b->[5] <=> $a->[5] } @Trades);
## }

## sub must_get {
##     my ($TeamsRef, $BaseTeam, $HashRef, $PosRef, $Period) = @_;
##     
##     my @BasePlayers = sort @{$TeamsRef->{$BaseTeam}->{'players'}};
##     my ($BaseRPTS) = Player::best_team($HashRef,
##                                        \@BasePlayers,
##                                        $PosRef,
##                                        $Period);
##     $BaseRPTS = 0 unless(defined($BaseRPTS));
##     
##     my %Getters;
##     for my $NewPlayerName (sort keys %$HashRef) {
##         next unless($HashRef->{$NewPlayerName}->{'team'} eq 'Free Agent');
##         next unless($HashRef->{$NewPlayerName}->{'active'});
##         
##         warn("Considering $NewPlayerName ...\n");
##         my $NewPlayerScore = $HashRef->{$NewPlayerName}->{'period'}->{$Period}->{'fpts'};
##         for(my $OldIdx = 0; $OldIdx != @BasePlayers; ++$OldIdx) {
##             my $OldPlayer = $BasePlayers[$OldIdx];
##             my $OldPlayerScore = $HashRef->{$OldPlayer}->{'period'}->{$Period}->{'fpts'};
##             
##             my @NewPlayers = @BasePlayers;
##             $NewPlayers[$OldIdx] = $NewPlayerName;
##             
##             my ($NewRPTS) = Player::best_team($HashRef,
##                                               \@NewPlayers,
##                                               $PosRef,
##                                               $Period);
##             $NewRPTS = 0 unless(defined($NewRPTS));
##             next unless($NewRPTS > $BaseRPTS ||
##                         ($NewRPTS == $BaseRPTS &&
##                          $NewPlayerScore > $OldPlayerScore));
##             
##             $Getters{$NewPlayerName}->{$OldPlayer} = $NewRPTS - $BaseRPTS;
##         }
##     }
##     return(%Getters);
## }

1;
