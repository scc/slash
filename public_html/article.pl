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
use vars '%I';
use Slash;
use Slash::DB;
use Slash::Utility;

##################################################################
sub main {
	*I = getSlashConf();
	getSlash();

	if ($I{F}{refresh}) {
		$I{dbobject}->refreshStories($I{F}{sid});
		# won't work now because HTTP headers not printed until header() below
		# print qq[<FONT COLOR="white" SIZE="${\( $I{fontbase} + 5 )}">How Refreshing! ($I{F}{sid}) </FONT>\n];
	}

	my($sect, $title, $ws);

	# Worst case condition here is that the first lookup will cause
	# a hit to the database. -Brian
	$sect	= $I{dbobject}->getStory($I{F}{sid}, 'section');
	$title	= $I{dbobject}->getStory($I{F}{sid}, 'title');
	$ws	= $I{dbobject}->getStory($I{F}{sid}, 'writestatus');

	if ($ws == 10) {
		$ENV{SCRIPT_NAME} = '';
		redirect("$I{rootdir}/$sect/$I{F}{sid}$I{userMode}.shtml");
		return;
	};

	my $SECT = getSection($sect);
	$title = $SECT->{isolate} ? "$SECT->{title} | $title" : "$I{sitename} | $title";
	header($title, $sect);

	my($S, $A, $T) = displayStory($I{F}{sid}, 'Full');

	print "<P>";
	articleMenu($S, $SECT);
#	print qq!</TD><TD VALIGN="TOP">\n!;
	print qq!</TD><TD>&nbsp;</TD><TD VALIGN="TOP">\n!;

	yourArticle($S);

	# Poll Booth
	pollbooth($I{F}{sid}) if $I{dbobject}->getPollQuestion($S->{sid});

	# Related Links
	fancybox($I{fancyboxwidth}, 'Related Links', $S->{relatedtext});

	# Display this section's Section Block (if Found)
	fancybox($I{fancyboxwidth}, $SECT->{title},
		$I{dbobject}->getBlock($SECT->{section}, 'block'));

	print qq!</TD></TR><TR><TD COLSPAN="3">\n!;

	printComments($I{F}{sid});
	$I{dbobject}->writelog($SECT->{section}, $I{F}{sid}) unless $I{F}{ssi};
	footer();
}


##################################################################
sub pleaseLogin {
	return unless getCurrentUser('is_anon');
	my $block = eval prepBlock $I{dbobject}->getBlock('userlogin', 'block');
	$block =~ s/index\.pl/article.pl?sid=$I{F}{sid}/;
	$block =~ s/\$I{rootdir}/$I{rootdir}/g;
	fancybox($I{fancyboxwidth}, "$I{sitename} Login", $block);
}

##################################################################
sub yourArticle {
	if (isAnon($I{U}{uid})) {
		pleaseLogin();
		return;
	}

	my $S = shift;
	my $m = qq![ <A HREF="$I{rootdir}/users.pl?op=preferences">Preferences</A> !;
	$m .= qq! | <A HREF="$I{rootdir}/admin.pl">Admin</A> |! .
		qq! <A HREF="$I{rootdir}/admin.pl?op=edit&sid=$S->{sid}">Editor</A> !
		if $I{U}{aseclev} > 99 and $I{U}{aid};
	$m .= " ]<P>\n";

	$m .= <<EOT if $I{U}{points} or $I{U}{aseclev} > 99;

<A HREF="$I{rootdir}/users.pl">You</A> have moderator access and 
<B>$I{U}{points}</B> points.  Welcome to the those of you
just joining: <B>please</B> read the
<A HREF="$I{rootdir}/moderation.shtml">moderator guidelines</A>
for instructions. (<B>updated 9.9!</B>)

<P>

<LI>You can't post & moderate the same discussion.
<LI>Concentrate on Promoting more than Demoting.
<LI>Browse at -1 to keep an eye out for abuses.
<LI><A HREF="mailto:$I{adminmail}">Mail admin</A> URLs showing abuse (the cid link please!).

EOT

	$m .= "<P> $I{U}{mylinks} ";

	fancybox($I{fancyboxwidth}, $I{U}{aid} || $I{U}{nickname}, $m);
}

##################################################################
sub articleMenu {
	my($story, $SECT) = @_;

	my $front  = nextStory('<', $story, $SECT);
	print " &lt;&nbsp; $front" if $front;

	my $n = nextStory('>', $story, $SECT);
	print " | $n &nbsp;&gt; " if $n;

	print ' <P>&nbsp;';
}

##################################################################
sub nextStory {
	my($sign, $story, $SECT) = @_;

	# Slightly less efficient then the way it had worked, but
	# a heck of a lot easier to understand
	if (my $next = $I{dbobject}->getStoryByTime($sign, $story, $SECT->{isolate})) {
		return if ($next->{title} eq  $story->{title});
		return linkStory({ 'link' => $next->{'title'}, sid => $next->{'sid'}, section => $next->{'section'} });
	}
}

main();
1;
