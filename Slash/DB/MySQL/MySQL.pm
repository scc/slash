package Slash::DB::MySQL;
# Big note on *User methods. They are in need of clean
# up in a big way. If we had one normalized table
# this would be quite clean. I will find a way around 
# this.  -Brian

use strict;
use DBIx::Password;
use Slash::DB::Utility;
use Slash::Utility;

@Slash::DB::MySQL::ISA = qw( Slash::DB::Utility );
($Slash::DB::MySQL::VERSION) = ' $Revision$ ' =~ /\$Revision:\s+([^\s]+)/;

my $user; #Who we are to DBIx
my $timeout = 30; #This should eventualy be a parameter that is configurable
my %authorBank; # This is here to save us a database call
my %storyBank; # This is here to save us a database call
my %topicBank; # This is here to save us a database call
my %codeBank; # This is here to save us a database call
my $commonportals; # portals on the front page.
my $boxes;
my $sectionBoxes;
my $dbh;

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
			$sql .= "($c LIKE " . $dbh->quote("%$w%") . ")";
		}
	}
#	void context, does nothing?
	$sql = "0" unless $sql;
	$sql .= " as kw";
	return $sql;
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
	my $self = shift;
	($user) = @_;

	if(defined($self->{dbh})) {
		unless (eval {$self->{dbh}->ping}) {
			print STDERR ("Undefining and calling to reconnect \n");
			undef $self->{dbh};
			sqlConnect();
		}
	} else {
# Ok, new connection, lets create it
		{
			local @_;
			eval {
				local $SIG{'ALRM'} = sub { die "Connection timed out" };
				alarm $timeout;
				$self->{dbh} = DBIx::Password->connect($user);
				alarm 0;
			};
			if ($@) {
				#In the future we should have a backupdatabase 
				#connection in here. For now, we die
				print STDERR "unable to connect to MySQL $DBI::errstr\n";
				kill 9, $$ unless $self->{dbh};	 # The Suicide Die
			}
		}
	}
	#This is only here for backwards compatibility
	$Slash::I{dbh} = $self->{dbh};
	$dbh = $self->{dbh};
}

########################################################
# Handles admin logins (checks the sessions table for a cookie that
# matches).  Called by getSlash
sub getAdminInfo {
	my($self , $session, $admin_timeout) = @_;

	$self->{dbh}->do("DELETE from sessions WHERE now() > DATE_ADD(lasttime, INTERVAL $admin_timeout MINUTE)");

	my($aid, $seclev, $section, $url) = $self->sqlSelect(
		'sessions.aid, authors.seclev, section, url',
		'sessions, authors',
		'sessions.aid=authors.aid AND session=' . $self->{dbh}->quote($session)
	);

	unless ($aid) {
		return('', 0, '', '');
	} else {
		$self->{dbh}->do("DELETE from sessions WHERE aid = '$aid' AND session != " .
			$self->{dbh}->quote($session)
		);
		$self->sqlUpdate('sessions', {-lasttime => 'now()'},
			'session=' . $self->{dbh}->quote($session)
		);
		return($aid, $seclev, $section, $url);
	}
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

		$self->{dbh}->do('DELETE FROM sessions WHERE aid=' . $self->{dbh}->quote($aid) );

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
sub writelog {
	my $self = shift;
	my $uid = shift;
	my $op = shift;
	my $dat = join("\t", @_);

	$self->sqlInsert('accesslog', {
		host_addr	=> $ENV{REMOTE_ADDR} || '0',
		dat		=> $dat,
		uid		=> $uid || '-1',
		op		=> $op,
		-ts		=> 'now()',
		query_string	=> $ENV{QUERY_STRING} || '0',
		user_agent	=> $ENV{HTTP_USER_AGENT} || '0',
	}, 2);

	if ($dat =~ m[/]) {
		$self->sqlUpdate('storiestuff', { -hits => 'hits+1' }, 
			'sid=' . $self->{dbh}->quote($dat)
		);
	} elsif ($op eq 'index') {
		# Update Section Counter
	}
}

########################################################
sub getCodes {
# Creating three different methods for this seems a bit
# silly. 
#
  my ($self, $codetype) = @_;
	return $codeBank{$codetype} if $codeBank{$codetype};

	my $sth;
	if($codetype eq 'sortcodes') {
		$sth = $self->sqlSelectMany('code,name', 'sortcodes');
	}
	if($codetype eq 'tzcodes') {
		$sth = $self->sqlSelectMany('tz,offset', 'tzcodes');
	}
	if($codetype eq 'dateformats') {
		$sth = $self->sqlSelectMany('id,format', 'dateformats');
	}
	if($codetype eq 'commentmodes') {
		$sth = $self->sqlSelectMany('mode,name', 'commentmodes');
	}

	my $codeBank_hash_ref={};
	while (my($id, $desc) = $sth->fetchrow) {
		$codeBank_hash_ref->{$id} = $desc;
	}

	$codeBank{$codetype} = $codeBank_hash_ref;
	$sth->finish;

	return $codeBank_hash_ref;
}

########################################################
sub getDescriptions {
# Creating three different methods for this seems a bit
# silly. 
# This is getting way to long... probably should
# become a generic getDescription method
  my $self = shift; # Shit off to keep things clean
  my $codetype = shift; # Shit off to keep things clean
	my $codeBank_hash_ref={};
	my $sth = $descriptions{$codetype}($self);
	while (my($id, $desc) = $sth->fetchrow) {
		$codeBank_hash_ref->{$id} = $desc;
	}
	$sth->finish;

	return  $codeBank_hash_ref;
}
########################################################
# Get user info from the users table.
sub getUserInfoAuthenticate{
  my($self, $uid, $passwd, $script) = @_;
	my $user = $self->sqlSelectHashref('*', 'users',
		' uid = ' . $self->{dbh}->quote($uid) .
		' AND passwd = ' . $self->{dbh}->quote($passwd)
	);
	return undef unless ($user);
	my $user_extra = $self->sqlSelectHashref('*', "users_prefs", "uid=$uid");
	while(my ($key, $val) = each %$user_extra) {
		$user->{$key} = $val;
	}

	$user->{ keys %$user_extra } = values %$user_extra;

	if (!$script || $script =~ /index|article|comments|metamod|search|pollBooth/) {
		my $user_extra = $self->sqlSelectHashref('*', "users_comments", "uid=$uid");
		while(my ($key, $val) = each %$user_extra) {
			$user->{$key} = $val;
		}
	}
	# Do we want the index stuff?
	if (!$script || $script =~ /index/) {
		my $user_extra = $self->sqlSelectHashref('*', "users_index", "uid=$uid");
		while(my ($key, $val) = each %$user_extra) {
			$user->{$key} = $val;
		}
	}


	$user_extra = $self->sqlSelectHashref('*', "users_prefs", "uid=$uid");
	while(my ($key, $val) = each %$user_extra) {
		$user->{$key} = $val;
	}

	return $user;
}

########################################################
# Get user info from the users table.
sub getUserAuthenticate{
  my($self, $name, $passwd) = @_;

	my ($uid) = $self->sqlSelect('uid', 'users',
			'passwd=' . $self->{dbh}->quote($passwd) .
			' AND nickname=' . $self->{dbh}->quote($name)
	);
	return $uid;

}
########################################################
# Get user info from the users table.
# May be worth it to cache this at some point
sub getUserUID{
  my($self, $name) = @_;

#!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
# We need to add BINARY to this
# as is, it may be a security flaw
#!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
	my ($uid) = $self->sqlSelect('uid', 'users',
			'nickname=' . $self->{dbh}->quote($name)
	);

	return $uid;
}

########################################################
# Get user info from the users table.
sub getUserPoints{
  my($self, $uid) = @_;

	my ($points) = $self->sqlSelect('points', 'users_comments',
			"uid='$uid'");

	return $points;

}
########################################################
# Get user info from the users table.
sub getUserPublicKey{
  my($self, $uid) = @_;

	my ($key) = $self->sqlSelect('pubkey', 'users_key',
			"uid='$uid'");

	return $key;

}
#################################################################
sub getUserComments{
  my($self, $uid, $min) = @_;

	my $sqlquery = "SELECT pid,sid,cid,subject,"
			. getDateFormat("date","d")
			. ",points FROM comments WHERE uid=$uid "
			. " ORDER BY date DESC LIMIT $min,50 ";

	my $sth = $self->{dbh}->prepare($sqlquery);
	$sth->execute;
	my ($comments) = $sth->fetchall_arrayref;

	return $comments;

}
#################################################################
sub getUserIndexExboxes {
	my($self, $uid) = @_;
	my($exboxes) = $self->sqlSelect("exboxes", "users_index", "uid=$uid");
	return $exboxes
}
########################################################
# Get user info from the users table.
sub getUserInfoByUID{
  my($self, $uid) = @_;

	my $user = $self->sqlSelectHashref('nickname,realemail', 'users',
			'nickname=' . $self->{dbh}->quote($uid)); 
	return $user;
}
########################################################
# Get user info from the users table.
sub getUserFakeEmail{
  my($self, $uid) = @_;

	my $user = $self->sqlSelectHashref('nickname,fakeemail', 'users',
			'nickname=' . $self->{dbh}->quote($uid)); 
	return $user;
}

########################################################
# Get user info from the users table.
sub getUserInfoByNickname{
  my($self, $name) = @_;

	my $user = $self->sqlSelectArrayRef('passwd,realemail', 'users',
			'nickname=' . $self->{dbh}->quote($name)); 
	return $user;

}
#################################################################
sub createUser {
	my ($self, $matchname, $email, $newuser) = @_;
	
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
	$self->sqlInsert("users_info", { uid => $uid, lastaccess=>'now()' } );
	$self->sqlInsert("users_prefs", { uid => $uid } );
	$self->sqlInsert("users_comments", { uid => $uid } );
	$self->sqlInsert("users_index", { uid => $uid } );

	return $uid;
}

########################################################
sub getAC{
	my ($self) = @_;
  my $ac_hash_ref;
	$ac_hash_ref = $self->sqlSelectHashref('*',
		'users, users_index, users_comments, users_prefs',
		'users.uid=-1 AND users_index.uid=-1 AND ' .
		'users_comments.uid=-1 AND users_prefs.uid=-1'
	);
	return $ac_hash_ref;
}

########################################################
sub getACTz{
	my ($self, $tzcode, $dfid) = @_;
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
sub getVar {
	my ($self, $var) = @_;
	my($value, $desc) = $self->sqlSelect('value,description', 'vars', "name='$var'");
}

########################################################
sub setVar {
	my($self, $name, $value) = @_;
	$self->sqlUpdate('vars', {value => $value}, 'name=' . $self->{dbh}->quote($name));
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
		}, 'sid=' . $self->{dbh}->quote($sid)
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
sub getBlockBank {
	my ($self, $iHashRef) = @_;
	return if $iHashRef->{blockBank}{cached};
	$iHashRef->{blockBank}{cached} = localtime;

	my $sth = $self->sqlSelectMany ('bid,block', 'blocks');
	while (my($thisbid, $thisblock) = $sth->fetchrow) {
		$iHashRef->{blockBank}{$thisbid} = $thisblock;
	}
	$sth->finish;
}

########################################################
sub getSectionBank {
	my ($self) = @_;
	my $sectionbank = {};
	my $sth = $self->sqlSelectMany('*', 'sections');
	while (my $S = $sth->fetchrow_hashref) {
		$sectionbank->{ $S->{section} } = $S;
	}
	$sth->finish;
	return $sectionbank;
}
########################################################
sub getSection {
	my ($self, $section) = @_;
	$self->sqlSelect(
			"artcount,title,qid,isolate,issue",
			"sections","section=". $self->{dbh}->quote($section));
}
########################################################
sub setSection {
# We should perhaps be passing in a reference to F here. More
# thought is needed. -Brian
	my ($self, $section, $qid, $title, $issue, $isolate, $artcount) = @_;
	my ($count) = $self->sqlSelect("count(*)","sections","section = '$section'");
	#This is a poor attempt at a transaction I might add. -Brian
	#I need to do this diffently under Oracle
	if ($count) {
		$self->{dbh}->do("INSERT into sections (section) VALUES( '$section')"
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
sub getSectionTitle {
	my ($self) = @_;
	my $sth = $self->{dbh}->prepare("SELECT section,title FROM sections ORDER BY section");
	$sth->execute;
	my $sections = $sth->fetchrow_arrayref;
	$sth->finish;

	return $sections;
}
########################################################
sub deleteSection{
	my ($self, $section) = @_;
	$self->{dbh}->do("DELETE from sections WHERE section='$section'");
}
########################################################
sub getSectionBlock {
	my ($self, $section) = @_;
	my $block = $self->sqlSelectAll("section,bid,ordernum,title,portal,url,rdf,retrieve",
			"sectionblocks", "section=" . $self->{dbh}->quote($section), 
			"ORDER by ordernum");

	return $block;
}

########################################################
sub getAuthor {
  my ($self, $aid) = @_;

	return $authorBank{$aid} if $authorBank{$aid};
	# Get all the authors and throw them in a hash for later use:
	my $sth = $self->sqlSelectMany('*', 'authors');
	while (my $author = $sth->fetchrow_hashref) {
		$authorBank{ $author->{aid} } = $author;
	}
	$sth->finish;
	return $authorBank{$aid};
}
########################################################
sub getAuthorDescription {
  my ($self) = @_;
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
  my ($self) = @_;

	my $author_hash_ref={};
	my $sth = $self->sqlSelectMany('aid,name', 'authors');
	while (my($id, $desc) = $sth->fetchrow) {
		$author_hash_ref->{$id} = $desc;
	}
	$sth->finish;

	return  $author_hash_ref;
}

########################################################
sub getPollQuestions {
# This may go away. Haven't finished poll stuff yet
# 
  my ($self) = @_;

	my $poll_hash_ref={};
	my $sql = "SELECT qid,question FROM pollquestions ORDER BY date DESC LIMIT 25"; 
	my $sth = $self->{dbh}->prepare_cached($sql);
	$sth->execute;
	while (my($id, $desc) = $sth->fetchrow) {
		$poll_hash_ref->{$id} = $desc;
	}
	$sth->finish;

	return  $poll_hash_ref;
}

########################################################
# I don't like this method at all (AKA how it is used).
# There has to be a better way. Should be a way to 
# combine its usage with the getPollQuestions()
# All we are doing is making sure qid exists.
sub getPollQuestionID {
	my ($self, $qid) = @_;
	my ($fetched_qid) = $self->sqlSelect('qid', 'pollquestions', "qid='${qid}'");

	return $fetched_qid;
}
########################################################
# Simple method
sub getPollQuestionBySID {
	my ($self, $sid) = @_;
	my ($question) = $self->sqlSelect("question", "pollquestions", "qid='$sid'");

	return $question;
}
########################################################
sub getUserEditInfo {
	my ($self, $name) = @_;
	my $bio = $self->sqlSelectHashref("users.uid, realname, realemail, fakeemail, homepage, nickname, passwd, sig, seclev, bio, maillist", "users, users_info", "users.uid=users_info.uid AND nickname=" . $self->{dbh}->quote($name));

	return $bio;

}
########################################################
sub getUserEditHome {
	my ($self, $name) = @_;
	my $bio = $self->sqlSelectHashref("users.uid, willing, dfid, tzcode, noicons, light, mylinks, users_index.extid, users_index.exaid, users_index.exsect, users_index.exboxes, users_index.maxstories, users_index.noboxes", "users, users_info", "users.uid=users_info.uid AND nickname=" . $self->{dbh}->quote($name));

	return $bio;

}
########################################################
sub getUserEditComment  {
	my ($self, $name) = @_;
	my $bio = $self->sqlSelectHashref("users.uid, points, posttype, defaultpoints, maxcommentsize, clsmall, clbig, reparent, noscores, highlightthresh, commentlimit, nosigs, commentspill, commentsort, mode, threshold, hardthresh", "users, users_comments", "users.uid=users_info.uid AND nickname=" . $self->{dbh}->quote($name));

	return $bio;

}
########################################################
sub getUserBio {
	my ($self, $nick) = @_;
	my $sth = $self->{dbh}->prepare(
			"SELECT homepage,fakeemail,users.uid,bio, seclev,karma
			FROM users, users_info
			WHERE users.uid = users_info.uid AND nickname="
			. $self->{dbh}->quote($nick) . " and users.uid > 0"
		);
	$sth->execute;
	my $bio = $sth->fetchrow_arrayref;

	return $bio;

}
########################################################
sub getStoryBySid {
	my ($self, $sid, $member) = @_;
	
	if($member) {
		return $storyBank{$sid}->{$member} if $storyBank{$sid}->{$member};
	} else {
		return $storyBank{$sid} if $storyBank{$sid};
	}
	my $hashref = $self->sqlSelectHashref('title,dept,time as sqltime,time,introtext,sid,commentstatus,bodytext,aid, tid,section,commentcount, displaystatus,writestatus,relatedtext,extratext',
		'stories', 'sid=' . $self->{dbh}->quote($sid)
		);
	$storyBank{$sid} = $hashref;
	if($member) {
		$storyBank{$sid}->{$member};
	} else {
		return $storyBank{$sid};
	}
}
########################################################
sub clearStory {
	my ($self, $sid) = @_;
	if($sid) {
		undef $storyBank{$sid};
	} else {
		undef %storyBank;
	}
}

########################################################
sub setStoryBySid {
	my ($self, $sid, $key, $value, $perm) = @_;
	# The idea with $perm, is that at some point, if you set it
	# it will update the database with the change you requested
	$storyBank{$sid}{$key} = $value;
}

########################################################
sub getSubmissionLast {
	my($self, $id, $formname) = @_;

	my $where = $self->whereFormkey($id);
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
########################################################
sub getStaticBlock {
  my ($self, $seclev) = @_;

	my $block_hash_ref={};
	my $sql = "SELECT bid,bid FROM blocks WHERE $seclev >= seclev AND type != 'portald'"; 
	my $sth = $self->{dbh}->prepare_cached($sql);
	$sth->execute;
	while (my($id, $desc) = $sth->fetchrow) {
		$block_hash_ref->{$id} = $desc;
	}
	$sth->finish;

	return  $block_hash_ref;
}

sub getPortaldBlock {
  my ($self, $seclev) = @_;

	my $block_hash_ref={};
	my $sql = "SELECT bid,bid FROM blocks WHERE $seclev >= seclev and type = 'portald'"; 
	my $sth = $self->{dbh}->prepare_cached($sql);
	$sth->execute;
	while (my($id, $desc) = $sth->fetchrow) {
		$block_hash_ref->{$id} = $desc;
	}
	$sth->finish;

	return  $block_hash_ref;
}
sub getColorBlock {
  my ($self) = @_;

	my $block_hash_ref={};
	my $sql = "SELECT bid,bid FROM blocks WHERE type = 'color'"; 
	my $sth = $self->{dbh}->prepare_cached($sql);
	$sth->execute;
	while (my($id, $desc) = $sth->fetchrow) {
		$block_hash_ref->{$id} = $desc;
	}
	$sth->finish;

	return  $block_hash_ref;
}
########################################################
sub getSectionblocks {
	my ($self) = @_;

	my $blocks = $self->sqlSelectAll("bid,title,ordernum", "sectionblocks", "portal=1", "order by bid");

	return $blocks;
}

########################################################
sub getLock {
	my ($self) = @_;
	my $locks = $self->sqlSelectAll('lasttitle,aid', 'sessions');

	return $locks;
}


########################################################
sub whereFormkey {
	my($self, $formkey_id) = @_;
	my $where;

	# anonymous user without cookie, check host, not formkey id
	if ($I{U}{anon_id} && ! $I{U}{anon_cookie}) {
		$where = "host_name = '$ENV{REMOTE_ADDR}'";
	} else {
		$where = "id='$formkey_id'";
	}

	return $where;
}

########################################################
sub updateFormkeyId {
	my($self, $formname, $formkey) = @_;
	if ($I{U}{uid} != $I{anonymous_coward} && $I{query}->param('rlogin') && length($I{F}{upasswd}) > 1) {
		sqlUpdate("formkeys", {
			id	=> $I{U}{uid},
			uid	=> $I{U}{uid},
		}, "formname='$formname' AND uid = $I{anonymous_coward} AND formkey=" .
			$self->{dbh}->quote($formkey));
	}
}

########################################################
sub insertFormkey {
	my($self, $formname, $id, $sid, $formkey, $uid, $remote ) = @_;


	# insert the fact that the form has been displayed, but not submitted at this point
	$self->sqlInsert("formkeys", {
		formkey		=> $formkey,
		formname 	=> $formname,
		id 		=> $id,
		sid		=> $sid,
		uid		=> $uid,
		host_name	=> $remote,
		value		=> 0,
		ts		=> time()
	});
}
########################################################
sub checkFormkey {
	my($self, $formkey_earliest, $formname, $formkey_id, $formkey) = @_;

	my $where = $self->whereFormkey($formkey_id);
	my($is_valid) = $self->sqlSelect('count(*)', 'formkeys',
		'formkey = ' . $self->{dbh}->quote($I{F}{formkey}) .
		" AND $where " .
		"AND ts >= $formkey_earliest AND formname = '$formname'");
	return($is_valid);
}

##################################################################
sub checkTimesPosted {
	my($self, $formname, $max, $id, $formkey_earliest) = @_;

	my $where = $self->whereFormkey($id);
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
	my ($self, $formkey) = @_;
	sqlUpdate("formkeys", {
			value   => -1,
			}, "formkey=" . $self->{dbh}->quote($formkey)
	);
}
##################################################################
# logs attempts to break, fool, flood a particular form
sub formAbuse {
  my ($self, $reason, $remote_addr, $script_name, $query_string) = @_;
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
	my ($self, $formkey, $formname) = @_;
	$self->sqlSelect(
	    "value,submit_ts",
			"formkeys", "formkey='$formkey' and formname = '$formname'"
			);
}

##################################################################
# Current admin users
sub currentAdmin {
my ($self) = @_;
  my $aids = $self->sqlSelectAll('aid,now()-lasttime,lasttitle', 'sessions',
			'aid=aid GROUP BY aid'
			#   'aid!=' . $self->{dbh}->quote($I{U}{aid}) . ' GROUP BY aid'
			);

	return $aids;
}
########################################################
# getTopic() 
# I'm torn, currently we just dump the entire database
# into topicBank if we don't find our topic. I am 
# wondering if it wouldn't be better to just grab them
# as needed (when we need them).
# Probably ought to spend some time to actually figure
# this out. 
# 
# -Brian
sub getTopic {
  my ($self, $topic) = @_;

	if($topic) {
		return $topicBank{$topic} if $topicBank{$topic};
	} else {
		return \%topicBank if (keys %topicBank);
	}
	# Lets go knock on the door of the database
	# and grab the Topic's since they are not cached
	# On a side note, I hate grabbing "*" from a database
	# -Brian
	my $sth = $self->sqlSelectMany('*', 'topics');
	while (my $single_topic = $sth->fetchrow_hashref) {
		$topicBank{ $single_topic->{tid} } = $single_topic;
	}
	$sth->finish;

	if($topic) {
		return $topicBank{$topic};
	} else {
		return \%topicBank;
	}
}

########################################################
# Need to change this method at some point... I hate
# useing a push
sub getTopNewsstoryTopics {
  my ($self, $all) = @_;
	my $when = "AND to_days(now()) - to_days(time) < 14" unless $all;
	my $order = $all ? "ORDER BY alttext" : "ORDER BY cnt DESC";
	my $topics=$self->sqlSelectAll("topics.tid, alttext, image, width, height, count(*) as cnt","topics,newstories",
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
#	my ($self) = @_;
#  my($qid) = $self->sqlSelect('qid', 'pollquestions', '', 'ORDER BY date DESC LIMIT 1');
#	return $qid;
#}

##################################################################
# Get poll
sub getPoll {
	my ($self, $qid) = @_;

	my $sth = $self->{dbh}->prepare_cached("
			SELECT question,answer,aid  from pollquestions, pollanswers
			WHERE pollquestions.qid=pollanswers.qid AND
			pollquestions.qid=$self->{dbh}->quote($qid)
			ORDER BY pollanswers.aid
	");
	$sth->execute;
	my $polls = $sth->fetchall_arrayref;
	$sth->finish;

	return $polls;
}
##################################################################
# Get poll
sub getPollVoters {
	my ($self, $qid) = @_;
	my($voters) = $self->sqlSelect('voters', 'pollquestions', " qid=$self-{dbh}->quote($qid)");

	return $voters;
}
sub getPollComments {
	my ($self, $qid) = @_;
	my($comments) = $self->sqlSelect('count(*)', 'comments', " sid=$self-{dbh}->quote($qid)");

	return $comments;
}
##################################################################
# Get submission count
sub getSubmissions{
	my ($self, $uid) = @_;
	my $submissions = $self->sqlSelectAll("time, subj, section, tid, del", "submissions", "uid=$uid");

	return $submissions;
}
##################################################################
# Get submission count
sub getSubmissionCount{
	my ($self, $articles_only) = @_;
	my($count);
	if($articles_only) {
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
	my ($self) = @_;
	# As a side note portal seems to only be a 1 and 0 in
	# in slash's database currently (even though since it
	# is a tinyint it could easily be a negative number).
	# It is a shame we are currently hitting the database
	# for this since the same info can be found in $commonportals
	my $strsql="SELECT block,title,blocks.bid,url
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
	my ($self) = @_;
	return ($boxes, $sectionBoxes) if (keys %$boxes);
	$boxes = {};
	$sectionBoxes = {};
	my $sth = $self->sqlSelectMany(
			'blocks.bid as bid,title,url,section,portal,ordernum',
			'sectionblocks,blocks',
			'sectionblocks.bid=blocks.bid ORDER BY ordernum ASC'
	);
	# We could get rid of tmp at some point
	my %tmp;
	while (my $SB = $sth->fetchrow_hashref) {
		$boxes->{$SB->{bid}} = $SB;  # Set the Slashbox
		next unless $SB->{ordernum} > 0;  # Set the index if applicable
		push @{$tmp{$SB->{section}}}, $SB->{bid};
	}
	$sectionBoxes = \%tmp;
	$sth->finish;

	return ($boxes, $sectionBoxes);
}
##################################################################
# counts the number of comments for a user
sub countComments {
	my ($self, $sid, $cid) = @_;
	my ($value) = $self->sqlSelect("count(*)", "comments", "sid=" . $self->{dbh}->quote($sid) . " AND pid = ". $self->{dbh}->quote($cid));

	return $value;
}
##################################################################
# counts the number of stories
sub countStory {
	my ($self, $tid) = @_;
	my ($value) = $self->sqlSelect("count(*)", "stories", "tid=" . $self->{dbh}->quote($tid));

	return $value;
}

##################################################################
sub checkForModerator {
	my ($self, $user) = @_;
	return unless $user->{willing};
	return if $user->{uid} < 1;
	return if $user->{karma} < 0;
	my($d) = $self->sqlSelect('to_days(now()) - to_days(lastmm)',
	'users_info', "uid = '$user->{uid}'");
}

##################################################################
sub setUserBoxes {
	my ($self, $uid, $exboxes) = @_;
	$self->sqlUpdate('users_index', { exboxes => $exboxes },
			"uid=$uid", 1)
}

##################################################################
sub getAuthorAids {
# getAids.... get aids... huhu,huhu...
	my ($self) = @_;
	my $aids = $self->sqlSelectAll("aid", "authors", "seclev > 99", "order by aid");

	return $aids;
}
##################################################################
sub refreshStories {
	my ($self, $sid) = @_;
	$self->sqlUpdate('stories',
			{ writestatus => 1 },
			'sid=' . $self->{dbh}->quote($sid) . ' and writestatus=0'
	);
}
##################################################################
sub getStoryByTime {
	my ($self, $sign, $sqltime, $isolate, $section, $extid, $exaid, $exsect) = @_;
	my ($where, $order);
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

#################################################################
#These methods should be the same
#and to be honest add little. Perfect for 
#a rewrite.
########################################################
sub setUsersKey{
	my ($self, $uid, $hashref) = @_;
	# Replace is a naughy thing
	$self->sqlReplace("users_key", $hashref);
}
########################################################
sub setUsersInfo{
	my ($self, $uid, $hashref) = @_;
	$self->sqlUpdate("users_info", $hashref, "uid=" . $uid . " AND uid>0", 1);
}
########################################################
sub setUsersComments{
	my ($self, $uid, $hashref) = @_;
	$self->sqlUpdate("users_info", $hashref, "uid=" . $uid . " AND uid>0", 1);
}
########################################################
sub setUsers{
	my ($self, $uid, $hashref) = @_;
	$self->sqlUpdate("users", $hashref, "uid=" . $uid . " AND uid>0", 1);
}
########################################################
sub setUsersPrefrences{
	my ($self, $uid, $hashref) = @_;
	$self->sqlUpdate("users_prefs", $hashref, "uid=" . $uid . " AND uid>0", 1);
}
########################################################
sub countStories{
	my ($self) = @_;
	my $stories = $self->sqlSelectAll("sid,title,section,commentcount,aid",
			"stories","", "ORDER BY commentcount DESC LIMIT 10"
			);
	return $stories;
}
########################################################
sub countStoriesStuff{
	my ($self) = @_;
	my $stories = $self->sqlSelectAll("stories.sid,title,section,storiestuff.hits as hits,aid",
			"stories,storiestuff","stories.sid=storiestuff.sid",
			"ORDER BY hits DESC LIMIT 10"
			);
	return $stories;
}
########################################################
sub countStoriesAuthors{
	my ($self) = @_;
	my $authors = $self->sqlSelectAll("count(*) as c, stories.aid, url", 
			"stories, authors","authors.aid=stories.aid",
			"GROUP BY aid ORDER BY c DESC LIMIT 10"
			);
	return $authors;
}
########################################################
sub countPollquestions{
	my ($self) = @_;
	my $pollquestions = $self->sqlSelectAll("voters,question,qid", "pollquestions",
			"1=1", "ORDER by voters DESC LIMIT 10"
			);
	return $pollquestions;
}
########################################################
sub countUsersIndexExboxesByBid{
	my ($self, $bid) = @_;
	my ($count) = $self->sqlSelect("count(*)","users_index",
			qq!exboxes like "%'$bid'%" !
			);

	return $count;
}
########################################################
sub getCommentsTop{
	my ($self, $sid, $user) = @_;
	my $where ="stories.sid=comments.sid"; 
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
my ($self) = @_;
# This is doing nothing (unless I am just missing the point). We grab
# them and then null them? -Brian
#  my($stuff) = $self->sqlSelect("story", "submissions", "subid='quickies'");
#	$stuff = "";
	$self->{dbh}->do("DELETE FROM submissions WHERE subid='quickies'");
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
sub getSubmission {
	my($self, $dateformat, $form, $user) = @_;
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
sub getSearch{
	my($self, $form, $user) =  @_;
	# select comment ID, comment Title, Author, Email, link to comment
	# and SID, article title, type and a link to the article
	my $sqlquery = "SELECT section, newstories.sid, aid, title, pid, subject, writestatus," .
		getDateFormat("time","d", $user) . ",".
		getDateFormat("date","t", $user) . ", 
		uid, cid, ";

	$sqlquery .= "	  " . $keysearch->($form->{query}, "subject", "comment") if $form->{query};
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
	my ($self, $storyid, $sid) = @_;
	my($title) = sqlSelect("title", "newstories",
	      "sid=" . $self->{dbh}->quote($sid)
				);

	return $title;
}

1;

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
