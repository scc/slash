package Slash::DB::MySQL;

use strict;
use DBI;
use Slash::DB::Utility;
use Slash::Utility;

@Slash::DB::MySQL::ISA = qw( Slash::DB::Utility );
($Slash::DB::MySQL::VERSION) = ' $Revision$ ' =~ /\$Revision:\s+([^\s]+)/;

my ($dsn ,$dbuser, $dbpass, $dbh);
my $timeout = 30; #This should eventualy be a parameter that is configurable

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
		$sth = $self->sqlSelectMany('code,name', $codetype);
	}
	if($codetype eq 'tzcodes') {
		$sth = $self->sqlSelectMany('tz,offset', $codetype);
	}
	if($codetype eq 'dateformats') {
		$sth = $self->sqlSelectMany('id,format', $codetype);
	}
	while (my($id, $desc) = $sth->fetchrow) {
		$codeBank_hash_ref->{$id} = $desc;
	}
	$sth->finish;
}

########################################################
# Get user info from the users table.
sub getUserInfo{
  my($self, $uid, $passwd) = @_;
	my $user = $self->sqlSelectHashref('*', 'users',
		' uid = ' . $self->{dbh}->quote($uid) .
		' AND passwd = ' . $self->{dbh}->quote($passwd)
	);

	return $user;
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
