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
use vars '%I';
use Slash;

#################################################################
sub main {
	*I = getSlashConf();
	getSlash();

	if (defined $I{F}{aid} && $I{F}{aid} !~ /^\-?\d$/) {
		undef $I{F}{aid};
	}

	header("$I{sitename} Poll", $I{F}{section});

	if ($I{U}{aseclev} > 99) { 
		print qq!<FONT SIZE="2">[ <A HREF="$ENV{SCRIPT_NAME}?op=edit">New Poll</A> ]!;
	}
	my $op = $I{F}{op};
	if ($I{U}{aseclev} > 99 && $op eq "edit") {
		editpoll($I{F}{qid});

	} elsif ($I{U}{aseclev} > 99 && $op eq "save") {
		savepoll();

	} elsif (! defined $I{F}{qid}) {
		listPolls();

	} elsif (! defined $I{F}{aid}) {
		print "<CENTER><P>";
		pollbooth($I{F}{qid});
		print "</CENTER>";

	} else {
		print "<H1>Got here coments :$op:$I{F}{qid}:</H1>\n";
		my $vote = vote($I{F}{qid}, $I{F}{aid});
		printComments($I{F}{qid})
			if $vote && ! $I{dbobject}->getVar("nocomment");
	}

	$I{dbobject}->writelog("pollbooth", $I{F}{qid});
	footer();
}

#################################################################
sub editpoll {
	my($qid) = @_;
	my $qid_htm = stripByMode($qid, 'attribute');

	# Display a form for the Question
	my $question = $I{dbobject}->getPollQuestion($qid, 'question', 'voters');

	$question->{'voters'} = 0 if ! defined $question->{'voters'};

	my($currentqid) = $I{dbobject}->getVar("currentqid");
	printf <<EOT, $currentqid eq $qid ? " CHECKED" : "";

<FORM ACTION="$ENV{SCRIPT_NAME}" METHOD="POST">
	<B>id</B> (if this matches a story's ID, it will appear with the story,
		else just pick a unique string)<BR>
	<INPUT TYPE="TEXT" NAME="qid" VALUE="$qid_htm" SIZE="20">
	<INPUT TYPE="CHECKBOX" NAME="currentqid"%s> (appears on homepage)

	<BR><B>The Question</B> (followed by the total number of voters so far)<BR>
	<INPUT TYPE="TEXT" NAME="question" VALUE="$question->{'question'}" SIZE="40">
	<INPUT TYPE="TEXT" NAME="voters" VALUE="$question->{'voters'}" SIZE="5">
	<BR><B>The Answers</B> (voters)<BR>
EOT

	my $answers = $I{dbobject}->getPollAnswers($qid, 'answer', 'votes');
	my $x = 0;
	for (@$answers) {
		my($answers, $votes) = @$_;
		$x++;
		print <<EOT;
	<INPUT TYPE="text" NAME="aid$x" VALUE="$answers" SIZE="40">
	<INPUT TYPE="text" NAME="votes$x" VALUE="$votes" SIZE="5"><BR>
EOT
	}

	while ($x < 8) {
		$x++;
		print <<EOT;
	<INPUT TYPE="text" NAME="aid$x" VALUE="" SIZE="40">
	<INPUT TYPE="text" NAME="votes$x" VALUE="0" SIZE="5"><BR>
EOT
	}

	print <<EOT;
	<INPUT TYPE="SUBMIT" VALUE="Save">
	<INPUT TYPE="HIDDEN" NAME="op" VALUE="save">
</FORM>

EOT

}

#################################################################
sub savepoll {
	return unless $I{F}{qid};
	for (my $x = 1; $x < 9; $x++) {
		if ($I{F}{"aid$x"}) {
			print qq!<BR>Answer $x '$I{F}{"aid$x"}' $I{F}{"votes$x"}!;
		}
	}
	$I{dbobject}->savePollQuestion();
}

#################################################################
sub vote {
	my($qid, $aid) = @_;

	my $qid_htm = stripByMode($qid, 'attribute');

	# get valid answer IDs
	my(%all_aid) = map { ($_->[0], 1) }
		@{$I{dbobject}->getPollAnswer($qid,'aid')} if $qid;

	if (! keys %all_aid) {
		print "Invalid poll!<BR>";
		# Non-zero denotes error condition and that comments should not be 
		# printed.
		return;
	}

	my $notes = "Displaying poll results";
	if ($I{U}{uid} == $I{anonymous_coward_uid} && ! $I{allow_anonymous}) {
		$notes = "You may not vote anonymously.  " .
		    qq[Please <A HREF="$I{rootdir}/users.pl">log in</A>.];
	} elsif ($aid > 0) {
		my $id = $I{dbobject}->getPollVoter($qid);

		if ($id) {
			$notes = "$I{U}{nickname} at $ENV{REMOTE_ADDR} has already voted.";
			if ($ENV{HTTP_X_FORWARDED_FOR}) { 
				$notes .= " (proxy for $ENV{HTTP_X_FORWARDED_FOR})";
			}

		} elsif (exists $all_aid{$aid}) {
			$notes = "Your vote ($aid) has been registered.";
			$I{dbobject}->createPollVoter($qid, $aid);
		} else {
			$notes = "Your vote ($aid) was rejected.";
		}
	} 

	my $question = $I{dbobject}->getPollQuestion($qid, 'voters', 'question');

	my $maxvotes  = getPollVotesMax($qid);

	print <<EOT;
<CENTER><TABLE BORDER="0" CELLPADDING="2" CELLSPACING="0" WIDTH="500">
	<TR><TD> </TD><TD COLSPAN="1">
EOT

	titlebar("99%", $question->{'question'});
	print qq!\t<FONT SIZE="2">$notes</FONT></TD></TR>!;

	my $answers = $I{dbobject}->getPollAnswers($qid, 'answer', 'votes');

	for (@$answers) {
		my($answer, $votes) = @$_;
		my $imagewidth	= $maxvotes
			? int(350 * $votes / $maxvotes) + 1
			: 0;
		my $percent	= $question->{'totalvotes'}
			? int(100 * $votes / $question->{'totalvotes'})
			: 0;
		pollItem($answer, $imagewidth, $votes, $percent);
	}

	my $postvote = blockCache("$I{currentSection}_postvote")
		|| blockCache("postvote");

	print <<EOT;
	<TR><TD COLSPAN="2" ALIGN="RIGHT">
		<FONT SIZE="4"><B>$question->{'totalvotes'} total votes.</B></FONT>
	</TD></TR><TR><TD COLSPAN="2"><P ALIGN="CENTER">
		[
			<A HREF="$ENV{SCRIPT_NAME}?qid=$qid_htm">Voting Booth</A> |
			<A HREF="$ENV{SCRIPT_NAME}">Other Polls</A> |
			<A HREF="$I{rootdir}/">Back Home</A>
		]
	</TD></TR><TR><TD COLSPAN="2">$postvote</TD></TR>
</TABLE></CENTER>

EOT
}

#################################################################
sub listPolls {
	$I{F}{min} ||= "0";

	my $questions = $I{dbobject}->getPollQuestionList($I{F}{min});

	titlebar("99%", "$I{sitename} Polls");
	for (@$questions) {
		my($qid, $question, $date) = @$_;
		my $href = $I{U}{aseclev} >= 100
			? qq! (<A HREF="$ENV{SCRIPT_NAME}?op=edit&qid=$qid">Edit</A>)!
			: '';

		print <<EOT;
<BR><LI><A HREF="$ENV{SCRIPT_NAME}?qid=$qid">$question</A> $date$href</LI>
EOT

	}

	my $number = @$questions;
	my $startat = $I{F}{min} + $number;
	print <<EOT;
<P><FONT SIZE="4"><B><A HREF="$ENV{SCRIPT_NAME}?min=$startat">More Polls</A></B></FONT>
EOT

}

main();
#$I{dbh}->disconnect if $I{dbh};
1;
