#!/usr/bin/perl -w
# This code is a part of Slash, and is released under the GPL.
# Copyright 1997-2001 by Open Source Development Network. See README
# and COPYING for more information, or see http://slashcode.com/.
# $Id$

use strict;
use vars qw( %task );
use FindBin '$Bin';
use File::Basename;
use Slash::DB;
use Slash::Display;
use Slash::Utility;
use Digest::MD5 'md5_hex';
use Getopt::Std;

(my $VERSION) = ' $Revision$ ' =~ /\$Revision:\s+([^\s]+)/;
my $PROGNAME = basename($0);
(my $PREFIX = $Bin) =~ s|/[^/]+/?$||;

# Remember that timespec goes by the database's time, which should be
# GMT if you installed everything correctly.  So 6 AM GMT is a good
# sort of midnightish time for the Western Hemisphere.  Adjust for
# your audience and admins.
$task{$PROGNAME}{timespec} = '0 6 * * *';

# Handles mail and administrivia necessary for RECENTLY expired users.
$task{$PROGNAME}{code} = sub {
    my ($virtual_user, $constants, $slashdb, $user);

    # We only perform the check if any of the following are turned on.
    # the logic below, should probably be moved into Slash::Utility.
    return unless allowExpire();

    # Error check here? If so, die with what error if this fails?
    my $messages = getObject('Slash::Messages');
 
     # Loop over all about-to-expire users.
    my $reg_subj = "You're $constants->{sitename} password has expired.";
    for my $e_user (@{$slashdb->checkUserExpiry()}) {
        # Put user in read-only mode for all forms and other 'pages' that
        # should be.
	setUserExpired($e_user->{uid}, 1);
 
        # Determine regid. We want to strive for as much randomness as we
        # can without getting overly complex. Let's just create a string
        # that should have a reasonable degree of uniqueness by user.
        #
        # Now, how likely is it that this will result in a collision?
        # Note that we obscure with an MD5 hex has which is safer in URLs
        # than base65 hashes.
        my $regid = md5_hex(
            time . "$e_user->{nickname}" . int(rand * 255)
        );
 
        # We now unregister the user, but we need to keep the ID for later.
        # Consider removal of the 'registered' flag. This state can simply
        # be determined by the presence of a non-zero length value in
        # 'reg_id'. If 'reg_id' doesn't exist, that is considered to be
        # a zero-length value.
        $slashdb->setUser($e_user->{uid}, {
            'registered'    => '0',
            'reg_id'        => $regid,
        });
 
        # Send the mail notification, note that we pass the into the template
        # since we aren't in the mod_perl environment when this runs.
        my $reg_msg = slashDisplay('reRegisterMail',
            {
                # This should probably be renamed to prevent confusion.
                # But there is no real need for the CURRENT user's value
                # in this template.
                user        => $e_user,
                registryid  => $regid,
                useradmin   => $constants->{reg_useradmin} ||
                               $constants->{adminmail},
            },
 
            {
                Return  => 1,
                Nocomm  => 1,
                Page    => 'messages',
                Section => 'NONE'
            }
        );

        # Send the message.
        $messages->quicksend($e_user->{uid}, $reg_subj, $reg_msg,  1);
    }            
};

# Standalone code.
if ($0 =~ /$PROGNAME$/) {
	my(%opts);

	getopts('huv', \%opts);
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
