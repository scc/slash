package Slash::Journal;

use strict;
use vars qw($VERSION @ISA @EXPORT @EXPORT_OK);
use DBIx::Password;
use Slash::DB::Utility;


@Slash::Journal::ISA = qw(Slash::DB::Utility);
@Slash::Journal::EXPORT = qw();
$Slash::Journal::VERSION = '0.01';

sub new {
	my ($class, $user) = @_;
	my $self = {};
	bless ($self,$class);
	$self->{_dbh} = DBIx::Password->connect($user);

	return $self;
}

sub set {
	my ($self, $id, $values) = @_;
	my $uid = $ENV{SLASH_USER};
	$self->sqlUpdate('journals', $values, "uid=$uid AND id=$id");
}

sub gets {
	my ($self, $uid, $values) = @_;
	my $keys = join ',', @$values if $values;
	$keys ||= '*';
	my $answer = $self->sqlSelectAll($keys, 'journals', "uid = $uid");
	return $answer;
}
sub get {
	my $answer = _genericGet('journals', 'id', @_);
	return $answer;
}

sub create {
	my ($self, $description, $article) = @_;
	my $uid = $ENV{SLASH_USER};
	$self->sqlInsert("journals", {
		uid => $uid,
		description => $description,
		article => $article,
		-date => 'now()'
	});
	my($id) = $self->sqlSelect("LAST_INSERT_ID()");
	
	return $id;
}

sub friends {
	my ($self) = @_;
	my $uid = $ENV{SLASH_USER};
	my $sql;
	$sql .= "SELECT u.nickname, j.friend, MAX(jo.date) as date ";
	$sql .= " FROM journals as jo, journal_friends as j,users as u ";
	$sql .= " WHERE j.uid = $uid AND j.friend = u.uid AND j.friend = jo.uid";
	$sql .= " GROUP BY u.nickname ORDER BY date DESC";
	my $friends = $self->{_dbh}->selectall_arrayref($sql);

	return $friends;
}

sub add {
	my ($self, $friend) = @_;
	my $uid = $ENV{SLASH_USER};
	$self->{_dbh}->do("INSERT INTO journal_friends (uid,friend) VALUES ($uid, $friend)");
}

sub delete {
	my ($self, $friend) = @_;
	my $uid = $ENV{SLASH_USER};
	$self->{_dbh}->do("DELETE FROM  journal_friends WHERE uid=$uid AND friend=$friend");
}

sub top {
	my ($self, $limit) = @_;
	$limit ||= 10;
	my $sql;
	$sql .= "SELECT count(j.uid) as c, u.nickname, j.uid ";
	$sql .= " FROM journals as j,users as u WHERE ";
	$sql .= " j.uid = u.uid";
	$sql .= " GROUP BY u.nickname ORDER BY c DESC";
	$sql .= " LIMIT $limit";
	my $losers = $self->{_dbh}->selectall_arrayref($sql);

	return $losers;
}

########################################################
# This is protected and don't call it from your
# scripts directly.
sub _genericGet {
	my($table, $table_where, $self, $id, $val) = @_;
	my $answer;

	if((ref($val) eq 'ARRAY')) {
		my $values = join ',', @$val;
		$answer = $self->sqlSelectHashref($values, $table, $table_where . '=' . $self->{_dbh}->quote($id));
	} elsif ($val) {
		($answer) = $self->sqlSelect($val, $table, $table_where . '='  . $self->{_dbh}->quote($id));
	} else {
		$answer = $self->sqlSelectHashref('*', $table, $table_where . '=' . $self->{_dbh}->quote($id));
	}

	return $answer;
}

sub DESTROY {
	my ($self) = @_;
	$self->{_dbh}->disconnect;
}


1;
__END__
# Below is the stub of documentation for your module. You better edit it!

=head1 NAME

Slash::Journal - Journal system splace

=head1 SYNOPSIS

  use Slash::Journal;

=head1 DESCRIPTION

This is a port of Tangent's journal system. 

Blah blah blah.

=head1 AUTHOR

Brian Aker, brian@tangent.org

=head1 SEE ALSO

perl(1).

=cut
