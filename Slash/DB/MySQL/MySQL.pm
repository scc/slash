package Slash::DB::MySQL;
use strict;
use Slash::DB::Utility;
use Slash::Utility;
use URI ();

@Slash::DB::MySQL::ISA = qw( Slash::DB::Utility );
($Slash::DB::MySQL::VERSION) = ' $Revision$ ' =~ /\$Revision:\s+([^\s]+)/;

# BENDER: I hate people who love me.  And they hate me.

# For the getDecriptions() method
my %descriptions = (
	'sortcodes'
		=> sub { $_[0]->sqlSelectMany('code,name', 'code_param', "type='$_[1]'") },

	'default'
		=> sub { $_[0]->sqlSelectMany('code,name', 'code_param', "type='$_[1]'") },

	'statuscodes'
		=> sub { $_[0]->sqlSelectMany('code,name', 'code_param', "type='statuscodes'") },

	'tzcodes'
		=> sub { $_[0]->sqlSelectMany('tz,offset', 'tzcodes') },

	'tzdescription'
		=> sub { $_[0]->sqlSelectMany('tz,description', 'tzcodes') },

	'dateformats'
		=> sub { $_[0]->sqlSelectMany('id,description', 'dateformats') },

	'datecodes'
		=> sub { $_[0]->sqlSelectMany('id,format', 'dateformats') },

	'commentmodes'
		=> sub { $_[0]->sqlSelectMany('mode,name', 'commentmodes') },

	'threshcodes'
		=> sub { $_[0]->sqlSelectMany('code,name', 'code_param', "type='threshcodes'") },

	'postmodes'
		=> sub { $_[0]->sqlSelectMany('code,name', 'code_param', "type='postmodes'") },

	'isolatemodes'
		=> sub { $_[0]->sqlSelectMany('code,name', 'code_param', "type='isolatemodes'") },

	'issuemodes'
		=> sub { $_[0]->sqlSelectMany('code,name', 'code_param', "type='issuemodes'") },

	'vars'
		=> sub { $_[0]->sqlSelectMany('name,name', 'vars') },

	'topics'
		=> sub { $_[0]->sqlSelectMany('tid,alttext', 'topics') },

	'maillist'
		=> sub { $_[0]->sqlSelectMany('code,name', 'code_param', "type='maillist'") },

	'session_login'
		=> sub { $_[0]->sqlSelectMany('code,name', 'code_param', "type='session_login'") },

	'displaycodes'
		=> sub { $_[0]->sqlSelectMany('code,name', 'code_param', "type='displaycodes'") },

	'commentcodes'
		=> sub { $_[0]->sqlSelectMany('code,name', 'code_param', "type='commentcodes'") },

	'sections'
		=> sub { $_[0]->sqlSelectMany('section,title', 'sections', 'isolate=0', 'order by title') },

	'static_block'
		=> sub { $_[0]->sqlSelectMany('bid,bid', 'blocks', "$_[2] >= seclev AND type != 'portald'") },

	'portald_block'
		=> sub { $_[0]->sqlSelectMany('bid,bid', 'blocks', "$_[2] >= seclev AND type = 'portald'") },

	'color_block'
		=> sub { $_[0]->sqlSelectMany('bid,bid', 'blocks', "type = 'color'") },

	'authors'
		=> sub { $_[0]->sqlSelectMany('uid,nickname', 'users', 'seclev >= 99') },

	'users'
		=> sub { $_[0]->sqlSelectMany('uid,nickname', 'users') },

	'templates'
		=> sub { $_[0]->sqlSelectMany('tpid,tpid', 'templates') },

	'sectionblocks'
		=> sub { $_[0]->sqlSelectMany('bid,title', 'blocks', 'portal=1') }

);

sub _whereFormkey {
	my($self, $formkey_id) = @_;
	my $where;

	my $user = getCurrentUser();
	# anonymous user without cookie, check host, not formkey id
	if ($user->{anon_id} && ! $user->{anon_cookie}) {
		$where = "host_name = '$ENV{REMOTE_ADDR}'";
	} else {
		$where = "id='$formkey_id'";
	}

	return $where;
};

########################################################
# Notes:
#  formAbuse, use defaults as ENV, be able to override
#  	(pudge idea).
#  description method cleanup. (done)
#  fetchall_rowref vs fetch the hashses and push'ing
#  	them into an array (good arguments for both)
#	 break up these methods into multiple classes and
#   use the dB classes to override methods (this
#   could end up being very slow though since the march
#   is kinda slow...).
#	 the getAuthorEdit() methods need to be refined
########################################################

########################################################
sub init {
	my($self) = @_;
	# These are here to remind us of what exists
	$self->{_storyBank} = {};
	$self->{_codeBank} = {};
	$self->{_sectionBank} = {};
	$self->{_boxes} = {};
	$self->{_sectionBoxes} = {};
}

########################################################
sub setComment {
	my($self, $form, $user, $pts, $default_user) = @_;
	my $sid_db = $self->{_dbh}->quote($form->{sid});

	$self->sqlDo("LOCK TABLES comments WRITE");
	my($maxCid) = $self->sqlSelect(
		"max(cid)", "comments", "sid=$sid_db"
	);

	$maxCid++; # This is gonna cause troubles
	my $insline = "INSERT into comments values ($sid_db,$maxCid," .
		$self->{_dbh}->quote($form->{pid}) . ",now(),'$ENV{REMOTE_ADDR}'," .
		$self->{_dbh}->quote($form->{postersubj}) . "," .
		$self->{_dbh}->quote($form->{postercomment}) . "," .
		($form->{postanon} ? $default_user : $user->{uid}) . ", $pts,-1,0)";

	# don't allow pid to be passed in the form.
	# This will keep a pid from being replace by
	# with other comment's pid
	if ($form->{pid} >= $maxCid || $form->{pid} < 0) {
		$self->sqlDo("UNLOCK TABLES");
		return;
	}

	if ($self->sqlDo($insline)) {
		$self->sqlDo("UNLOCK TABLES");
		my $copyline = "insert into newcomments select * from comments where cid = $maxCid";
		$copyline .= " AND sid = $sid_db";

		$self->sqlDo($copyline);

		# Update discussion
		my($dtitle) = $self->sqlSelect(
			'title', 'discussions', "sid=$sid_db"
		);

		unless ($dtitle) {
			$self->sqlUpdate(
				"discussions",
				{ title => $form->{postersubj} },
				"sid=$sid_db"
			) if $form->{sid};
		}

		my($ws) = $self->sqlSelect(
			"writestatus", "stories", "sid=$sid_db"
		);

		if ($ws == 0) {
			$self->sqlUpdate(
				"stories",
				{ writestatus => 1 },
				"sid=$sid_db"
			);
		}

		$self->sqlUpdate(
			"users_info",
			{ -totalcomments => 'totalcomments+1' },
			"uid=" . $self->{_dbh}->quote($user->{uid}), 1
		);

		# successful submission
		$self->formSuccess($form->{formkey}, $maxCid, length($form->{postercomment}));

		my($tc, $mp, $cpp) = $self->getVars(
			"totalComments",
			"maxPoints",
			"commentsPerPoint"
		);

		$self->setVar("totalComments", ++$tc);

		return $maxCid;

	} else {
		$self->sqlDo("UNLOCK TABLES");
		errorLog("$DBI::errstr $insline");
		return -1;
	}
}

########################################################
sub setModeratorLog {
	my($self, $cid, $sid, $uid, $val, $reason) = @_;
	$self->sqlInsert("moderatorlog", {
		uid => $uid,
		val => $val,
		sid => $sid,
		cid => $cid,
		reason  => $reason,
		-ts => 'now()'
	});
}

########################################################
sub getMetamodComments {
	my($self, $id, $uid, $num_comments) = @_;

	my $sth = $self->sqlSelectMany(
		'newcomments.cid,date,' .
		'subject,comment,nickname,homepage,fakeemail,realname,users.uid as uid,
		sig,newcomments.points as points,pid,newcomments.sid as sid,
		moderatorlog.id as id,title,moderatorlog.reason as modreason,
		newcomments.reason',
		'newcomments,users,users_info,moderatorlog,stories',
		"stories.sid=newcomments.sid AND moderatorlog.sid=newcomments.sid AND
		moderatorlog.cid=newcomments.cid AND moderatorlog.id>$id AND
		newcomments.uid!=$uid AND users.uid=newcomments.uid AND
		users.uid=users_info.uid AND users.uid!=$uid AND
		moderatorlog.uid!=$uid AND moderatorlog.reason<8 LIMIT $num_comments"
	);

	my $comments;
	while (my $comment = $sth->fetchrow_hashref) {
		# Anonymize comment that is to be metamoderated.
		@{$comment}{qw(nickname uid fakeemail homepage points)} =
			('-', -1, '', '', 0);

		push @$comments, $comment;
	}
	$sth->finish;

	formatDate($comments);
	return $comments;
}

########################################################
sub getModeratorCommentLog {

# why was this removed?  -- pudge
#				"moderatorlog.active=1

	my($self, $sid, $cid) = @_;
	my $comments = $self->sqlSelectMany(  "newcomments.sid as sid,
				 newcomments.cid as cid,
				 newcomments.points as score,
				 subject, moderatorlog.uid as uid,
				 users.nickname as nickname,
				 moderatorlog.val as val,
				 moderatorlog.reason as reason",
				"moderatorlog, users, newcomments",
				"moderatorlog.sid='$sid'
			     AND moderatorlog.cid=$cid
			     AND moderatorlog.uid=users.uid
			     AND newcomments.sid=moderatorlog.sid
			     AND newcomments.cid=moderatorlog.cid"
	);
	my(@comments, $comment);
	push @comments, $comment while ($comment = $comments->fetchrow_hashref);
	return \@comments;
}

########################################################
sub getModeratorLogID {
	my($self, $cid, $sid, $uid) = @_;
	my($mid) = $self->sqlSelect(
		"id", "moderatorlog",
		"uid=$uid and cid=$cid and sid='$sid'"
	);
	return $mid;
}

########################################################
sub unsetModeratorlog {
	my($self, $uid, $sid, $max, $min) = @_;
	my $cursor = $self->sqlSelectMany("cid,val", "moderatorlog",
			"uid=$uid and sid=" . $self->{_dbh}->quote($sid)
	);
	my @removed;

	while (my($cid, $val, $active, $max, $min) = $cursor->fetchrow){
		# We undo moderation even for inactive records (but silently for
		# inactive ones...)
		$self->sqlDo("delete from moderatorlog where
			cid=$cid and uid=$uid and sid=" .
			$self->{_dbh}->quote($sid)
		);

		# If moderation wasn't actually performed, we should not change
		# the score.
		next if ! $active;

		# Insure scores still fall within the proper boundaries
		my $scorelogic = $val < 0
			? "points < $max"
			: "points > $min";
		$self->sqlUpdate(
			"comments",
			{ -points => "points+" . (-1 * $val) },
			"cid=$cid and sid=" . $self->{_dbh}->quote($sid) . " AND $scorelogic"
		);
		my $copyline = "replace into newcomments select * from comments where cid = $cid and sid = ";
		$copyline .= $self->{_dbh}->quote($sid);
		$self->sqlDo($copyline);
		push(@removed, $cid);
	}

	return \@removed;
}

########################################################
sub getContentFilters {
	my($self) = @_;
	my $filters = $self->sqlSelectAll("*","content_filters","regex != '' and field != ''");
	return $filters;
}

########################################################
sub createPollVoter {
	my($self, $qid, $aid) = @_;

	$self->sqlInsert("pollvoters", {
		qid	=> $qid,
		id	=> $ENV{REMOTE_ADDR} . $ENV{HTTP_X_FORWARDED_FOR},
		-'time'	=> 'now()',
		uid	=> $ENV{SLASH_USER}
	});

	my $qid_db = $self->{_dbh}->quote($qid);
	$self->sqlDo("update pollquestions set
		voters=voters+1 where qid=$qid_db");
	$self->sqlDo("update pollanswers set votes=votes+1 where
		qid=$qid_db and aid=" . $self->{_dbh}->quote($aid));
}

########################################################
sub createSubmission {
	my($self) = @_;
	my $form = getCurrentForm();
	my $uid = getCurrentUser('uid');
	my($sec, $min, $hour, $mday, $mon, $year) = localtime;
	my $subid = "$hour$min$sec.$mon$mday$year";

	$self->sqlInsert("submissions", {
			email	=> $form->{email},
			uid	=> $ENV{SLASH_USER},
			name	=> $form->{from},
			story	=> strip_html($form->{story}),
			-'time'	=> 'now()',
			subid	=> $subid,
			subj	=> $form->{subj},
			tid	=> $form->{tid},
			section	=> $form->{section}
	});
	$self->formSuccess($form->{formkey}, 0, length($form->{subj}));
}

########################################################
sub createDiscussions {
	my($self, $sid) = @_;
	# Posting from outside discussions...
	$sid = $ENV{HTTP_REFERER} ? crypt($ENV{HTTP_REFERER}, 0) : '';
	$sid = $self->{_dbh}->quote($sid);
	my($story_time) = $self->sqlSelect("time", "stories", "sid=$sid");
	$story_time ||= "now()";
	unless ($self->sqlSelect("title", "discussions", "sid=$sid")) {
		$self->sqlInsert("discussions", {
			sid	=> $sid,
			title	=> '',
			ts	=> $story_time,
			url	=> $ENV{HTTP_REFERER}
		});
	}
}

#################################################################
sub getDiscussions {
	my($self) = @_;
	my $discussion = $self->sqlSelectAll("discussions.sid,discussions.title,discussions.url",
		"discussions,stories ",
		"displaystatus > -1 and discussions.sid=stories.sid and time <= now() ",
		"order by time desc LIMIT 50"
	);

	return $discussion;
}

########################################################
# Handles admin logins (checks the sessions table for a cookie that
# matches).  Called by getSlash
sub getSessionInstance {
	my($self, $uid, $session) = @_;
	my $admin_timeout = getCurrentStatic('admin_timeout');

	if (length($session) > 3) {
		$self->sqlDo("DELETE from sessions WHERE now() > DATE_ADD(lasttime, INTERVAL $admin_timeout MINUTE)");

		my($uid) = $self->sqlSelect(
			'uid',
			'sessions',
			'session=' . $self->{_dbh}->quote($session)
		);

		if ($uid) {
			$self->sqlDo("DELETE from sessions WHERE uid = '$uid' AND session != " .
				$self->{_dbh}->quote($session)
			);
			$self->sqlUpdate('sessions', {-lasttime => 'now()'},
				'session=' . $self->{_dbh}->quote($session)
			);
		}
	} else {
		my($title) = $self->sqlSelect('lasttitle', 'sessions',
			"uid=$uid"
		);

		$self->sqlDo("DELETE FROM sessions WHERE uid=$uid");

		my $sid = $self->generatesession($uid);
		$self->sqlInsert('sessions', { session => $sid, -uid => $uid,
			-logintime => 'now()', -lasttime => 'now()',
			lasttitle => $title }
		);

		return $sid;
	}
	return;
}

########################################################
sub setContentFilter {
	my($self) = @_;
	my $form = getCurrentForm();
	$self->sqlUpdate("content_filters", {
			regex		=> $form->{regex},
			modifier	=> $form->{modifier},
			field		=> $form->{field},
			ratio		=> $form->{ratio},
			minimum_match	=> $form->{minimum_match},
			minimum_length	=> $form->{minimum_length},
			maximum_length	=> $form->{maximum_length},
			err_message	=> $form->{err_message},
		}, "filter_id=$form->{filter_id}"
	);
}

########################################################
# Only Slashdot uses this method
sub setSectionExtra {
	my($self, $full, $story) = @_;

	if ($full && $self->sqlTableExists($story->{section}) && $story->{section}) {
		my $extra = $self->sqlSelectHashref('*', $story->{section}, "sid='$story->{sid}'");
		for (keys %$extra) {
			$story->{$_} = $extra->{$_};
		}
	}

}

########################################################
# This creates an entry in the accesslog
sub createAccessLog {
	my($self, $op, $dat) = @_;

	my $uid;
	if ($ENV{SLASH_USER}) {
		$uid = $ENV{SLASH_USER};
	} else {
		$uid = getCurrentStatic('anonymous_coward_uid');
	}

	$self->sqlInsert('accesslog', {
		host_addr	=> $ENV{REMOTE_ADDR} || '0',
		dat		=> $dat,
		uid		=> $uid,
		op		=> $op,
		-ts		=> 'now()',
		query_string	=> $ENV{QUERY_STRING} || '0',
		user_agent	=> $ENV{HTTP_USER_AGENT} || '0',
	}, 2);

	if ($dat =~ /\//) {
		$self->sqlUpdate('storiestuff', { -hits => 'hits+1' },
			'sid=' . $self->{_dbh}->quote($dat)
		);
	}
}

########################################################
sub getDescriptions {
	my ($self, $codetype) =  @_;
	return unless $codetype;
	my $codeBank_hash_ref = {};
	my $cache = '_getDescriptions_' . $codetype;

	return $self->{$cache} if $self->{$cache};

	my $sth = $descriptions{$codetype}->(@_);
	while (my($id, $desc) = $sth->fetchrow) {
		$codeBank_hash_ref->{$id} = $desc;
	}
	$sth->finish;

	$self->{$cache} = $codeBank_hash_ref if getCurrentStatic('cache_enabled');
	return $codeBank_hash_ref;
}

########################################################
# Get user info from the users table.
# If you don't pass in a $script, you get everything
# which is handy for you if you need the entire user

# why not just axe this entirely and always get all the data? -- pudge

sub getUserInstance {
	my($self, $uid, $script) = @_;

	my $user;
	unless ($script) {
		$user = $self->getUser($uid);
		return $user || undef;
	}

	$user = $self->sqlSelectHashref('*', 'users',
		' uid = ' . $self->{_dbh}->quote($uid)
	);
	return undef unless $user;
	my $user_extra = $self->sqlSelectHashref('*', "users_prefs", "uid=$uid");
	while (my($key, $val) = each %$user_extra) {
		$user->{$key} = $val;
	}

	# what is this for?  it appears to want to do the same as the
	# code above ... but this assigns a scalar to a scalar ...
	# perhaps `@{$user}{ keys %foo } = values %foo` is wanted?  -- pudge
#	$user->{ keys %$user_extra } = values %$user_extra;

#	if (!$script || $script =~ /index|article|comments|metamod|search|pollBooth/)
	{
		my $user_extra = $self->sqlSelectHashref('*', "users_comments", "uid=$uid");
		while (my($key, $val) = each %$user_extra) {
			$user->{$key} = $val;
		}
	}

	# Do we want the index stuff?
#	if (!$script || $script =~ /index/)
	{
		my $user_extra = $self->sqlSelectHashref('*', "users_index", "uid=$uid");
		while (my($key, $val) = each %$user_extra) {
			$user->{$key} = $val;
		}
	}

	return $user;
}

########################################################
sub deleteUser {
	my($self, $uid) = @_;
	$self->setUser($uid, {
		bio		=> '',
		nickname	=> 'deleted user',
		matchname	=> 'deleted user',
		realname	=> '',
		realemail	=> '',
		fakeemail	=> '',
		newpasswd	=> '',
		homepage	=> '',
		passwd		=> '',
		sig		=> '',
		seclev		=> 0
	});
	$self->sqlDo("DELETE FROM users_param WHERE uid=$uid");
}

########################################################
# Get user info from the users table.
sub getUserAuthenticate {
	my($self, $user, $passwd, $kind) = @_;
	my($uid, $cookpasswd, $newpass, $dbh, $user_db,
		$cryptpasswd, @pass);

	return unless $user && $passwd;

	# if $kind is 1, then only try to auth password as plaintext
	# if $kind is 2, then only try to auth password as encrypted
	# if $kind is undef or 0, try as encrypted
	#	(the most common case), then as plaintext
	my($EITHER, $PLAIN, $ENCRYPTED) = (0, 1, 2);
	my($UID, $PASSWD, $NEWPASSWD) = (0, 1, 2);
	$kind ||= $EITHER;

	# RECHECK LOGIC!!  -- pudge

	$dbh = $self->{_dbh};
	$user_db = $dbh->quote($user);
	$cryptpasswd = encryptPassword($passwd);
	@pass = $self->sqlSelect(
		'uid,passwd,newpasswd',
		'users',
		"uid=$user_db"
	);

	# try ENCRYPTED -> ENCRYPTED
	if ($kind == $EITHER || $kind == $ENCRYPTED) {
		if ($passwd eq $pass[$PASSWD]) {
			$uid = $pass[$UID];
			$cookpasswd = $passwd;
		}
	}

	# try PLAINTEXT -> ENCRYPTED
	if (($kind == $EITHER || $kind == $PLAIN) && !defined $uid) {
		if ($cryptpasswd eq $pass[$PASSWD]) {
			$uid = $pass[$UID];
			$cookpasswd = $cryptpasswd;
		}
	}

	# try PLAINTEXT -> NEWPASS
	if (($kind == $EITHER || $kind == $PLAIN) && !defined $uid) {
		if ($passwd eq $pass[$NEWPASSWD]) {
			$self->sqlUpdate('users', {
				newpasswd	=> '',
				passwd		=> $cryptpasswd
			}, "uid=$user_db");
			$newpass = 1;

			$uid = $pass[$UID];
			$cookpasswd = $cryptpasswd;
		}
	}

	# return UID alone in scalar context
	return wantarray ? ($uid, $cookpasswd, $newpass) : $uid;
}

########################################################
# Make a new password, save it in the DB, and return it.
sub getNewPasswd {
	my($self, $uid) = @_;
	my $newpasswd = changePassword();
	$self->sqlUpdate('users', {
		newpasswd => $newpasswd
	}, 'uid=' . $self->{_dbh}->quote($uid));
	return $newpasswd;
}


########################################################
# Get user info from the users table.
# May be worth it to cache this at some point
sub getUserUID {
	my($self, $name) = @_;

#!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
# We need to add BINARY to this
# as is, it may be a security flaw
#!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
	my($uid) = $self->sqlSelect('uid', 'users',
		'nickname=' . $self->{_dbh}->quote($name)
	);

	return $uid;
}

#################################################################
sub getCommentsByUID {
	my($self, $uid, $min) = @_;

	my $sqlquery = "SELECT pid,sid,cid,subject,date,points "
			. " FROM newcomments WHERE uid=$uid "
			. " ORDER BY date DESC LIMIT $min,50 ";

	my $sth = $self->{_dbh}->prepare($sqlquery);
	$sth->execute;
	my($comments) = $sth->fetchall_arrayref;
	formatDate($comments, 4);
	return $comments;
}

#################################################################
# Just create an empty content_filter
sub createContentFilter {
	my($self) = @_;

	$self->sqlInsert("content_filters", {
		regex		=> '',
		modifier	=> '',
		field		=> '',
		ratio		=> 0,
		minimum_match	=> 0,
		minimum_length	=> 0,
		maximum_length	=> 0,
		err_message	=> ''
	});

	my($filter_id) = $self->sqlSelect("max(filter_id)", "content_filters");

	return $filter_id;
}

#################################################################
# Replication issue. This needs to be a two-phase commit.
sub createUser {
	my($self, $matchname, $email, $newuser) = @_;
	return unless $matchname && $email && $newuser;

	return if ($self->sqlSelect(
		"count(uid)","users",
		"matchname=" . $self->{_dbh}->quote($matchname)
	))[0] || ($self->sqlSelect(
		"count(uid)","users",
		" realemail=" . $self->{_dbh}->quote($email)
	))[0];

	$self->sqlInsert("users", {
		uid		=> '',  # this would be done automatically ... ? -- pudge
		realemail	=> $email,
		nickname	=> $newuser,
		matchname	=> $matchname,
		passwd		=> encryptPassword(changePassword())
	});

# This is most likely a transaction problem waiting to
# bite us at some point. -Brian
	my($uid) = $self->sqlSelect("LAST_INSERT_ID()");
	$self->sqlInsert("users_info", { uid => $uid, -lastaccess => 'now()' } );
	$self->sqlInsert("users_prefs", { uid => $uid } );
	$self->sqlInsert("users_comments", { uid => $uid } );
	$self->sqlInsert("users_index", { uid => $uid } );

	return $uid;
}

########################################################
# This method should be questioned long term
sub getACTz {
	my($self, $tzcode, $dfid) = @_;
	my $ac_hash_ref;
	$ac_hash_ref = $self->sqlSelectHashref('*',
		'tzcodes,dateformats',
		"tzcodes.tz='$tzcode' AND dateformats.id=$dfid"
	);
	return $ac_hash_ref;
}

###############################################################################
# Functions for dealing with vars (system config variables)

########################################################
sub getVars {
	my($self, @invars) = @_;

	my @values;
	for (@invars) {
		push @values, $self->sqlSelect('value', 'vars', "name='$_'");
	}

	return @values;
}


########################################################
sub setVar {
	my($self, $name, $value) = @_;
	$self->sqlUpdate('vars', {value => $value}, 'name=' . $self->{_dbh}->quote($name));
}

########################################################
sub setSession {
	my($self, $name, $value) = @_;
	$self->sqlUpdate('sessions', $value, 'uid=' . $self->{_dbh}->quote($name));
}

########################################################
sub setBlock {
	_genericSet('blocks', 'bid', @_);
}

########################################################
sub setTemplate {
	_genericSet('templates', 'tpid', @_);
}

########################################################
sub newVar {
	my($self, $name, $value, $desc) = @_;
	$self->sqlInsert('vars', {name => $name, value => $value, description => $desc});
}

########################################################
sub updateCommentTotals {
	my($self, $sid, $comments) = @_;
	my $hp = join ',', @{$comments->[0]{totals}};
	$self->sqlUpdate("stories", {
			hitparade	=> $hp,
			writestatus	=> 0,
			commentcount	=> $comments->[0]{totals}[0]
		}, 'sid=' . $self->{_dbh}->quote($sid)
	);
}

########################################################
sub getCommentCid {
	my($self, $sid, $cid) = @_;
	my($scid) = $self->sqlSelectAll("cid", "newcomments", "sid='$sid' and pid='$cid'");

	return $scid;
}

########################################################
sub deleteComment {
	my($self, $sid, $cid) = @_;
	if ($cid) {
		$self->sqlDo("delete from newcomments WHERE sid=" .
			$self->{_dbh}->quote($sid) . " and cid=" . $self->{_dbh}->quote($cid)
		);
		$self->sqlDo("delete from comments WHERE sid=" .
			$self->{_dbh}->quote($sid) . " and cid=" . $self->{_dbh}->quote($cid)
		);
	} else {
		$self->sqlDo("delete from newcomments WHERE sid=" .
			$self->{_dbh}->quote($sid));
		$self->sqlDo("delete from comments WHERE sid=" .
			$self->{_dbh}->quote($sid));

		$self->sqlDo("UPDATE stories SET writestatus=10 WHERE sid='$sid'");
	}
}

########################################################
sub getCommentPid {
	my($self, $sid, $cid) = @_;
	$self->sqlSelect('pid', 'newcomments',
		"sid='$sid' and cid=$cid");
}

########################################################
sub setSection {
# We should perhaps be passing in a reference to F here. More
# thought is needed. -Brian
	my($self, $section, $qid, $title, $issue, $isolate, $artcount) = @_;
	my $section_dbh = $self->{_dbh}->quote($section);
	my($count) = $self->sqlSelect("count(*)","sections","section=$section_dbh");
	my($ok1, $ok2);

	# This is a poor attempt at a transaction I might add. -Brian
	# I need to do this diffently under Oracle
	unless ($count) {
		$self->sqlDo("INSERT into sections (section) VALUES($section_dbh)");
		$ok1++ unless $self->{_dbh}->errstr;
	}

	$self->sqlUpdate('sections', {
			qid		=> $qid,
			title		=> $title,
			issue		=> $issue,
			isolate		=> $isolate,
			artcount	=> $artcount
		}, "section=$section_dbh"
	);
	$ok2++ unless $self->{_dbh}->errstr;

	return($count, $ok1, $ok2);
}

########################################################
sub setStoriesCount {
	my($self, $sid, $count) = @_;
	$self->sqlUpdate('stories', {
		-commentcount	=> "commentcount-$count",
		writestatus	=> 1
	}, 'sid=' . $self->{_dbh}->quote($sid));
}

########################################################
sub getSectionTitle {
	my($self) = @_;
	my $sth = $self->{_dbh}->prepare("SELECT section,title FROM sections ORDER BY section");
	$sth->execute;
	my $sections = $sth->fetchall_arrayref;
	$sth->finish;

	return $sections;
}

########################################################
# Long term, this needs to be modified to take in account
# of someone wanting to delete a submission that is
# not part in the form
sub deleteSubmission {
	my($self, $subid) = @_;
	my $uid = getCurrentUser('uid');
	my $form = getCurrentForm();
	my %subid;

	if ($form->{subid}) {
		$self->sqlUpdate("submissions", { del => 1 },
			"subid=" . $self->{_dbh}->quote($form->{subid})
		);
		$self->setUser($uid,
			{ -deletedsubmissions => 'deletedsubmissions+1' }
		);
		$subid{$form->{subid}}++;
	}

	foreach (keys %{$form}) {
		next unless /(.*)_(.*)/;
		my($t, $n) = ($1, $2);
		if ($t eq "note" || $t eq "comment" || $t eq "section") {
			$form->{"note_$n"} = "" if $form->{"note_$n"} eq " ";
			if ($form->{$_}) {
				my %sub = (
					note	=> $form->{"note_$n"},
					comment	=> $form->{"comment_$n"},
					section	=> $form->{"section_$n"}
				);

				if (!$sub{note}) {
					delete $sub{note};
					$sub{-note} = 'NULL';
				}

				$self->sqlUpdate("submissions", \%sub,
					"subid=" . $self->{_dbh}->quote($n));
			}
		} else {
			my $key = $n;
			$self->sqlUpdate("submissions", { del => 1 },
				"subid='$key'");
			$self->setUser($uid,
				{ -deletedsubmissions => 'deletedsubmissions+1' }
			);
			$subid{$n}++;
		}
	}

	return keys %subid;
}

########################################################
sub deleteSession {
	my($self, $uid) = @_;
	$uid = defined($uid) || getCurrentUser('uid');
	if (defined $uid) {
		$self->sqlDo("DELETE FROM sessions WHERE uid=$uid");
	}
}

########################################################
sub deleteAuthor {
	my($self, $uid) = @_;
	$self->sqlDo("DELETE FROM sessions WHERE uid=$uid");
}

########################################################
sub deleteTopic {
	my($self, $tid) = @_;
	$self->sqlDo('DELETE from topics WHERE tid=' . $self->{_dbh}->quote($tid));
}

########################################################
sub revertBlock {
	my($self, $bid) = @_;
	my $db_bid = $self->{_dbh}->quote($bid);
	my $block = $self->{_dbh}->selectrow_array("SELECT block from backup_blocks WHERE bid=$db_bid");
	$self->sqlDo("update blocks set block = $block where bid = $db_bid");
}

########################################################
sub deleteTemplate {
	my($self, $tpid) = @_;
	$self->sqlDo('DELETE FROM templates WHERE tpid=' . $self->{_dbh}->quote($tpid));
}

########################################################
sub deleteSection {
	my($self, $section) = @_;
	$self->sqlDo("DELETE from sections WHERE section='$section'");
}

########################################################
sub deleteContentFilter {
	my($self, $id) = @_;
	$self->sqlDo("DELETE from content_filters WHERE filter_id = $id");
}

########################################################
sub saveTopic {
	my($self) = @_;
	my $form = getCurrentForm();
	my($rows) = $self->sqlSelect('count(*)', 'topics', 'tid=' . $self->{_dbh}->quote($form->{tid}));
	if ($rows == 0) {
		$self->sqlInsert('topics', {
			tid	=> $form->{tid},
			image	=> $form->{image},
			alttext	=> $form->{alttext},
			width	=> $form->{width},
			height	=> $form->{height}
		});
	}

	$self->sqlUpdate('topics', {
			image	=> $form->{image},
			alttext	=> $form->{alttext},
			width	=> $form->{width},
			height	=> $form->{height}
		}, 'tid=' . $self->{_dbh}->quote($form->{tid})
	);
}

##################################################################
sub saveBlock {
	my($self, $bid) = @_;
	my($rows) = $self->sqlSelect('count(*)', 'blocks',
		'bid=' . $self->{_dbh}->quote($bid)
	);

	my $form = getCurrentForm();
	if ($form->{save_new} && $rows > 0) {
		return $rows;
	}

	if ($rows == 0) {
		$self->sqlInsert('blocks', { bid => $bid, seclev => 500 });
	}

	my($portal, $retrieve) = (0, 0);

	# this is to make sure that a  static block doesn't get
	# saved with retrieve set to true
	$form->{retrieve} = 0 if $form->{type} ne 'portald';

	$form->{block} = $self->autoUrl($form->{section}, $form->{block})
		unless $form->{type} eq 'template';

	if ($rows == 0 || $form->{blocksavedef}) {
		$self->sqlUpdate('blocks', {
			seclev		=> $form->{bseclev},
			block		=> $form->{block},
			description	=> $form->{description},
			type		=> $form->{type},
			ordernum	=> $form->{ordernum},
			title		=> $form->{title},
			url		=> $form->{url},
			rdf		=> $form->{rdf},
			section		=> $form->{section},
			retrieve	=> $form->{retrieve},
			portal		=> $form->{portal},
		}, 'bid=' . $self->{_dbh}->quote($bid));
		$self->sqlUpdate('backup_blocks', {
			block		=> $form->{block},
		}, 'bid=' . $self->{_dbh}->quote($bid));
	} else {
		$self->sqlUpdate('blocks', {
			seclev		=> $form->{bseclev},
			block		=> $form->{block},
			description	=> $form->{description},
			type		=> $form->{type},
			ordernum	=> $form->{ordernum},
			title		=> $form->{title},
			url		=> $form->{url},
			rdf		=> $form->{rdf},
			section		=> $form->{section},
			retrieve	=> $form->{retrieve},
			portal		=> $form->{portal},
		}, 'bid=' . $self->{_dbh}->quote($bid));
	}


	return $rows;
}

########################################################
sub saveColorBlock {
	my($self, $colorblock) = @_;
	my $form = getCurrentForm();

	my $db_bid = $self->{_dbh}->quote($form->{color_block} || 'colors');

	if ($form->{colorsave}) {
		# save into colors and colorsback
		$self->sqlUpdate('blocks', {
				block => $colorblock,
			}, "bid = $db_bid"
		);

	} elsif ($form->{colorsavedef}) {
		# save into colors and colorsback
		$self->sqlUpdate('blocks', {
				block => $colorblock,
			}, "bid = $db_bid"
		);
		$self->sqlUpdate('backup_blocks', {
				block => $colorblock,
			}, "bid = $db_bid"
		);

	} elsif ($form->{colororig}) {
		# reload original version of colors
		my $block = $self->{_dbh}->selectrow_array("SELECT block FROM backup_blocks WHERE bid = $db_bid");
		$self->sqlDo("UPDATE blocks SET block = $block WHERE bid = $db_bid");
	}
}

########################################################
sub getSectionBlock {
	my($self, $section) = @_;
	my $block = $self->sqlSelectAll("section,bid,ordernum,title,portal,url,rdf,retrieve",
		"blocks", "section=" . $self->{_dbh}->quote($section),
		"ORDER by ordernum"
	);

	return $block;
}


########################################################
sub getAuthorDescription {
	my($self) = @_;
	my $authors = $self->sqlSelectAll("count(*) as c, uid",
		"stories", '', "GROUP BY uid ORDER BY c DESC"
	);

	return $authors;
}

########################################################
# This method does not follow basic guidlines
sub getPollVoter {
	my($self, $id) = @_;
	my($voters) = $self->sqlSelect('id', 'pollvoters',
		"qid=" . $self->{_dbh}->quote($id) .
		"AND id=" . $self->{_dbh}->quote($ENV{REMOTE_ADDR} . $ENV{HTTP_X_FORWARDED_FOR}) .
		"AND uid=" . $ENV{SLASH_USER}
	);

	return $voters;
}

########################################################
sub savePollQuestion {
	my($self) = @_;
	my $form = getCurrentForm();
	$form->{voters} ||= "0";
	$self->sqlReplace("pollquestions", {
		qid		=> $form->{qid},
		question	=> $form->{question},
		voters		=> $form->{voters},
		-date		=>'now()'
	});

	$self->setVar("currentqid", $form->{qid}) if $form->{currentqid};

	# Loop through 1..8 and insert/update if defined
	for (my $x = 1; $x < 9; $x++) {
		if ($form->{"aid$x"}) {
			$self->sqlReplace("pollanswers", {
				aid	=> $x,
				qid	=> $form->{qid},
				answer	=> $form->{"aid$x"},
				votes	=> $form->{"votes$x"}
			});

		} else {
			$self->sqlDo("DELETE from pollanswers WHERE qid="
				. $self->{_dbh}->quote($form->{qid}) . " and aid=$x");
		}
	}
}

########################################################
sub getPollQuestionList {
	my($self, $time) = @_;
	my $questions = $self->sqlSelectAll("qid, question, date_format(date,\"W M D\")",
		"pollquestions order by date DESC LIMIT $time,20");

	return $questions;
}

########################################################
sub getPollAnswers {
	my($self, $id, $val) = @_;
	my $values = join ',', @$val;
	my $answers = $self->sqlSelectAll($values, 'pollanswers', "qid=" . $self->{_dbh}->quote($id), 'ORDER by aid');

	return $answers;
}

########################################################
sub getPollQuestions {
# This may go away. Haven't finished poll stuff yet
#
	my($self) = @_;

	my $poll_hash_ref = {};
	my $sql = "SELECT qid,question FROM pollquestions ORDER BY date DESC LIMIT 25";
	my $sth = $self->{_dbh}->prepare_cached($sql);
	$sth->execute;
	while (my($id, $desc) = $sth->fetchrow) {
		$poll_hash_ref->{$id} = $desc;
	}
	$sth->finish;

	return $poll_hash_ref;
}

########################################################
sub deleteStory {
	my($self, $sid) = @_;
	$self->sqlUpdate('stories', { writestatus => 5 },
		'sid=' . $self->{_dbh}->quote($sid)
	);

	$self->sqlDo("DELETE from discussions WHERE sid = '$sid'");
}

########################################################
# for slashd
sub deleteStoryAll {
	my($self, $sid) = @_;

	$self->sqlDo("DELETE from stories where sid='$sid'");
	$self->sqlDo("DELETE from newstories where sid='$sid'");
}

########################################################
# for slashd
# This method is used in a pretty wasteful way
sub getBackendStories {
	my($self, $section) = @_;

	my $cursor = $self->{_dbh}->prepare("SELECT stories.sid,title,time,dept,uid,alttext,
		image,commentcount,section,introtext,bodytext,
		topics.tid as tid
		    FROM stories,topics
		   WHERE ((displaystatus = 0 and \"$section\"=\"\")
		      OR (section=\"$section\" and displaystatus > -1))
		     AND time < now()
		     AND writestatus > -1
		     AND stories.tid=topics.tid
		ORDER BY time DESC
		   LIMIT 10");

		  # AND time < date_add(now(), INTERVAL 4 HOUR)

	$cursor->execute;
	my $returnable = [];
	my $row;
	push(@$returnable, $row) while ($row = $cursor->fetchrow_hashref);

	return $returnable;
}

########################################################
sub clearStory {
	 _genericClearCache('stories', @_);
}

########################################################
sub setStory {
	_genericSet('blocks', 'bid', @_);
}

########################################################
sub getSubmissionLast {
	my($self, $id, $formname) = @_;

	my $where = $self->_whereFormkey($id);
	my($last_submitted) = $self->sqlSelect(
		"max(submit_ts)",
		"formkeys",
		"$where AND formname = '$formname'");
	$last_submitted ||= 0;

	return $last_submitted;
}


########################################################
sub getSectionBlocks {
	my($self) = @_;

	my $blocks = $self->sqlSelectAll("bid,title,ordernum", "blocks", "portal=1", "order by bid");

	return $blocks;
}

########################################################
sub getLock {
	my($self) = @_;
	my $locks = $self->sqlSelectAll('lasttitle,uid', 'sessions');

	return $locks;
}

########################################################
sub updateFormkeyId {
	my($self, $formname, $formkey, $anon, $uid, $rlogin, $upasswd) = @_;

	if ($uid != $anon && $rlogin && length($upasswd) > 1) {
		$self->sqlUpdate("formkeys", {
			id	=> $uid,
			uid	=> $uid,
		}, "formname='$formname' AND uid = $anon AND formkey=" .
			$self->{_dbh}->quote($formkey));
	}
}

########################################################
sub insertFormkey {
	my($self, $formname, $id, $sid) = @_;
	my $form = getCurrentForm();

	# save in form object for printing to user
	$form->{formkey} = getFormkey();

	# insert the fact that the form has been displayed, but not submitted at this point
	$self->sqlInsert("formkeys", {
		formkey		=> $form->{formkey},
		formname 	=> $formname,
		id 		=> $id,
		sid		=> $sid,
		uid		=> $ENV{SLASH_USER},
		host_name	=> $ENV{REMOTE_ADDR},
		value		=> 0,
		ts		=> time()
	});
}

########################################################
sub checkFormkey {
	my($self, $formkey_earliest, $formname, $formkey_id, $formkey) = @_;

	my $where = $self->_whereFormkey($formkey_id);
	my($is_valid) = $self->sqlSelect('count(*)', 'formkeys',
		'formkey = ' . $self->{_dbh}->quote($formkey) .
		" AND $where " .
		"AND ts >= $formkey_earliest AND formname = '$formname'");

	errorLog(<<EOT) unless $is_valid;

SELECT count(*) FROM formkeys WHERE formkey = '$formkey' AND $where \
	AND ts >=  $formkey_earliest AND formname = '$formname'
EOT

	return $is_valid;
}

##################################################################
sub checkTimesPosted {
	my($self, $formname, $max, $id, $formkey_earliest) = @_;

	my $where = $self->_whereFormkey($id);
	my($times_posted) = $self->sqlSelect(
		"count(*) as times_posted",
		"formkeys",
		"$where AND submit_ts >= $formkey_earliest AND formname = '$formname'");

	return $times_posted >= $max ? 0 : 1;
}

##################################################################
# the form has been submitted, so update the formkey table
# to indicate so
sub formSuccess {
	my($self, $formkey, $cid, $length) = @_;

	# update formkeys to show that there has been a successful post,
	# and increment the value from 0 to 1 (shouldn't ever get past 1)
	# meaning that yes, this form has been submitted, so don't try i t again.
	$self->sqlUpdate("formkeys", {
			-value          => 'value+1',
			cid             => $cid,
			submit_ts       => time(),
			content_length  => $length,
		}, "formkey=" . $self->{_dbh}->quote($formkey)
	);
}

##################################################################
sub formFailure {
	my($self, $formkey) = @_;
	$self->sqlUpdate("formkeys", {
			value   => -1,
		}, "formkey=" . $self->{_dbh}->quote($formkey)
	);
}

##################################################################
# logs attempts to break, fool, flood a particular form
sub formAbuse {
	my($self, $reason, $remote_addr, $script_name, $query_string) = @_;
	# logem' so we can banem'
	$self->sqlInsert("abusers", {
		host_name => $remote_addr,
		pagename  => $script_name,
		querystring => $query_string,
		reason    => $reason,
		-ts   => 'now()',
	});
}

##################################################################
# Check to see if the form already exists
sub checkForm {
	my($self, $formkey, $formname) = @_;
	$self->sqlSelect(
		"value,submit_ts",
		"formkeys", "formkey='$formkey' and formname = '$formname'"
	);
}

##################################################################
# Current admin users
sub currentAdmin {
	my($self) = @_;
	my $aids = $self->sqlSelectAll('nickname,now()-lasttime,lasttitle', 'sessions,users',
		'sessions.uid=users.uid GROUP BY sessions.uid'
	);

	return $aids;
}

########################################################
# Need to change this method at some point... I hate
# useing a push
sub getTopNewsstoryTopics {
	my($self, $all) = @_;
	my $when = "AND to_days(now()) - to_days(time) < 14" unless $all;
	my $order = $all ? "ORDER BY alttext" : "ORDER BY cnt DESC";
	my $topics = $self->sqlSelectAll("topics.tid, alttext, image, width, height, count(*) as cnt","topics,newstories",
		"topics.tid=newstories.tid
		$when
		GROUP BY topics.tid
		$order"
	);

	return $topics;
}

##################################################################
# Get poll
sub getPoll {
	my($self, $qid) = @_;

	my $sth = $self->{_dbh}->prepare_cached("
			SELECT question,answer,aid  from pollquestions, pollanswers
			WHERE pollquestions.qid=pollanswers.qid AND
			pollquestions.qid= " . $self->{_dbh}->quote($qid) . "
			ORDER BY pollanswers.aid
	");
	$sth->execute;
	my $polls = $sth->fetchall_arrayref;
	$sth->finish;

	return $polls;
}

##################################################################
# This should be deletable at this point
#sub getPollComments {
#	my($self, $qid) = @_;
#	my($comments) = $self->sqlSelect('count(*)', 'comments', "sid=" .$self->{_dbh}->quote($qid));
#
#	return $comments;
#}

##################################################################
sub getSubmissionsSections {
	my($self) = @_;
	my $del = getCurrentForm('del');

	my $hash = $self->sqlSelectAll("section,note,count(*)", "submissions WHERE del=$del GROUP BY section,note");

	return $hash;
}

##################################################################
# Get submission count
sub getSubmissionsPending {
	my($self, $uid) = @_;
	my $submissions;

	if ($uid) {
		$submissions = $self->sqlSelectAll("time, subj, section, tid, del", "submissions", "uid=$uid");
	} else {
		$uid = getCurrentUser('uid');
		$submissions = $self->sqlSelectAll("time, subj, section, tid, del", "submissions", "uid=$uid");
	}
	return $submissions;
}

##################################################################
# Get submission count
sub getSubmissionCount {
	my($self, $articles_only) = @_;
	my($count);
	if ($articles_only) {
		($count) = $self->sqlSelect('count(*)', 'submissions',
			"(length(note)<1 or isnull(note)) and del=0" .
			" and section='articles'"
		);
	} else {
		($count) = $self->sqlSelect("count(*)", "submissions",
			"(length(note)<1 or isnull(note)) and del=0"
		);
	}
	return $count;
}

##################################################################
# Get all portals
sub getPortals {
	my($self) = @_;
	# As a side note portal seems to only be a 1 and 0 in
	# in slash's database currently (even though since it
	# is a tinyint it could easily be a negative number).
	# It is a shame we are currently hitting the database
	# for this since the same info can be found in $commonportals
	my $strsql = "SELECT block,title,blocks.bid,url
		   FROM blocks
		  WHERE section='index'
		    AND portal > -1
		  GROUP BY bid
		  ORDER BY ordernum";

	my $sth = $self->{_dbh}->prepare($strsql);
	$sth->execute;
	my $portals = $sth->fetchall_arrayref;

	return $portals;
}

##################################################################
# Get standard portals
sub getPortalsCommon {
	my($self) = @_;
	return($self->{_boxes}, $self->{_sectionBoxes}) if keys %{$self->{_boxes}};
	$self->{_boxes} = {};
	$self->{_sectionBoxes} = {};
	my $sth = $self->sqlSelectMany(
			'bid,title,url,section,portal,ordernum',
			'blocks',
			'',
			'ORDER BY ordernum ASC'
	);
	# We could get rid of tmp at some point
	my %tmp;
	while (my $SB = $sth->fetchrow_hashref) {
		$self->{_boxes}{$SB->{bid}} = $SB;  # Set the Slashbox
		next unless $SB->{ordernum} > 0;  # Set the index if applicable
		push @{$tmp{$SB->{section}}}, $SB->{bid};
	}
	$self->{_sectionBoxes} = \%tmp;
	$sth->finish;

	return($self->{_boxes}, $self->{_sectionBoxes});
}

##################################################################
# counts the number of comments for a user
# This is pretty questionable -Brian
sub countComments {
	my($self, $sid, $cid, $comment, $uid) = @_;
	my $value;
	if ($uid) {
		($value) = $self->sqlSelect("count(*)", "newcomments", "sid=" . $self->{_dbh}->quote($sid) . " AND uid = ". $self->{_dbh}->quote($uid));
	} elsif ($cid) {
		($value) = $self->sqlSelect("count(*)", "newcomments", "sid=" . $self->{_dbh}->quote($sid) . " AND pid = ". $self->{_dbh}->quote($cid));
	} elsif ($comment) {
		($value) = $self->sqlSelect("count(*)", "newcomments", "sid=" . $self->{_dbh}->quote($sid) . ' AND comment=' . $self->{_dbh}->quote($comment));
	} else {
		($value) = $self->sqlSelect("count(*)", "newcomments", "sid=" . $self->{_dbh}->quote($sid));
	}

	return $value;
}

##################################################################
# counts the number of stories
sub countStory {
	my($self, $tid) = @_;
	my($value) = $self->sqlSelect("count(*)", "stories", "tid=" . $self->{_dbh}->quote($tid));

	return $value;
}

##################################################################
sub checkForModerator {	# check for MetaModerator / M2, not Moderator
	my($self, $user) = @_;
	return unless $user->{willing};
	return if $user->{is_anon};
	return if $user->{karma} < 0;
	my($d) = $self->sqlSelect('to_days(now()) - to_days(lastmm)',
		'users_info', "uid = '$user->{uid}'");
	return unless $d;
	my($tuid) = $self->sqlSelect('count(*)', 'users');
	# what to do with I hash here?
	return 1;  # OK to M2
}

##################################################################
sub getAuthorNames {
	my($self) = @_;
	my $authors = $self->getDescriptions('authors');
	my @authors;
	for (values %$authors){
		push @authors, $_;
	}

	return [sort(@authors)];
}

##################################################################
sub refreshStories {
	my($self, $sid) = @_;
	$self->sqlUpdate('stories',
			{ writestatus => 1 },
			'sid=' . $self->{_dbh}->quote($sid) . ' and writestatus=0'
	);
}

##################################################################
# Oranges to Apples. Would it be faster to grab some of this
# data from the cache? Or is it just as fast to grab it from
# the database?
sub getStoryByTime {
	my($self, $sign, $story, $isolate, $section) = @_;
	my($where);
	my $user = getCurrentUser();

	my $order = $sign eq '<' ? 'DESC' : 'ASC';
	if ($isolate) {
		$where = 'AND section=' . $self->{_dbh}->quote($story->{'section'})
			if $isolate == 1;
	} else {
		$where = 'AND displaystatus=0';
	}

	$where .= "   AND tid not in ($user->{'extid'})" if $user->{'extid'};
	$where .= "   AND uid not in ($user->{'exaid'})" if $user->{'exaid'};
	$where .= "   AND section not in ($user->{'exsect'})" if $user->{'exsect'};
	$where .= "   AND sid != '$story->{'sid'}'";

	my $time = $story->{'time'};
	my $returnable = $self->sqlSelectHashref(
			'title, sid, section', 'newstories',
			"time $sign '$time' AND writestatus >= 0 AND time < now() $where",
			"ORDER BY time $order LIMIT 1"
	);

	return $returnable;
}

########################################################
sub countStories {
	my($self) = @_;
	my $stories = $self->sqlSelectAll("sid,title,section,commentcount,uid",
		"stories","", "ORDER BY commentcount DESC LIMIT 10"
	);
	return $stories;
}

########################################################
sub setModeratorVotes {
	my($self, $uid, $metamod) = @_;
	$self->sqlUpdate("users_info",{
		-m2unfairvotes	=> "m2unfairvotes+$metamod->{unfair}",
		-m2fairvotes	=> "m2fairvotes+$metamod->{fair}",
		-lastmm		=> 'now()',
		lastmmid	=> 0
	}, "uid=$uid");
}

########################################################
sub setMetaMod {
	my($self, $m2victims, $flag, $ts) = @_;

	my $constants = getCurrentStatic();
	my $returns = [];

	# Update $muid's Karma
	$self->sqlDo("LOCK TABLES users_info WRITE, metamodlog WRITE");
	for (keys %{$m2victims}) {
		my $muid = $m2victims->{$_}[0];
		my $val = $m2victims->{$_}[1];
		next unless $val;
		push(@$returns , [$muid, $val]);

		my $mmid = $_;
		if ($muid && $val && !$flag) {
			if ($val eq '+') {
				$self->sqlUpdate("users_info", { -m2fair => "m2fair+1" }, "uid=$muid");
				# There is a limit on how much karma you can get from M2.
				$self->sqlUpdate("users_info", { -karma => "karma+1" },
					"$muid=uid and karma<$constants->{m2_maxbonus}");
			} elsif ($val eq '-') {
				$self->sqlUpdate("users_info", { -m2unfair => "m2unfair+1" },
					"uid=$muid");
				$self->sqlUpdate("users_info", { -karma => "karma-1" },
					"$muid=uid and karma>$constants->{badkarma}");
			}
		}
		# Time is now fixed at form submission time to ease 'debugging'
		# of the moderation system, ie 'GROUP BY uid, ts' will give
		# you the M2 votes for a specific user ordered by M2 'session'
		$self->sqlInsert("metamodlog", {
			-mmid => $mmid,
			-uid  => $ENV{SLASH_USER},
			-val  => ($val eq '+') ? 1 : -1,
			-ts   => "from_unixtime($ts)",
			-flag => $flag
		});
	}
	$self->sqlDo("UNLOCK TABLES");

	return $returns;
}

########################################################
sub getModeratorLast {
	my($self, $uid) = @_;
	my $last = $self->sqlSelectHashref(
		"(to_days(now()) - to_days(lastmm)) as lastmm, lastmmid",
		"users_info",
		"uid=$uid"
	);

	return $last;
}

########################################################
# No, this is not API, this is pretty specialized
sub getModeratorLogRandom {
	my($self) = @_;
	my $m2 = getCurrentStatic('m2_comments');
	my($min, $max) = $self->sqlSelect("min(id),max(id)", "moderatorlog");
	return $min + int rand($max - $min - $m2);
}

########################################################
sub countUsers {
	my($self) = @_;
	my($users) = $self->sqlSelect("count(*)", "users");
	return $users;
}

########################################################
sub countStoriesStuff {
	my($self) = @_;
	my $stories = $self->sqlSelectAll("stories.sid,title,section,storiestuff.hits as hits,uid",
		"stories,storiestuff","stories.sid=storiestuff.sid",
		"ORDER BY hits DESC LIMIT 10"
	);
	return $stories;
}

########################################################
sub countStoriesAuthors {
	my($self) = @_;
	my $authors = $self->sqlSelectAll("count(*) as c, uid, fakeemail",
		"stories, users","users.uid=stories.uid",
		"GROUP BY uid ORDER BY c DESC LIMIT 10"
	);
	return $authors;
}

########################################################
sub countPollquestions {
	my($self) = @_;
	my $pollquestions = $self->sqlSelectAll("voters,question,qid", "pollquestions",
		"1=1", "ORDER by voters DESC LIMIT 10"
	);
	return $pollquestions;
}

########################################################
sub saveVars {
#this is almost copied verbatium. Needs to be cleaned up
	my($self) = @_;
	my $form = getCurrentForm();
	my $name = $self->{_dbh}->quote($form->{thisname});
	if ($form->{desc}) {
		my($exists) = $self->sqlSelect('count(*)', 'vars',
			"name=$name"
		);
		if ($exists == 0) {
			$self->sqlInsert('vars', { name => $form->{thisname} });
		}
		$self->sqlUpdate("vars", {
				value		=> $form->{value},
				description	=> $form->{desc},
				datatype	=> $form->{datatype},
				dataop		=> $form->{dataop}
			}, "name=$name"
		);
	} else {
		$self->sqlDo("DELETE from vars WHERE name=$name");
	}
}

########################################################
# I'm not happy with this method at all
sub setCommentCleanup {
	my($self, $val, $sid, $reason, $modreason, $cid) = @_;
	# Grab the user object.
	my $user = getCurrentUser();
	my $constants = getCurrentStatic();
	my($cuid, $ppid, $subj, $points, $oldreason) = $self->getComments($sid, $cid);

	my $strsql = "UPDATE comments SET
		points=points$val,
		reason=$reason,
		lastmod=$user->{uid}
		WHERE sid=" . $self->{_dbh}->quote($sid)."
		AND cid=$cid
		AND points " .
			($val < 0 ? " > $constants->{comment_minscore}" : "") .
			($val > 0 ? " < $constants->{comment_maxscore}" : "");

	$strsql .= " AND lastmod<>$user->{uid}"
		unless $user->{seclev} > 99 && $constants->{authors_unlimited};

	if ($val ne "+0" && $self->sqlDo($strsql)) {
		$self->setModeratorLog($cid, $sid, $user->{uid}, $modreason, $val);

		# copy to comments cache
		my $copyline = "replace into newcomments select * from comments where cid = $cid";
		$copyline .= " and sid = " .  $self->{_dbh}->quote($sid);

		$self->sqlDo($copyline);

		# Adjust comment posters karma
		if ($cuid != $constants->{anonymous_coward}) {
			if ($val > 0) {
				$self->sqlUpdate("users_info", {
						-karma	=> "karma$val",
						-upmods	=> 'upmods+1',
					}, "uid=$cuid AND karma < $constants->{maxkarma}"
				);
			} elsif ($val < 0) {
				$self->sqlUpdate("users_info", {
						-karma		=> "karma$val",
						-downmods	=> 'downmods+1',
					}, "uid=$cuid AND karma > $constants->{minkarma}"
				);
			}
		}

		# Adjust moderators total mods
		$self->sqlUpdate(
			"users_info",
			{ -totalmods => 'totalmods+1' },
			"uid=$user->{uid}"
		);

		# And deduct a point.
		$user->{points} = $user->{points} > 0 ? $user->{points} - 1 : 0;
		$self->sqlUpdate(
			"users_comments",
			{ -points=>$user->{points} },
			"uid=$user->{uid}"
		); 
		return 1;
	}
	return;
}

########################################################
sub countUsersIndexExboxesByBid {
	my($self, $bid) = @_;
	my($count) = $self->sqlSelect("count(*)", "users_index",
		qq!exboxes like "%'$bid'%" !
	);

	return $count;
}

########################################################
sub getCommentReply {
	my($self, $sid, $pid) = @_;
	my $reply = $self->sqlSelectHashref("date, subject,newcomments.points as points,
		comment,realname,nickname,
		fakeemail,homepage,cid,sid,users.uid as uid",
		"newcomments,users,users_info,users_comments",
		"sid=" . $self->{_dbh}->quote($sid) . "
		AND cid=" . $self->{_dbh}->quote($pid) . "
		AND users.uid=users_info.uid
		AND users.uid=users_comments.uid
		AND users.uid=newcomments.uid"
	) || {};

	formatDate([$reply]);
	return $reply;
}

########################################################
sub getCommentsForUser {
	my($self, $sid, $cid) = @_;
	my $user = getCurrentUser();
	my $form = getCurrentForm();
	my $sql = "SELECT cid,date,
				subject,comment,
				nickname,homepage,fakeemail,
				users.uid as uid,sig,
				newcomments.points as points,pid,sid,
				lastmod, reason
			   FROM newcomments,users
			  WHERE sid=" . $self->{_dbh}->quote($sid) . "
			    AND newcomments.uid=users.uid";
	$sql .= "	    AND (";
	$sql .= "		newcomments.uid=$user->{uid} OR " unless $user->{is_anon};
	$sql .= "		cid=$cid OR " if $cid;
	$sql .= "		newcomments.points >= " . $self->{_dbh}->quote($user->{threshold}) . " OR " if $user->{hardthresh};
	$sql .= "		  1=1 )   ";
	$sql .= "	  ORDER BY ";
	$sql .= "newcomments.points DESC, " if $user->{commentsort} eq '3';
	$sql .= " cid ";
	$sql .= ($user->{commentsort} == 1 || $user->{commentsort} == 5) ? 'DESC' : 'ASC';


	my $thisComment = $self->{_dbh}->prepare_cached($sql) or errorLog($sql);
	$thisComment->execute or errorLog($sql);
	my $comments = [];
	while (my $comment = $thisComment->fetchrow_hashref){
		push @$comments, $comment;
	}
	formatDate($comments);
	return $comments;
}

########################################################
sub getComments {
	my($self, $sid, $cid) = @_;
	$self->sqlSelect("uid,pid,subject,points,reason",
		"newcomments", "cid=$cid and sid='$sid'"
	);
}

########################################################
# Do we need to bother passing in User and Form?
sub getStories {
	my($self, $section, $limit, $tid) = @_;

	my $user = getCurrentUser();
	my $form = getCurrentForm();

	$limit ||= $user->{currentSection} eq 'index'
		? $user->{maxstories} : $self->getSection($section, 'artcount');

	my $tables = 'newstories';
	my $columns = 'sid, section, title, time, commentcount, time, hitparade';

	my $where = "1=1 AND time<now() "; # Mysql's Optimize gets 1 = 1";
	$where .= "AND displaystatus=0 " unless $form->{section};
	$where .= "AND (displaystatus>=0 AND section='$section') " if $form->{section};
	$where .= "AND tid='$tid' " if $tid;

	# User Config Vars
	$where .= "AND tid not in ($user->{extid}) "		if $user->{extid};
	$where .= "AND uid not in ($user->{exaid}) "		if $user->{exaid};
	$where .= "AND section not in ($user->{exsect}) "	if $user->{exsect};

	# Order
	my $other = "ORDER BY time DESC ";

	# We need to check up on this later for performance -Brian
	my(@stories, $count);
	my $cursor = $self->sqlSelectMany($columns, $tables, $where, $other)
		or errorLog("error in getStories columns $columns table $tables where $where other $other");

	while (my(@data) = $cursor->fetchrow) {
		formatDate([\@data], 3, 3, '%A %B %d %I %M %p');
		formatDate([\@data], 5, 5, '%Q');
		next if $form->{issue} && $data[5] > $form->{issue};
		push @stories, [@data];
		last if ++$count >= $limit;
	}

	return \@stories;
}

########################################################
sub getCommentsTop {
	my($self, $sid) = @_;
	my $user = getCurrentUser();
	my $where = "stories.sid=newcomments.sid";
	$where .= " AND stories.sid=" . $self->{_dbh}->quote($sid) if $sid;
	my $stories = $self->sqlSelectAll("section, stories.sid, uid, title, pid, subject,"
		. "date, time, uid, cid, points"
		, "stories, newcomments"
		, $where
		, " ORDER BY points DESC, d DESC LIMIT 10 ");

	formatDate($stories, 'date', 'd');
	formatDate($stories, 'time', 't');
	return $stories;
}

########################################################
# This makes me nervous... we grab, and they get
# deleted? I may move the delete to the setQuickies();
sub getQuickies {
	my($self) = @_;
# This is doing nothing (unless I am just missing the point). We grab
# them and then null them? -Brian
#  my($stuff) = $self->sqlSelect("story", "submissions", "subid='quickies'");
#	$stuff = "";
	$self->sqlDo("DELETE FROM submissions WHERE subid='quickies'");
	my $stuff;

	my $submission = $self->sqlSelectAll("subid,subj,email,name,story",
		"submissions", "note='Quik' and del=0"
	);

	return $submission;
}

########################################################
sub setQuickies {
	my($self, $content) = @_;
	$self->sqlInsert("submissions", {
		subid	=> 'quickies',
		subj	=> 'Generated Quickies',
		email	=> '',
		name	=> '',
		-'time'	=> 'now()',
		section	=> 'articles',
		tid	=> 'quickies',
		story	=> $content,
		uid	=> getCurrentStatic('anonymous_coward_uid'),
	});
}

########################################################
# What an ugly method
sub getSubmissionForUser {
	my($self) = @_;
	my $form = getCurrentForm();
	my $user = getCurrentUser();

	my $sql = "SELECT subid,subj,time,tid,note,email,name,section,comment,submissions.uid,karma FROM submissions,users_info";
	$sql .= "  WHERE submissions.uid=users_info.uid AND $form->{del}=del AND (";
	$sql .= $form->{note} ? "note=" . $self->{_dbh}->quote($form->{note}) : "isnull(note)";
	$sql .= "		or note=' ' " unless $form->{note};
	$sql .= ")";
	$sql .= "		and tid='$form->{tid}' " if $form->{tid};
	$sql .= "         and section=" . $self->{_dbh}->quote($user->{section}) if $user->{section};
	$sql .= "         and section=" . $self->{_dbh}->quote($form->{section}) if $form->{section};
	$sql .= "	  ORDER BY time";

	my $cursor = $self->{_dbh}->prepare($sql);
	$cursor->execute;

	my $submission = $cursor->fetchall_arrayref;

	formatDate($submission, 2, 2, '%m/%d  %H:%M');

	return $submission;
}


########################################################
sub getNewstoryTitle {
	my($self, $storyid, $sid) = @_;
	my($title) = $self->sqlSelect("title", "newstories",
	      "sid=" . $self->{_dbh}->quote($sid)
	);

	return $title;
}


########################################################
sub getTrollAddress {
	my($self) = @_;
	my($badIP) = $self->sqlSelect("sum(val)","newcomments,moderatorlog",
			"newcomments.sid=moderatorlog.sid AND newcomments.cid=moderatorlog.cid
			AND host_name='$ENV{REMOTE_ADDR}' AND moderatorlog.active=1
			AND (to_days(now()) - to_days(ts) < 3) GROUP BY host_name"
	);

	return $badIP;
}

########################################################
sub getTrollUID {
	my($self) = @_;
	my $user = getCurrentUser();
	my($badUID) = $self->sqlSelect("sum(val)","newcomments,moderatorlog",
		"newcomments.sid=moderatorlog.sid AND newcomments.cid=moderatorlog.cid
		AND newcomments.uid=$user->{uid} AND moderatorlog.active=1
		AND (to_days(now()) - to_days(ts) < 3)  GROUP BY newcomments.uid"
	);

	return $badUID;
}

########################################################
sub setCommentCount {
	my($self, $delCount) = @_;
	my $form =  getCurrentForm();
	$self->sqlDo("UPDATE stories SET commentcount=commentcount-$delCount,
	      writestatus=1 WHERE sid=" . $self->{_dbh}->quote($form->{sid})
	);
}

########################################################
sub saveStory {
	my($self) = @_;
	my $form = getCurrentForm();
	my $constants = getCurrentStatic();
	$self->sqlInsert('storiestuff', { sid => $form->{sid} });
	$self->sqlInsert('discussions', {
		sid	=> $form->{sid},
		title	=> $form->{title},
		ts	=> $form->{'time'},
		url	=> "$constants->{rootdir}/article.pl?sid=$form->{sid}"
	});


	# If this came from a submission, update submission and grant
	# Karma to the user
	my $suid;
	if ($form->{subid}) {
		my($suid) = $self->sqlSelect(
			'uid','submissions',
			'subid=' . $self->{_dbh}->quote($form->{subid})
		);

		# i think i got this right -- pudge
 		my($userkarma) = $self->sqlSelect('karma', 'users_info', "uid=$suid");
 		my $newkarma = (($userkarma + $constants->{submission_bonus})
 			> $constants->{maxkarma})
 				? $constants->{maxkarma}
 				: "karma+$constants->{submission_bonus}";
 		$self->sqlUpdate('users_info', { -karma => $newkarma }, "uid=$suid")
 			if $suid != $constants->{anonymous_coward_uid};

		$self->sqlUpdate('users_info',
			{ -karma => 'karma + 3' },
			"uid=$suid"
		) if $suid != $constants->{anonymous_coward_uid};

		$self->sqlUpdate('submissions',
			{ del=>2 },
			'subid=' . $self->{_dbh}->quote($form->{subid})
		);
	}

	$self->sqlInsert('stories',{
		sid		=> $form->{sid},
		uid		=> $form->{uid},
		tid		=> $form->{tid},
		dept		=> $form->{dept},
		'time'		=> $form->{'time'},
		title		=> $form->{title},
		section		=> $form->{section},
		bodytext	=> $form->{bodytext},
		introtext	=> $form->{introtext},
		writestatus	=> $form->{writestatus},
		relatedtext	=> $form->{relatedtext},
		displaystatus	=> $form->{displaystatus},
		commentstatus	=> $form->{commentstatus}
	});
	$self->saveExtras($form);
}

########################################################
# Now, the idea is to not cache here, since we actually
# cache elsewhere (namely in %Slash::Apache::constants)
# Getting populated with my info for the moment
sub getSlashConf {
	my($self) = @_;
	my %conf; # We are going to populate this and return a reference
	my @keys = qw(
		absolutedir
		admin_timeout
		adminmail
		allow_anonymous
		anonymous_coward_uid
		approvedtags
		archive_delay
		articles_only
		authors_unlimited
		badkarma
		basedir
		basedomain
		block_expire
		breaking
		cache_enabled
		comment_maxscore
		comment_minscore
		cookiedomain
		cookiepath
		datadir
		defaultsection
		down_moderations
		fancyboxwidth
		fontbase
		formkey_timeframe
		goodkarma
		http_proxy
		imagedir
		logdir
		m2_bonus
		m2_comments
		m2_maxbonus
		m2_maxunfair
		m2_mincheck
		m2_penalty
		m2_toomanyunfair
		m2_userpercentage
		mailfrom
		mainfontface
		max_depth
		max_posts_allowed
		max_submissions_allowed
		maxkarma
		maxkarma
		maxpoints
		maxtokens
		metamod_sum
		post_limit
		rdfencoding
		rdfimg
		rdfimg
		rdflanguage
		rootdir
		run_ads
		sbindir
		send_mail
		siteadmin
		siteadmin_name
		sitename
		siteowner
		slogan
		slashdir
		smtp_server
		stats_reports
		stir
		story_expire
		submiss_ts
		submiss_view
		submission_bonus
		submission_speed_limit
		submit_categories
		titlebar_width
		tokenspercomment
		tokensperpoint
		updatemin
		use_dept
	);

	# This should be optimized.
	for (@keys) {
		my $value = $self->getVar($_, 'value');
		$conf{$_} = $value;
	}

	$conf{rootdir}		||= "http://$conf{basedomain}";
	$conf{absolutedir}	||= $conf{rootdir};
	$conf{basedir}		||= $conf{datadir} . "/public_html";
	$conf{imagedir}		||= "$conf{rootdir}/images";
	$conf{rdfimg}		||= "$conf{imagedir}/topics/topicslash.gif";
	$conf{cookiepath}	||= URI->new($conf{rootdir})->path . '/';
	$conf{maxkarma}		= 999  unless defined $conf{maxkarma};
	$conf{minkarma}		= -999 unless defined $conf{minkarma};

	$conf{m2_mincheck} = defined($conf{m2_mincheck})
				? $conf{m2_mincheck}
				: int $conf{m2_comments} / 3;

	if (!$conf{m2_maxbonus} || $conf{m2_maxbonus} > $conf{maxkarma}) {
		$conf{m2_maxbonus} = int $conf{goodkarma} / 2;
	}

	$conf{fixhrefs} = [];  # fix later
	$conf{stats_reports} = eval $conf{stats_reports}
		|| { $conf{adminmail} => "$conf{sitename} Stats Report" };

	$conf{submit_categories} = eval $conf{submit_categories}
		|| [];

	$conf{approvedtags} = eval $conf{approvedtags}
		|| [qw(B I P A LI OL UL EM BR TT STRONG BLOCKQUOTE DIV)];

	$conf{reasons} = [
		'Normal',	# "Normal"
		'Offtopic',	# Bad Responses
		'Flamebait',
		'Troll',
		'Redundant',
		'Insightful',	# Good Responses
		'Interesting',
		'Informative',
		'Funny',
		'Overrated',	# The last 2 are "Special"
		'Underrated'
	];

	$conf{badreasons} = 4;	# number of "Bad" reasons in @{$constants->{reasons}},
				# skip 0 (which is neutral)
	return \%conf;
}

##################################################################
sub autoUrl {
	my $self = shift;
	my $section = shift;
	local $_ = join ' ', @_;
	my $user = getCurrentUser();
	my $form = getCurrentForm();

	s/([0-9a-z])\?([0-9a-z])/$1'$2/gi if $form->{fixquotes};
	s/\[(.*?)\]/linkNode($1)/ge if $form->{autonode};

	my $initials = substr $user->{nickname}, 0, 1;
	my $more = substr $user->{nickname}, 1;
	$more =~ s/[a-z]//g;
	$initials = uc($initials . $more);
	my($now) = $self->sqlSelect('date_format(now(),"m/d h:i p")');

	# Assorted Automatic Autoreplacements for Convenience
	s|<disclaimer:(.*)>|<B><A HREF="/about.shtml#disclaimer">disclaimer</A>:<A HREF="$user->{url}">$user->{nickname}</A> owns shares in $1</B>|ig;
	s|<update>|<B>Update: <date></B> by <author>|ig;
	s|<date>|$now|g;
	s|<author>|<B><A HREF="$user->{url}">$initials</A></B>:|ig;
	s/\[%(.*?)%\]/$self->getUrlFromTitle($1)/exg;

	# Assorted ways to add files:
	s|<import>|importText()|ex;
	s/<image(.*?)>/importImage($section)/ex;
	s/<attach(.*?)>/importFile($section)/ex;
	return $_;
}

##################################################################
# autoUrl & Helper Functions
# Image Importing, Size checking, File Importing etc
sub getUrlFromTitle {
	my($self, $title) = @_;
	my($sid) = $self->sqlSelect('sid', 'stories',
		qq[title like "\%$title%"],
		'order by time desc LIMIT 1'
	);
	my $rootdir = getCurrentStatic('rootdir');
	return "$rootdir/article.pl?sid=$sid";
}

##################################################################
# Should this really be in here?
sub getTime {
	my($self) = @_;
	my($now) = $self->sqlSelect('now()');

	return $now;
}

##################################################################
# Should this really be in here? -- krow
# dunno ... sigh, i am still not sure this is best
# (see getStories()) -- pudge
sub getDay {
#	my($self) = @_;	
#	my($now) = $self->sqlSelect('to_days(now())');
	my $yesterday = timeCalc('epoch ' . time, '%Q');
	return $yesterday;
}

##################################################################
sub getStoryList {
	my($self) = @_;

	my $user = getCurrentUser();
	my $form = getCurrentForm();

	my $sql = q[SELECT storiestuff.hits, commentcount, stories.sid, title, uid,
			date_format(time,"%k:%i") as t,tid,section,
			displaystatus,writestatus,
			date_format(time,"%W %M %d"),
			date_format(time,"%m/%d")
			FROM stories,storiestuff
			WHERE storiestuff.sid=stories.sid];
	$sql .= "	AND section='$user->{section}'" if $user->{section};
	$sql .= "	AND section='$form->{section}'" if $form->{section} && !$user->{section};
	$sql .= "	AND time < DATE_ADD(now(), interval 72 hour) " if $form->{section} eq "";
	$sql .= "	ORDER BY time DESC";

	my $cursor = $self->{_dbh}->prepare($sql);
	$cursor->execute;
	my $list = $cursor->fetchall_arrayref;

	return $list;
}

##################################################################
sub updateStory {
	my($self) = @_;
	my $form = getCurrentForm();
	my $constants = getCurrentStatic();
	$self->sqlUpdate('discussions',{
			sid	=> $form->{sid},
			title	=> $form->{title},
			url	=> "$constants->{rootdir}/article.pl?sid=$form->{sid}",
			ts	=> $form->{'time'},
		},
		'sid = ' . $self->{_dbh}->quote($form->{sid})
	);

	$self->sqlUpdate('stories', {
			uid		=> $form->{uid},
			tid		=> $form->{tid},
			dept		=> $form->{dept},
			'time'		=> $form->{'time'},
			title		=> $form->{title},
			section		=> $form->{section},
			bodytext	=> $form->{bodytext},
			introtext	=> $form->{introtext},
			writestatus	=> $form->{writestatus},
			relatedtext	=> $form->{relatedtext},
			displaystatus	=> $form->{displaystatus},
			commentstatus	=> $form->{commentstatus}
		}, 'sid=' . $self->{_dbh}->quote($form->{sid})
	);

	$self->sqlDo('UPDATE stories SET time=now() WHERE sid='
		. $self->{_dbh}->quote($form->{sid})
	) if $form->{fastforward} eq 'on';
	$self->saveExtras($form);
}

##################################################################
sub getPollVotesMax {
	my($self, $id) = @_;
	my($answer) = $self->sqlSelect("max(votes)", "pollanswers", "qid=" . $self->{_dbh}->quote($id));
	return $answer;
}

##################################################################
# Probably should make this private at some point
sub saveExtras {
	my($self, $form) = @_;
	return unless $self->sqlTableExists($form->{section});
	my @extras = $self->sqlSelectColumns($form->{section});
	my $E;

	foreach (@extras) { $E->{$_} = $form->{$_} }

	if ($self->sqlUpdate($form->{section}, $E, "sid='$form->{sid}'") eq '0E0') {
		$self->sqlInsert($form->{section}, $E);
	}
}

########################################################
sub getStory {
	my($self) = @_;
	# We need to expire stories
	_genericCacheRefresh($self, 'stories', getCurrentStatic('story_expire'));
	my $answer = _genericGetCache('stories', 'sid', @_);

	return $answer;
}

########################################################
sub getAuthor {
	my($self, $id, $values, $cache_flag) = @_;
	my $table = 'authors';
	my $table_cache = '_' . $table . '_cache';
	my $table_cache_time= '_' . $table . '_cache_time';

	my $type;
	if (ref($values) eq 'ARRAY') {
		$type = 0;
	} else {
		$type  = $values ? 1 : 0;
	}

	if ($type) {
		return $self->{$table_cache}{$id}{$values}
			if (keys %{$self->{$table_cache}{$id}} and !$cache_flag);
	} else {
		if (keys %{$self->{$table_cache}{$id}} && !$cache_flag) {
			my %return = %{$self->{$table_cache}{$id}};
			return \%return;
		}
	}

	# Lets go knock on the door of the database
	# and grab the data's since it is not cached
	# On a side note, I hate grabbing "*" from a database
	# -Brian
	$self->{$table_cache}{$id} = {};
	my $answer = $self->sqlSelectHashref('users.uid as uid,nickname,fakeemail,bio', 
		'users,users_info', 'users.uid=' . $self->{_dbh}->quote($id) . ' AND users.uid = users_info.uid');
	$self->{$table_cache}{$id} = $answer;

	$self->{$table_cache_time} = time();

	if ($type) {
		return $self->{$table_cache}{$id}{$values};
	} else {
		if ($self->{$table_cache}{$id}) {
			my %return = %{$self->{$table_cache}{$id}};
			return \%return;
		} else {
			return;
		}
	}
}

########################################################
# This of course is modified from the norm
sub getAuthors {
	my($self, $cache_flag) = @_;

	my $table = 'authors';
	my $table_cache= '_' . $table . '_cache';
	my $table_cache_time= '_' . $table . '_cache_time';
	my $table_cache_full= '_' . $table . '_cache_full';

	if (keys %{$self->{$table_cache}} && $self->{$table_cache_full} && !$cache_flag) {
		my %return = %{$self->{$table_cache}};
		return \%return;
	}

	$self->{$table_cache} = {};
	my $sth = $self->sqlSelectMany('uid,nickname,fakeemail', 'users', 'seclev >= 99');
	while (my $row = $sth->fetchrow_hashref) {
		$self->{$table_cache}{ $row->{'uid'} } = $row;
	}

	$self->{$table_cache_full} = 1;
	$sth->finish;
	$self->{$table_cache_time} = time();

	my %return = %{$self->{$table_cache}};
	return \%return;
}

########################################################
sub getPollQuestion {
	my $answer = _genericGet('pollquestions', 'qid', @_);
	return $answer;
}

########################################################
sub getBlock {
	my($self) = @_;
	_genericCacheRefresh($self, 'blocks', getCurrentStatic('block_expire'));
	my $answer = _genericGetCache('blocks', 'bid', @_);
	return $answer;
}

########################################################
sub getTemplate {
	my($self) = @_;
	_genericCacheRefresh($self, 'templates', getCurrentStatic('block_expire'));
	my $answer = _genericGetCache('templates', 'tpid', @_);
	return $answer;
}

########################################################
sub getTopic {
	my $answer = _genericGetCache('topics', 'tid', @_);
	return $answer;
}

########################################################
sub getTopics {
	my $answer = _genericGetsCache('topics', 'tid', @_);
	return $answer;
}

########################################################
sub getContentFilter {
	my $answer = _genericGet('content_filters', 'filter_id', @_);
	return $answer;
}

########################################################
sub getSubmission {
	my $answer = _genericGet('submissions', 'subid', @_);
	return $answer;
}

########################################################
sub getSection {
	my $answer = _genericGetCache('sections', 'section', @_);
	return $answer;
}

########################################################
sub getSections {
	my $answer = _genericGetsCache('sections', 'section', @_);
	return $answer;
}

########################################################
sub getModeratorLog {
	my $answer = _genericGet('moderatorlog', 'id', @_);
	return $answer;
}

########################################################
sub getNewStory {
	my $answer = _genericGet('newstories', 'sid', @_);
	return $answer;
}

########################################################
sub getVar {
	my $answer = _genericGet('vars', 'name', @_);
	return $answer;
}

########################################################
sub setUser {
	my($self, $uid, $hashref) = @_;
	my(@param, %update_tables, $cache);
	my $tables = [qw(
		users users_comments users_index
		users_info users_prefs
	)];

	# special cases for password, exboxes
	if (exists $hashref->{passwd}) {
		# get rid of newpasswd if defined in DB
		$hashref->{newpasswd} = '';
		$hashref->{passwd} = encryptPassword($hashref->{passwd});
	}

	# hm, come back to exboxes later -- pudge
	if (0 && exists $hashref->{exboxes}) {
		if (ref $hashref->{exboxes} eq 'ARRAY') {
			$hashref->{exboxes} = sprintf("'%s'", join "','", @{$hashref->{exboxes}});
		} elsif (ref $hashref->{exboxes}) {
			$hashref->{exboxes} = '';
		} # if nonref scalar, just let it pass
	}

	$cache = _genericGetCacheName($self, $tables);

	for (keys %$hashref) {
		(my $clean_val = $_) =~ s/^-//;
		my $key = $self->{$cache}{$clean_val};
		if ($key) {
			push @{$update_tables{$key}}, $_;
		} else {
			push @param, [$_, $hashref->{$_}];
		}
	}

	for my $table (keys %update_tables) {
		my %minihash;
		for my $key (@{$update_tables{$table}}){
			$minihash{$key} = $hashref->{$key}
				if defined $hashref->{$key};
		}
		$self->sqlUpdate($table, \%minihash, 'uid=' . $uid, 1);
	}
	# What is worse, a select+update or a replace?
	# I should look into that.
	for (@param)  {
		$self->sqlDo("REPLACE INTO users_param values ('', $uid, '$_->[0]', '$_->[1]')");
	}
}

########################################################
# Now here is the thing. We want getUser to look like
# a generic, despite the fact that it is not :)
sub getUser {
	my($self, $id, $val) = @_;
	my $answer;
	my $tables = [qw(
		users users_comments users_index
		users_info users_prefs
	)];
	# The sort makes sure that someone will always get the cache if
	# they have the same tables
	my $cache = _genericGetCacheName($self, $tables);

	if (ref($val) eq 'ARRAY') {
		my($values, %tables, @param, $where, $table);
		for (@$val) {
			(my $clean_val = $_) =~ s/^-//;
			if ($self->{$cache}{$clean_val}) {
				$tables{$self->{$cache}{$_}} = 1;
				$values .= "$_,";
			} else {
				push @param, $_;
			}
		}
		chop($values);

		for (keys %tables) {
			$where .= "$_.uid=$id AND ";
		}
		$where =~ s/ AND $//;

		$table = join ',', keys %tables;
		$answer = $self->sqlSelectHashref($values, $table, $where);
		for (@param) {
			my $val = $self->sqlSelect('value', 'users_param', "uid=$id AND name='$_'");
			$answer->{$_} = $val;
		}

	} elsif ($val) {
		(my $clean_val = $val) =~ s/^-//;
		my $table = $self->{$cache}{$clean_val};
		if ($table) {
			($answer) = $self->sqlSelect($val, $table, "uid=$id");
		} else {
			($answer) = $self->sqlSelect('value', 'users_param', "uid=$id AND name='$val'");
		}

	} else {
		my($where, $table, $append);
		for (@$tables) {
			$where .= "$_.uid=$id AND ";
		}
		$where =~ s/ AND $//;

		$table = join ',', @$tables;
		$answer = $self->sqlSelectHashref('*', $table, $where);
		$append = $self->sqlSelectAll('name,value', 'users_param', "uid=$id");
		for (@$append) {
			$answer->{$_->[0]} = $_->[1];
		}
	}

	return $answer;
}

########################################################
# This could be optimized by not making multiple calls
# to getKeys or by fixing getKeys() to return multiple
# values
sub _genericGetCacheName {
	my($self, $tables) = @_;
	my $cache = '_' . join ('_', sort(@$tables), 'cache');
	unless (keys %{$self->{$cache}}) {
		for my $table (@$tables) {
			my $keys = $self->getKeys($table);
			for (@$keys) {
				$self->{$cache}{$_} = $table;
			}
		}
	}
	return $cache;
}

########################################################
# Now here is the thing. We want setUser to look like
# a generic, despite the fact that it is not :)
# We assum most people called set to hit the database
# and just not the cache (if one even exists)
sub _genericSet {
	my($table, $table_prime, $self, $id, $value) = @_;
	$self->sqlUpdate($table, $value, $table_prime . '=' . $self->{_dbh}->quote($id));

	my $table_cache= '_' . $table . '_cache';
	return unless (keys %{$self->{$table_cache}});
	my $table_cache_time= '_' . $table . '_cache_time';
	$self->{$table_cache_time} = time();
	for (keys %$value) {
		$self->{$table_cache}{$id}{$_} = $value->{$_};
	}
}

########################################################
# You can use this to reset cache's in a timely
# manner :)
sub _genericCacheRefresh {
	my($self, $table,  $expiration) = @_;
	return unless $expiration;
	my $table_cache = '_' . $table . '_cache';
	my $table_cache_time = '_' . $table . '_cache_time';
	my $table_cache_full = '_' . $table . '_cache_full';
	return unless $self->{$table_cache_time};
	my $time = time();
	my $diff = $time - $self->{$table_cache_time};

	if ($diff > $expiration) {
	print STDERR "TIME:$diff:$expiration:$time:$self->{$table_cache_time}:\n";
		$self->{$table_cache} = {};
		$self->{$table_cache_time} = 0;
		$self->{$table_cache_full} = 0;
	}
}

########################################################
# This is protected and don't call it from your
# scripts directly.
sub _genericGetCache {
	return _genericGet(@_) unless getCurrentStatic('cache_enabled');

	my($table, $table_prime, $self, $id, $values, $cache_flag) = @_;
	my $table_cache = '_' . $table . '_cache';
	my $table_cache_time= '_' . $table . '_cache_time';

	my $type;
	if (ref($values) eq 'ARRAY') {
		$type = 0;
	} else {
		$type  = $values ? 1 : 0;
	}

	if ($type) {
		return $self->{$table_cache}{$id}{$values}
			if (keys %{$self->{$table_cache}{$id}} and !$cache_flag);
	} else {
		if (keys %{$self->{$table_cache}{$id}} && !$cache_flag) {
			my %return = %{$self->{$table_cache}{$id}};
			return \%return;
		}
	}

	# Lets go knock on the door of the database
	# and grab the data's since it is not cached
	# On a side note, I hate grabbing "*" from a database
	# -Brian
	$self->{$table_cache}{$id} = {};
	my $answer = $self->sqlSelectHashref('*', $table, "$table_prime=" . $self->{_dbh}->quote($id));
	$self->{$table_cache}{$id} = $answer;

	$self->{$table_cache_time} = time();

	if ($type) {
		return $self->{$table_cache}{$id}{$values};
	} else {
		if ($self->{$table_cache}{$id}) {
			my %return = %{$self->{$table_cache}{$id}};
			return \%return;
		} else {
			return;
		}
	}
}

########################################################
# This is protected and don't call it from your
# scripts directly.
sub _genericClearCache {
	my($table, $self) = @_;
	my $table_cache= '_' . $table . '_cache';

	$self->{$table_cache} = {};
}

########################################################
# This is protected and don't call it from your
# scripts directly.
sub _genericGet {
	my($table, $table_prime, $self, $id, $val) = @_;
	my($answer, $type);
	my $id_db = $self->{_dbh}->quote($id);

	if (ref($val) eq 'ARRAY') {
		my $values = join ',', @$val;
		$answer = $self->sqlSelectHashref($values, $table, "$table_prime=$id_db");
	} elsif ($val) {
		($answer) = $self->sqlSelect($val, $table, "$table_prime=$id_db");
	} else {
		$answer = $self->sqlSelectHashref('*', $table, "$table_prime=$id_db");
	}

	return $answer;
}

########################################################
# This is protected and don't call it from your
# scripts directly.
sub _genericGetsCache {
	return _genericGets(@_) unless getCurrentStatic('cache_enabled');

	my($table, $table_prime, $self, $cache_flag) = @_;
	my $table_cache= '_' . $table . '_cache';
	my $table_cache_time= '_' . $table . '_cache_time';
	my $table_cache_full= '_' . $table . '_cache_full';

	if (keys %{$self->{$table_cache}} && $self->{$table_cache_full} && !$cache_flag) {
		my %return = %{$self->{$table_cache}};
		return \%return;
	}

	# Lets go knock on the door of the database
	# and grab the data since it is not cached
	# On a side note, I hate grabbing "*" from a database
	# -Brian
	$self->{$table_cache} = {};
	my $sth = $self->sqlSelectMany('*', $table);
	while (my $row = $sth->fetchrow_hashref) {
		$self->{$table_cache}{ $row->{$table_prime} } = $row;
	}
	$self->{$table_cache_full} = 1;
	$sth->finish;
	$self->{$table_cache_time} = time();

	my %return = %{$self->{$table_cache}};
	return \%return;
}

########################################################
# This is protected and don't call it from your
# scripts directly.
sub _genericGets {
	my($table, $table_prime, $self) = @_;

	# Lets go knock on the door of the database
	# and grab the data since it is not cached
	# On a side note, I hate grabbing "*" from a database
	# -Brian
	my %return;
	my $sth = $self->sqlSelectMany('*', $table);
	while (my $row = $sth->fetchrow_hashref) {
		$return{ $row->{$table_prime} } = $row;
	}
	$sth->finish;

	return \%return;
}
########################################################
sub createBlock {
	my($self, $hash) = @_;
	$self->sqlInsert('blocks', $hash);
}

########################################################
sub createTemplate {
	my($self, $hash) = @_;
	$self->sqlInsert('blocks', $hash);
}

########################################################
sub createMenuItem {
	my($self, $hash) = @_;
	$self->sqlInsert('menus', $hash);
}

########################################################
sub getMenuItems {
	my($self, $script) = @_;
	my $sql = "SELECT * FROM menus WHERE page=" . $self->{_dbh}->quote($script) . "ORDER by menuorder";
	my $sth = $self->{_dbh}->prepare($sql);
	$sth->execute();
	my(@menu, $row);
	push(@menu, $row) while ($row = $sth->fetchrow_hashref);
	$sth->finish;

	return \@menu;
}

########################################################
sub getMenus {
	my($self) = @_;

	my $sql = "SELECT DISTINCT menu FROM menus ORDER BY menu";
	my $sth = $self->{_dbh}->prepare($sql);
	$sth->execute;
	my $menu_names = $sth->fetchall_arrayref;
	$sth->finish;

	my $menus;
	for (@$menu_names) {
		my $script = $_->[0];
		$sql = "SELECT * FROM menus WHERE menu=" . $self->{_dbh}->quote($script) . "ORDER by menuorder";
		$sth =	$self->{_dbh}->prepare($sql);
		$sth->execute();
		my(@menu, $row);
		push(@menu, $row) while ($row = $sth->fetchrow_hashref);
		$sth->finish;
		$menus->{$script} = \@menu;
	}

	return $menus;
}

########################################################
sub sqlReplace {
	my($self, $table, $data) = @_;
	my($names, $values);

	foreach (keys %$data) {
		if (/^-/) {
			$values .= "\n  $data->{$_},";
			s/^-//;
		} else {
			$values .= "\n  " . $self->{_dbh}->quote($data->{$_}) . ',';
		}
		$names .= "$_,";
	}

	chop($names);
	chop($values);

	my $sql = "REPLACE INTO $table ($names) VALUES($values)\n";
	$self->sqlConnect();
	return $self->sqlDo($sql) or errorLog($sql);
}

##################################################################
# This should be rewritten so that at no point do we
# pass along an array -Brian
sub getKeys {
	my($self, $table) = @_;
	my @keys = $self->sqlSelectColumns($table)
		if $self->sqlTableExists($table);

	return \@keys;
}

########################################################
sub sqlTableExists {
	my($self, $table) = @_;
	return unless $table;

	my $sth = $self->{_dbh}->prepare_cached(qq!SHOW TABLES LIKE "$table"!);
	$self->sqlConnect();
	$sth->execute;
	my $te = $sth->rows;
	$sth->finish;
	return $te;
}

########################################################
sub sqlSelectColumns {
	my($self, $table) = @_;
	return unless $table;

	my $sth = $self->{_dbh}->prepare_cached("SHOW COLUMNS FROM $table");
	$self->sqlConnect();
	$sth->execute;
	my @ret;
	while (my @d = $sth->fetchrow) {
		push @ret, $d[0];
	}
	$sth->finish;
	return @ret;
}

########################################################
# Get a unique string for an admin session
sub generatesession {
	my $newsid = crypt(rand(99999), $_[0]);
	$newsid =~ s/[^A-Za-z0-9]//i;

	return $newsid;
}

1;

__END__

=head1 NAME

Slash::DB::MySQL - MySQL Interface for Slashcode

=head1 SYNOPSIS

  use Slash::DB::MySQL;

=head1 DESCRIPTION

No documentation yet. Sue me.

=head1 AUTHOR

Brian Aker, brian@tangent.org

Chris Nandor, pudge@pobox.com

=head1 SEE ALSO

Slash(3). Slash::DB(3)

=cut
