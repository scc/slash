#!/usr/bin/perl -w

use strict;
my $me = 'run_moderatord.pl';

use Slash::DB;
use Slash::Utility;

use vars qw( %task );

$task{$me}{timespec} = '15 0-23/2 * * *';
$task{$me}{code} = sub {

	my($virtual_user, $constants, $slashdb, $user) = @_;

	slashdLog("$me begin");
	if (! $constants->{allow_moderation}) {
		slashdLog(<<EOT);
$me - Moderation system is inactive. No action performed.
EOT

	} else {
		# This will soon call a local sub that performs all necessary
		# moderation actions.
		my $moderatord = "$constants->{sbindir}/moderatord";
		if (-e $moderatord and -x _) {
			system("$moderatord $virtual_user");
		} else {
			slashdLog(<<EOT);
$me cannot find $moderatord or not executable
EOT

		}
		reconcileM2($constants, $slashdb);
	}
	slashdLog("$me end");

};


sub reconcileM2 {
	my($constants, $slashdb) = @_;

	for ($slashdb->getM2QuorumIDs()) {
		my $m2_list = $slashdb->getMetaModerations($_);
		my %m2_votes;

		map { $m2_votes{$_->{val}}++; } @{$m2_list};

		# %m2_votes now holds the tally. Which ever value is the
		# highest is the consensus.
		my @rank = sort {
			$m2_votes{$a} <=> $m2_votes{$b}
		} keys $m2_votes;
		my($con, $dis) = @{%m2_votes}{@rank};

		# Try to penalize suspicious M2 behavior.
		if ( $dis &&
		   (($dis/($cons+$dis)) < $constants->{m2_minority_trigger}) )
		{
			for (@{$m2_list}) {
				next if $_->{val} == $rank[0];

				# Penalty cost is the dissention cost per head
				# of each dissenter.
				my $penalty = int(
					($con/$dis) *
					$constants->{m2_dissention_penalty}
				);

				setUser($_->{uid}, {
					-karma => "karma-$penalty",
				});

				# Also flag these specific M2 instances as
				# suspect for later analysis.
			}
		}

		# Reward all


	}
}

1;

