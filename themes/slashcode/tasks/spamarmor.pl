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

# This is just a default. See the 'timespec' file in your slash site directory.
$task{$PROGNAME}{timespec} = '0 6 * * *';

# Handles rotation of fakeemail address of all users.
$task{$PROGNAME}{code} = sub {
	my ($virtual_user, $constants, $slashdb, $user) = @_;

	# Loop over all users.
	for ($slashdb->getDescriptions('users')) {
		# Iterates over an array of array references. Each array
		# reference contains ($uid, $nickname).
		my $user = getCurrentUser($_->[0]);
		
		# Should be a constant somewhere, probably. The naked '1' below
		# refers to the code in $users->{emaildisplay} corresponding to 
		# random rotation of $users->{fakeemail}. This would be much
		# easier to do if $users->{emaildisplay} was in the schema.
		next if $user->{emaildisplay} != 1;

		# Get a random record from the 'spamarmor' table and then 
		# create a Safe compartment to execute its regexp code.
		my $armor_code = $slashdb->getRandomSpamArmor()->{code};
		my $cpt = new Safe;
		# We only permit basic arithmetic, loop and looping opcodes.
		# We also explicitly allow join since some code may involve
		# Separating the address so that obfuscation can be performed
		# in parts.
		$cpt->permit(qw[:base_core :base_loop :base_math join]);
		# Each compartment should be designed to take input from, and 
		# send output to, $_.
		$_ = $user->{realemail};
		$cpt->reval($armor_code);

		# Now check for errors.
		if ($@) {
			$print "Error in compartment execution: $@\n";
			next;
		} else {
			# If no errors? Save the result.
			$slashdb->setUser($uid, {
				fakeemail	=> $new_fake_email,
			});
		}
	}
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
