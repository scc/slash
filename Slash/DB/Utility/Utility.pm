package Slash::DB::Utility;

use strict;
use Slash::Utility;

	
($Slash::DB::Utility::VERSION) = ' $Revision$ ' =~ /\$Revision:\s+([^\s]+)/;

#Class variable that stores the database handle

########################################################
# Useful SQL Wrapper Functions
########################################################

sub sanityCheck {
	print STDERR "Sanity Check for Utility\n";
}
########################################################
sub sqlSelectMany {
	my($self, $select, $from, $where, $other) = @_;

	my $sql = "SELECT $select ";
	$sql .= "   FROM $from " if $from;
	$sql .= "  WHERE $where " if $where;
	$sql .= "        $other" if $other;

	my $sth = $self->{dbh}->prepare_cached($sql);
	$self->sqlConnect();
	if ($sth->execute) {
		return $sth;
	} else {
		$sth->finish;
		apacheLog($sql);
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
	
	my $sth = $self->{dbh}->prepare_cached($sql);
	$self->sqlConnect();
	if (!$sth->execute) {
		apacheLog($sql);
		# print "\n<P><B>SQL Error</B><BR>\n";
		# kill 9,$$;
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
	my $sth = $self->{dbh}->prepare_cached($sql);
	if (!$sth->execute) {
		apacheLog($sql);
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
	my $sth = $self->{dbh}->selectall_arrayref($sql);
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
	my $sth = $self->{dbh}->prepare_cached($sql);
	# $sth->execute or print "\n<P><B>SQL Hashref Error</B><BR>\n";
	
	#print STDERR "SQL: $sql \n";
	unless ($sth->execute) {
		apacheLog($sql);
		return;
		#kill 9,$$;
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
	my $H = $self->{dbh}->selectall_arrayref($sql);
	return $H;
}

########################################################
sub sqlUpdate
{
	my($self, $table, $data, $where, $lp) = @_;
	$lp = 'LOW_PRIORITY' if $lp;
	$lp = '';
	my $sql = "UPDATE $lp $table SET";
	foreach (keys %$data) {
		if (/^-/) {
			s/^-//;
			$sql .= "\n  $_ = $data->{-$_},";
		} else { 
			# my $d=$self->{dbh}->quote($data->{$_}) || "''";
			$sql .= "\n $_ = " . $self->{dbh}->quote($data->{$_}) . ',';
		}
	}
	chop $sql;
	$sql .= "\nWHERE $where\n";
	$self->sqlConnect();
	my $rows = $self->{dbh}->do($sql);
#	print STDERR "SQL: $sql\n";
	apacheLog($sql) unless($rows);
	return $rows;
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
			$values .= "\n  " . $self->{dbh}->quote($data->{$_}) . ',';
		}
		$names .= "$_,";
	}

	chop($names);
	chop($values);

	my $sql = "REPLACE INTO $table ($names) VALUES($values)\n";
	$self->sqlConnect();
	return $self->{dbh}->do($sql) or apacheLog($sql);
}

########################################################
sub sqlInsert {
	my($self, $table, $data, $delay) = @_;
	my($names, $values);

	foreach (keys %$data) {
		if (/^-/) {
			$values .= "\n  $data->{$_},";
			s/^-//;
		} else {
			$values .= "\n  " . $self->{dbh}->quote($data->{$_}) . ',';
		}
		$names .= "$_,";	
	}

	chop($names);
	chop($values);

	my $p = 'DELAYED' if $delay;
	my $sql = "INSERT $p INTO $table ($names) VALUES($values)\n";
	$self->sqlConnect();
	return $self->{dbh}->do($sql) or apacheLog($sql) && kill 9, $$;
}

########################################################
sub getKeys {
	my($self, $table) = @_;
	$self->sqlSelectColumns($table)
		if $self->sqlTableExists($table);

}
########################################################
sub sqlTableExists {
	my($self, $table) = @_;
	return unless $table;

	my $sth = $self->{dbh}->prepare_cached(qq!SHOW TABLES LIKE "$table"!);
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

	my $sth = $self->{dbh}->prepare_cached("SHOW COLUMNS FROM $table");
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

#################################################################
sub getSectionBlocksByBid {
	my($self, $bid) = @_;
	$self->sqlConnect();
	$self->sqlSelect(
		"title,block,url", "blocks, sectionblocks",
		"blocks.bid = sectionblocks.bid AND blocks.bid = "
		. $self->{dbh}->quote($bid)
	);
}
#################################################################
sub sqlDo {
	my($self, $sql) = @_;
	$self->sqlConnect();
	$self->{dbh}->do($sql);
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
