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
use Slash::DB;
use Slash::Utility;

##################################################################
sub main {
	getSlash();
	my $user = getCurrentUser();
	my $db = getCurrentDB();
	my $constants = getCurrentStatic();

	header("Cheesy Portal");
	# Display Blocks
	titlebar("100%", "Cheesy $constants->{sitename} Portal Page");
	my $portals = $db->getPortals();

	print qq!<MULTICOL COLS="3">\n!;
	my $b;
	for(@$portals) {
		my($block, $title, $bid, $url) = @$_ ;
		if ($bid eq "mysite") {
			$b = portalbox($constants->{fancyboxwidth},
				"$user->{nickname}'s Slashbox",
				$user->{mylinks} ||  $block
			);

		} elsif ($bid =~ /_more$/) {	# do nothing
		} elsif ($bid eq "userlogin") {	# do nothing
		} else {
			$b = portalbox($constants->{fancyboxwidth},
				$title, $block, "", $url
			);
		}

		print $b;
	}

	print "\n</MULTICOL>\n";

	footer();

	writeLog("cheesyportal") unless getCurrentForm('ssi');
}

main();
