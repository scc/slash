package Slash::DB::Utility;

use strict;
use Slash::Utility;

($Slash::DB::Utility::VERSION) = ' $Revision$ ' =~ /\$Revision:\s+([^\s]+)/;

# BENDER: Oh no! Not the magnet! 

my $timeout = 30; #This should eventualy be a parameter that is configurable
#Class variable that stores the database handle

########################################################
# This should be inherited by all 3rd party modules
########################################################
sub sqlConnect {
# What we are going for here, is the ability to reuse
# the database connection.
# Ok, first lets see if we already have a connection
	my($self) = @_;

	if (defined($self->{_dbh})) {
		unless ($self->{_dbh}) {
			print STDERR ("Undefining and calling to reconnect: $@\n");
			$self->{_dbh}->disconnect;
			undef $self->{_dbh};
			$self->sqlConnect();
		}
	} else {
# Ok, new connection, lets create it
		{
			local @_;
			eval {
				local $SIG{'ALRM'} = sub { die "Connection timed out" };
				alarm $timeout;
				$self->{_dbh} = DBIx::Password->connect($self->{virtual_user});
				alarm 0;
			};
			if ($@) {
				#In the future we should have a backupdatabase
				#connection in here. For now, we die
				print STDERR "Major Mojo Bad things\n";
				print STDERR "unable to connect to MySQL: $@ : $DBI::errstr\n";
				kill 9, $$ unless $self->{_dbh};	 # The Suicide Die
			}
		}
	}
}
########################################################
# Useful SQL Wrapper Functions
########################################################
sub sqlSelectMany {
	my($self, $select, $from, $where, $other) = @_;

	my $sql = "SELECT $select ";
	$sql .= "   FROM $from " if $from;
	$sql .= "  WHERE $where " if $where;
	$sql .= "        $other" if $other;

	my $sth = $self->{_dbh}->prepare_cached($sql);
	$self->sqlConnect();
	if ($sth->execute) {
		return $sth;
	} else {
		$sth->finish;
		errorLog($sql);
		return undef;
	}
}

########################################################
sub sqlSelect {
	my($self, $select, $from, $where, $other) = @_;
	my $sql = "SELECT $select ";
	$sql .= "FROM $from " if $from;
	$sql .= "WHERE $where " if $where;
	$sql .= "$other" if $other;
	
	my $sth = $self->{_dbh}->prepare_cached($sql);
	$self->sqlConnect();
	if (!$sth->execute) {
		errorLog($sql);
		return undef;
	}
	my @r = $sth->fetchrow;
	$sth->finish;

	return @r;
}

########################################################
sub sqlSelectArrayRef {
	my($self, $select, $from, $where, $other) = @_;
	my $sql = "SELECT $select ";
	$sql .= "FROM $from " if $from;
	$sql .= "WHERE $where " if $where;
	$sql .= "$other" if $other;
	
	$self->sqlConnect();
	my $sth = $self->{_dbh}->prepare_cached($sql);
	if (!$sth->execute) {
		errorLog($sql);
		return undef;
	}
	my $r = $sth->fetchrow_arrayref;
	return $r;
}

########################################################
sub sqlSelectHash {
	my($self) = @_;
	my $hash = $self->sqlSelectHashref(@_);
	return map { $_ => $hash->{$_} } keys %$hash;
}

##########################################################
# selectCount 051199
# inputs: scalar string table, scaler where clause 
# returns: via ref from input
# Simple little function to get the count of a table
##########################################################
sub selectCount  {
	my($self, $table, $where) = @_;

	my $sql = "SELECT count(*) AS count FROM $table $where";
	# we just need one stinkin value - count
	$self->sqlConnect();
	my $sth = $self->{_dbh}->selectall_arrayref($sql);
	return $sth->[0][0];  # count
}

########################################################
sub sqlSelectHashref {
	my($self, $select, $from, $where, $other) = @_;

	my $sql = "SELECT $select ";
	$sql .= "FROM $from " if $from;
	$sql .= "WHERE $where " if $where;
	$sql .= "$other" if $other;

	$self->sqlConnect();
	my $sth = $self->{_dbh}->prepare_cached($sql);
	
	unless ($sth->execute) {
		errorLog($sql);
		return;
	} 
	my $H = $sth->fetchrow_hashref;
	$sth->finish;
	return $H;
}

########################################################
# sqlSelectAll - this function returns the entire 
# array ref of all records selected. Use this in the case
# where you want all the records and have to do a time consuming
# process that would tie up the db handle for too long.   
# 
# inputs: 
# select - columns selected 
# from - tables 
# where - where clause 
# other - limit, asc ...
#
# returns: 
# array ref of all records
sub sqlSelectAll {
	my($self, $select, $from, $where, $other) = @_;

	my $sql = "SELECT $select ";
	$sql .= "FROM $from " if $from;
	$sql .= "WHERE $where " if $where;
	$sql .= "$other" if $other;

	$self->sqlConnect();
	my $H = $self->{_dbh}->selectall_arrayref($sql);
	return $H;
}

########################################################
sub sqlUpdate {
	my($self, $table, $data, $where) = @_;
	my $sql = "UPDATE $table SET";
	foreach (keys %$data) {
		if (/^-/) {
			s/^-//;
			$sql .= "\n  $_ = $data->{-$_},";
		} else { 
			$sql .= "\n $_ = " . $self->{_dbh}->quote($data->{$_}) . ',';
		}
	}
	chop $sql;
	$sql .= "\nWHERE $where\n";
	$self->sqlConnect();
	my $rows = $self->{_dbh}->do($sql);
	#print STDERR "SQL: $sql\n";
	errorLog($sql) unless($rows);
	return $rows;
}

########################################################
sub sqlInsert {
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

	my $sql = "INSERT INTO $table ($names) VALUES($values)\n";
	$self->sqlConnect();
	return $self->{_dbh}->do($sql) or errorLog($sql);
}



#################################################################
sub sqlDo {
	my($self, $sql) = @_;
	$self->sqlConnect();
	$self->{_dbh}->do($sql) or errorLog($sql);
}

1;

=head1 NAME

Slash::DB::Utility - Generic SQL code which is common to all DB interfaces for Slashcode

=head1 SYNOPSIS

  use Slash::DB::Utility;

=head1 DESCRIPTION

No documentation yet.

=head1 AUTHOR

Brian Aker, brian@tangent.org

=head1 SEE ALSO

Slash(3). Slash::DB(3)

=cut
