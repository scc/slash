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
use vars '%I';
use Slash;

#################################################################
sub main {
	*I = getSlashConf();
	getSlash();
	my $SECT = getSection();

	header("$I{sitename}: Topics", $SECT->{section});
	print <<EOT;
[	<A HREF="$I{rootdir}/topics.pl?op=toptopics">Recent Topics</A> |
	<A HREF="$I{rootdir}/topics.pl?op=listtopics">List Topics</A> ]
EOT

	if ($I{F}{op} eq "toptopics") {
#		return;
		topTopics($SECT);
	} else {
		listTopics();
	}

	$I{dbobject}->writelog($I{U}{uid}, "topics");
	footer($I{F}{ssi});
}

#################################################################
sub topTopics {
	my ($SECT) = @_;

	titlebar("90%", "Recent Topics");

	my $topics = $I{dbobject}->getTopNewsstoryTopics($I{F}{all});
	my $col=0;
	printf <<EOT;

<TABLE WIDTH="90%" BORDER="0" CELLPADDING="3">
EOT

	for my $topic (@$topics) {
	my ($tid, $alttext, $image, $width, $height, $cnt) = @$_;
		print $I{dbobject}->countStory($tid);
		print <<EOT;

	<TR><TD ALIGN="RIGHT" VALIGN="TOP>
		<FONT SIZE="6" COLOR="$I{bg}[3]">$alttext</FONT>
		<BR>( %s )
		<A HREF="$I{rootdir}/search.pl?topic=$tid"><IMG
			SRC="$I{imagedir}/topics/$image"
			BORDER="0" ALT="$alttext" ALIGN="RIGHT"
			HSPACE="0" VSPACE="10" WIDTH="$width"
			HEIGHT="$height"></A>
	</TD><TD BGCOLOR="$I{bg}[2]" VALIGN="TOP">
EOT

		my $limit = $cnt;
		$limit = 10 if $limit > 10;
		$limit = 3  if $limit < 3 or $I{F}{all};
		$SECT->{issue} = 0;

		my $stories = selectStories($SECT, $limit, $tid);
		print getOlderStories($stories, $SECT);
		$stories->finish;
		print "\n\t</TD></TR>\n";
	} 
	print "</TABLE>\n\n";

	printf <<EOT, scalar localtime;
<BR><FONT SIZE="2"><CENTER>generated on %s</CENTER></FONT><BR>
EOT

	$I{dbobject}->writelog($I{U}{uid}, "topics");
}

#################################################################
sub listTopics {
	titlebar("99%", "Current Topic Categories");
	my $x = 0;

	print qq!\n<TABLE ALIGN="CENTER">\n\t<TR>\n!;

	my $topics = $I{dbobject}->getTopic();
	# Somehow sort by the alttext? Need to return to this -Brian
	for my $topic (%{$topics}) {
		unless ($x++ % 6) {
			print "\t</TR><TR>";
		}

		my $href = $I{U}{aseclev} > 500 ? <<EOT : '';
</A><A HREF="$I{rootdir}/admin.pl?op=topiced&nexttid=$topic->{'tid'}">
EOT

		print <<EOT;
<TD ALIGN="CENTER">
		<A HREF="$I{rootdir}/search.pl?topic=$topic->{'tid'}"><IMG
			SRC="$I{imagedir}/topics/$topic->{'image'}" ALT="$topic->{'alttext'}"
			WIDTH="$topic->{'width'}" HEIGHT="$topic->{'height'}"
			BORDER="0">$href<BR>$topic->{'alttext'}</A>
		</TD>
EOT
	}

	print "\t</TR>\n</TABLE>\n\n";
}

main();
# Don't kick the baby!
#$I{dbh}->disconnect if $I{dbh};
