#!/usr/bin/perl -w
# This code is a part of Slash, and is released under the GPL.
# Copyright 1997-2001 by Open Source Development Network. See README
# and COPYING for more information, or see http://slashcode.com/.
# $Id$

use strict;
use vars qw( %task );
use FindBin '$Bin';
use File::Basename;
use Slash;
use Slash::DB;
use Slash::Display;
use Slash::Utility;
use Getopt::Std;

(my $VERSION) = ' $Revision$ ' =~ /\$Revision:\s+([^\s]+)/;
#my $PROGNAME = basename($0);
my $PROGNAME = 'expire.pl';
(my $PREFIX = $Bin) =~ s|/[^/]+/?$||;

$task{$PROGNAME}{timespec} = '2 6 * * *';

# Handles mail and administrivia necessary for RECENTLY expired users.
$task{$PROGNAME}{code} = sub {
	my($virtual_user, $constants, $slashdb, $user) = @_;

	# We only perform the check if any of the following are turned on.
	# the logic below, should probably be moved into Slash::Utility.
	unless (allowExpiry()) {
		slashdLog("$PROGNAME - user expiration is disabled");
		return;
	}

	# This may need to go into a template somewhere.
	my $reg_subj = "Your $constants->{sitename} password has expired.";
	# Loop over all about-to-expire users.
	my @users_to_expire = @{$slashdb->checkUserExpiry()};
	for my $e_user (@users_to_expire) {
		# Put user in read-only mode for all forms and other 'pages' that
		# should be. This should also send the appropriate email. This
		# is better off in the API, as it is used in users.pl, as well.
		setUserExpired($e_user, 1);
	}

	slashdLog(sprintf "$PROGNAME: Expired %d users\n", @users_to_expire);
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
