#!/usr/bin/perl -w

use strict;

use lib ".";
use Player;

Player->fillData('data');

my ($Weeks) = @ARGV;

$Weeks //= 20;

my @Teams = Player->allOwners();

if(@Teams % 2 != 0) { push(@Teams, "<bye>"); }

my @LIdx = (0..(@Teams - 1));

for(my $Week = 1; $Week <= $Weeks; ++$Week) {
    print "==== WEEK $Week ====\n";

    for(my $GIdx = 0; $GIdx != @LIdx / 2; ++$GIdx) {
        if($GIdx == 0 ? $LIdx[-1] % 2 == 1 : $GIdx % 2 == 1) {
            printf("%30s @ %-30s\n",
                   $Teams[$LIdx[$GIdx]],
                   $Teams[$LIdx[@LIdx - $GIdx - 1]]);
        } else {
            printf("%30s @ %-30s\n",
                   $Teams[$LIdx[@LIdx - $GIdx - 1]],
                   $Teams[$LIdx[$GIdx]]);
        }
    }

    splice(@LIdx, 1, 0, splice(@LIdx, -1, 1));
}

exit 0;
