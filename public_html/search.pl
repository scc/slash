#!/usr/bin/perl -w

###############################################################################
# search.pl - this code is the search page 
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
use Slash::DB;
use Slash::Utility;

#################################################################
sub main {
	*I = getSlashConf();
	getSlash();

	# Set some defaults
	$I{F}{query}		||= "";
	$I{F}{section}		||= "";
	$I{F}{op}		||= "";
	$I{F}{min}		||= "0";
	$I{F}{max}		||= "30";
	$I{F}{threshold}	||= getCurrentUser('threshold');
	$I{F}{'last'}		||= $I{F}{min} + $I{F}{max};

	# get rid of bad characters
	$I{F}{query} =~ s/[^A-Z0-9'. ]//gi;

	header("$I{sitename}: Search $I{F}{query}", $I{F}{section});
	titlebar("99%", "Searching $I{F}{query}");

	searchForm();

	if	($I{F}{op} eq 'comments')	{ commentSearch()	}
	elsif	($I{F}{op} eq 'users')		{ userSearch()		}
	elsif	($I{F}{op} eq 'stories')	{ storySearch()		}
	else	{
		print "Invalid operation!<BR>";
	}
	$I{dbobject}->writelog("search", $I{F}{query})
		if $I{F}{op} =~ /^(?:comments|stories|users)$/;
	footer();	
}

#################################################################
sub linkSearch {
	my $C = shift;
	my $r;

	foreach (qw[threshold query min author op sid topic section total hitcount]) {
		my $x = "";
		$x =  $C->{$_} if defined $C->{$_};
		$x =  $I{F}{$_} if defined $I{F}{$_} && $x eq "";
		$x =~ s/ /+/g;
		$r .= "$_=$x&" unless $x eq "";
	}
	$r =~ s/&$//;

	$r = qq!<A HREF="$ENV{SCRIPT_NAME}?$r">$C->{'link'}</A>!;
}


#################################################################
sub searchForm {
	my $SECT = getSection($I{F}{section});

	my $t = lc $I{sitename};
	$t = $I{F}{topic} if $I{F}{topic};
	my $tref = $I{dbobject}->getTopic($t);
	print <<EOT if $tref;

<IMG SRC="$I{imagedir}/topics/$tref->{image}"
	ALIGN="RIGHT" BORDER="0" ALT="$tref->{alttext}"
	HSPACE="30" VSPACE="10" WIDTH="$tref->{width}"
	HEIGHT="$tref->{height}">

EOT

	print <<EOT;
<FORM ACTION="$ENV{SCRIPT_NAME}" METHOD="POST">
	<INPUT TYPE="TEXT" NAME="query" VALUE="$I{F}{query}">
	<INPUT TYPE="SUBMIT" VALUE="Search">
EOT

	$I{F}{op} ||= "stories";
	my %ch;
	$ch{$I{F}{op}} = $I{F}{op} ? ' CHECKED' : '';

	print <<EOT;
	<INPUT TYPE="RADIO" NAME="op" VALUE="stories"$ch{stories}> Stories
	<INPUT TYPE="RADIO" NAME="op" VALUE="comments"$ch{comments}> Comments
	<INPUT TYPE="RADIO" NAME="op" VALUE="users"$ch{users}> Users<BR>

EOT

	if ($I{F}{op} eq "stories") {
		my $authors = $I{dbobject}->getDescriptions('authors');
		createSelect('author', $authors, $I{F}{author});
	} elsif ($I{F}{op} eq "comments") {
		print <<EOT;
	Threshold <INPUT TYPE="TEXT" SIZE="3" NAME="threshold" VALUE="$I{F}{threshold}">
	<INPUT TYPE="HIDDEN" NAME="sid" VALUE="$I{F}{sid}">
EOT
	}

	selectSection("section", $I{F}{section}, $SECT)
		unless $I{F}{op} eq "users";
	print "\n<P></FORM>\n\n";
}

#################################################################
sub commentSearch {
	print <<EOT;
<P>This search covers the name, email, subject and contents of
each of the last 30,000 or so comments posted.  Older comments
are removed and currently only visible as static HTML.<P>
EOT
	
	my $prev = $I{F}{min} - $I{F}{max};
	print linkSearch({
		'link'	=> "<B>$I{F}{min} previous matches...</B>",
		min	=> $prev
	}), "<P>" if $prev >= 0;
	
	# select comment ID, comment Title, Author, Email, link to comment
	# and SID, article title, type and a link to the article

	if ($I{F}{sid}) {
		my $title = $I{dbobject}->getNewstoryTitle($I{F}{sid}) || "discussion";

		printf "<B>Return to %s</B><P>", linkComment({
			sid	=> $I{F}{sid},
			pid	=> 0,
			subject	=> $title
		});
		print "</B><P>";
		return unless $I{F}{query};
	}

	my $search = $I{dbobject}->getSearch();
	my $x = $I{F}{min};
	for (@$search) {
		my($section, $sid, $aid, $title, $pid, $subj, $ws, $sdate,
		$cdate, $uid, $cid, $match) = @$_;
		last if $I{F}{query} && !$match;
		$x++;

		my $href = $ws == 10
			? "$I{rootdir}/$section/$sid.shtml#$cid"
			: "$I{rootdir}/comments.pl?sid=$sid&pid=$pid#$cid";

		my $user_email = $I{dbobject}->getUser($uid, 'fakeemail', 'nickname');
		printf <<EOT, $match ? $match : $x;
<BR><B>%s</B>
	<A HREF="$href">$subj</A>
	by <A HREF="mailto:$user_email->{fakeemail}">$user_email->{nickname}</A> on $cdate<BR>
	<FONT SIZE="2">attached to <A HREF="$I{rootdir}/$section/$sid.shtml">$title</A> 
	posted on $sdate by $aid</FONT><BR>
EOT
	}


	print "No Matches Found for your query" if $x < 1;

	my $remaining = "";
	print "<P>", linkSearch({
		'link'	=> "<B>More matches...</B>",
		min	=> $x
	}) unless !$x || $x < $I{F}{max};
}

#################################################################
sub userSearch {
	my $prev = int($I{F}{min}) - $I{F}{max};
	print linkSearch({
		'link'	=> "<B>$I{F}{min} previous matches...</B>",
		min	=> $prev
	}), "<P>" if $prev >=0;

	my($x, $cnt) = 0;

	my $users = $I{dbobject}->getSearchUsers($I{F}, $I{anonymous_coward_uid});
	for (@$users) {
		my($fakeemail, $nickname, $uid) = @$_;
		my $ln = $nickname;
		$ln =~ s/ /+/g;

		my $fake = $fakeemail ? <<EOT : '';
	email: <A HREF="mailto:$fakeemail">$fakeemail</A>
EOT
		print <<EOT;
<A HREF="$I{rootdir}/users.pl?nick=$ln">$nickname</A> &nbsp;
($uid) $fake<BR>
EOT

		$x++;
	}


	print "No Matches Found for your query" if $x < 1;

	print "<P>";
	print linkSearch({
		'link'	=> "<B>More matches...</B>",
		min	=> $I{F}{'last'},
	}) unless !$x || $x < $I{F}{max};
}

#################################################################
sub storySearch {
	my $prev = $I{F}{min} - $I{F}{max};
	print linkSearch({
		'link'	=> "<B>$I{F}{min} previous matches...</B>",
		min	=> $prev
	}), "<P>" if $prev >= 0;

	my($x, $cnt) = 0;
	print " ";

	my $stories = $I{dbobject}->getSearchStory($I{F});
	for (@$stories) {
		my($aid, $title, $sid, $time, $commentcount, $section, $cnt) = @$_;
		last unless $cnt || ! $I{F}{query};
		print $cnt ? $cnt :  $x + $I{F}{min};
		print " ";
		print linkStory({
			section	=> $section,
			sid	=> $sid,
			'link'	=> "<B>$title</B>"
		}), qq! by $aid <FONT SIZE="2">on $time <b>$commentcount</b></FONT><BR>!;
		$x++;
	}


	print "No Matches Found for your query" if $x < 1;

	my $remaining = "";
	print "<P>", linkSearch({
		'link'	=> "<B>More Articles...</B>",
		min	=> $I{F}{'last'}
	}) unless !$x || $x < $I{F}{max};
}

main;
# Don't kick the baby
#$I{dbh}->disconnect if $I{dbh};
1;
