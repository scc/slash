# This code is a part of Slash, and is released under the GPL.
# Copyright 1997-2001 by Open Source Development Network. See README
# and COPYING for more information, or see http://slashcode.com/.
# $Id$

package Slash::DB::Static::MySQL;
#####################################################################
#
# Note, this is where all of the ugly red headed step children go.
# This does not exist, these are not the methods you are looking for.
#
#####################################################################
use strict;
use Slash::Utility;
use URI ();
use vars qw($VERSION);
use base 'Slash::DB::MySQL';

($VERSION) = ' $Revision$ ' =~ /\$Revision:\s+([^\s]+)/;

# BENDER: Bite my shiny, metal ass!

########################################################
# for slashd
# This method is used in a pretty wasteful way
sub getBackendStories {
	my($self, $section) = @_;

	my $story_table = getCurrentStatic('mysql_heap_table') ? 'story_heap' : 'stories';
	my $cursor = $self->{_dbh}->prepare("SELECT
		$story_table.sid, $story_table.title, time, dept, $story_table.uid,
		alttext,
		image, commentcount, $story_table.section as section,
		story_text.introtext, story_text.bodytext,
		topics.tid as tid
		    FROM $story_table, story_text, topics, discussions
		   WHERE $story_table.sid = story_text.sid
		     AND $story_table.discussion = discussions.id
		     AND $story_table.tid=topics.tid
		     AND ((displaystatus = 0 and \"$section\"=\"\")
			      OR ($story_table.section=\"$section\" and displaystatus > -1))
		     AND time < NOW()
		     AND NOT FIND_IN_SET('delete_me', $story_table.flags)
		ORDER BY time DESC
		   LIMIT 10");

	$cursor->execute;
	my $returnable = [];
	my $row;
	push(@$returnable, $row) while ($row = $cursor->fetchrow_hashref);
	$cursor->finish;

	# XXX Need to stuff hitparade values in here or open_backend.pl
	# will not write its RSS etc. files correctly. - Jamie

	return $returnable;
}

########################################################
# This is only called if ssi is set
# XXX Outdated, delete before tarball release - Jamie 2001/07/08
#sub updateCommentTotals {
#	my($self, $sid, $comments) = @_;
#	my $hp = join ',', @{$comments->[0]{totals}};
#	$self->sqlUpdate("stories", {
#			hitparade	=> $hp,
#			writestatus	=> 0,
#			commentcount	=> $comments->[0]{totals}[0]
#		}, 'sid=' . $self->{_dbh}->quote($sid)
#	);
#	if (getCurrentStatic('mysql_heap_table')) {
#		$self->sqlUpdate("story_heap", {
#				hitparade	=> $hp,
#				writestatus	=> 0,
#				commentcount	=> $comments->[0]{totals}[0]
#			}, 'sid=' . $self->{_dbh}->quote($sid)
#		);
#	}
#}

########################################################
# For slashd
# Does nothing. Back when this was a copy of stories that needed to be
# periodically updated, this did something.
# XXX Outdated, delete before tarball release - Jamie 2001/07/08
#
#sub setStoryIndex {
#	my($self, @sids) = @_;
#
#	my %stories;
#
#	for my $sid (@sids) {
#		$stories{$sid} = $self->sqlSelectHashref("*", "stories", "sid='$sid'");
#	}
#	$self->sqlTransactionStart("LOCK TABLES story_heap WRITE");
#
#	foreach my $sid (keys %stories) {
#		$self->sqlReplace("story_heap", $stories{$sid}, "sid='$sid'");
#	}
#
#	$self->sqlTransactionFinish();
#}

########################################################
# For slashd
# "LIMIT 10" chosen arbitrarily, actually could be LIMIT 5 but doesn't
# hurt much to kick in some more in case the caller has been changed to
# want more.
sub getNewStoryTopic {
	my($self) = @_;

	my $story_table = getCurrentStatic('mysql_heap_table') ? 'story_heap' : 'stories';
	my $sth = $self->sqlSelectMany(
		"alttext, image, width, height, $story_table.tid",
		"$story_table, topics",
		"$story_table.tid=topics.tid AND displaystatus = 0
		AND NOT FIND_IN_SET('delete_me', flags) AND time < NOW()",
		"ORDER BY time DESC LIMIT 10"
	);

	return $sth;
}

########################################################
# For dailystuff
sub archiveComments {
	my($self) = @_;
	my $constants = getCurrentStatic();

	$self->sqlDo("update discussions SET type=2  WHERE to_days(now()) - to_days(ts) > $constants->{discussion_archive} AND type = 0 ");
	# Optimize later to use heap table -Brian
	for($self->sqlSelect('cid', 'comments,discussions', "WHERE to_days(now()) - to_days(date) > $constants->{discussion_archive} AND discussion.id = comments.sid AND discussion.type = 1 AND discussion.pid = 0")) {
		$self->deleteComments('',$_);
	}
}

########################################################
# For dailystuff
sub deleteDaily {
	my($self) = @_;
	my $constants = getCurrentStatic();

	my $delay1 = $constants->{archive_delay} * 2;
	my $delay2 = $constants->{archive_delay} * 9;
	$constants->{defaultsection} ||= 'articles';

# We no longer delete stories or comments that are too old.
#	$self->sqlDo("DELETE FROM newstories WHERE
#			(section='$constants->{defaultsection}' and to_days(now()) - to_days(time) > $delay1)
#			or (to_days(now()) - to_days(time) > $delay2)");
#	$self->sqlDo("DELETE FROM comments where to_days(now()) - to_days(date) > $constants->{archive_delay}");

	# Now for some random stuff
	$self->sqlDo("DELETE from pollvoters");
	$self->sqlDo("DELETE from moderatorlog WHERE
	  to_days(now()) - to_days(ts) > $constants->{archive_delay} ");
	$self->sqlDo("DELETE from metamodlog WHERE
		to_days(now()) - to_days(ts) > $constants->{archive_delay} ");
	# Formkeys
	my $delete_time = time() - $constants->{'formkey_timeframe'};
	$self->sqlDo("DELETE FROM formkeys WHERE ts < $delete_time");
	$self->sqlDo("DELETE FROM accesslog WHERE date_add(ts,interval 48 hour) < now()");
}

########################################################
# For dailystuff
sub countDaily {
	my($self) = @_;
	my %returnable;

	my $constants = getCurrentStatic();

	($returnable{'total'}) = $self->sqlSelect("count(*)", "accesslog",
		"to_days(now()) - to_days(ts)=1");

	my $c = $self->sqlSelectMany("count(*)","accesslog",
		"to_days(now()) - to_days(ts)=1 GROUP BY host_addr");
	$returnable{'unique'} = $c->rows;
	$c->finish;

#	my($comments) = $self->sqlSelect("count(*)","accesslog",
#		"to_days(now()) - to_days(ts)=1 AND op='comments'");

	$c = $self->sqlSelectMany("dat,count(*)","accesslog",
		"to_days(now()) - to_days(ts)=1 AND
		(op='index' OR dat='index')
		GROUP BY dat");

	my(%indexes, %articles, %commentviews);

	while (my($sect, $cnt) = $c->fetchrow) {
		$indexes{$sect} = $cnt;
	}
	$c->finish;

	$c = $self->sqlSelectMany("dat,count(*),op", "accesslog",
		"to_days(now()) - to_days(ts)=1 AND op='article'",
		"GROUP BY dat");

	while (my($sid, $cnt) = $c->fetchrow) {
		$articles{$sid} = $cnt;
	}
	$c->finish;

	# clean the key table


	$c = $self->sqlSelectMany("dat,count(*)", "accesslog",
		"to_days(now()) - to_days(ts)=1 AND op='comments'",
		"GROUP BY dat");
	while (my($sid, $cnt) = $c->fetchrow) {
		$commentviews{$sid} = $cnt;
	}
	$c->finish;

	$returnable{'index'} = \%indexes;
	$returnable{'articles'} = \%articles;


	return \%returnable;
}

########################################################
# For dailystuff
sub updateStamps {
	my($self) = @_;
	my $columns = "uid";
	my $tables = "accesslog";
	my $where = "to_days(now())-to_days(ts)=1 AND uid > 0";
	my $other = "GROUP BY uid";

	my $E = $self->sqlSelectAll($columns, $tables, $where, $other);

	$self->sqlTransactionStart("LOCK TABLES users_info WRITE");

	for (@{$E}) {
		my $uid = $_->[0];
		$self->setUser($uid, {-lastaccess=>'now()'});
	}
	$self->sqlTransactionFinish();
}

########################################################
# For dailystuff
sub getDailyMail {
	my($self) = @_;

	my $story_table = getCurrentStatic('mysql_heap_table') ? 'story_heap' : 'stories';
	my $columns = "$story_table.sid, $story_table.title, $story_table.section,
		users.nickname,
		$story_table.tid, $story_table.time, $story_table.dept,
		story_text.introtext, story_text.bodytext";
	my $tables = "$story_table, story_text, users";
	my $where = "time < NOW() AND TO_DAYS(NOW())-TO_DAYS(time)=1 ";
	$where .= "AND users.uid=$story_table.uid AND $story_table.sid=story_text.sid ";
	$where .= "AND $story_table.displaystatus=0 ";
	my $other = " ORDER BY $story_table.time DESC";

	my $email = $self->sqlSelectAll($columns, $tables, $where, $other);

	return $email;
}

########################################################
# For dailystuff
sub getMailingList {
	my($self) = @_;

	my $columns = "realemail,nickname,users.uid";
	my $tables  = "users,users_comments,users_info";
	my $where   = "users.uid=users_comments.uid AND users.uid=users_info.uid AND maillist=1";
	my $other   = "order by realemail";

	my $users = $self->sqlSelectAll($columns, $tables, $where, $other);

	return $users;
}

########################################################
# For dailystuff
# XXX Outdated, delete before tarball release - Jamie 2001/07/08
#sub getOldStories {
#	my($self, $delay) = @_;
#
#	my $columns = "sid,time,section,title";
#	my $tables = "stories";
#	my $where = "writestatus<5 AND writestatus >= 0 AND to_days(now()) - to_days(time) > $delay";
#
#	my $stories = $self->sqlSelectAll($columns, $tables, $where);
#
#	return $stories;
#}

########################################################
# For portald
sub getTop10Comments {
	my($self) = @_;
	my $story_table = getCurrentStatic('mysql_heap_table') ? 'story_heap' : 'stories';
	my $c = $self->sqlSelectMany("$story_table.sid, title, cid, subject, date, nickname, comments.points",
		"comments, $story_table, users",
		"comments.points >= 4 AND users.uid=comments.uid AND comments.sid=$story_table.sid",
		"ORDER BY date DESC LIMIT 10");

	my $comments = $c->fetchall_arrayref;
	$c->finish;

	formatDate($comments, 4, 4);

	return $comments;
}

########################################################
# For portald
sub randomBlock {
	my($self) = @_;
	my $c = $self->sqlSelectMany("bid,title,url,block",
		"blocks",
		"section='index' AND portal=1 AND ordernum < 0");

	my $A = $c->fetchall_arrayref;
	$c->finish;

	my $R = $A->[rand @$A];
	my($bid, $title, $url, $block) = @$R;

	$self->sqlUpdate("blocks", {
		title	=> "rand($title);",
		url	=> $url
	}, "bid='rand'");

	return $block;

}

########################################################
# For portald
# ugly method name
sub getAccesLogCountTodayAndYestarday {
	my($self) = @_;
	my $c = $self->sqlSelectMany("count(*), to_days(now()) - to_days(ts) as d", "accesslog", "", "GROUP by d order by d asc");

	my($today) = $c->fetchrow;
	my($yesterday) = $c->fetchrow;
	$c->finish;

	return ($today, $yesterday);

}

########################################################
# For portald
sub getSitesRDF {
	my($self) = @_;
	my $columns = "bid,url,rdf,retrieve";
	my $tables = "blocks";
	my $where = "rdf != '' and retrieve=1";
	my $other = "";
	my $rdf = $self->sqlSelectAll($columns, $tables, $where, $other);

	return $rdf;
}

########################################################
# For the sectionblock, which is generated by
# tasks/refresh_sectionblocks.pl in the defaut theme.
sub getSectionInfo {
	my($self) = @_;
	my $story_table = getCurrentStatic('mysql_heap_table') ?
		'story_heap' : 'stories';
	my $sections = $self->sqlSelectAllHashrefArray(
		'section', "sections",
		"isolate=0 and (section != '' and section != 'articles')
		ORDER BY section"
	);

	for (@{$sections}) {
		@{%{$_}}{qw(month day)} =
			$self->{_dbh}->selectrow_array(<<EOT);
SELECT MONTH(time), DAYOFMONTH(time)
FROM $story_table
WHERE section='$_->{section}' AND time < NOW() AND displaystatus > -1
ORDER BY time DESC LIMIT 1
EOT

		$_->{count} =
			$self->{_dbh}->selectrow_array(<<EOT);
SELECT COUNT(*) FROM $story_table
WHERE 	section='$_->{section}' AND
	TO_DAYS(NOW()) - TO_DAYS(time) <= 2 AND time < NOW() AND
	displaystatus > -1
EOT

	}

	return $sections;
}

########################################################
# For moderatord
sub tokens2points {
	my($self) = @_;
	my $constants = getCurrentStatic();
	my @log;
	# rtbl
	my $cursor = $self->sqlSelectMany('uid,tokens,value as rtbl',
		'users_info, users_param',
		"tokens >= $constants->{maxtokens}
		 AND users_param.uid = users_info.uid 
		 AND name='rtbl' AND value=1");
	$self->sqlTransactionStart('LOCK TABLES users READ,
		users_info WRITE, users_comments WRITE');

	# rtbl
	while (my($uid, $tokens, $rtbl) = $cursor->fetchrow) {
		# rtbl
		if ($rtbl) {
			push @log, getData(
				'moderatord_tokennotgrantmsg', { uid => $uid }
			);
		} else {
			push @log, getData(
				'moderatord_tokengrantmsg', { uid => $uid }
			);
		}

		my %userFields = (
			-lastgranted	=> 'now()',
			-tokens		=>
				"tokens*$constants->{token_retention}",
		);
		$userFields{'-points'} =
			($constants->{maxtokens} / $constants->{tokensperpoint})
			if ! $rtbl;
			
		$self->setUser($uid, \%userFields);
	}

	$cursor->finish;

	$cursor = $self->sqlSelectMany('users.uid as uid',
		'users,users_comments,users_info',
		"karma >= 0 AND
		points > $constants->{maxpoints} AND
		seclev < 100 AND
		users.uid=users_comments.uid AND
		users.uid=users_info.uid");
	$self->sqlTransactionFinish();

	$self->sqlTransactionStart("LOCK TABLES users_comments WRITE");
	while (my($uid) = $cursor->fetchrow) {
		$self->sqlUpdate('users_comments', {
			points => $constants->{maxpoints},
		}, "uid=$uid");
	}
	$self->sqlTransactionFinish();

	return \@log;
}

########################################################
# For moderatord
sub stirPool {
	my($self) = @_;
	my $stir = getCurrentStatic('stir');
	my $cursor = $self->sqlSelectMany("points,users.uid as uid",
			"users,users_comments,users_info",
			"users.uid=users_comments.uid AND
			 users.uid=users_info.uid AND
			 seclev = 0 AND
			 points > 0 AND
			 to_days(now())-to_days(lastgranted) > $stir");

	my $revoked = 0;

	$self->sqlTransactionStart("LOCK TABLES users_comments WRITE");

	while (my($p, $u) = $cursor->fetchrow) {
		$revoked += $p;
		$self->sqlUpdate("users_comments", { points => '0' }, "uid=$u");
	}

	$self->sqlTransactionFinish();
	$cursor->finish;

	# We aren't using this for Slashdot, feel free to turn this on if you
	# wish to use it (the proper return value is: $revoked)
	return 0;
}

########################################################
# For moderatord
sub getUserLast {
	my($self) = @_;
	my($totalusers) = $self->sqlSelect("max(uid)", "users_info");

	return $totalusers;
}

########################################################
# For tailslash
sub pagesServed {
	my($self) = @_;
	my $returnable = $self->sqlSelectAll("count(*),ts",
			"accesslog", "1=1",
			"GROUP BY ts ORDER BY ts ASC");

	return $returnable;

}

########################################################
# For tailslash
sub maxAccessLog {
	my($self) = @_;
	my($returnable) = $self->sqlSelect("max(id)", "accesslog");;

	return $returnable;
}

########################################################
# For tailslash
sub getAccessLogInfo {
	my($self, $id) = @_;
	my $returnable = $self->sqlSelectAll("host_addr,uid,op,dat,ts,id",
				"accesslog", "id > $id",
				"ORDER BY ts DESC");
	formatDate($returnable, 4, 4, '%H:%M');
	return $returnable;
}

########################################################
# For moderatord
sub fetchEligibleModerators {
	my($self) = @_;
	my $constants = getCurrentStatic();
	my $eligibleUsers =
		$self->getLastUser() * $constants->{m1_eligible_percentage};

	my $returnable =
		$self->sqlSelectAll("users_info.uid,count(*) as c",
			"users_info,users_prefs, accesslog",
			"users_info.uid < $eligibleUsers
			 AND users_info.uid=accesslog.uid
			 AND users_info.uid=users_prefs.uid
			 AND (op='article' or op='comments')
			 AND willing=1
			 AND karma >= 0
			 GROUP BY users_info.uid
			 HAVING c >= $constants->{m1_eligible_hitcount}
			 ORDER BY c");

	return $returnable;
}

########################################################
# For moderatord
sub updateTokens {
	my($self, $modlist) = @_;

	$self->sqlTransactionStart("LOCK TABLES users_info WRITE");
	for (@{$modlist}) {
		$self->setUser($_, {
			-tokens	=> "tokens+1",
		});
	}
	$self->sqlTransactionFinish();
}

########################################################
# For dailyStuff
# 	This should only be run once per day, if this isn't
#	true, the simple logic below, breaks. This can be
#	fixed by moving the by_days trigger to a date
#	based system as opposed to a counter-based one,
#	or even adding a date component to expiry checks,
#	which might be a better solution.
sub checkUserExpiry {
	my($self) = @_;
	my($ret);

	# Subtract one from number of 'registered days left' for all users.
	$self->sqlTransactionStart("LOCK TABLES users_param WRITE");
	$self->sqlUpdate('users_param', {
		-'value'	=> 'value-1',
	}, "name='expiry_days' AND value >= 0");
	$self->sqlTransactionFinish();

	# Now grab all UIDs that look to be expired, we explicitly exclude
	# authors from this search.
	$ret = $self->sqlSelectAll('distinct uid', 'users_param',
		"(name='expiry_days' OR name='expiry_comm')
		AND value < 0");

	# We only want the list of UIDs that aren't authors and have not already
	# expired. The extra perl code would be completely unavoidable if we had
	# subselects... *sigh*
	my(@returnable) = grep {
		my $user = $self->getUser($_->[0]);
		$_ = $_->[0];
		!($user->{author} || ! $user->{registered});
	} @{$ret};

	return \@returnable;
}

########################################################
# For moderation scripts.
#	This sub returns the mmids of M2 votes
#	that are eligible for processing M1s that are
#	about the age of the archive delay.
#
sub getMetamodIDs {
	my($self) = @_;

	my $constants = getCurrentStatic();

	# The previous code was shite because I let myself get distracted
	# due to a silly logic error. The way to REALLY do this is to wait a
	# day LATER than the life of a discussion. This way, YOU KNOW that 
	# no further M2 records will show up in the database after 
	# reconciliation. 
	#
	# Cliff == B4K4!
	#
	# We could even change the increment to a specific var if someone
	# finds a need to add more "lag time" into the system.
	#					- Cliff 7/12/01
	my $num_days = $constants->{archive_delay} + 1;
	my $list = $self->sqlSelectAll(
		'mmid', 'metamodlog', 
		"TO_DAYS(CURDATE())-TO_DAYS(ts) >= $num_days AND flag=10",
	);
	# Flatten the returned list out to a simple list of mmids.
	my(@returnable) = map { $_ = $_->[0] } @{$list};

	return \@returnable;
}

########################################################
# For moderation scripts.
#	This sub returns the meta-moderation information
#	given the appropriate M2ID (primary
#	key into the metamodlog table).
#
sub getMetaModerations {
	my($self, $mmid) = @_;

	my $mmid_quoted = $self->sqlQuote($mmid);
	my $ret = $self->sqlSelectAllHashref(
		'id','*','metamodlog', "mmid=$mmid_quoted"
	);

	return $ret;
}

########################################################
# for tasks/freshenup.pl
sub setDiscussionHitParade {
	my($self, $discussion_id, $hp) = @_;
	return if !$discussion_id;
	# Clear the hitparade_dirty flag.
	my $rows_changed = $self->sqlUpdate(
		"discussions",
		{ -flags => "flags & -3" }, # works, but depends on SET() order
		"id=$discussion_id AND FIND_IN_SET('hitparade_dirty', flags)"
	);
	if ($rows_changed) {
		# Update the hitparade only if the flag was changed just now.
		# (Guaranteed atomicity is not necessary here;  hitparade is
		# only supposed to be close enough for horseshoes.)
		for my $threshold (sort {$a<=>$b} keys %$hp) {
			# We *should* be able to just sqlUpdate, not Replace,
			# but this doesn't get performed all that much, it's
			# not performance-intensive, and the algorithm fails
			# annoyingly if those rows are absent, so Replace is
			# a good thing IMHO.
			$self->sqlReplace("discussion_hitparade", {
				discussion	=> $discussion_id,	# key
				threshold	=> $threshold,		# key
				count		=> $hp->{$threshold},	# value
			});
		}
	}
}

########################################################
# For moderation scripts. 
#
#
sub updateMMFlag {
	my($self, $id, $val);

	$self->sqlUpdate('metamodlog', {
		-flag => $val,
	}, "id=$id");
}

########################################################
# For moderation scripts. 
#
#
sub clearM2Flag {
	my($self, $id);

	# Note that we only update flags that are in the:
	#	10 - M2 Pending
	# state.
	$self->sqlUpdate('metamodlog', {
		-flag => '0',
	}, "where flag=10 and id=$id");
}

########################################################
# For freshneup.pl
#
#
sub getDiscussionsWithFlag {
	my($self, $flag) = @_;
	my $flag_quoted = $self->sqlQuote($flag);
	my $story_table = getCurrentStatic('mysql_heap_table') ? 'story_heap' : 'stories';
	return $self->sqlSelectAll(
		"id",
		"discussions",
		"FIND_IN_SET($flag_quoted, discussions.flags)",
		# update the stuff at the top of the page first
		"ORDER BY id DESC LIMIT 200",
	);
}

########################################################
# For freshneup.pl
#
#
sub getStoriesWithFlag {
	my($self, $flag) = @_;
	my $flag_quoted = $self->sqlQuote($flag);
	my $story_table = getCurrentStatic('mysql_heap_table') ? 'story_heap' : 'stories';
	return $self->sqlSelectAll(
		"sid, discussion, title, section",
		$story_table,
		"FIND_IN_SET($flag_quoted, flags)",
		# update the stuff at the top of the page first
		"ORDER BY time DESC LIMIT 200",
	);
}

1;

__END__

=head1 NAME

Slash::DB::Static::MySQL - MySQL Interface for Slash

=head1 SYNOPSIS

	use Slash::DB::Static::MySQL;

=head1 DESCRIPTION

No documentation yet. Sue me.

=head1 SEE ALSO

Slash(3), Slash::DB(3).

=cut
