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
use Slash;
use Slash::Display;
use Slash::Utility;

#################################################################
sub main {
	my $form = getCurrentForm();
	my $user = getCurrentUser();
	my $op = getCurrentForm('op');
	my $constants = getCurrentStatic();
	my $dbslash = getCurrentDB();

	header("Meta Moderation");

	my $id = isEligible($user, $dbslash, $constants);
	if (!$id) {
		slashDisplay('metamod-not-eligible', {
			rootdir => $constants->{rootdir},
			sitename => $constants->{sitename},
		});

	} elsif ($op eq "MetaModerate") {
		metaModerate($id, $form, $user, $dbslash, $constants);
	} else {
		displayTheComments($id, $user, $dbslash, $constants);
	}

	writeLog("metamod", $op);
	footer();
}

#################################################################
sub karmaBonus {
	my ($u, $c) = @_;

	my $x = $c->{m2_maxbonus} - $u->{karma};

	return 0 unless $x > 0;
	return 1 if rand($c->{m2_maxbonus}) < $x;
	return 0;
}

#################################################################
sub metaModerate {
	my ($id, $f, $u, $db, $c) = @_;

	my $y = 0;								# Sum of elements from form.
	my (%metamod, @mmids);

	$metamod{unfair} = $metamod{fair} = 0;
	foreach (keys %{$f}) {
		# Meta mod form data can only be a '+' or a '-' so we apply some
		# protection from taint.
		next if $f->{$_} !~ /^[+-]$/; # bad input, bad!
		if (/^mm(\d+)$/) {
			push(@mmids, $1) if $f->{$_};
			$metamod{unfair}++ if $f->{$_} eq '-';
			$metamod{fair}++ if $f->{$_} eq '+';
		}
	}

	my %m2victims;
	foreach (@mmids) {
		if ($y < $c->{m2_comments}) { 
			$y++;
			my $muid = $db->getModeratorLog($_, 'uid');

			$m2victims{$_} = [$muid, $f->{"mm$_"}];
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
	if ($y >= $c->{m2_mincheck}) {
		# Test for excessive number of unfair votes (by percentage)
		# (Ignore M2 & penalize user)
		$flag = 2 if ($metamod{unfair}/$y >= $c->{m2_maxunfair});
		# Test for questionable number of unfair votes (by percentage)
		# (Ignore M2).
		$flag = 1 if (!$flag && ($metamod{unfair}/$y >= $c->{m2_toomanyunfair}));
	}

	my $changes = $db->setMetaMod(\%m2victims, $flag, $ts);

	slashDisplay('metamod-results', {
		changes => $changes,
		count	=> $y,
		rootdir => $c->{rootdir},
		seclev => $u->{seclev},
		metamod => \%metamod,
	});

	$db->setModeratorVotes($u->{uid}, \%metamod) unless $u->{is_anon};

	# Of course, I'm waiting for someone to make the eventual joke...
	my($change, $excon);
	if ($y > $c->{m2_mincheck} && !$u->{is_anon}) {
		if (!$flag && karmaBonus($u, $c)) {
			# Bonus Karma For Helping Out - the idea here, is to not 
			# let meta-moderators get the +1 posting bonus.
			($change, $excon) =
				("karma$c->{m2_bonus}", "and karma<$c->{m2_maxbonus}");
			$change = $c->{m2_maxbonus}
				if $c->{m2_maxbonus} < $u->{karma} + $c->{m2_bonus};

		} elsif ($flag == 2) {
			# Penalty for Abuse
			($change, $excon) = ("karma$c->{m2_penalty}", '');
		}

		# Update karma.
		# This is an abuse
		$db->setUser($u->{uid}, { -karma => "karma$change" }) if $change;
	}
}


#################################################################
sub displayTheComments {
	my ($id, $u, $db, $c) = @_;

	$u->{points} = 0;
	my $comments = $db->getMetamodComments($id, $u->{uid}, $c->{m2_comments});

	slashDisplay('metamod-display', {
		constants 	=> $c,
		comments 	=> $comments,
		user 		=> $u,
	});
}


#################################################################
# This is going to break under replication
sub isEligible {
	my ($u, $db, $c) = @_;

	my $tuid = $db->countUsers();
	my $last = $db->getModeratorLast($u->{uid});

	my $result = slashDisplay('metamod-eligibility-tests', {
		user 		=> $u,
		constants 	=> $c,
		user_count	=> $tuid,
		'last'		=> $last,
	}, 1, 1);

	if ($result ne 'Eligible') {
		print $result;
		return 0;
	}

	# Eligible for M2. Determine M2 comments by selecting random starting
	# point in moderatorlog.
	unless ($last->{'lastmmid'}) {
		$last->{'lastmmid'} = $db->getModeratorLogRandom();
		$db->setUser($u->{uid}, { lastmmid => $last->{'lastmmid'} });
	}

	return $last->{'lastmmid'}; # Hooray!
}

main();

