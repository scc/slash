#!/usr/bin/perl -w

###############################################################################
# pollBooth.pl - this page displays the page where users can vote in a poll, 
# or displays poll results 
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
	my $slashdb = getCurrentDB();
	my $form = getCurrentForm();
	my $user = getCurrentUser();

	my $op = $form->{op};
	if (defined $form->{aid} && $form->{aid} !~ /^\-?\d$/) {
		undef $form->{aid};
	}

	# add to admin menu before calling header()
	# remove this, maybe, and just add it to the database?
	# -- pudge
	if ($user->{is_admin}) {
		my @menu = split /\|/, getData('admin');
		addToMenu('admin', 'newpoll', {
			value	=> $menu[0],
			label	=> $menu[1],
			seclev	=> $menu[2]
		});
	}

	header(getData('title'), $form->{section});

	if ($user->{seclev} > 99 && $op eq 'edit') {
		editpoll($form->{qid});

	} elsif ($user->{seclev} > 99 && $op eq 'save') {
		savepoll();

	} elsif (! defined $form->{qid}) {
		listpolls();

	} elsif (! defined $form->{aid}) {
		pollbooth($form->{qid}, 0, 1);

	} else {
		my $vote = vote($form->{qid}, $form->{aid});
		printComments($form->{qid})
			if $vote && ! $slashdb->getVar('nocomment', 'value');
	}

	writeLog('pollbooth', $form->{qid});
	footer();
}

#################################################################
sub editpoll {
	my($qid) = @_;
	my $slashdb = getCurrentDB();

	my($currentqid) = $slashdb->getVar('currentqid', 'value');
	my $question = $slashdb->getPollQuestion($qid, ['question', 'voters']);
	$question->{voters} ||= 0;

	my $answers = $slashdb->getPollAnswers($qid, ['answer', 'votes']);

	slashDisplay('pollBooth-editpoll', {
		checked		=> $currentqid eq $qid ? ' CHECKED' : '',
		qid		=> strip_attribute($qid),
		question	=> $question,
		answers		=> $answers,
	});
}

#################################################################
sub savepoll {
	return unless getCurrentForm('qid');
	my $slashdb = getCurrentDB();
	slashDisplay('pollBooth-savepoll');
	$slashdb->savePollQuestion();
}

#################################################################
sub vote {
	my($qid, $aid) = @_;
	return unless $qid;

	my $user = getCurrentUser();
	my $constants = getCurrentStatic();
	my $slashdb = getCurrentDB();

	my(%all_aid) = map { ($_->[0], 1) }
		@{$slashdb->getPollAnswers($qid, ['aid'])};

	if (! keys %all_aid) {
		print getData('invalid');
		# Non-zero denotes error condition and that comments
		# should not be printed.
		return;
	}

	my $question = $slashdb->getPollQuestion($qid, ['voters', 'question']);
	my $notes = getData('display');
	if ($user->{is_anon} && ! $constants->{allow_anonymous}) {
		$notes = getData('anon');
	} elsif ($aid > 0) {
		my $id = $slashdb->getPollVoter($qid);

		if ($id) {
			$notes = getData('uid_voted');
		} elsif (exists $all_aid{$aid}) {
			$notes = getData('success', { aid => $aid });
			$slashdb->createPollVoter($qid, $aid);
			$question->{voters}++;
		} else {
			$notes = getData('reject', { aid => $aid });
		}
	}

	my $answers  = $slashdb->getPollAnswers($qid, ['answer', 'votes']);
	my $maxvotes = $slashdb->getPollVotesMax($qid);
	my @pollitems;
	for (@$answers) {
		my($answer, $votes) = @$_;
		my $imagewidth	= $maxvotes
			? int(350 * $votes / $maxvotes) + 1
			: 0;
		my $percent	= $question->{voters}
			? int(100 * $votes / $question->{voters})
			: 0;
		push @pollitems, [$answer, $imagewidth, $votes, $percent];
	}

	my $postvote = $slashdb->getBlock("$user->{currentSection}_postvote", 'block')
		|| $slashdb->getBlock('postvote', 'block');

	slashDisplay('pollBooth-vote', {
		qid		=> strip_attribute($qid),
		width		=> '99%',
		title		=> $question->{question},
		voters		=> $question->{voters},
		pollitems	=> \@pollitems,
		postvote	=> $postvote,
		notes		=> $notes
	});
}

#################################################################
sub listpolls {
	my $slashdb = getCurrentDB();
	my $min = getCurrentForm('min') || 0;
	my $questions = $slashdb->getPollQuestionList($min);
	my $sitename = getCurrentStatic('sitename');

	slashDisplay('pollBooth-listpolls', {
		questions	=> $questions,
		startat		=> $min + @$questions,
		admin		=> getCurrentUser('seclev') >= 100,
		title		=> "$sitename Polls",
		width		=> '99%'
	});
}

#################################################################
# this gets little snippets of data all in grouped together in
# one template, called "pollbooth-data"
sub getData {
	my($value, $hashref) = @_;
	$hashref ||= {};
	$hashref->{value} = $value;
	return slashDisplay('pollBooth-data', $hashref,
		{ Return => 1, Nocomm => 1 });
}

createEnvironment();
main();

1;
