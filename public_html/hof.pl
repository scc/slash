#!/usr/bin/perl -w

###############################################################################
# hof.pl - this page displays statistics about stories posted to the site 
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
	my $SECT=getSection($I{F}{section});

	header("$I{sitename}: Hall of Fame", $SECT->{section});

	my $storyDisp = sub { <<EOT };
<B><FONT SIZE=4>$_[3]</FONT></B>
<A HREF="$I{rootdir}/$_[2]/$_[0].shtml">$_[1]</A> by $_[4]<BR>
EOT

	# Top 10 Hit Generating Articles
	titlebar("98%", "Most Active Stories");
	displayCursor($storyDisp, $I{dbobject}->countStories());

	print "<P>";
	titlebar("98%", "Most Visited Stories");
	displayCursor($storyDisp, $I{dbobject}->countStoriesStuff());
	
	print "<P>";
	titlebar("98%", "Most Active Authors");
	displayCursor(sub { qq!<B>$_[0]</B> <A HREF="$_[2]">$_[1]</A><BR>! },
		$I{dbobject}->countStoriesAuthors());

	print "<P>";
	titlebar("98%", "Most Active Poll Topics");
	displayCursor(sub { qq!<B>$_[0]</B> <A HREF="$I{rootdir}/pollBooth.pl?qid=$_[2]">$_[1]</A><BR>! }, $I{dbobject}->countPollquestions());

	if (0) {  #  only do this in static mode
		print "<P>";
		titlebar("100%", "Most Popular Slashboxes");
		my $boxes = $I{dbobject}->getDescription('sectionblocks');
		my(%b, %titles);

		while (my($bid, $title) = each %$boxes) {
			$b{$bid} = 1;
			$titles{$bid} = $title;
		}


		#Something tells me we could simplify this with some 
		# thought -Brian
		foreach my $bid (keys %b) {
			$b{$bid} = $I{dbobject}->countUsersIndexExboxesByBid($bid);
		}

		my $x;
		foreach my $bid (sort { $b{$b} <=> $b{$a} } keys %b) {
			$x++;
			$titles{$bid} =~ s/<(.*?)>//g;
			print <<EOT;

<B>$b{$bid}</B> <A HREF="$I{rootdir}/users.pl?op=preview&bid=$bid">$titles{$bid}</A><BR>
EOT
			last if $x > 10;
		}
	}

	topComments();

	printf <<EOT, scalar localtime;
<BR><FONT SIZE="2"><CENTER>generated on %s</CENTER></FONT><BR>
EOT

	$I{dbobject}->writelog("hof");
	footer($I{F}{ssi});
}

##################################################################
sub displayCursor {
	my($d, $c) = @_;
	return unless $c;
	for (@$c) {
		print $d->(@$_);
	}
}

##################################################################
sub topComments {
	# and SID, article title, type and a link to the article
	print "<P>";
	titlebar("100%","Top 10 Comments");
	my $story_comments = $I{dbobject}->getCommentsTop($I{F}{sid},$I{U});

	my $x = $I{F}{min};
	for(@$story_comments) {
		my($section, $sid, $aid, $title, $pid, $subj, $cdate, $sdate,
				$uid, $cid, $score) = @$_;
		my $user_email = $I{dbobject}->getUser($uid, 'fakeemail', 'nickname');
	
		print <<EOT;
<BR><B>$score</B>
	<A HREF="$I{rootdir}/comments.pl?sid=$sid&pid=$pid#$cid">$subj</A>
	by <A HREF="mailto:$user_email->{fakeemail}">$user_email->{nickname}</A> on $cdate<BR>

	<FONT SIZE="2">attached to <A HREF="$I{rootdir}/$section/$sid.shtml">$title</A>
	posted on $sdate by $aid</FONT><BR>
EOT

	}

}

main();
#Don't kick the baby
#$I{dbh}->disconnect if $I{dbh};
