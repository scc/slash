package Slash::DB::Static::MySQL;
use strict;
use DBIx::Password;
use Slash::DB::Utility;
use Slash::Utility;
use URI ();

($Slash::DB::Static::MySQL::VERSION) = ' $Revision$ ' =~ /\$Revision:\s+([^\s]+)/;
1;


########################################################
# For slashd
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
# For slashd
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
# For slashd
sub getStoriesForSlashdb {
	my($self) = @_;

	my $returnable = $self->sqlSelectAll("sid,title,section", 
			"stories", "writestatus=1");

	return $returnable;
}

########################################################
# For dailystuff
sub deleteDaily {
	my ($self) = @_;
	my $constants = getCurrentStatic();

	my $delay1 = $constants->{archive_delay} * 2;
	my $delay2 = $constants->{archive_delay} * 9;
	$constants->{defaultsection} ||= 'articles';

	$self->sqlDo("DELETE FROM newstories WHERE
			(section='$constants->{defaultsection}' and to_days(now()) - to_days(time) > $delay1)
			or (to_days(now()) - to_days(time) > $delay2)");

	$self->sqlDo("DELETE FROM comments where to_days(now()) - to_days(date) > $constants->{archive_delay}");

	# Now for some random stuff
	$self->sqlDo("DELETE from pollvoters");
	$self->sqlDo("DELETE from moderatorlog WHERE
	  to_days(now()) - to_days(ts) > $constants->{archive_delay} ");
	$self->sqlDo("DELETE from metamodlog WHERE
		to_days(now()) - to_days(ts) > $constants->{archive_delay} ");
	# Formkeys
	my $delete_time = time() - $constants->{'formkey_timeframe'};
	$self->sqlDo("DELETE FROM formkeys WHERE ts < $delete_time");
}

########################################################
# For dailystuff
sub countDaily {
	my ($self) = @_;
	my %returnable;

	my $constants = getCurrentStatic();

	($returnable{'total'}) = $self->sqlSelect("count(*)", "accesslog",
		"to_days(now()) - to_days(ts)=1");

	my $c = $self->sqlSelectMany("count(*)","accesslog",
		"to_days(now()) - to_days(ts)=1 GROUP BY host_addr");
	returnable{'unique'} = $c->rows;
	$c->finish;

#	my ($comments) = $self->sqlSelect("count(*)","accesslog",
#		"to_days(now()) - to_days(ts)=1 AND op='comments'");

	$c = $self->sqlSelectMany("dat,count(*)","accesslog",
		"to_days(now()) - to_days(ts)=1 AND 
		(op='index' OR dat='index')
		GROUP BY dat");

	my(%indexes, %articles, %commentviews);

	while(my($sect, $cnt) = $c->fetchrow) {
		$indexes{$sect} = $cnt;
	}
	$c->finish;

	$c = $self->sqlSelectMany("dat,count(*),op","accesslog",
		"to_days(now()) - to_days(ts)=1 AND op='article'",
		"GROUP BY dat");

	while(my($sid, $cnt) = $c->fetchrow) {
		$articles{$sid} = $cnt;
	}
	$c->finish;

	# clean the key table


	$c = $self->sqlSelectMany("dat,count(*)","accesslog",
		"to_days(now()) - to_days(ts)=1 AND op='comments'",
		"GROUP BY dat");
	while(my($sid, $cnt) = $c->fetchrow) {
		$commentviews{$sid} = $cnt;
	}
	$c->finish;

	$self->sqlDo("delete from accesslog where date_add(ts,interval 48 hour) < now()");
	$returnable{'index'} = \%indexes;
	$returnable{'articles'} = \%articles;


	return \%returnable;
}

########################################################
# For dailystuff
sub updateStamps {
	my ($self) = @_;
	my $columns = "uid";
	my $tables = "accesslog";
	my $where = "to_days(now())-to_days(ts)=1 AND uid > 0";
	my $other = "GROUP BY uid";

	my $E = $self->sqlSelectAll($columns, $tables, $where, $other);

	$self->sqlDo("LOCK TABLES users_info WRITE");

	for (@{$E}) {
		my $uid=$_->[0];
		$self->setUser($uid, {-lastaccess=>'now()'});
	}
	$self->sqlDo("UNLOCK TABLES");
}

########################################################
# For dailystuff
sub cleanFormKeys {
	my ($self) = @_;


}

########################################################
# For dailystuff
sub getDailyMail {	
	my ($self) = @_;
	my $columns = "sid,title,section,aid,tid,date_format(time,\"\%W \%M \%d, \@h:\%i\%p\"),dept";
	my $tables = "stories";
	my $where = "to_days(now()) - to_days(time) = 1 AND displaystatus=0 AND time < now()";
	my $other = " ORDER BY time DESC";

	my $email = $self->sqlSelectAll($columns,$tables,$where,$other);

	return $email;
}
########################################################
# For dailystuff
sub getMailingList {
	my($self) = @_;

	my $columns ="realemail,mode,nickname";
	my $tables = "users,users_comments,users_info";
	my $where = "users.uid=users_comments.uid AND users.uid=users_info.uid AND maillist=1";
	my $other = "order by realemail";

	my $users = $self->sqlSelectAll($columns,$tables,$where,$other);

	return $users;
}

1;
__END__

=head1 NAME

Slash::DB::Static::MySQL - MySQL Interface for Slashcode

=head1 SYNOPSIS

  use Slash::DB::Static::MySQL;

=head1 DESCRIPTION

No documentation yet. Sue me.

=head1 AUTHOR

Brian Aker, brian@tangent.org

=head1 SEE ALSO

Slash(3). Slash::DB(3)

=cut
