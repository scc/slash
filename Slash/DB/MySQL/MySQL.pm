package Slash::DB::MySQL;

use strict;
use DBI;
use Slash::DB::Utility;
use Slash::Utility;

@Slash::DB::MySQL::ISA = qw( Slash::DB::Utility );
($Slash::DB::MySQL::VERSION) = ' $Revision$ ' =~ /\$Revision:\s+([^\s]+)/;

my ($dsn ,$dbuser, $dbpass, $dbh);
my $timeout = 30; #This should eventualy be a parameter that is configurable
my %authorBank; # This is here to save us a database call
my %storyBank; # This is here to save us a database call
my %topicBank; # This is here to save us a database call
my %codeBank; # This is here to save us a database call

########################################################
sub sqlConnect {
# What we are going for here, is the ability to reuse
# the database connection.
# Ok, first lets see if we already have a connection
	my $self = shift;
	if(@_) {
		($dsn ,$dbuser, $dbpass) = @_;
	}
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
				$self->{dbh} = DBI->connect($dsn, $dbuser, $dbpass);
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
sub getFormatDescriptions {
# Creating three different methods for this seems a bit
# silly. 
# This is getting way to long... probably should
# become a generic getDescription method
  my $self = shift; # Shit off to keep things clean
  my $codetype = shift; # Shit off to keep things clean
	my $sth;
	my $codeBank_hash_ref={};
	if($codetype eq 'sortcodes') {
		$sth = $self->sqlSelectMany('code,name', 'sortcodes');
	}
	if($codetype eq 'tzcodes') {
		$sth = $self->sqlSelectMany('tz,description', 'tzcodes');
	}
	if($codetype eq 'dateformats') {
		$sth = $self->sqlSelectMany('id,description', 'dateformats');
	}
	if($codetype eq 'commentmodes') {
		$sth = $self->sqlSelectMany('mode,name', 'commentmodes');
	}
	if($codetype eq 'threshcodes') {
		$sth = $self->sqlSelectMany('thresh,description', 'threshcodes');
	}
	if($codetype eq 'postmodes') {
		$sth = $self->sqlSelectMany('code,name', 'postmodes');
	}
	if($codetype eq 'isolatemodes') {
		$sth = $self->sqlSelectMany('code,name', 'isolatemodes');
	}
	if($codetype eq 'issuemodes') {
		$sth = $self->sqlSelectMany('code,name', 'issuemodes');
	}
	if($codetype eq 'vars') {
		$sth = $self->sqlSelectMany('name,description', 'vars');
	}
	if($codetype eq 'topics') {
		$sth = $self->sqlSelectMany('tid,alttext', 'topics');
	}
	if($codetype eq 'maillist') {
		$sth = $self->sqlSelectMany('code,name', 'maillist');
	}
	if($codetype eq 'displaycodes') {
		$sth = $self->sqlSelectMany('code,name', 'displaycodes');
	}
	if($codetype eq 'commentcodes') {
		$sth = $self->sqlSelectMany('code,name', 'commentcodes');
	}
	while (my($id, $desc) = $sth->fetchrow) {
		$codeBank_hash_ref->{$id} = $desc;
	}
	$sth->finish;

	return  $codeBank_hash_ref;
}
########################################################
# Get user info from the users table.
sub getUserInfo{
  my($self, $uid, $passwd, $script) = @_;
	my $user = $self->sqlSelectHashref('*', 'users',
		' uid = ' . $self->{dbh}->quote($uid) .
		' AND passwd = ' . $self->{dbh}->quote($passwd)
	);
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
sub getUserUID{
  my($self, $name, $passwd) = @_;

	$self->sqlSelect('uid', 'users',
			'passwd=' . $self->{dbh}->quote($passwd) .
			' AND nickname=' . $self->{dbh}->quote($name)
	);

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

sub getSubmissionLast {
my ($self, $id, $formname) = @_;
  my($last_submitted) = $self->sqlSelect(
		"max(submit_ts)",
		"formkeys",
		"id = '$id' AND formname = '$formname'");
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
sub getLock {
	my ($self, $subj, $return_array) = @_;
	my $sth = $self->sqlSelectMany('lasttitle,aid', 'sessions');
	my @session;
	while (my($thissubj, $aid) = $sth->fetchrow) {
		push( @$return_array, [$thissubj, $aid]);	
	}
	$sth->finish;
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

	# make sure that there's a valid form key, and we only care about formkeys
	# submitted $formkey_earliest seconds ago
	my($is_valid_formkey) = $self->sqlSelect("count(*)", "formkeys",
		"ts >= $formkey_earliest AND formname = '$formname' and " .
		"id='$formkey_id' and formkey=" .
		$self->{dbh}->quote($formkey));

	return($is_valid_formkey);
}

##################################################################
sub checkTimesPosted {
	my($self, $formname, $max, $id, $formkey_earliest) = @_;
	my($times_posted) = $self->sqlSelect(
		"count(*) as times_posted",
		"formkeys",
		"id = '$id' AND submit_ts >= $formkey_earliest AND formname = '$formname'");

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

##################################################################
# logs attempts to break, fool, flood a particular form
getSubmissionCount{
	my ($self) = @_;
	$self->sqlSelect("count(*)", "submissions", "del=0");
}

return;
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
  my $sth = $self->sqlSelectMany('aid,now()-lasttime,lasttitle', 'sessions',
			'aid=aid GROUP BY aid'
			#   'aid!=' . $self->{dbh}->quote($I{U}{aid}) . ' GROUP BY aid'
			);

	my @aids;
	while (my @row = $sth->fetchrow) {
		push @aids, \@row;
	}

	$sth->finish;
	return \@aids;
}
########################################################
# getTopic() 
# I'm torn, currently we just dump the entire database
# into topicBank if we don't find out topic. I am 
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


	my @polls;
	while (my @row = $sth->fetchrow) {
		push @polls, \@row;
	}
	$sth->finish;

	return \@polls;
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
# Get poll
sub getSubmissionCount{
	my ($self, $articles_only) = @_;
	my($cnt) = $self->sqlSelect('count(*)', 'submissions',
			"(length(note)<1 or isnull(note)) and del=0" .
			($articles_only ? " and section='articles'" : '')
	);
	return $cnt;
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
