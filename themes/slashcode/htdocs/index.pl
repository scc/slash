#!/usr/bin/perl -w
###############################################################################
# index.pl - this code displays the index page 
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
# pre stories cache update
use strict;
use vars qw(%I);
use Slash;
use Slash::Utility;
use Slash::DB;

#################################################################
# I really dislike Apache::Registry sometimes. If index.pl
# was a real handler, this would be a lot more fun.
# The lesson learned, is that a little extra time spent making
# $user and $form not global saves on debugging headache like
# global issues.
#
# It might behove us to rewrite Apache::Registry so that it
# passes our variables into the script. Heck, we could combine
# up some of the other logic at the same time (AKA the index
# bits).	-Brian
#################################################################
sub main {
	my $user = getCurrentUser();
	my $form = getCurrentForm();
	*I = getSlashConf();
	getSlash();

	if ($form->{op} eq 'userlogin' && $form->{upasswd} && $form->{unickname}) {
		redirect($ENV{SCRIPT_NAME});
		return;
	}

	# $form->{mode} = $user->{mode}="dynamic" if $ENV{SCRIPT_NAME};

	for ($form->{op}) {
		my $c;
		upBid($form->{bid}), $c++ if /^u$/;
		dnBid($form->{bid}), $c++ if /^d$/;
		rmBid($form->{bid}), $c++ if /^x$/;
		redirect($ENV{SCRIPT_NAME}) if $c;
	}

	my $SECT = getSection($form->{section});
	$SECT->{mainsize} = int($SECT->{artcount} / 3);

	my $title = $SECT->{title};
	$title = "$I{sitename}: $title" unless $SECT->{isolate};
	
	header($title, $SECT->{section});
#	print qq'Have you <A HREF="$I{rootdir}/metamod.pl">Meta Moderated</A> Today?<BR>' if $I{dbobject}->checkForModerator($user);
		
	my $block = getEvalBlock("index");
	my $execme = prepEvalBlock($block);

	eval $execme;

	print "\n<H1>Error while processing 'index' block:$@</H1>\n" if $@;

	footer();

	$I{dbobject}->writelog('index', $form->{section} || 'index') unless $form->{ssi};
}

#################################################################
# Should this method be in the DB library?
sub saveUserBoxes {
	my(@a) = @_;

	my $user = getCurrentUser();
	$user->{exboxes} = @a ? sprintf("'%s'", join "','", @a) : '';
	$I{dbobject}->setUser($user->{uid}, { exboxes => $user->{exboxes} })
		unless $user->{is_anon};
}

#################################################################
sub getUserBoxes {
	my $boxes = getCurrentUser('exboxes');
	$boxes =~ s/'//g;
	return split m/,/, $boxes;
}

#################################################################
sub upBid {
	my($bid) = @_;
	my @a = getUserBoxes();

	if ($a[0] eq $bid) {
		($a[0], $a[@a-1]) = ($a[@a-1], $a[0]);
	} else {
		for (my $x = 1; $x < @a; $x++) {
			($a[$x-1], $a[$x]) = ($a[$x], $a[$x-1]) if $a[$x] eq $bid;
		}
	}

	saveUserBoxes(@a);
}

#################################################################
sub dnBid {
	my($bid) = @_;
	my @a = getUserBoxes();
	if ($a[@a-1] eq $bid) {
		($a[0], $a[@a-1]) = ($a[@a-1], $a[0]);
	} else {
		for(my $x = @a-1; $x > -1; $x--) {
			($a[$x], $a[$x+1]) = ($a[$x+1], $a[$x]) if $a[$x] eq $bid;
		}
	}

	saveUserBoxes(@a);
}

#################################################################
sub rmBid {
	my($bid) = @_;
	my @a = getUserBoxes();
	foreach (my $x = @a; $x >= 0; $x--) {
		splice @a, $x, 1 if $a[$x] eq $bid;
	}
	saveUserBoxes(@a);
}

#################################################################

#################################################################
sub displayStandardBlocks {
	my ($SECT, $olderStuff) = @_;
	my $user = getCurrentUser();
	return if $user->{noboxes};

	my ($boxBank, $sectionBoxes) = $I{dbobject}->getPortalsCommon();

	my $getblocks = $SECT->{section} || 'index';

	my @boxes;
	if ($user->{exboxes} && $getblocks eq 'index') {
		$user->{exboxes} =~ s/'//g;
		@boxes = split m/,/, $user->{exboxes};
	} else {
		@boxes = @{$sectionBoxes->{$getblocks}} if ref $sectionBoxes->{$getblocks};
	}

	for my $bid (@boxes) {
		if ($bid eq 'mysite') {
			print portalbox(
				$I{fancyboxwidth}, "$user->{nickname}'s Slashbox",
				$user->{mylinks} || 'This is your user space.  Love it.',
				$bid
			);
		} elsif ($bid =~ /_more$/) {
			print portalbox($I{fancyboxwidth}, "Older Stuff",
				getOlderStories($olderStuff, $SECT),
				$bid) if $olderStuff;
		} elsif ($bid eq "userlogin" && !$user->{is_anon}) {
			# Don't do nuttin'
		} elsif ($bid eq "userlogin") {
			my $SB = $boxBank->{$bid};
			my $B = eval prepBlock $I{dbobject}->getBlock($bid, 'block');
			#my $B = eval prepBlock $I{blockBank}{$bid};
			print portalbox($I{fancyboxwidth}, $SB->{title}, $B, $SB->{bid}, $SB->{url});
		} else {
			my $SB = $boxBank->{$bid};
			my $B = $I{dbobject}->getBlock($bid, 'block');
			#my $B = $I{blockBank}{$bid};
			print portalbox($I{fancyboxwidth}, $SB->{title}, $B, $SB->{bid}, $SB->{url});
		}
	}
}

#################################################################
# pass it how many, and what.
sub displayStories {
	my $stories_arrayref = shift;
	my($today, $x) = ('', 1);
	my $user = getCurrentUser();
	my $cnt = int($user->{maxstories} / 3);

	for (@{$stories_arrayref}) {
		my($sid, $thissection, $title, $time, $cc, $d, $hp) = @{$_};

		my @threshComments = split m/,/, $hp;

		# Prefix story with section if section != this section and no
		# colon
		my($S) = displayStory($sid, '', 'index');

		my $execme = getEvalBlock('story_link');

		print eval $execme;

		if ($@) {
			print STDERR "<!-- story_link eval failed!\n$@\n-->\n";
		}

		print linkStory({
			'link'	=> "<B>Read More...</B>",
			sid	=> $sid,
			section	=> $thissection
		});

		if ($S->{bodytext} || $cc) {
			print ' | ', linkStory({
				'link'	=> length($S->{bodytext}) . ' bytes in body',
				sid	=> $sid,
				mode	=> 'nocomment'
			}) if $S->{bodytext};

			$cc = $threshComments[0];
			print ' | <B>' if $cc;

			if ($cc && $user->{threshold} > -1
				&& $cc ne $threshComments[$user->{threshold} + 1]) {

				print linkStory({
					sid	  => $sid,
					threshold => $user->{threshold},
					'link'	  => $threshComments[$user->{threshold} + 1]
				});
				print ' of ';
			}

			print linkStory({
				sid		=> $sid, 
				threshold	=> '-1', 
				'link'		=> $cc
			}) if $cc;

			print ' </B>comment', $cc > 1 ? 's' : '' if $cc;

		}

		if ($thissection ne $I{defaultsection} && !getCurrentForm('section')) {
			my($SEC) = getSection($thissection);
			print qq' | <A HREF="$I{rootdir}/$thissection/">$SEC->{title}</A>';
		}
		print qq' | <A HREF="$I{rootdir}/admin.pl?op=edit&sid=$sid">Edit</A>'
			if $user->{aseclev} > 100;

		$execme = getEvalBlock('story_trailer');
		print eval $execme; 

		if ($@) {
			print "<!-- story_trailer eval failed!\n$@\n-->\n";
		}

		my($w) = join ' ', (split m/ /, $time)[0 .. 2];
		$today ||= $w;
#		print "<!-- <$today> <$w> <$x> <$cnt> <$time> -->\n";
		last if ++$x > $cnt && $today ne $w;
	}
}


#################################################################
main();
#################################################################
