#!/usr/bin/perl -w
# This code is a part of Slash, and is released under the GPL.
# Copyright 1997-2001 by Open Source Development Network. See README
# and COPYING for more information, or see http://slashcode.com/.
# $Id$

use strict;
use vars qw( %task );
use FindBin '$Bin';
use File::Basename;
use Getopt::Std;
use Safe;
use Slash;
use Slash::DB;
use Slash::Display;
use Slash::Utility;

(my $VERSION) = ' $Revision$ ' =~ /\$Revision:\s+([^\s]+)/;
#my $PROGNAME = basename($0);
my $PROGNAME = 'spamarmor.pl';
(my $PREFIX = $Bin) =~ s|/[^/]+/?$||;

$task{$PROGNAME}{timespec} = '30 0 * * *';

# Handles rotation of fakeemail address of all users.
$task{$PROGNAME}{code} = sub {
	my($virtual_user, $constants, $slashdb, $user) = @_;

#	# Loop over all users. The call to iterateUsers gets a block of 
#	# users and iterates over that. As opposed to trying to grab all
#	# of the ENTIRE USERBASE at once. Since a statement handle would
#	# be the best way to get this data, but the API doesn't return 
#	# statement handles, we'll have to use a few tricks.
#	my ($count, $usr_block) = (0, 0);
#	do {
#		my $usr_block = $slashdb->iterateUsers(1000);
#
#		for my $user (@{$usr_block}) {
#	# Should be a constant somewhere, probably. The naked '1' below
#	# refers to the code in $users->{emaildisplay} corresponding to
#	# random rotation of $users->{fakeemail}.
#			next if !defined($user->{emaildisplay})
#				or $user->{emaildisplay} != 1;
#
#	# Randomize the email armor.
#			$user->{fakeemail} = getArmoredEmail($_);
#
#	# If executed properly, $user->{fakeemail} should have a value.
#	# If so, save the result.
#			if ($user->{fakeemail}) {
#				$slashdb->setUser($user->{uid}, {
#					fakeemail	=> $user->{fakeemail},
#				});
#				$count++;
#			}
#		}
#	} while $usr_block;

	my $count = 0;
	my $hr = $slashdb->getTodayArmorList();
	for my $uid (sort { $a <=> $b } keys %$hr) {
		my $fakeemail = getArmoredEmail($uid, $hr->{$uid}{realemail});
		$slashdb->setUser($uid, { fakeemail => $fakeemail });
		++$count;
		sleep 1 if ($count % 20) == 0;
	}

	slashdLog("$PROGNAME: Rotated armoring on $count user accounts");
};


# Standalone code.
if ($0 =~ /$PROGNAME$/) {
	my(%opts);

	getopts('hu:v', \%opts);
	if (exists $opts{h} || !exists $opts{u}) {
		print <<EOT;

Usage: $PROGNAME -u [virtual user]

	This program is designed for execution within the Slash architecture
	and should only be run as a standalone for testing purposes.
EOT

		exit 1;
	} elsif (exists $opts{v}) {
		print "(slashd task) $PROGNAME $VERSION.\n\n";
	}

	createEnvironment($opts{u});
	my $constants = getCurrentStatic();
	my $slashdb = getCurrentDB();

	# Calls the code defined above.
	$task{$PROGNAME}{code}->($opts{u}, $constants, $slashdb);
}

1;
