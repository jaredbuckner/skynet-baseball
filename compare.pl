#!/usr/bin/perl -w

use strict;

use lib ".";
use Player;

Player->fillData('data');

my @Players = sort { $b->fptsWtd() <=> $a->fptsWtd() } Player->allPlayers();

for my $Player (@Players) {
    printf("%-30s %11s %1s %-28s %7.2f [%7.2f]\n",
           $Player->name(),
           (join(':', sort $Player->pos())),
           ($Player->isActive() ? '*' : ''),
           (defined($Player->owner()) ? $Player->owner() : ''),
           $Player->fptsWtd(),
           $Player->fptsRoS());
}

