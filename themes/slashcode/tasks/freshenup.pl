#!/usr/bin/perl -w

use File::Path;

use strict;
my $me = 'freshenup.pl';

use vars qw( %task );

my $total_freshens = 0;

$task{$me}{timespec} = '4-59/5 * * * *';
$task{$me}{code} = sub {

	my($virtual_user, $constants, $slashdb, $user) = @_;

	my $bd = $constants->{basedir}; # convenience
	my $start_total_freshens = $total_freshens;
	my %updates;

	warn "user not anon!" if !$user->{is_anon};

	my($min, $max) = ($constants->{comment_minscore}, $constants->{comment_maxscore});
        my $num_scores = $max-$min+1;

	# Mark discussions with new comment data as needing to be freshened.
	my $discussions = getDiscussionsWithFlag($slashdb, "hitparade_dirty");
	my $start_time = time;
	for my $id_ary (@$discussions) {
		# @$discussions is an array of arrays, annoyingly.
		my($discussion_id) = @$id_ary;
		# Don't do too many at once.
		last if time > $start_time+30;
		my($comments, $count) = Slash::selectComments($discussion_id, 0);
		my $hp = { };
                for my $score (0 .. $num_scores-1) {
                        $hp->{$score + $min} = $comments->[0]{natural_totals}[$score];
                }
		# This will clear the flag, too.
                $slashdb->setDiscussionHitParade($discussion_id, $hp);
		# Take a pause so we don't load the DB too much.
		sleep 1;
		++$total_freshens;
	}

	# Mark stories with new data as needing to be freshened.
	my $stories = getStoriesWithFlag($slashdb, "data_dirty");
	for my $info_ary (@$stories) {
		my($sid, $discussion_id, $title, $section) = @$info_ary;
		next unless $sid;	# XXX for now, skip poll/journal discussions since we don't know how to write their hitparades in yet
		# For each story, we need to update its section...
		$updates{section}{$section} = 1;
		# ...and the story itself.  We don't update it yet
		# because if it turns out we're deleting it (below),
		# there's no need.
		$updates{story}{$sid} = [@$info_ary];
	}

	# Delete stories marked as needing such
	$stories = getStoriesWithFlag($slashdb, "delete_me");
	for my $info_ary (@$stories) {
		my($sid, $discussion_id, $title, $section) = @$info_ary;
		$slashdb->finalDeleteStory($sid);
		# Section needs to be updated.
		$updates{section}{$section} = 1;
		# But the story does not.
		delete $updates{story}{$sid};
		slashdLog("$me deleted $sid ($title)");
		++$total_freshens;
	}

	# Freshen changed stories (that haven't been deleted)
	for my $sid (sort keys %{$updates{story}}) {
		my($sid, $discussion_id, $title, $section) = @{$updates{story}{$sid}};
		if ($section) {
			makeDir($bd, $section, $sid);
			prog2file("$bd/article.pl",
				"ssi=yes sid='$sid' section='$section'",
				"$bd/$section/$sid.shtml");
			slashdLog("$me updated $section:$sid ($title)");
		} else {
			prog2file("$bd/article.pl",
				"ssi=yes sid='$sid'",
				"$bd/$sid.shtml");
			slashdLog("$me updated $sid ($title)");
		}
		++$total_freshens;
	}

	# index.shtml just gets written every 5 minutes, rain or shine.
	prog2file("$bd/index.pl", "ssi=yes", "$bd/index.shtml");
	++$total_freshens;

	for my $key (keys %{$updates{section}}) {
		next unless $key;
		prog2file("$bd/index.pl", "ssi=yes section=$key", "$bd/$key/index.shtml");
		++$total_freshens;
	}

	slashdLog("$me total_freshens $total_freshens")
		if $total_freshens != $start_total_freshens;

};

sub makeDir {
	my($bd, $section, $sid) = @_;

	my $monthid = substr($sid, 3, 2);
	my $yearid = substr($sid, 0, 2);
	my $dayid = substr($sid, 6, 2);

	mkpath "$bd/$section/$yearid/$monthid/$dayid", 0, 0755;
}

sub getDiscussionsWithFlag {
	my($slashdb, $flag) = @_;
	my $flag_quoted = $slashdb->sqlQuote($flag);
	my $story_table = getCurrentStatic('mysql_heap_table') ? 'story_heap' : 'stories';
	return $slashdb->sqlSelectAll(
		"id",
		"discussions",
		"FIND_IN_SET($flag_quoted, discussions.flags)",
		# update the stuff at the top of the page first
		"ORDER BY id DESC LIMIT 100",
	);
}

sub getStoriesWithFlag {
	my($slashdb, $flag) = @_;
	my $flag_quoted = $slashdb->sqlQuote($flag);
	my $story_table = getCurrentStatic('mysql_heap_table') ? 'story_heap' : 'stories';
	return $slashdb->sqlSelectAll(
		"sid, discussion, title, section",
		$story_table,
		"FIND_IN_SET($flag_quoted, flags)",
		# update the stuff at the top of the page first
		"ORDER BY time DESC LIMIT 100",
	);
}

1;

