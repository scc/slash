#!/usr/bin/perl -w

###############################################################################
# cheesyportal.pl - this code displays a bunch of portals 
#
# Copyright (C) 1997 Rob "CmdrTaco" Malda
# malda@slashdot.org
#
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License
# as published by the Free Software Foundation; either version 2
# of the License, or (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program; if not, write to the Free Software
# Foundation, Inc., 59 Temple Place - Suite 330, Boston, MA  02111-1307, USA.
#
#
#  $Id$
###############################################################################
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

	slashDisplay('cheesyportal-main', {
		title	=> "Cheesy $constants->{sitename} Portal Page",
		width	=> '100%',
		portals	=> \@portals,
	});

	footer();

	writeLog('cheesyportal') unless $form->{ssi};
}

#################################################################
# this gets little snippets of data all in grouped together in
# one template, called "cheesyportal-data"
sub getData {
	my($value, $hashref) = @_;
	$hashref ||= {};
	$hashref->{value} = $value;
	return slashDisplay('cheesyportal-data', $hashref, 1, 1);
}

#################################################################
createEnvironment();
main();

1;
