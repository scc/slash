package Slash::DB::Utility;

use strict;
	
($Slash::DB::Utility::VERSION) = ' $Revision$ ' =~ /\$Revision:\s+([^\s]+)/;

#Class variable that stores the database handle
my $dbh;

########################################################
# Useful SQL Wrapper Functions
########################################################

########################################################
sub sqlSelectMany {
	my($select, $from, $where, $other) = @_;

	my $sql = "SELECT $select ";
	$sql .= "   FROM $from " if $from;
	$sql .= "  WHERE $where " if $where;
	$sql .= "        $other" if $other;

	sqlConnect();
	my $sth = $dbh->prepare_cached($sql);
	if ($sth->execute) {
		return $sth;
	} else {
		$sth->finish;
		apacheLog($sql);
		die;
		return undef;
	}
}

########################################################
sub sqlSelect {
	my($select, $from, $where, $other) = @_;
	my $sql = "SELECT $select ";
	$sql .= "FROM $from " if $from;
	$sql .= "WHERE $where " if $where;
	$sql .= "$other" if $other;
	
	sqlConnect();
	my $sth = $dbh->prepare_cached($sql) or die "Sql has gone away\n";
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
sub sqlSelectHash {
	my $H = sqlSelectHashref(@_);
	return map { $_ => $H->{$_} } keys %$H;
}

##########################################################
# selectCount 051199
# inputs: scalar string table, scaler where clause 
# returns: via ref from input
# Simple little function to get the count of a table
##########################################################
sub selectCount  {
	my ($table, $where) = @_;

	my $sql = "SELECT count(*) AS count FROM $table $where";
	# we just need one stinkin value - count
	my $sth = $dbh->selectall_arrayref($sql);
	return $sth->[0][0];  # count
}

########################################################
sub sqlSelectHashref {
	my($select, $from, $where, $other) = @_;

	my $sql = "SELECT $select ";
	$sql .= "FROM $from " if $from;
	$sql .= "WHERE $where " if $where;
	$sql .= "$other" if $other;

	sqlConnect();
	my $sth = $dbh->prepare_cached($sql);
	# $sth->execute or print "\n<P><B>SQL Hashref Error</B><BR>\n";
	
	unless ($sth->execute) {
		apacheLog($sql);
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
	my($select, $from, $where, $other) = @_;

	my $sql = "SELECT $select ";
	$sql .= "FROM $from " if $from;
	$sql .= "WHERE $where " if $where;
	$sql .= "$other" if $other;

	sqlConnect();
	my $H = $dbh->selectall_arrayref($sql);
	return $H;
}

########################################################
sub sqlUpdate
{
	my($table, $data, $where, $lp) = @_;
	$lp = 'LOW_PRIORITY' if $lp;
	$lp = '';
	my $sql = "UPDATE $lp $table SET";
	foreach (keys %$data) {
		if (/^-/) {
			s/^-//;
			$sql .= "\n  $_ = $data->{-$_},";
		} else { 
			# my $d=$dbh->quote($data->{$_}) || "''";
			$sql .= "\n $_ = " . $dbh->quote($data->{$_}) . ',';
		}
	}
	chop $sql;
	$sql .= "\nWHERE $where\n";
	return $dbh->do($sql) or apacheLog($sql);
}

########################################################
sub sqlReplace {
	my($table, $data) = @_;
	my($names, $values);

	foreach (keys %$data) {
		if (/^-/) {
			$values .= "\n  $data->{$_},";
			s/^-//;
		} else {
			$values .= "\n  " . $dbh->quote($data->{$_}) . ',';
		}
		$names .= "$_,";
	}

	chop($names);
	chop($values);

	my $sql = "REPLACE INTO $table ($names) VALUES($values)\n";
	sqlConnect();
	return $dbh->do($sql) or apacheLog($sql);
}

########################################################
sub sqlInsert {
	my($table, $data, $delay) = @_;
	my($names, $values);

	foreach (keys %$data) {
		if (/^-/) {
			$values .= "\n  $data->{$_},";
			s/^-//;
		} else {
			$values .= "\n  " . $dbh->quote($data->{$_}) . ',';
		}
		$names .= "$_,";	
	}

	chop($names);
	chop($values);

	my $p = 'DELAYED' if $delay;
	my $sql = "INSERT $p INTO $table ($names) VALUES($values)\n";
	sqlConnect();
	return $dbh->do($sql) or apacheLog($sql) && kill 9, $$;
}

########################################################
sub sqlTableExists {
	my $table = shift or return;

	my $sth = $dbh->prepare_cached(qq!SHOW TABLES LIKE "$table"!);
	$sth->execute;
	my $te = $sth->rows;
	$sth->finish;
	return $te;
}

########################################################
sub sqlSelectColumns {
	my $table = shift or return;

	my $sth = $dbh->prepare_cached("SHOW COLUMNS FROM $table");
	$sth->execute;
	my @ret;
	while (my @d = $sth->fetchrow) {
		push @ret, $d[0];
	}
	$sth->finish;
	return @ret;
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
