package Slash::DB::MySQL;
# Big note on *User methods. They are in need of clean
# up in a big way. If we had one normalized table
# this would be quite clean. I will find a way around
# this.  -Brian

use strict;
use Digest::MD5 'md5_hex';
use DBIx::Password;
use Slash::DB::Utility;
use Slash::Utility;
use URI ();

@Slash::DB::MySQL::ISA = qw( Slash::DB::Utility );
($Slash::DB::MySQL::VERSION) = ' $Revision$ ' =~ /\$Revision:\s+([^\s]+)/;

my $timeout = 30; #This should eventualy be a parameter that is configurable
# The following two are for CommonPortals

# For the getDecriptionsk() method
my %descriptions = (
	'sortcodes'
		=> sub { $_[0]->sqlSelectMany('code,name', 'sortcodes') },

	'tzcodes'
		=> sub { $_[0]->sqlSelectMany('tz,description', 'tzcodes') },

	'dateformats'
		=> sub { $_[0]->sqlSelectMany('id,description', 'dateformats') },

	'commentmodes'
		=> sub { $_[0]->sqlSelectMany('mode,name', 'commentmodes') },

	'threshcodes'
		=> sub { $_[0]->sqlSelectMany('thresh,description', 'threshcodes') },

	'postmodes'
		=> sub { $_[0]->sqlSelectMany('code,name', 'postmodes') },

	'isolatemodes'
		=> sub { $_[0]->sqlSelectMany('code,name', 'isolatemodes') },

	'issuemodes'
		=> sub { $_[0]->sqlSelectMany('code,name', 'issuemodes') },

	'vars'
		=> sub { $_[0]->sqlSelectMany('name,description', 'vars') },

	'topics'
		=> sub { $_[0]->sqlSelectMany('tid,alttext', 'topics') },

	'maillist'
		=> sub { $_[0]->sqlSelectMany('code,name', 'maillist') },

	'displaycodes'
		=> sub { $_[0]->sqlSelectMany('code,name', 'displaycodes') },

	'commentcodes'
		=> sub { $_[0]->sqlSelectMany('code,name', 'commentcodes') },

	'sections'
		=> sub { $_[0]->sqlSelectMany('section,title', 'sections', 'isolate=0', 'order by title') },

	'sectionblocks'
		=> sub { $_[0]->sqlSelectMany('bid,title', 'sections', 'portal=1') }

);

#################################################################
# Private method used by the search methods
my $keysearch = sub {
	my $self = shift;
	my $keywords = shift;
	my @columns = @_;

	my @words = split m/ /, $keywords;
	my $sql;
	my $x = 0;

	foreach my $w (@words) {
		next if length $w < 3;
		last if $x++ > 3;
		foreach my $c (@columns) {
			$sql .= "+" if $sql;
			$sql .= "($c LIKE " . $self->{dbh}->quote("%$w%") . ")";
		}
	}
#	void context, does nothing?
	$sql = "0" unless $sql;
	$sql .= " as kw";
	return $sql;
};

########################################################
my $whereFormkey = sub {
	my($formkey_id, $user) = @_;
	my $where;

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
sub sqlConnect {
# What we are going for here, is the ability to reuse
# the database connection.
# Ok, first lets see if we already have a connection
	my($self) = @_;

	if (defined($self->{dbh})) {
		#unless (eval {$self->{dbh}->ping}) {
		unless ($self->{dbh}) {
			print STDERR ("Undefining and calling to reconnect: $@\n");
			$self->{dbh}->disconnect;
			undef $self->{dbh};
			$self->sqlConnect();
		}
	} else {
# Ok, new connection, lets create it
		{
			local @_;
			eval {
				local $SIG{'ALRM'} = sub { die "Connection timed out" };
				alarm $timeout;
				$self->{dbh} = DBIx::Password->connect($self->{virtual_user});
				alarm 0;
			};
			if ($@) {
				#In the future we should have a backupdatabase
				#connection in here. For now, we die
				print STDERR "Major Mojo Bad things\n";
				print STDERR "unable to connect to MySQL: $@ : $DBI::errstr\n";
				kill 9, $$ unless $self->{dbh};	 # The Suicide Die
			}
		}
	}
}

########################################################
# Lets say views? How about a better update?
# This is here because MySQL can suck
sub init {
	my($self) = @_;
	my @user_tables = qw(
		users users_comments users_index
		users_info users_key users_prefs
	);
	for my $table (@user_tables) {
		my $keys = $self->getKeys($table);
		for (@$keys) {
			$self->{'_all_user_keys'}->{$_} = $table;
		}
	}
	$self->{_user_tables} = \@user_tables;
	# These are here to remind us of what exists
	$self->{_authorBank} = {};
	$self->{_storyBank} = {};
	$self->{_topicBank} = {};
	$self->{_blockBank} = {};
	$self->{_codeBank} = {};
	$self->{_sectionBank} = {};
	$self->{_boxes} = {};
	$self->{_sectionBoxes} = {};
}

########################################################
sub setComment {
	my($self, $form, $user, $pts, $default_user) = @_;

	$self->sqlDo("LOCK TABLES comments WRITE");
	my($maxCid) = $self->sqlSelect(
		"max(cid)", "comments", "sid=" . $self->{dbh}->quote($form->{sid})
	);

	$maxCid++; # This is gonna cause troubles
	my $insline = "INSERT into comments values (".
		$self->{dbh}->quote($form->{sid}) . ",$maxCid," .
		$self->{dbh}->quote($form->{pid}) . ",now(),'$ENV{REMOTE_ADDR}'," .
		$self->{dbh}->quote($form->{postersubj}) . "," .
		$self->{dbh}->quote($form->{postercomment}) . "," .
		($form->{postanon} ? $default_user : $user->{uid}) . ", $pts,-1,0)";

	# don't allow pid to be passed in the form.
	# This will keep a pid from being replace by
	# with other comment's pid
	if ($form->{pid} >= $maxCid || $form->{pid} < 0) {
		return;
	}

	if ($self->sqlDo($insline)) {
		$self->sqlDo("UNLOCK TABLES");

		# Update discussion
		my($dtitle) = $self->sqlSelect(
			'title', 'discussions', "sid=" . $self->{dbh}->quote($form->{sid})
		);

		unless ($dtitle) {
			$self->sqlUpdate(
				"discussions",
				{ title => $form->{postersubj} },
				"sid=" . $self->{dbh}->quote($form->{sid})
			) if $form->{sid};
		}

		my($ws) = $self->sqlSelect(
			"writestatus", "stories", "sid=" . $self->{dbh}->quote($form->{sid})
		);

		if ($ws == 0) {
			sqlUpdate(
				"stories",
				{ writestatus => 1 },
				"sid=" . $self->{dbh}->quote($form->{sid})
			);
		}

		$self->sqlUpdate(
			"users_info",
			{ -totalcomments => 'totalcomments+1' },
			"uid=" . $self->{dbh}->quote($user->{uid}), 1
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
		apacheLog("$DBI::errstr $insline");
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
sub getModeratorLogID {
	my($self, $cid, $sid, $uid) = @_;
	my($mid) = sqlSelect(
		"id", "moderatorlog",
		"uid=$uid and cid=$cid and sid='$sid'"
	);
	return $mid;
}

########################################################
sub unsetModeratorlog {
	my($self, $uid, $sid, $max, $min) = @_;
	my $cursor = $self->sqlSelectMany("cid,val", "moderatorlog",
			"uid=$uid and sid=" . $self->{dbh}->quote($sid)
	);
	my @removed;

	while (my($cid, $val, $active, $max, $min) = $cursor->fetchrow){
		# We undo moderation even for inactive records (but silently for
		# inactive ones...)
		$self->sqlDo("delete from moderatorlog where
			cid=$cid and uid=$uid and sid=" .
			$self->{dbh}->quote($sid)
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
			"cid=$cid and sid=" . $self->{dbh}->quote($sid) . " AND $scorelogic"
		);
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
		uid	=> $ENV{REMOTE_USER}
	});

	$self->{dbh}->do("update pollquestions set 
		voters=voters+1 where qid=$qid");
	$self->{dbh}->do("update pollanswers set votes=votes+1 where 
		qid=$qid and aid=" . $self->{dbh}->quote($aid));
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
			uid	=> $uid,
			name	=> $form->{from},
			story	=> $form->{story},
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
	$sid = $self->{dbh}->quote($sid);
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
sub getAdminInfo {
	my($self, $session, $admin_timeout) = @_;

	$self->sqlDo("DELETE from sessions WHERE now() > DATE_ADD(lasttime, INTERVAL $admin_timeout MINUTE)");

	my($aid, $seclev, $section, $url) = $self->sqlSelect(
		'sessions.aid, authors.seclev, section, url',
		'sessions, authors',
		'sessions.aid=authors.aid AND session=' . $self->{dbh}->quote($session)
	);

	unless ($aid) {
		return('', 0, '', '');
	} else {
		$self->sqlDo("DELETE from sessions WHERE aid = '$aid' AND session != " .
			$self->{dbh}->quote($session)
		);
		$self->sqlUpdate('sessions', {-lasttime => 'now()'},
			'session=' . $self->{dbh}->quote($session)
		);
		return($aid, $seclev, $section, $url);
	}
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
# Initial Administrator Login.
sub setAdminInfo {
	my($self, $aid, $pwd) = @_;

	if (my($seclev) = $self->sqlSelect('seclev', 'authors',
			'aid=' . $self->{dbh}->quote($aid) .
			' AND pwd=' . $self->{dbh}->quote($pwd) ) ) {

		my($title) = $self->sqlSelect('lasttitle', 'sessions',
			'aid=' . $self->{dbh}->quote($aid)
		);

		$self->sqlDo('DELETE FROM sessions WHERE aid=' . $self->{dbh}->quote($aid) );

		my $sid = $self->generatesession($aid);
		$self->sqlInsert('sessions', { session => $sid, aid => $aid,
			-logintime => 'now()', -lasttime => 'now()',
			lasttitle => $title }
		);
		return($seclev, $sid);

	} else {
		return(0);
	}
}

########################################################
# In need of rewriting
sub writelog {
	my $self = shift;
	my $op = shift;
	my $dat = join("\t", @_);

	my $uid;
	if ($ENV{REMOTE_ADDR}) {
		$uid = getCurrentUser('uid')
	} else {
		$self->getVar('anonymous_coward_uid');
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

	if ($dat =~ m[/]) {
		$self->sqlUpdate('storiestuff', { -hits => 'hits+1' },
			'sid=' . $self->{dbh}->quote($dat)
		);
	}
}

########################################################
sub getCodes {
# Creating three different methods for this seems a bit
# silly.
#
	my($self, $codetype) = @_;
	return $self->{_codeBank}{$codetype} if $self->{_codeBank}{$codetype};

	my $sth;
	if ($codetype eq 'sortcodes') {
		$sth = $self->sqlSelectMany('code,name', 'sortcodes');
	} elsif ($codetype eq 'tzcodes') {
		$sth = $self->sqlSelectMany('tz,offset', 'tzcodes');
	} elsif ($codetype eq 'dateformats') {
		$sth = $self->sqlSelectMany('id,format', 'dateformats');
	} elsif ($codetype eq 'commentmodes') {
		$sth = $self->sqlSelectMany('mode,name', 'commentmodes');
	}

	my $codeBank_hash_ref = {};
	while (my($id, $desc) = $sth->fetchrow) {
		$codeBank_hash_ref->{$id} = $desc;
	}

	$self->{_codeBank}{$codetype} = $codeBank_hash_ref;
	$sth->finish;

	return $codeBank_hash_ref;
}

########################################################
sub getDescriptions {
# Creating three different methods for this seems a bit
# silly.
# This is getting way to long... probably should
# become a generic getDescription method
	my $self = shift; # Shift off to keep things clean
	my $codetype = shift; # Shift off to keep things clean
	my $codeBank_hash_ref = {};
	my $sth = $descriptions{$codetype}->($self);
	while (my($id, $desc) = $sth->fetchrow) {
		$codeBank_hash_ref->{$id} = $desc;
	}
	$sth->finish;

	return $codeBank_hash_ref;
}

########################################################
# Get user info from the users table.
# If you don't pass in a $script, you get everything
# which is handy for you if you need the entire user
sub getUserInstance {
	my($self, $uid, $script) = @_;

	my $user;
	unless ($script) {
		$user = $self->sqlSelectHashref('*',
			'users, users_index, users_comments, users_prefs',
			"users.uid=$uid AND users_index.uid=$uid AND " .
			"users_comments.uid=$uid AND users_prefs.uid=$uid"
		);
		return $user || undef;
	}

	$user = $self->sqlSelectHashref('*', 'users',
		' uid = ' . $self->{dbh}->quote($uid)
	);
	return undef unless $user;
	my $user_extra = $self->sqlSelectHashref('*', "users_prefs", "uid=$uid");
	while (my($key, $val) = each %$user_extra) {
		$user->{$key} = $val;
	}

	# what is this for?  it appears to want to do the same as the
	# code above ... but this assigns a scalar to a scalar ...
	# perhaps `@{$user}{ keys %foo } = values %foo` is wanted?  -- pudge
	$user->{ keys %$user_extra } = values %$user_extra;

	if (!$script || $script =~ /index|article|comments|metamod|search|pollBooth/) {
		my $user_extra = $self->sqlSelectHashref('*', "users_comments", "uid=$uid");
		while (my($key, $val) = each %$user_extra) {
			$user->{$key} = $val;
		}
	}
	# Do we want the index stuff?
	if (!$script || $script =~ /index/) {
		my $user_extra = $self->sqlSelectHashref('*', "users_index", "uid=$uid");
		while (my($key, $val) = each %$user_extra) {
			$user->{$key} = $val;
		}
	}

	return $user;
}

########################################################
# Get user info from the users table.
sub getUserAuthenticate {
	my($self, $user, $passwd, $kind) = @_;
	my($uid, $cookpasswd, $newpass);

	# if $kind is 1, then only try to auth password as plaintext
	# if $kind is 2, then only try to auth password as MD5
	# if $kind is undef or 0, try as MD5 (the most common case),
	#     then as plaintext
	my($EITHER, $PLAIN, $MD5) = (0, 1, 2);
	$kind ||= 0;

	my $dbh = $self->{dbh};
	my $user_db = $dbh->quote($user);
	my $pass_db = $dbh->quote($passwd);

	# try MD5 -> MD5
	if ($kind == $EITHER || $kind == $MD5) {
		($uid) = $self->sqlSelect('uid', 'users',
			"passwd=$pass_db AND uid=$user_db"
		);
		$cookpasswd = $passwd if defined $uid;
	}

	# try plaintext -> MD5
	if (($kind == $EITHER || $kind == $PLAIN) && !defined $uid) {
		my $hexpasswd = md5_hex($passwd);
		($uid) = $self->sqlSelect('uid', 'users',
			'passwd=' . $dbh->quote($hexpasswd) .
			" AND uid=$user_db"
		);
		$cookpasswd = $hexpasswd if defined $uid;
	}

	# try newpass?
	if (($kind == $EITHER || $kind == $PLAIN) && !defined $uid) {
		($uid) = $self->sqlSelect('uid', 'users',
			"newpasswd=$pass_db AND uid=$user_db"
		);

		if (defined $uid) {
			my $hexpasswd = md5_hex($passwd);
			$self->sqlUpdate('users', {
				newpasswd	=> '',
				passwd		=> $hexpasswd
			}, "uid=$user_db");
			$cookpasswd = $hexpasswd;
			$newpass = 1;
		}
	}

	return wantarray ? ($uid, $cookpasswd, $newpass) : $uid;
}

########################################################
# Make a new password, save it in the DB, and return it.
sub getNewPasswd {
	my($self, $uid) = @_;
	my $newpasswd = changePassword();
	$self->sqlUpdate('users', {
		newpasswd => $newpasswd
	}, 'uid=' . $self->{dbh}->quote($uid));
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
		'nickname=' . $self->{dbh}->quote($name)
	);

	return $uid;
}

#################################################################
sub getUserComments {
	my($self, $uid, $min) = @_;

	my $sqlquery = "SELECT pid,sid,cid,subject,"
			. getDateFormat("date","d")
			. ",points FROM comments WHERE uid=$uid "
			. " ORDER BY date DESC LIMIT $min,50 ";

	my $sth = $self->{dbh}->prepare($sqlquery);
	$sth->execute;
	my($comments) = $sth->fetchall_arrayref;

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

	my($cnt) = $self->sqlSelect(
		"matchname","users",
		"matchname=" . $self->{dbh}->quote($matchname)
	) || $self->sqlSelect(
		"realemail","users",
		" realemail=" . $self->{dbh}->quote($email)
	);
	return 0 if ($cnt);

	$self->sqlInsert("users", {
		realemail	=> $email,
		nickname	=> $newuser,
		matchname	=> $matchname,
		passwd		=> changePassword()
	});
# This is most likely a transaction problem waiting to
# bite us at some point. -Brian
	my($uid) = $self->sqlSelect("LAST_INSERT_ID()");
	$self->sqlInsert("users_info", { uid => $uid, -lastaccess => 'now()' } );
	$self->sqlInsert("users_prefs", { uid => $uid } );
	$self->sqlInsert("users_comments", { uid => $uid } );
	$self->sqlInsert("users_index", { uid => $uid } );
	$self->sqlInsert("users_key", { uid => $uid } );

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

	my @vars;
	for (@invars) {
		push @vars, $self->sqlSelect('value', 'vars', "name='$_'");
	}

	return @vars;
}


########################################################
sub setVar {
	my($self, $name, $value) = @_;
	$self->sqlUpdate('vars', {value => $value}, 'name=' . $self->{dbh}->quote($name));
}

########################################################
sub setSessionByAid {
	my($self, $name, $value) = @_;
	$self->sqlUpdate('sessions', $value, 'aid=' . $self->{dbh}->quote($name));
}

########################################################
sub setAuthor {
	my($self, $author, $value) = @_;
	$self->sqlUpdate('authors', $value, 'name=' . $self->{dbh}->quote($author));
}

########################################################
sub setBlock {
	my($self, $bid, $block) = @_;
	$self->sqlUpdate('blocks', $block, 'bid=' . $self->{dbh}->quote($bid));
}

########################################################
sub newVar {
	my($self, $name, $value, $desc) = @_;
	$self->sqlInsert('vars', {name => $name, value => $value, description => $desc});
}

########################################################
sub createAuthor {
	my($self, $aid) = @_;
	$self->sqlInsert('authors', { aid => $aid});
}

########################################################
sub updateCommentTotals {
	my($self, $sid, $comments) = @_;
	my $hp = join ',', @{$comments->[0]{totals}};
	$self->sqlUpdate("stories", {
			hitparade	=> $hp,
			writestatus	=> 0,
			commentcount	=> $comments->[0]{totals}[0]
		}, 'sid=' . $self->{dbh}->quote($sid)
	);
}

########################################################
sub getCommentCid {
	my($self, $sid, $cid) = @_;
	my($scid) = $self->sqlSelectMany("cid", "comments", "sid='$sid' and pid='$cid'");

	return $scid;
}

########################################################
sub removeComment {
	my($self, $sid, $cid) = @_;
	$self->sqlDo("delete from comments WHERE sid=" .
		$self->{dbh}->quote($sid) . " and cid=" . $self->{dbh}->quote($cid)
	);
}

########################################################
sub getCommentPid {
	my($self, $sid, $cid) = @_;
	$self->sqlSelect('pid', 'comments',
		"sid='$sid' and cid=$cid");
}

########################################################
# This method will go away when I am finished with the
# user methods
sub getNicknameByUID {
	my($self, $uid) = @_;
	$self->sqlSelect('nickname', 'users', "uid=$uid");
}

########################################################
# All cache'ing happens in here.
sub getBlock {
	my($self, $bid) = @_;
	return $self->{_blockBank}{$bid} if $self->{_blockBank}{$bid};

	my $sth = $self->sqlSelectMany ('bid,block', 'blocks');
	while (my($thisbid, $thisblock) = $sth->fetchrow) {
		$self->{_blockBank}{$thisbid} = $thisblock;
	}
	$sth->finish;

	return $self->{_blockBank}{$bid};
}

########################################################
sub getSectionBank {
	my($self, $section) = @_;
	if ($section) {
		return $self->{_sectionBank}{$section} if $self->{_sectionBank}{$section};
	} else {
		return $self->{_sectionBank} if keys %{$self->{_sectionBank}};
	}

	my $sth = $self->sqlSelectMany('*', 'sections');
	while (my $section = $sth->fetchrow_hashref) {
		$self->{_sectionBank}{ $section->{section} } = $section;
	}
	$sth->finish;

	if ($section) {
		return $self->{_sectionBank}{$section};
	} else {
		return $self->{_sectionBank};
	}
}

########################################################
#This should be made to be generic
# This should be combinded with the above method
sub getSection {
	my($self, $section) = @_;
	$self->sqlSelect(
		"artcount,title,qid,isolate,issue",
		"sections", "section=" . $self->{dbh}->quote($section)
	);
}

########################################################
sub getSections {
	my($self, $id, @val) = @_;
	my $values;
	unless (scalar @val) {
		$values = '*';
	} else {
		my $values = join ',', @val;
	}
	my $answers = $self->sqlSelectAll($values, 'sections');

	return $answers;
}

########################################################
sub setSection {
# We should perhaps be passing in a reference to F here. More
# thought is needed. -Brian
	my($self, $section, $qid, $title, $issue, $isolate, $artcount) = @_;
	my($count) = $self->sqlSelect("count(*)","sections","section = '$section'");
	#This is a poor attempt at a transaction I might add. -Brian
	#I need to do this diffently under Oracle
	if ($count) {
		$self->sqlDo("INSERT into sections (section) VALUES( '$section')"
		);
	}
	$self->sqlUpdate("sections", {
			qid   => $qid,
			title   => $title,
			issue   => $issue,
			isolate   => $isolate,
			artcount  => $artcount
		}, "section=" . $self->{dbh}->quote($section)
	);

	return $count;
}

########################################################
sub setStoriesCount {
	my($self, $sid, $count) = @_;
	$self->sqlUpdate(
			"stories",
			{
				-commentcount => "commentcount-$count",
				writestatus => 1
			},
			"sid=" . $self->{dbh}->quote($sid)
	);
}

########################################################
sub getSectionTitle {
	my($self) = @_;
	my $sth = $self->{dbh}->prepare("SELECT section,title FROM sections ORDER BY section");
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
	my $aid = getCurrentUser('aid');
	my $form = getCurrentForm();

	if ($form->{subid}) {
		$self->sqlUpdate("submissions", { del => 1 }, 
			"subid=" . $self->{dbh}->quote($form->{subid})
		);

		$self->sqlUpdate("authors",
			{ -deletedsubmissions => 'deletedsubmissions+1' },
			"aid='$aid'"
		);
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
					"subid=" . $self->{dbh}->quote($n));
			}
		} else {
			my $key = $n;
			print "$key " if $self->sqlUpdate(
				"submissions", { del => 1 }, "subid='$key'"
			) && $self->sqlUpdate("authors",
				{ -deletedsubmissions => 'deletedsubmissions+1' },
				"aid='$aid'"
			);
		}
	}
}

########################################################
sub deleteSession {
	my($self, $aid) = @_;
	if ($aid) {
		$self->sqlDo('DELETE FROM sessions WHERE aid=' . $self->{dbh}->quote($aid));
	} else {
		my $user = getCurrentUser();
		$self->sqlDo('DELETE FROM sessions WHERE aid=' . $self->{dbh}->quote($user->{aid}));
	}
}

########################################################
sub deleteAuthor {
	my($self, $aid) = @_;
	$self->sqlDo('DELETE FROM sessions WHERE authors=' . $self->{dbh}->quote($aid));
}

########################################################
sub deleteTopic {
	my($self, $tid) = @_;
	$self->sqlDo('DELETE from topics WHERE tid=' . $self->{dbh}->quote($tid));
}

########################################################
sub revertBlock {
	my($self, $bid) = @_;
	$self->sqlDo("update blocks set block = blockbak where bid = '$bid'");
}

########################################################
sub deleteBlock {
	my($self, $bid) = @_;
	$self->sqlDo('DELETE FROM blocks WHERE bid=' . $self->{dbh}->quote($bid));
	$self->sqlDo('DELETE FROM sectionblocks WHERE bid=' . $self->{dbh}->quote($bid));
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
	my($rows) = $self->sqlSelect('count(*)', 'topics', 'tid=' . $self->{dbh}->quote($form->{tid}));
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
		}, 'tid=' . $self->{dbh}->quote($form->{tid})
	);
}

##################################################################
sub saveBlock {
	my($self, $bid) = @_;
	my($rows) = $self->sqlSelect('count(*)', 'blocks',
		'bid=' . $self->{dbh}->quote($bid)
	);

	my $form = getCurrentForm();
	if ($form->{save_new} && $rows > 0) {
		print qq[<P><B>This block, $bid, already exists! <BR>Hit the "back" button, and try another bid (look at the blocks pulldown to see if you are using an existing one.)</P>]; 
		return $rows;
	}	

	if ($rows == 0) {
		$self->sqlInsert('blocks', { bid => $bid, seclev => 500 });
		$self->sqlInsert('sectionblocks', { bid => $bid });
	}

	my($portal, $retrieve) = (0, 0);

	# this is to make sure that a  static block doesn't get
	# saved with retrieve set to true
	$form->{retrieve} = 0 if $form->{type} ne 'portald';

	$form->{block} = $self->autoUrl($form->{section}, $form->{block});

	if ($rows == 0 || $form->{blocksavedef}) {
		$self->sqlUpdate('blocks', {
			seclev		=> $form->{bseclev}, 
			block		=> $form->{block},
			blockbak	=> $form->{block},
			description	=> $form->{description},
			type		=> $form->{type},
		}, 'bid=' . $self->{dbh}->quote($bid));
	} else {
		$self->sqlUpdate('blocks', {
			seclev		=> $form->{bseclev}, 
			block		=> $form->{block},
			description	=> $form->{description},
			type		=> $form->{type},
		}, 'bid=' . $self->{dbh}->quote($bid));
	}

	$self->sqlUpdate('sectionblocks', {
		ordernum	=> $form->{ordernum}, 
		title		=> $form->{title},
		url		=> $form->{url},	
		rdf		=> $form->{rdf},	
		section		=> $form->{section},	
		retrieve	=> $form->{retrieve}, 
		portal		=> $form->{portal}, 
	}, 'bid=' . $self->{dbh}->quote($bid));

	return $rows;
}

########################################################
sub saveColorBlock {
	my($self, $colorblock) = @_;
	my $form = getCurrentForm();

	$form->{color_block} ||= 'colors';

	if ($form->{colorsave}) {
		# save into colors and colorsback
		$self->sqlUpdate('blocks', {
				block => $colorblock, 
			}, "bid = '$form->{color_block}'"
		);
		
	} elsif ($form->{colorsavedef}) {
		# save into colors and colorsback
		$self->sqlUpdate('blocks', {
				block => $colorblock, 
				blockbak => $colorblock, 
			}, "bid = '$form->{color_block}'"
		);
		
	} elsif ($form->{colororig}) {
		# reload original version of colors
		$self->{dbh}->do("update blocks set block = blockbak where bid = '$form->{color_block}'");
	}
}

########################################################
sub getSectionBlock {
	my($self, $section) = @_;
	my $block = $self->sqlSelectAll("section,bid,ordernum,title,portal,url,rdf,retrieve",
		"sectionblocks", "section=" . $self->{dbh}->quote($section),
		"ORDER by ordernum"
	);

	return $block;
}

########################################################
sub getAuthor {
	my($self, $aid) = @_;

	return $self->{_authorBank}{$aid} if $self->{_authorBank}{$aid};
	# Get all the authors and throw them in a hash for later use:
	my $sth = $self->sqlSelectMany('*', 'authors');
	while (my $author = $sth->fetchrow_hashref) {
		$self->{_authorBank}{ $author->{aid} } = $author;
	}
	$sth->finish;
	return $self->{_authorBank}{$aid};
}

########################################################
sub getAuthorDescription {
	my($self) = @_;
	my $authors = $self->sqlSelectAll("count(*) as c, stories.aid as aid, url, copy",
		"stories, authors",
		"authors.aid=stories.aid", "
		GROUP BY aid ORDER BY c DESC"
	);

	return $authors;
}

########################################################
sub getAuthorNameByAid {
# Ok, this is really similair to the code get methods
# for the moment it will stay seperate just becuase
# those tables will change. My be a good idea to
# cache this at some point.
# We should be smart at some point and actually see if
# we can just grab data from the author bank hash
	my($self) = @_;

	my $author_hash_ref = {};
	my $sth = $self->sqlSelectMany('aid,name', 'authors');
	while (my($id, $desc) = $sth->fetchrow) {
		$author_hash_ref->{$id} = $desc;
	}
	$sth->finish;

	return  $author_hash_ref;
}

########################################################
# This method does not follow basic guidlines
sub getPollVoter {
	my($self, $id) = @_;
	my($voters) = $self->sqlSelect('id', 'pollvoters', 
		"qid=" . $self->{dbh}->quote($id) .
		"AND id=" . $self->{dbh}->($ENV{REMOTE_ADDR} . $ENV{HTTP_X_FORWARDED_FOR}) .
		"AND uid=" . $ENV{REMOTE_USER}
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
			$self->{dbh}->do("DELETE from pollanswers WHERE qid=" 
					. $self->{dbh}->quote($form->{qid}) . " and aid=$x"); 
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
	my($self, $id, @val) = @_;
	my $values = join ',', @val;
	my $answers = $self->sqlSelectAll($values, 'pollanswers', "qid=" . $self->{dbh}->quote($id), 'ORDER by aid');

	return $answers;
}

########################################################
sub getPollQuestions {
# This may go away. Haven't finished poll stuff yet
#
	my($self) = @_;

	my $poll_hash_ref = {};
	my $sql = "SELECT qid,question FROM pollquestions ORDER BY date DESC LIMIT 25";
	my $sth = $self->{dbh}->prepare_cached($sql);
	$sth->execute;
	while (my($id, $desc) = $sth->fetchrow) {
		$poll_hash_ref->{$id} = $desc;
	}
	$sth->finish;

	return $poll_hash_ref;
}

########################################################
# I don't like this method at all (AKA how it is used).
# There has to be a better way. Should be a way to
# combine its usage with the getPollQuestions()
# All we are doing is making sure qid exists.
sub getPollQuestionID {
	my($self, $qid) = @_;
	my($fetched_qid) = $self->sqlSelect('qid', 'pollquestions', "qid='${qid}'");

	return $fetched_qid;
}

########################################################
# Simple method
sub getPollQuestionBySID {
	my($self, $sid) = @_;
	my($question) = $self->sqlSelect("question", "pollquestions", "qid='$sid'");

	return $question;
}

########################################################
sub deleteStory {
	my($self, $sid) = @_;
	$self->sqlUpdate('stories', { writestatus => 5 }, 
		'sid=' . $self->{dbh}->quote($sid)
	);

	$self->{dbh}->do("DELETE from discussions WHERE sid = '$sid'");
}

########################################################
# for slashd
sub deleteStoryAll {
	my($self, $sid) = @_;

	$self->{dbh}->do("DELETE from stories where sid='$sid'");
	$self->{dbh}->do("DELETE from newstories where sid='$sid'");
}

########################################################
# for slashd
# This method is used in a pretty wasteful way
sub getBackendStories {
	my($self, $section) = @_;

	my $cursor = $self->{dbh}->prepare("SELECT stories.sid,title,time,dept,aid,alttext,
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
	while (my $row = $cursor->fetchrow_hashref) {
		push(@$returnable, $row);
	}

	return $returnable;
}

########################################################
# This needs to be made to look like other methods so
# you can request multiple objects
sub getStoryBySid {
	my($self, $sid, $member) = @_;

	if ($member) {
		return $self->{_storyBank}{$sid}->{$member} if $self->{_storyBank}{$sid}->{$member};
	} else {
		return $self->{_storyBank}{$sid} if $self->{_storyBank}{$sid};
	}
	my $hashref = $self->sqlSelectHashref('title,dept,time as sqltime,time,introtext,sid,commentstatus,bodytext,aid, tid,section,commentcount, displaystatus,writestatus,relatedtext,extratext',
		'stories', 'sid=' . $self->{dbh}->quote($sid)
	);
	$self->{_storyBank}{$sid} = $hashref;
	if ($member) {
		$self->{_storyBank}{$sid}->{$member};
	} else {
		return $self->{_storyBank}{$sid};
	}
}

########################################################
sub clearStory {
	my($self, $sid) = @_;
	if ($sid) {
		undef $self->{_storyBank}{$sid};
	} else {
		undef $self->{_storyBank};
	}
}

########################################################
sub setStoryBySid {
	my($self, $sid, $key, $value, $perm) = @_;
	# The idea with $perm, is that at some point, if you set it
	# it will update the database with the change you requested
	$self->{_storyBank}{$sid}{$key} = $value;
}

########################################################
sub getSubmissionLast {
	my($self, $id, $formname, $user) = @_;

	my $where = $whereFormkey->($id, $user);
	my($last_submitted) = $self->sqlSelect(
		"max(submit_ts)",
		"formkeys",
		"$where AND formname = '$formname'");
	$last_submitted ||= 0;

	return $last_submitted;
}

########################################################
# Below are the block methods. These will be cleaned
# up a bit (so names and methods may change)
# This should be in getDescription
########################################################
sub getStaticBlock {
	my($self, $seclev) = @_;

	my $block_hash_ref = {};
	my $sql = "SELECT bid,bid FROM blocks WHERE $seclev >= seclev AND type != 'portald'";
	my $sth = $self->{dbh}->prepare_cached($sql);
	$sth->execute;
	while (my($id, $desc) = $sth->fetchrow) {
		$block_hash_ref->{$id} = $desc;
	}
	$sth->finish;

	return $block_hash_ref;
}

sub getPortaldBlock {
	my($self, $seclev) = @_;

	my $block_hash_ref = {};
	my $sql = "SELECT bid,bid FROM blocks WHERE $seclev >= seclev and type = 'portald'";
	my $sth = $self->{dbh}->prepare_cached($sql);
	$sth->execute;
	while (my($id, $desc) = $sth->fetchrow) {
		$block_hash_ref->{$id} = $desc;
	}
	$sth->finish;

	return $block_hash_ref;
}

sub getColorBlock {
	my($self) = @_;

	my $block_hash_ref = {};
	my $sql = "SELECT bid,bid FROM blocks WHERE type = 'color'";
	my $sth = $self->{dbh}->prepare_cached($sql);
	$sth->execute;
	while (my($id, $desc) = $sth->fetchrow) {
		$block_hash_ref->{$id} = $desc;
	}
	$sth->finish;

	return $block_hash_ref;
}

########################################################
sub getSectionblocks {
	my($self) = @_;

	my $blocks = $self->sqlSelectAll("bid,title,ordernum", "sectionblocks", "portal=1", "order by bid");

	return $blocks;
}

########################################################
sub getLock {
	my($self) = @_;
	my $locks = $self->sqlSelectAll('lasttitle,aid', 'sessions');

	return $locks;
}

########################################################
sub updateFormkeyId {
	my($self, $formname, $formkey, $anon, $uid, $rlogin, $upasswd) = @_;

	if ($uid != $anon && $rlogin && length($upasswd) > 1) {
		sqlUpdate("formkeys", {
			id	=> $uid,
			uid	=> $uid,
		}, "formname='$formname' AND uid = $anon AND formkey=" .
			$self->{dbh}->quote($formkey));
	}
}

########################################################
sub insertFormkey {
	my($self, $formname, $id, $sid, $formkey, $uid) = @_;


	# insert the fact that the form has been displayed, but not submitted at this point
	$self->sqlInsert("formkeys", {
		formkey		=> $formkey,
		formname 	=> $formname,
		id 		=> $id,
		sid		=> $sid,
		uid		=> $uid,
		host_name	=> $ENV{REMOTE_ADDR},
		value		=> 0,
		ts		=> time()
	});
}

########################################################
sub checkFormkey {
	my($self, $formkey_earliest, $formname, $formkey_id, $formkey, $user) = @_;

	my $where = $whereFormkey->($formkey_id, $user);
	my($is_valid) = $self->sqlSelect('count(*)', 'formkeys',
		'formkey = ' . $self->{dbh}->quote($formkey) .
		" AND $where " .
		"AND ts >= $formkey_earliest AND formname = '$formname'");
	return($is_valid);
}

##################################################################
sub checkTimesPosted {
	my($self, $formname, $max, $id, $formkey_earliest, $user) = @_;

	my $where = $whereFormkey->($id, $user);
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
		}, "formkey=" . $self->{dbh}->quote($formkey)
	);
}

##################################################################
sub formFailure {
	my($self, $formkey) = @_;
	sqlUpdate("formkeys", {
			value   => -1,
		}, "formkey=" . $self->{dbh}->quote($formkey)
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
	my $aids = $self->sqlSelectAll('aid,now()-lasttime,lasttitle', 'sessions',
		'aid=aid GROUP BY aid'
	);

	return $aids;
}

########################################################
# getTopics()
# I'm torn, currently we just dump the entire database
# into topicBank if we don't find our topic. I am
# wondering if it wouldn't be better to just grab them
# as needed (when we need them).
# Probably ought to spend some time to actually figure
# this out.
#
# -Brian
sub getTopics {
	my($self, $topic) = @_;

	if ($topic) {
		return $self->{_topicBank}{$topic} if $self->{_topicBank}{$topic};
	} else {
		return $self->{_topicBank} if (keys %{$self->{_topicBank}});
	}
	# Lets go knock on the door of the database
	# and grab the Topic's since they are not cached
	# On a side note, I hate grabbing "*" from a database
	# -Brian
	my $sth = $self->sqlSelectMany('*', 'topics');
	while (my $single_topic = $sth->fetchrow_hashref) {
		$self->{_topicBank}{ $single_topic->{tid} } = $single_topic;
	}
	$sth->finish;

	if ($topic) {
		return $self->{_topicBank}{$topic};
	} else {
		return $self->{_topicBank};
	}
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

########################################################
# This was added to replace latestpoll() except I
# don't think anything is using it anymore
#sub getPoll{
#	my($self) = @_;
#  my($qid) = $self->sqlSelect('qid', 'pollquestions', '', 'ORDER BY date DESC LIMIT 1');
#	return $qid;
#}

##################################################################
# Get poll
sub getPoll {
	my($self, $qid) = @_;

	my $sth = $self->{dbh}->prepare_cached("
			SELECT question,answer,aid  from pollquestions, pollanswers
			WHERE pollquestions.qid=pollanswers.qid AND
			pollquestions.qid= " . $self->{dbh}->quote($qid) . "
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
#	my($comments) = $self->sqlSelect('count(*)', 'comments', "sid=" .$self->{dbh}->quote($qid));
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
		$count = $self->sqlSelect('count(*)', 'submissions',
			"(length(note)<1 or isnull(note)) and del=0" .
			($articles_only ? " and section='articles'" : '')
		);
	} else {
		$count = $self->sqlSelect("count(*)", "submissions", "del=0");
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
		   FROM blocks,sectionblocks
		  WHERE section='index'
		    AND portal > -1
		    AND blocks.bid=sectionblocks.bid
		  GROUP BY blocks.bid
		  ORDER BY ordernum";

	my $sth = $self->{dbh}->prepare($strsql);
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
			'blocks.bid as bid,title,url,section,portal,ordernum',
			'sectionblocks,blocks',
			'sectionblocks.bid=blocks.bid ORDER BY ordernum ASC'
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
		($value) = $self->sqlSelect("count(*)", "comments", "sid=" . $self->{dbh}->quote($sid) . " AND uid = ". $self->{dbh}->quote($uid));
	} elsif ($cid) {
		($value) = $self->sqlSelect("count(*)", "comments", "sid=" . $self->{dbh}->quote($sid) . " AND pid = ". $self->{dbh}->quote($cid));
	} elsif ($comment) {
		($value) = $self->sqlSelect("count(*)", "comments", "sid=" . $self->{dbh}->quote($sid) . ' AND comment=' . $self->{dbh}->quote($comment));
	} else {
		($value) = $self->sqlSelect("count(*)", "comments", "sid=" . $self->{dbh}->quote($sid));
	}

	return $value;
}

##################################################################
sub method {
	my($self, $sid) = @_;
	my $count = $self->countComments($sid);
	$self->sqlUpdate(
		"stories",
		{ commentcount => $count },
		"sid=" . $self->{dbh}->quote($sid)
	);

	return $count;
}

##################################################################
# counts the number of stories
sub countStory {
	my($self, $tid) = @_;
	my($value) = $self->sqlSelect("count(*)", "stories", "tid=" . $self->{dbh}->quote($tid));

	return $value;
}

##################################################################
sub checkForModerator {	# check for MetaModerator / M2, not Moderator
	my($self, $user) = @_;
	return unless $user->{willing};
	return if $user->{uid} < 1;
	return if $user->{karma} < 0;
	my($d) = $self->sqlSelect('to_days(now()) - to_days(lastmm)',
		'users_info', "uid = '$user->{uid}'");
	return unless $d;
	my($tuid) = sqlSelect('count(*)', 'users');
	# what to do with %I here?
	return 1;  # OK to M2
}

##################################################################
sub getAuthorAids {
	my($self, $aid) = @_;
	my $aids = $self->sqlSelectAll("aid", "authors", "seclev > 99", "order by aid");

	return $aids;
}

##################################################################
sub refreshStories {
	my($self, $sid) = @_;
	$self->sqlUpdate('stories',
			{ writestatus => 1 },
			'sid=' . $self->{dbh}->quote($sid) . ' and writestatus=0'
	);
}

##################################################################
sub getStoryByTime {
	my($self, $sign, $sqltime, $isolate, $section, $extid, $exaid, $exsect) = @_;
	my($where, $order);
	$order = $sign eq '<' ? 'DESC' : 'ASC';
	if ($isolate) {
		$where = 'AND section=' . $self->{dbh}->quote($section)
			if $isolate == 1;
	} else {
		$where = 'AND displaystatus=0';
	}

	$where .= "   AND tid not in ($extid)" if $extid;
	$where .= "   AND aid not in ($exaid)" if $exaid;
	$where .= "   AND section not in ($exsect)" if $exsect;

	$self->sqlSelect(
			'title, sid, section', 'newstories',
			"time $sign '$sqltime' AND writestatus >= 0 AND time < now() $where",
			"ORDER BY time $order LIMIT 1"
	);
}

########################################################
sub setUsers {
	my($self, $uid, $hashref) = @_;
	if (exists $hashref->{passwd}) {
		# get rid of newpasswd if defined in DB
		$hashref->{newpasswd} = '';
		$hashref->{passwd} = md5_hex($hashref->{passwd});
	}
	$self->sqlUpdate("users", $hashref, "uid=" . $uid, 1);
}

########################################################
sub countStories {
	my($self) = @_;
	my $stories = $self->sqlSelectAll("sid,title,section,commentcount,aid",
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
	$self->{dbh}->do("LOCK TABLES users_info WRITE, metamodlog WRITE");
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
			-uid  => $ENV{'REMOTE_USER'},
			-val  => ($val eq '+') ? 1 : -1,
			-ts   => "from_unixtime($ts)",
			-flag => $flag
		});
	}
	$self->{dbh}->do("UNLOCK TABLES");

	return $returns;
}

########################################################
sub getModeratorLast {
	my($self, $uid) = @_;
	my $last = sqlSelectHashref(
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
	my $stories = $self->sqlSelectAll("stories.sid,title,section,storiestuff.hits as hits,aid",
		"stories,storiestuff","stories.sid=storiestuff.sid",
		"ORDER BY hits DESC LIMIT 10"
	);
	return $stories;
}

########################################################
sub countStoriesAuthors {
	my($self) = @_;
	my $authors = $self->sqlSelectAll("count(*) as c, stories.aid, url",
		"stories, authors","authors.aid=stories.aid",
		"GROUP BY aid ORDER BY c DESC LIMIT 10"
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
	if ($form->{desc}) {
		my($exists) = $self->sqlSelect('count(*)', 'vars',
			"name='$form->{thisname}'"
		);
		if ($exists == 0) {
			$self->sqlInsert('vars', { name => $form->{thisname} });
		}
		$self->sqlUpdate("vars", {
			value => $form->{value},
			description => $form->{desc}
			}, "name=" . $self->{dbh}->quote($form->{thisname})
		);
	} else {
		$self->sqlDo("DELETE from vars WHERE name='$form->{thisname}'");
	}
}

########################################################
# I'm not happy with this method at all
sub setCommentCleanup {
	my($self, $val, $sid, $reason, $modreason, $cid) = @_;
	# Grab the user object.
	my $user = getCurrentUser();
	my $constants = getSlashConstants();
	my($cuid, $ppid, $subj, $points, $oldreason) = $self->getComments($sid, $cid);

	my $strsql = "UPDATE comments SET
		points=points$val,
		reason=$reason,
		lastmod=$user->{uid}
		WHERE sid=" . $self->{dbh}->quote($sid)."
		AND cid=$cid 
		AND points " .
			($val < 0 ? " > $constants->{comment_minscore}" : "") .
			($val > 0 ? " < $constants->{comment_maxscore}" : "");

	$strsql .= " AND lastmod<>$user->{uid}"
		unless $user->{aseclev} > 99 && $constants->{authors_unlimited};

	if ($val ne "+0" && $self->sqlDo($strsql)) {
		$self->setModeratorLog($cid, $sid, $user->{uid}, $modreason, $val);

		# Adjust comment posters karma
		if ($cuid != $constants->{anonymous_coward}) {
			if ($val > 0) {
				$self->sqlUpdate("users_info",
					{ -karma => "karma$val" }, 
					"uid=$cuid AND karma < $constants->{maxkarma}"
				);
			} elsif ($val < 0) {
				$self->sqlUpdate("users_info",
					{ -karma => "karma$val" }, "uid=$cuid"
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
		); # unless ($user->{aseclev} > 99 && $comments->{authors_unlimited});
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
	my($self, $time, $sid, $pid) = @_;
	my $reply = $self->sqlSelectHashref("$time, subject,comments.points as points,
		comment,realname,nickname,
		fakeemail,homepage,cid,sid,users.uid as uid",
		"comments,users,users_info,users_comments",
		"sid=" . $self->{dbh}->quote($sid) . "
		AND cid=" . $self->{dbh}->quote($pid) . "
		AND users.uid=users_info.uid
		AND users.uid=users_comments.uid
		AND users.uid=comments.uid"
	);

	return $reply;
}

########################################################
sub getComments {
	my($self, $sid, $cid) = @_;
	$self->sqlSelect( "uid,pid,subject,points,reason","comments",
			"cid=$cid and sid='$sid'"
	);
}

########################################################
sub getCommentsTop {
	my($self, $sid, $user) = @_;
	my $where = "stories.sid=comments.sid";
	$where .= " AND stories.sid=" . $self->{dbh}->quote($sid) if $sid;
	my $stories = $self->sqlSelectAll("section, stories.sid, aid, title, pid, subject,"
		. getDateFormat("date","d", $user) . "," . getDateFormat("time","t", $user)
		. ",uid, cid, points"
		, "stories, comments"
		, $where
		, " ORDER BY points DESC, d DESC LIMIT 10 ");

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
	});
}

########################################################
# What an ugly method
sub getSubmissionForUser {
	my($self, $dateformat) = @_;
	my $form = getCurrentForm();
	my $user = getCurrentUser();
	my $sql = "SELECT subid, subj, date_format($dateformat, 'm/d  H:i'), tid,note,email,name,section,comment,submissions.uid,karma FROM submissions,users_info";
	$sql .= "  WHERE submissions.uid=users_info.uid AND $form->{del}=del AND (";
	$sql .= $form->{note} ? "note=" . $self->{dbh}->quote($form->{note}) : "isnull(note)";
	$sql .= "		or note=' ' " unless $form->{note};
	$sql .= ")";
	$sql .= "		and tid='$form->{tid}' " if $form->{tid};
	$sql .= "         and section=" . $self->{dbh}->quote($user->{asection}) if $user->{asection};
	$sql .= "         and section=" . $self->{dbh}->quote($form->{section})  if $form->{section};
	$sql .= "	  ORDER BY time";

	my $cursor = $self->{dbh}->prepare($sql);
	$cursor->execute;

	my $submission = $cursor->fetchall_arrayref;

	return $submission;
}

########################################################
sub getSearch {
	my($self, $form, $user) = @_;
	# select comment ID, comment Title, Author, Email, link to comment
	# and SID, article title, type and a link to the article
	$form = getCurrentForm() unless $form;
	$user = getCurrentUser() unless $user;
	my $sqlquery = "SELECT section, newstories.sid, aid, title, pid, subject, writestatus," .
		getDateFormat("time","d", $user) . ",".
		getDateFormat("date","t", $user) . ", 
		uid, cid, ";

	$sqlquery .= "	  " . $keysearch->($self, $form->{query}, "subject", "comment") if $form->{query};
	$sqlquery .= "	  1 as kw " unless $form->{query};
	$sqlquery .= "	  FROM newstories, comments
			 WHERE newstories.sid=comments.sid ";
	$sqlquery .= "     AND newstories.sid=" . $self->{dbh}->quote($form->{sid}) if $form->{sid};
	$sqlquery .= "     AND points >= $user->{threshold} ";
	$sqlquery .= "     AND section=" . $self->{dbh}->quote($form->{section}) if $form->{section};
	$sqlquery .= " ORDER BY kw DESC, date DESC, time DESC LIMIT $form->{min},20 ";


	my $cursor = $self->{dbh}->prepare($sqlquery);
	$cursor->execute;

	my $search = $cursor->fetchall_arrayref;
	return $search;
}

########################################################
sub getNewstoryTitle {
	my($self, $storyid, $sid) = @_;
	my($title) = sqlSelect("title", "newstories",
	      "sid=" . $self->{dbh}->quote($sid)
	);

	return $title;
}

########################################################
# Search users, you can also optionally pass it
# array of users that can be ignored
sub getSearchUsers {
	my($self, $form, @users_to_ignore) = @_;
	# userSearch REALLY doesn't need to be ordered by keyword since you
	# only care if the substring is found.
	my $sqlquery = "SELECT fakeemail,nickname,uid ";
	$sqlquery .= " FROM users";
	$sqlquery .= " WHERE uid not $users_to_ignore[1]" if $users_to_ignore[1];
	shift @users_to_ignore;
	for my $user (@users_to_ignore) {
		$sqlquery .= " AND uid not $user";
	}
	if ($form->{query}) {
		my $kw = $keysearch->($self, $form->{query}, 'nickname', 'ifnull(fakeemail,"")');
		$kw =~ s/as kw$//;
		$kw =~ s/\+/ OR /g;
		$sqlquery .= "AND ($kw) ";
	}
	$sqlquery .= "ORDER BY uid LIMIT $form->{min}, $form->{max}";
	my $sth = $self->{dbh}->prepare($sqlquery);
	$sth->execute;

	my $users = $sth->fetchall_arrayref;

	return $users;
}

########################################################
sub getSearchStory {
	my($self, $form) = @_;
	my $sqlquery = "SELECT aid,title,sid," . getDateFormat("time","t") .
		", commentcount,section ";
	$sqlquery .= "," . $keysearch->($self, $form->{query}, "title", "introtext") . " "
		if $form->{query};
	$sqlquery .= "	,0 " unless $form->{query};

	if ($form->{query} || $form->{topic}) {
		$sqlquery .= "  FROM stories ";
	} else {
		$sqlquery .= "  FROM newstories ";
	}

	$sqlquery .= $form->{section} ? <<EOT : 'WHERE displaystatus >= 0';
WHERE ((displaystatus = 0 and "$form->{section}"="")
        OR (section="$form->{section}" and displaystatus>=0))
EOT

	$sqlquery .= "   AND time<now() AND writestatus>=0 AND displaystatus>=0";
	$sqlquery .= "   AND aid=" . $self->{dbh}->quote($form->{author})
		if $form->{author};
	$sqlquery .= "   AND section=" . $self->{dbh}->quote($form->{section})
		if $form->{section};
	$sqlquery .= "   AND tid=" . $self->{dbh}->quote($form->{topic})
		if $form->{topic};

	$sqlquery .= " ORDER BY ";
	$sqlquery .= " kw DESC, " if $form->{query};
	$sqlquery .= " time DESC LIMIT $form->{min},$form->{max}";

	my $cursor = $self->{dbh}->prepare($sqlquery);
	$cursor->execute;
	my $stories = $cursor->fetchall_arrayref;

	return $stories;
}

########################################################
sub getTrollAddress {
	my($self) = @_;
	my($badIP) = $self->sqlSelect("sum(val)","comments,moderatorlog",
			"comments.sid=moderatorlog.sid AND comments.cid=moderatorlog.cid
			AND host_name='$ENV{REMOTE_ADDR}' AND moderatorlog.active=1
			AND (to_days(now()) - to_days(ts) < 3) GROUP BY host_name"
	);

	return $badIP;
}

########################################################
sub getTrollUID {
	my($self) = @_;
	my $user =  getCurrentUser();
	my($badUID) = $self->sqlSelect("sum(val)","comments,moderatorlog",
		"comments.sid=moderatorlog.sid AND comments.cid=moderatorlog.cid
		AND comments.uid=$user->{uid} AND moderatorlog.active=1
		AND (to_days(now()) - to_days(ts) < 3)  GROUP BY comments.uid"
	);

	return $badUID;
}

########################################################
sub setCommentCount {
	my($self, $delCount) = @_;
	my $form =  getCurrentForm();
	$self->sqlDo("UPDATE stories SET commentcount=commentcount-$delCount,
	      writestatus=1 WHERE sid=" . $self->{dbh}->quote($form->{sid})
	);
}

########################################################
sub saveStory {
	my($self) = @_;
	my $form = getCurrentForm();
	my $constants = getSlashConstants();
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
			'subid=' . $self->{dbh}->quote($form->{subid})
		);

		# i think i got this right -- pudge
 		my($userkarma) = sqlSelect('karma', 'users_info', "uid=$suid");
 		my $newkarma = (($userkarma + $constants->{submission_bonus})
 			> $constants->{maxkarma})
 				? $constants->{maxkarma}
 				: "karma+$constants->{submission_bonus}";
 		sqlUpdate('users_info', { -karma => $newkarma }, "uid=$suid")
 			if $suid != $constants->{anonymous_coward_uid};

		$self->sqlUpdate('users_info',
			{ -karma => 'karma + 3' }, 
			"uid=$suid"
		) if $suid != $constants->{anonymous_coward_uid};

		$self->sqlUpdate('submissions',
			{ del=>2 }, 
			'subid=' . $self->{dbh}->quote($form->{subid})
		);
	}

	$self->sqlInsert('stories',{
		sid		=> $form->{sid},
		aid		=> $form->{aid},
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
		breaking
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
		send_mail
		shit
		siteadmin
		siteadmin_name
		sitename
		siteowner
		slogan
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
	$conf{maxkarma}		||= 999;

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

	$conf{badreasons} = 4; # number of "Bad" reasons in @$I{reasons}, skip 0 (which is neutral)
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
	
	my $initials = substr $user->{aid}, 0, 1;
	my $more = substr $user->{aid}, 1;
	$more =~ s/[a-z]//g;
	$initials = uc($initials . $more);
	my($now) = $self->sqlSelect('date_format(now(),"m/d h:i p")');

	# Assorted Automatic Autoreplacements for Convenience
	s|<disclaimer:(.*)>|<B><A HREF="/about.shtml#disclaimer">disclaimer</A>:<A HREF="$user->{url}">$user->{aid}</A> owns shares in $1</B>|ig;
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
sub getStoryList {
	my($self) = @_;

	my $user = getCurrentUser();
	my $form = getCurrentForm();

	my $sql = q[SELECT storiestuff.hits, commentcount, stories.sid, title, aid,
			date_format(time,"%k:%i") as t,tid,section,
			displaystatus,writestatus,
			date_format(time,"%W %M %d"),
			date_format(time,"%m/%d")
			FROM stories,storiestuff 
			WHERE storiestuff.sid=stories.sid];
	$sql .= "	AND section='$user->{asection}'" if $user->{asection};
	$sql .= "	AND section='$form->{section}'"  if $form->{section} && !$user->{asection};
	$sql .= "	AND time < DATE_ADD(now(), interval 72 hour) " if $form->{section} eq ""; 
	$sql .= "	ORDER BY time DESC";

	my $cursor = $self->{dbh}->prepare($sql);
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
			-ts	=> $form->{'time'},
		},
		'sid = ' . $self->{dbh}->quote($form->{sid})
	);

	$self->sqlUpdate('stories', {
			aid		=> $form->{aid},
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
		}, 'sid=' . $self->{dbh}->quote($form->{sid})
	);

	$self->{dbh}->do('UPDATE stories SET time=now() WHERE sid='
		. $self->{dbh}->quote($form->{sid})
	) if $form->{fastforward} eq 'on';
	$self->saveExtras($form);
}

##################################################################
sub getPollVotesMax {
	my($self, $id) = @_;
	my($answer) = $self->sqlSelect("max(votes)", "pollanswers", "qid=" . $self->{dbh}->quote($id));
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

	if (sqlUpdate($form->{section}, $E, "sid='$form->{sid}'") eq '0E0') {
		sqlInsert($form->{section}, $E);
	}
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
# This is protected and don't call it from your
# scripts directly.
sub _genericGet {
	my($table, $table_prime, $self, $id, @val) = @_;
	my $members = @val;
	my $answer;
	if ($members == 1) {
		($answer) = $self->sqlSelect($val[0], $table, "$table_prime=" . $self->{dbh}->quote($id));
	} elsif ($members > 1) {
		my $values = join ',', @val;
		$answer = $self->sqlSelectHashref($values, $table, "$table_prime=" . $self->{dbh}->quote($id));
	} else {
		$answer = $self->sqlSelectHashref('*', $table, "$table_prime=" . $self->{dbh}->quote($id));
	} 

	return $answer;
}

########################################################
sub getPollQuestion {
	my $answer = _genericGet('pollquestions', 'qid', @_);
	return $answer;
}

########################################################
sub getPollAnswer {
	my $answer = _genericGet('pollanswers', 'qid', @_);
	return $answer;
}

########################################################
sub getBlockByBid {
	my $answer = _genericGet('blocks', 'bid', @_);
	return $answer;
}

########################################################
# This should go along with the cached data and not
# hit the database
sub getTopicByTid {
	my $answer = _genericGet('topics', 'tid', @_);
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
sub getSectionBlockByBid {
	my $answer = _genericGet('sectionblocks', 'bid', @_);
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
# Now here is the thing. We want getUser to look like
# a generic, despite the fact that it is not :)
sub getUser {
	my($self, $uid, @val) = @_;
	my $members = @val;
	my $answer;
	if ($members == 1) {
		my $table = $self->{_all_user_keys}->{$val[0]};
		($answer) = $self->sqlSelect($val[0], $table, 'uid=' .$self->{dbh}->quote($uid));
	} elsif ($members > 1) {
		my $values = join ',', @val;
		my %tables;
		my $where;
		my $uid_db = $self->{dbh}->quote($uid);
		for(@val) {
			$tables{$self->{_all_user_keys}->{$_}} = 1;
		}
		for(keys %tables) {
			$where .= "$_.uid=$uid_db AND ";
		}
		# Probably less resource intensive way to do this (like just
		# chopping off the end of the array based on size). But
		# it is late, and I am tired. -Brian
		chop($where); chop($where); chop($where); chop($where); chop($where);
		my $table = join ',', keys %tables;
		$answer = $self->sqlSelectHashref($values, $table, $where);
	} else {
		my $where;
		my $uid_db = $self->{dbh}->quote($uid);
		for(keys %{$self->{_all_user_keys}}) {
			$where .= "$_.uid=$uid_db AND ";
		}
		chop($where); chop($where); chop($where); chop($where); chop($where);
		my $table = join ',', @$self->{_user_tables};
		$answer = $self->sqlSelectHashref('*', $table, $where);
	} 

	return $answer;
}

########################################################
# Now here is the thing. We want setUser to look like
# a generic, despite the fact that it is not :)
sub setUser {
	my($self, $uid, $hashref) = @_;
	my %tables;
	for(keys %$hashref) {
		my $key = $self->{_all_user_keys}->{$_};
		push @{$tables{$key}}, $_;
	}
	for my $table (keys %tables) {
		my %minihash;
		for(@{$tables{$table}}){
			$minihash{$_} = $hashref->{$_} if $hashref->{$_} ne undef;
		}
		$self->sqlUpdate($table, \%minihash, "uid=" . $uid, 1);
	}
}
########################################################
# For slashdb
sub setStoryIndex {
	my($self) = @_;

	my %stories;

	for my $sid (@_) {
		$stories{$sid} = $self->sqlSelectHashref("*","stories","sid='$sid'");
	}
	$self->{dbh}->do("LOCK TABLES newstories WRITE");

	foreach my $sid (keys %stories) {
		$self->sqlReplace("newstories", $stories{$sid}, "sid='$sid'");
	}

	$self->{dbh}->do("UNLOCK TABLES");
}

########################################################
# For slashdb
sub getNewStoryTopic {
	my($self) = @_;

	my $returnable = $self->sqlSelectHashref(
				"alttext,image,width,height,newstories.tid",
				"newstories,topics",
				"newstories.tid=topics.tid
				AND displaystatus = 0
				AND writestatus >= 0
				AND time < now()
				ORDER BY time DESC");

	return $returnable;
}

########################################################
# For slashdb
sub getStoriesForSlashdb {
	my($self) = @_;

	my $returnable = $self->sqlSelectAll("sid,title,section", 
			"stories", "writestatus=1");

	return $returnable;
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

=head1 SEE ALSO

Slash(3). Slash::DB(3)

=cut
