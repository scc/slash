#!/usr/bin/perl -w

###############################################################################
# article.pl - this code displays a particular story and it's comments 
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
	my $form = getCurrentForm();
	my $user = getCurrentUser();
	my $dbslash = getCurrentDB();
	my $constants = getCurrentStatic();

	# Let's make ONE call to getStory() and fetch all we need.
	# - Cliff
	my $story = $dbslash->getStory($form->{sid});

	if ($story->{writestatus} == 10) {
		$ENV{SCRIPT_NAME} = '';
		redirect(<<EOT);
$constants->{rootdir}/$story->{section}/$story->{sid}_$constants->{userMode}.shtml
EOT
		return;
	};

	my $SECT = $dbslash->getSection($story->{section});
	my $title = $SECT->{isolate} ?
		"$SECT->{title} | $story->{title}" :
		"$constants->{sitename} | $story->{title}";

	header($title, $story->{section});
	slashDisplay('display', {
		poll			=> pollbooth($story->{sid}, 1),
		section			=> $SECT,
		section_block	=> $dbslash->getBlock($SECT->{section}),
		show_poll		=> $dbslash->getPollQuestion($story->{sid}),
		story			=> $story,
		'next'			=> $dbslash->getStoryByTime('>', $story, $SECT),
		prev			=> $dbslash->getStoryByTime('<', $story, $SECT),
	});

	printComments($form->{sid});

	writeLog($SECT->{section}, $story->{sid} || $form->{sid})
		unless $form->{ssi};
	footer();
}

createEnvironment();
main();
1;
