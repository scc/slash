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
use Slash;
use Slash::Utility;
use Slash::Search;

#################################################################
sub main {
	my %ops = (
		comments => \&commentSearch,
		users => \&userSearch,
		stories => \&storySearch
	);

	my $constants = getCurrentStatic();
	my $form = getCurrentForm();
	my $slashdb = getCurrentDB();

	# Set some defaults
	$form->{query}		||= '';
	$form->{section}	||= '';
	$form->{min}		||= 0;
	$form->{max}		||= 30;
	$form->{threshold}	||= getCurrentUser('threshold');
	$form->{'last'}		||= $form->{min} + $form->{max};

	# get rid of bad characters
	$form->{query} =~ s/[^A-Z0-9'. ]//gi;

	header("$constants->{sitename}: Search $form->{query}", $form->{section});
	titlebar("99%", "Searching $form->{query}");

	slashDisplay('searchform', {
		section => getSection($form->{section}),
		tref =>$slashdb->getTopic($form->{topic}),
		op => $form->{op} ? $form->{op} : 'stories',
		authors => ($form->{op} eq 'stories') ? _authors() : '',
	});
	searchForm($form);

	if($ops{$form->{op}}) {
		$ops{$form->{op}}->($form);
	} 

	writeLog("search", $form->{query})
		if $form->{op} =~ /^(?:comments|stories|users)$/;
	footer();	
}


#################################################################
# Ugly isn't it?
sub _authors {
	my $slashdb = getCurrentDB();
	my $authors = $slashdb->getDescriptions('authors');
	$authors->{''} = 'All Authors';

	return $authors;
}
#################################################################
sub searchForm {
	my ($form) = @_;
	my $slashdb = getCurrentDB();
	my $constants = getCurrentStatic();

	my $SECT = getSection($form->{section});

	my $t = lc $constants->{sitename};
	$t = $form->{topic} if $form->{topic};
	my $tref = $slashdb->getTopic($t);
	print <<EOT if $tref;

<IMG SRC="$constants->{imagedir}/topics/$tref->{image}"
	ALIGN="RIGHT" BORDER="0" ALT="$tref->{alttext}"
	HSPACE="30" VSPACE="10" WIDTH="$tref->{width}"
	HEIGHT="$tref->{height}">

EOT

	print <<EOT;
<FORM ACTION="$ENV{SCRIPT_NAME}" METHOD="GET">
	<INPUT TYPE="TEXT" NAME="query" VALUE="$form->{query}">
	<INPUT TYPE="SUBMIT" VALUE="Search">
EOT

	$form->{op} ||= "stories";
	my %ch;
	$ch{$form->{op}} = $form->{op} ? ' CHECKED' : '';

	print <<EOT;
	<INPUT TYPE="RADIO" NAME="op" VALUE="stories"$ch{stories}> Stories
	<INPUT TYPE="RADIO" NAME="op" VALUE="comments"$ch{comments}> Comments
	<INPUT TYPE="RADIO" NAME="op" VALUE="users"$ch{users}> Users<BR>

EOT

	if ($form->{op} eq "stories") {
		my $authors = $slashdb->getDescriptions('authors');
		#Kinda hate this aye? -- Brian
		# Well, this used to be in the authors table, which
		# is now defunct.  -- pudge
		$authors->{''} = 'All Authors';
		createSelect('author', $authors, $form->{author});
	} elsif ($form->{op} eq "comments") {
		print <<EOT;
	Threshold <INPUT TYPE="TEXT" SIZE="3" NAME="threshold" VALUE="$form->{threshold}">
	<INPUT TYPE="HIDDEN" NAME="sid" VALUE="$form->{sid}">
EOT
	}

	selectSection("section", $form->{section}, $SECT)
		unless $form->{op} eq "users";
	print "\n<P></FORM>\n\n";
}

#################################################################
sub linkSearch {
	my $form = getCurrentForm();
	my $C = shift;
	my $r;

	foreach (qw[threshold query min author op sid topic section total hitcount]) {
		my $x = "";
		$x =  $C->{$_} if defined $C->{$_};
		$x =  $form->{$_} if defined $form->{$_} && $x eq "";
		$x =~ s/ /+/g;
		$r .= "$_=$x&" unless $x eq "";
	}
	$r =~ s/&$//;

	$r = qq!<A HREF="$ENV{SCRIPT_NAME}?$r">$C->{'link'}</A>!;
}


#################################################################
sub commentSearch {
	my ($form) = @_;
	my $slashdb = getCurrentDB();
	my $constants = getCurrentStatic();
	my $searchDB = Slash::Search->new(getCurrentSlashUser());

	print <<EOT;
<P>This search covers the name, email, subject and contents of
each of the last 30,000 or so comments posted.  Older comments
are removed and currently only visible as static HTML.<P>
EOT
	
	my $prev = $form->{min} - $form->{max};
	print linkSearch({
		'link'	=> "<B>$form->{min} previous matches...</B>",
		min	=> $prev
	}), "<P>" if $prev >= 0;
	
	# select comment ID, comment Title, Author, Email, link to comment
	# and SID, article title, type and a link to the article

	if ($form->{sid}) {
		my $title = $slashdb->getNewstory($form->{sid}, 'title') || "discussion";

		printf "<B>Return to %s</B><P>", linkComment({
			sid	=> $form->{sid},
			pid	=> 0,
			subject	=> $title
		});
		print "</B><P>";
		return unless $form->{query};
	}

	my $search = $searchDB->findComments($form);
	my $x = $form->{min};
	for (@$search) {
		my($section, $sid, $aid, $title, $pid, $subj, $ws, $sdate,
		$cdate, $uid, $cid, $match) = @$_;
		last if $form->{query} && !$match;
		$x++;

		my $href = $ws == 10
			? "$constants->{rootdir}/$section/$sid.shtml#$cid"
			: "$constants->{rootdir}/comments.pl?sid=$sid&pid=$pid#$cid";

		my $user_email = $slashdb->getUser($uid, ['fakeemail', 'nickname']);
		my $match_p = $match ? $match : $x;
		print <<EOT;
<BR><B>$match_p</B>
	<A HREF="$href">$subj</A>
	by <A HREF="mailto:$user_email->{fakeemail}">$user_email->{nickname}</A> on $cdate<BR>
	<FONT SIZE="2">attached to <A HREF="$constants->{rootdir}/$section/$sid.shtml">$title</A> 
	posted on $sdate by $aid</FONT><BR>
EOT
	}


	print "No Matches Found for your query" if $x < 1;

	my $remaining = "";
	print "<P>", linkSearch({
		'link'	=> "<B>More matches...</B>",
		min	=> $x
	}) unless !$x || $x < $form->{max};
}

#################################################################
sub userSearch {
	my ($form) = @_;
	my $constants = getCurrentStatic();
	my $searchDB = Slash::Search->new(getCurrentSlashUser());

	my $prev = int($form->{min}) - $form->{max};
	print linkSearch({
		'link'	=> "<B>$form->{min} previous matches...</B>",
		min	=> $prev
	}), "<P>" if $prev >=0;

	my($x, $cnt) = 0;

	my $users = $searchDB->findUsers($form, [getCurrentAnonymousCoward('nickname')]);
	for (@$users) {
		my($fakeemail, $nickname, $uid) = @$_;
		my $ln = $nickname;
		$ln =~ s/ /+/g;

		my $fake = '';
		$fake = qq|email: <A HREF="mailto:$fakeemail">$fakeemail</A>| if $fakeemail;
		print qq| <A HREF="$constants->{rootdir}/users.pl?nick=$ln">$nickname</A> &nbsp; |;
		print qq| ($uid) $fake<BR> |;
		$x++;
	}
	print "No Matches Found for your query" if $x < 1;

	print "<P>";
	print linkSearch({
		'link'	=> "<B>More matches...</B>",
		min	=> $form->{'last'},
	}) unless !$x || $x < $form->{max};
}

#################################################################
sub storySearch {
	my ($form) = @_;
	my $searchDB = Slash::Search->new(getCurrentSlashUser());

	my $prev = $form->{min} - $form->{max};
	print linkSearch({
		'link'	=> "<B>$form->{min} previous matches...</B>",
		min	=> $prev
	}), "<P>" if $prev >= 0;

	my($x, $cnt) = 0;
	print " ";

	my $stories = $searchDB->findStory($form);
	for (@$stories) {
		my($aid, $title, $sid, $time, $commentcount, $section, $cnt) = @$_;
		last unless $cnt || ! $form->{query};
		print $cnt ? $cnt :  $x + $form->{min};
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
		min	=> $form->{'last'}
	}) unless !$x || $x < $form->{max};
}

#################################################################
createEnvironment();
main();

1;
