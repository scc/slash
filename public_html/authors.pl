#!/usr/bin/perl -w

###############################################################################
# authors.pl - this code displays information about site authors
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

sub main {
	my $slashdb = getCurrentDB();
	my $constants = getCurrentStatic();
	my $form = getCurrentForm();

	my $section = getSection($form->{section});
	my $list = $slashdb->getAuthorDescription();
	my $authors = $slashdb->getAuthors();

	header("$constants->{sitename}: Authors", $section->{section});
	slashDisplay('authors-main', {
		aids	=> $list,
		authors	=> $authors,
		title	=> "The Authors",
		admin	=> getCurrentUser('seclev') >= 1000,
		'time'	=> scalar localtime,
	});

	writeLog('authors');
	footer($form->{ssi});
}

createEnvironment();
main();
