#!/usr/bin/perl -w

###############################################################################
# 404.pl - this code displays the error page
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
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.	See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program; if not, write to the Free Software
# Foundation, Inc., 59 Temple Place - Suite 330, Boston, MA	 02111-1307, USA.
#
#
#  $Id$
###############################################################################
use strict;
use Slash;
use Slash::Utility;
use Slash::Display;

sub main {
	my $constants = getCurrentStatic();
	$ENV{REQUEST_URI} ||= "";

	my $url = stripByMode(substr($ENV{REQUEST_URI}, 1), 'exttrans');

	my $admin = $constants->{adminmail};

	header("404 File Not Found", '', '404 File Not Found');

	my($new_url, $errnum) = fixHref($url, 1);

	if ($errnum && $errnum !~ /^\d+$/) {
		slashDisplay('404-main', {
			url => $new_url,
			origin => $url,
			message => $errnum,
		});
	} else {
		slashDisplay('404-main', {
			error  => $errnum,
			url => $new_url,
			origin => $url,
		});
	}

	writeLog("404","404");
	footer();
}

main();

1;
