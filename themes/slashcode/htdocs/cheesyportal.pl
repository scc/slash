#!/usr/bin/perl -w
# This code is a part of Slash, which is Copyright 1997-2001 OSDN, and
# released under the GPL.  See README and COPYING for more information.
# $Id$

use strict;
use Slash;
use Slash::Display;
use Slash::Utility;

##################################################################
sub main {
	my $slashdb = getCurrentDB();
	my $constants = getCurrentStatic();
	my $user = getCurrentUser();
	my $form = getCurrentForm();

	header(getData('head'));

	my @portals;
	my $portals = $slashdb->getPortals();

	for (@$portals) {
		my $portal = {};
		@{$portal}{qw(block title bid url)} = @$_;

		if ($portal->{bid} eq 'mysite') {
			$portal->{box} = portalbox($constants->{fancyboxwidth},
				getData('mysite'),
				$user->{mylinks} ||  $portal->{block}
			);
		} elsif ($portal->{bid} =~ /_more$/) {    # do nothing
			next;
		} elsif ($portal->{bid} eq 'userlogin') { # do nothing
			next;
		} else {
			$portal->{box} = portalbox($constants->{fancyboxwidth},
				$portal->{title},
				$portal->{block}, '', $portal->{url}
			);
		}

		push @portals, $portal;
	}

	slashDisplay('main', {
		title	=> "Cheesy $constants->{sitename} Portal Page",
		width	=> '100%',
		portals	=> \@portals,
	});

	footer();

	writeLog('cheesyportal') unless $form->{ssi};
}

#################################################################
createEnvironment();
main();

1;
