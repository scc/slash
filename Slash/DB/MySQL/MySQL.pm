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
# silly. Really I should change these over to just 
# grabbing hashref's.
#
  my ($self, $codeBank_hash_ref, $codetype) = @_;
	my $sth;
	$codeBank_hash_ref={};
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
	while (my($id, $desc) = $sth->fetchrow) {
		$codeBank_hash_ref->{$id} = $desc;
	}
	$sth->finish;
}

########################################################
sub getFormatDescriptions {
# Creating three different methods for this seems a bit
# silly. Really I should change these over to just 
# grabbing hashref's.
#
  my ($self, $codetype) = @_;
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
	my ($self, $sectionbank) = @_;
	unless ($sectionbank) {
		my $sth = $self->sqlSelectMany('*', 'sections');
		while (my $S = $sth->fetchrow_hashref) {
			$sectionbank->{ $S->{section} } = $S;
		}
		$sth->finish;
	}
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
sub getStoryBySid {
	my ($self, $sid, $member) = @_;
	
	if($member) {
		return $storyBank{$sid}->{$member} if $storyBank{$sid}->{$member};
	}

#	return $storyBank{$sid} if defined($storyBank{$sid});
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
	print "clearStory() was called\n";
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


1;

=head1 NAME

Slash::DB::MySQL - MySQL Interface for Slashcode

=head1 SYNOPSIS

  use Slash::DB::MySQL;

=head1 DESCRIPTION

No documentation yet.

=head1 AUTHOR

Brian Aker, brian@tangent.org

=head1 SEE ALSO

Slash(3). Slash::DB(3)

=cut
