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
use vars '%I';
use Slash;

##################################################################
sub main {
	*I = getSlashConf();
	getSlash();

	header("Cheesy Portal");
	# Display Blocks
	titlebar("100%", "Cheesy $I{sitename} Portal Page");
	my $portals = $I{dbobject}->getPortals();

	print qq!<MULTICOL COLS="3">\n!;
	my $b;
	for(@$portals) {
		my($block, $title, $bid, $url) = @$_ ;
		if ($bid eq "mysite") {
			$b = portalbox($I{fancyboxwidth},
				"$I{U}{nickname}'s Slashbox",
				$I{U}{mylinks} ||  $block
			);

		} elsif ($bid =~ /_more$/) {
		} elsif ($bid eq "userlogin") {
		} else {
			$b = portalbox($I{fancyboxwidth},
				$title, $block, "", $url
			);
		}

		print $b;
	}

	print "\n</MULTICOL>\n";

	footer();

	$I{dbobject}->writelog("cheesyportal") unless $I{F}{ssi};
}

main();
