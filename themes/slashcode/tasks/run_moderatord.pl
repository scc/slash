#!/usr/bin/perl -w

use strict;
my $me = 'run_moderatord.pl';

use Slash::DB;
use Slash::Utility;

use constant MSG_CODE_M2 => 2;

use vars qw( %task );

$task{$me}{timespec} = '18 0-23/2 * * *';
$task{$me}{code} = sub {

	my($virtual_user, $constants, $slashdb, $user) = @_;

	if (! $constants->{allow_moderation}) {
		slashdLog(<<EOT);
$me - moderation system is inactive, no action performed
EOT

	} else {
		# This will soon call a local sub that performs all necessary
		# moderation actions.
		my $moderatord = "$constants->{sbindir}/moderatord";
		if (-e $moderatord and -x _) {
			system("$moderatord $virtual_user");
		} else {
			slashdLog(<<EOT);
$me - cannot find $moderatord or not executable
EOT

		}
		reconcileM2($constants, $slashdb);
	}
};


sub reconcileM2 {
	my($constants, $slashdb) = @_;
	# We load the optional plugin object here, so we save a few cycles, 
	# rather than loading it constantly in a lower scope.
	my $messages;
	#my $messages = getObject('Slash::Messages');

	my $m2ids = $slashdb->getMetamodIDs();
	slashdLog(
		sprintf "$me - Iterating from %ld to %ld in lots of (%d)",
			$m2ids->[0], $m2ids->[-1], $constants->{m2_batchsize}
	);
	for my $m2id (@{$m2ids}) {
		my $m2_list = $slashdb->getMetaModerations($m2id);
		my %m2_votes;
		my(@con, @dis);

		map { $m2_votes{$_->{val}}++; } @{$m2_list};

		# %m2_votes now holds the tally. Which ever value is the
		# highest is the consensus.
		my @rank = sort { 
			$m2_votes{$a} <=> $m2_votes{$b}
		} keys %m2_votes;
		# Prevent errors due to undef'd value.
		map { $m2_votes{$_} ||= 0 } @rank;
		my($con, $dis) = @{%m2_votes}{@rank};
		next if $con+$dis == 0;
		my($con_avg, $dis_avg) = ($con/($con+$dis), $dis/($con+$dis));

		# Now organize list of consenters/dissenters by UID.
		for (@{$m2_list}) {
			# We only need a list of UIDs for consentors.
			push @con, $_->{uid} if $_->{val} eq $rank[0];
			# For each dissentor, we need UID and ID pairs.
			push @dis, [$_->{uid}, $_->{id}]
				if $_->{val} eq $rank[1];
		}

		# Try to penalize suspicious M2 behavior.
		if ($dis && $dis_avg < $constants->{m2_minority_trigger}) {
			# Penalty cost is the dissension cost per head
			# of each dissenter.
			my $penalty = int(
				($con/$dis) *
				$constants->{m2_dissension_penalty}
			);
			for (@dis) {
				$slashdb->setUser($_->[0], {
					-karma => "karma-$penalty",
				});

				# Also flag these specific M2 instances as 
				# suspect for later analysis.
				#
				# Note use of naked '8' to identify
				# penalized users at-a-glance.
				$slashdb->updateM2Flag($_->[1], 8);
			}
		}
		
		slashdLog(sprintf <<EOT, $con, $con_avg, $dis,$dis_avg);
$me - $m2id: CON=%d (%6.4f) DIS=%d (%6.4f)
EOT

		# Dole out reward among the consensus if there is a clear
		# victory. Note that a user only gets the optional message
		# if we have a clear victory.
		if ($con_avg > $constants->{m2_consensus_trigger}) {
			my %slots;
			my $pool = $constants->{m2_reward_pool};

			# Randomly distribute points from among the
			# consensus.
			$pool = 0 if $pool < 0;
			while ($pool--) { $slots{$con[rand @con]}++; }

			for (keys %slots) {
				# No user gets more than one point from the
				# pool as a default, if you want a random
				# distribution across users, uncomment
				# the first line and comment out the second.
				$slashdb->setUser($_, {
					# Uncomment only one of these at a time!
					#-karma => "karma+$slots{$_}",
					-karma => "karma+1",
				});
			}

			# Award moderator if moderation matches consensus.
			my $modlog =
				$slashdb->getModeratorLog($m2_list->[0]{mmid});
			if ($modlog->{val} eq $rank[0]) {
				my $mod_karma =
					$slashdb->getUser($m2_list->[0]{uid}, 'karma');
				$slashdb->setUser($m2_list->[0]{uid}, {
					karma => $mod_karma + 1,
				});
			}

			# Optional: Send message to original moderator 
			# indicating results of metamoderation.
			if ($messages) {
				# Why is there no $slashdb->getComment($cid)?
				# doesn't seem it is needed -- pudge
				my $comment = $slashdb->getComments(
					$modlog->{sid}, $modlog->{cid}
				);

				# Unfortunately, the template must be aware
				# of the valid states of $modlog->{val}, but
				# for default Slashcode (and Slashdot), this
				# isn't a problem.
				my $data = {
					template_name	=> 'msg_m2',
					subject		=> {
						template_name	=>
							'msg_m2_subj',
					},
					m2		=> {
						c_subj	=> $comment->{subj},
						m1_vote	=> $modlog->{val},
					},
				};
				
				$messages->create(
					$modlog->{uid}, MSG_CODE_M2, $data
				);
			}
		}

		# Mark remaining entries with a '0' which means that they have
		# been processed.
		#$slashdb->clearM2Flag($m2id);
	}
	slashdLog(<<EOT) if scalar @{$m2ids};
$me - Metamoderation processed @{[scalar @{$m2ids}]} discussions.
EOT

}

1;
