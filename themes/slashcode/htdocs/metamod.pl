#!/usr/bin/perl -w

###############################################################################
# metamod.pl - this code displays the page where users meta-moderate 
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

	$I{U}{karma} = $I{dbobject}->getUser($I{U}{uid}, 'karma')
		unless $I{U}{is_anon};
	header("Meta Moderation");

	my $id = isEligible();
	if (!$id) {
		print <<EOT;
<BR>You are currently not eligible to Meta Moderate.<BR>
Return to <A HREF="$I{rootdir}/">the $I{sitename} homepage</A>.<BR>
EOT

	} elsif ($I{F}{op} eq "MetaModerate") {
		metaModerate($id);
	} else {
		displayTheComments($id);
	}

	$I{dbobject}->writelog("metamod", $I{F}{op});
	footer();
}

#################################################################
sub karmaBonus {
	my $x = $I{m2_maxbonus} - $I{U}{karma};

	return 0 unless $x > 0;
	return 1 if rand($I{m2_maxbonus}) < $x;
	return 0;
}

#################################################################
sub metaModerate {
	my %metamod;

	my $id = shift;
	# Sum Elements from Form and Update User Record
	my $y = 0;

	foreach (keys %{$I{F}}) {

		# Meta mod form data can only be a '+' or a '-' so we apply some
		# protection from taint.
		next unless $I{F}{$_} =~ s/^[+-]$//; # bad input, bad!
		if (/^mm(\d+)$/) {
			$metamod{unfair}++ if $I{F}{$_} eq "-";
			$metamod{fair}++ if $I{F}{$_} eq "+";
		}
	}


	my %m2victims;
	foreach (keys %{$I{F}}) {
		if ($y < $I{m2_comments} && /^mm(\d+)$/ && $I{F}{$_}) { 
			my $id = $1;
			$y++;
			my $muid = $I{dbobject}->getModeratorLog($id);

			$m2victims{$id} = [$muid, $I{F}{$_}];
		}
	}

	# Perform M2 validity checks and set $flag accordingly. M2 is only recorded
	# if $flag is 0. Immediate and long term checks for M2 validity go here
	# (or in moderatord?).
	#
	# Also, it was probably unnecessary, but I want it to be understood that
	# an M2 session can be retrieved by:
	#		SELECT * from metamodlog WHERE uid=x and ts=y 
	# for a given x and y.
	my($flag, $ts) = (0, time);
	if ($y >= $I{m2_mincheck}) {
		# Test for excessive number of unfair votes (by percentage)
		# (Ignore M2 & penalize user)
		$flag = 2 if ($metamod{unfair}/$y >= $I{m2_maxunfair});
		# Test for questionable number of unfair votes (by percentage)
		# (Ignore M2).
		$flag = 1 if (!$flag && ($metamod{unfair}/$y >= $I{m2_toomanyunfair}));
	}

	my $changes = $I{dbobject}->setMetaMod(\%m2victims, $flag, $ts);
	for (@$changes) {
		print "<BR>Updating $_[0] with $_[1]" if $I{U}{aseclev} > 10;
	}

	print <<EOT;
$y comments have been meta moderated.  Thanks for participating.
You may wanna go back <A HREF="$I{rootdir}/">home</A> or perhaps to
<A HREF="$I{rootdir}/users.pl">your user page</A>.
EOT

	print "<BR>Total unfairs is $metamod{unfair}" if $I{U}{aseclev} > 10;

	$metamod{unfair} ||= 0;
	$metamod{fair} ||= 0;
	$I{dbobject}->setModerationVotes($I{U}{uid}, \%metamod)
		unless $I{U}{is_anon};

	# Of course, I'm waiting for someone to make the eventual joke...
	my($change, $excon);
	if ($y > $I{m2_mincheck}) {
		if (!$flag && karmaBonus()) {
			# Bonus Karma For Helping Out - the idea here, is to not 
			# let meta-moderators get the +1 posting bonus.
			($change, $excon) =
				("karma$I{m2_bonus}", "and karma<$I{m2_maxbonus}");
			$change = $I{m2_maxbonus}
				if $I{m2_maxbonus} < $I{U}{karma} + $I{m2_bonus};

		} elsif ($flag == 2) {
			# Penalty for Abuse
			($change, $excon) = ("karma$I{m2_penalty}", '');
		}

		# Update karma.
		# This is an abuse
		$I{dbobject}->setUser($I{U}{uid}, { -karma => "karma$change" })
			if $change;
	}
}


#################################################################
sub displayTheComments {
	my $id = shift;

	titlebar("99%","Meta Moderation");
	print <<EOT;
<B>PLEASE READ THE DIRECTIONS CAREFULLY BEFORE EMAILING
\U$I{siteadmin_name}\E!</B> <P>What follows is $I{m2_comments} random 
moderations performed on comments in the last few weeks on $I{sitename}. 
You are asked to <B>honestly</B> evaluate the actions of the moderator of each
comment. Moderators who are ranked poorly will cease to be eligible for
moderator access in the future.

<UL>

<LI>If you are confused about the context of a particular comment, just
link back to the comment page through the parent link, or the #XXX cid
link.</LI>

<LI><B><FONT SIZE="5">Duplicates are fine</FONT></B> (Big because over
<B>100</B> people have emailed me to tell me about this even though it is
explained <B>right here</B>.)  You are not moderating a "Comment" you
are moderating a "Moderation".  Therefore, if a comment is moderated
more than once, it can appear multiple times below.  Don't worry about it.</LI>

<LI>If you are unsure, feel free to leave it unchanged.</LI>

<LI>Please read the <A HREF="$I{rootdir}/moderation.shtml">Moderator Guidelines</A>
and try to be impartial and fair.  You are not moderating to make your
opinions heard, you are trying to help promote a rational discussion. 
Play fairly and help make $I{sitename} a little better for everyone.</LI>

<LI>Scores and information identifying the posters of these comments have been
removed to help prevent bias in meta moderation.
If you really need to know, you can click through and see the original message,
but we encourage you not to do this unless you need more context to fairly
meta moderate.</LI> 

</UL>

<FORM ACTION="$ENV{SCRIPT_NAME}" METHOD="POST">
<TABLE>

EOT
	
	$I{U}{noscores} = 1; # Keep Things Impartial

	my $c = sqlSelectMany("comments.cid," . getDateFormat("date","time") . ",
		subject,comment,nickname,homepage,fakeemail,realname,
		users.uid as uid,sig,comments.points as points,pid,comments.sid as sid,
		moderatorlog.id as id,title,moderatorlog.reason as modreason,
		comments.reason",
		"comments,users,users_info,moderatorlog,stories",
		"stories.sid=comments.sid AND 
		moderatorlog.sid = comments.sid AND
		moderatorlog.cid = comments.cid AND
		moderatorlog.id > $id AND
		comments.uid != $I{U}{uid} AND
		users.uid = comments.uid AND
		users.uid = users_info.uid AND
		users.uid != $I{U}{uid} AND
		moderatorlog.uid != $I{U}{uid} AND
		moderatorlog.reason < 8 LIMIT $I{m2_comments}");

	$I{U}{points} = 0;
	while(my $C = $c->fetchrow_hashref) {
		# Anonymize the comment; it should be safe to reset $C->{uid}, and 
		# $C->{points} (as a matter of fact, the latter SHOULD be done due to
		# the nickname).
		#
		# The '-' in place of nickname -may- be a problem, though. And we
		# Probably shouldn't assume a score of 0, here either but we'll leave
		# it for now.
		@{$C}{qw(nickname uid fakeemail homepage points)} =
			('-', -1, '', '', 0);
		dispComment($C);
		printf <<EOT, linkStory({ 'link' => $C->{title}, sid => $C->{sid} });
	<TR><TD>
		Story:<B>%s</B><BR> Rating:
		'<B>$I{reasons}[$C->{modreason}]</B>'.<BR>This rating is <B>Unfair
			<INPUT TYPE="RADIO" NAME="mm$C->{id}" VALUE="-">
			<INPUT TYPE="RADIO" NAME="mm$C->{id}" VALUE="0" CHECKED>
			<INPUT TYPE="RADIO" NAME="mm$C->{id}" VALUE="+">
		Fair</B><HR>
	</TD></TR>
	
EOT
	}

	print <<EOT;

</TABLE>

<INPUT TYPE="SUBMIT" NAME="op" VALUE="MetaModerate">

</FORM>

EOT


}

#################################################################
# This is going to break under replication
sub isEligible {

	if ($I{U}{is_anon}) {
		print "You are not logged in";
		return 0;
	}

	my $tuid = $I{dbobject}->countUsers();
	
	if ($I{U}{uid} > int($tuid * $I{m2_userpercentage}) ) {
		print "You haven't been a $I{sitename} user long enough.";
		return 0;
	}

	if ($I{U}{karma} < 0) {
		print "You have bad Karma.";
		return 0;	
	}

	my $last = $I{dbobject}->getModeratorLast($I{U}{uid});

	# must be eq "0", since == 0 might return true improperly
	if ($last->{'lastmm'} eq "0") {
		print "You have recently meta moderated.";
		return 0;
	}

	# Eligible for M2. Determine M2 comments by selecting random starting
	# point in moderatorlog.
	unless ($last->{'lastmmid'}) {
		$last->{'lastmmid'} = $I{dbobject}->getModeratorLogRandom();
		$I{dbobject}->setUser($I{U}{uid}, { lastmmid => $last->{'lastmmid'} });
	}

	return $last->{'lastmmid'}; # Hooray!
}

main();

