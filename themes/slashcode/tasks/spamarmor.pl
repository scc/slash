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

$task{$PROGNAME}{timespec} = '22 6 * * *';

# Handles rotation of fakeemail address of all users.
$task{$PROGNAME}{code} = sub {
	my($virtual_user, $constants, $slashdb, $user) = @_;

	# Loop over all users.
	my $nicks = ($slashdb->getDescriptions('users'))[0];
	for (keys %{$nicks}) {
		$user = $slashdb->getUser($_);

		# Should be a constant somewhere, probably. The naked '1' below
		# refers to the code in $users->{emaildisplay} corresponding to
		# random rotation of $users->{fakeemail}. This would be much
		# easier to do if $users->{emaildisplay} was in the schema.
		next if $user->{emaildisplay} != 1;

		# Randomize the email armor.
		$user->{fakeemail} = getArmoredEmail($_);

		# If executed properly, $user->{fakeemail} should have a value.
		# If so, save the result.
		$slashdb->setUser($user->{uid}, {
			fakeemail	=> $user->{fakeemail},
		}) if $user->{fakeemail};
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
