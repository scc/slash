#!/usr/bin/perl -w

###############################################################################
# topics.pl - this page is for the display and modification of system topics by
# authors 
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

#################################################################
sub main {
	my $form = getCurrentForm();
	my $section = getSection();

	header(getData('head'), $section->{section});
	print createMenu('topics');

	if ($form->{op} eq 'toptopics') {
		topTopics($section);
	} else {
		listTopics();
	}

	writeLog('topics');
	footer($form->{ssi});
}

#################################################################
sub topTopics {
	my($section) = @_;
	my $slashdb = getCurrentDB();
	my $form = getCurrentForm(); 

	$section->{issue} = 0;  # should this be local() ?  -- pudge

	my(@topics, $topics);
	$topics = $slashdb->getTopNewsstoryTopics($form->{all});

	for (@$topics) {
		my $top = $topics[@topics] = {};
		@{$top}{qw(tid alttext image width height cnt)} = @$_;
		$top->{count} = $slashdb->countStory($top->{tid});

		my $limit = $top->{cnt} > 10
			? 10 : $top->{cnt} < 3 || $form->{all}
			? 3 : $top->{cnt};

		$top->{stories} = getOlderStories(
			$slashdb->getStories($section, $limit, $top->{tid}),
			$section
		);
	}

	slashDisplay('topics-topTopics', {
		title		=> 'Recent Topics',
		width		=> '90%',
		topics		=> \@topics,
		currtime	=> scalar localtime,
	});

	writeLog('topics');
}

#################################################################
sub listTopics {
	my $slashdb = getCurrentDB();

	slashDisplay('topics-listTopics', {
		title		=> 'Current Topic Categories',
		width		=> '90%',
		topic_admin	=> getCurrentUser('seclev') > 500,
		topics		=> $slashdb->getTopics()
	});

}

#################################################################
# this gets little snippets of data all in grouped together in
# one template, called "topics-data"
sub getData {
	my($value, $hashref) = @_;
	$hashref ||= {};
	$hashref->{value} = $value;
	return slashDisplay('topics-data', $hashref, 1, 1);
}

#################################################################
createEnvironment();
main();

1;
