# This code is a part of Slash, and is released under the GPL.
# Copyright 1997-2001 by Open Source Development Network. See README
# and COPYING for more information, or see http://slashcode.com/.
# $Id$

package Slash::Messages::DB::MySQL;

=head1 NAME

Slash::Messages - Send messages for Slash


=head1 SYNOPSIS

	# basic example of usage

=head1 DESCRIPTION

LONG DESCRIPTION.

=cut

use strict;
use vars qw($VERSION @ISA);
use Slash::DB;
use Slash::DB::Utility;
use Slash::Utility;
use Storable qw(freeze thaw);

($VERSION) = ' $Revision$ ' =~ /\$Revision:\s+([^\s]+)/;
@ISA       = qw(Slash::DB::Utility);

my %descriptions = (
	'deliverymodes'
		=> sub { $_[0]->sqlSelectMany('code,name', 'code_param', "type='deliverymodes'") },
	'messagecodes'
		=> sub { $_[0]->sqlSelectMany('code,name', 'code_param', "type='messagecodes'") },
);

sub getDescriptions {
	my($self, $codetype, $optional, $flag) =  @_;
	return unless $codetype;
	my $codeBank_hash_ref = {};
	my $cache = '_getDescriptions_' . $codetype;

	if ($flag) {
		undef $self->{$cache};
	} else {
		return $self->{$cache} if $self->{$cache}; 
	}

	my $sth = $descriptions{$codetype}->(@_);
	while (my($id, $desc) = $sth->fetchrow) {
		$codeBank_hash_ref->{$id} = $desc;
	}
	$sth->finish;

	$self->{$cache} = $codeBank_hash_ref if getCurrentStatic('cache_enabled');
	return $codeBank_hash_ref;
}

sub init {
	my($self, @args) = @_;
	$self->{_drop_table} = 'message_drop';
	$self->{_drop_cols}  = 'id,uid,code,message,fid,date';
	$self->{_drop_prime} = 'id';
	$self->{_drop_store} = 3;
}


sub _create {
	my($self, $uid, $type, $message, $fid) = @_;
	my $table = $self->{_drop_table};

	# fix scalar to be a ref for freezing
	my $frozen = freeze(ref $message ? $message : \$message);
	$self->sqlInsert($table, {
		uid	=> $uid,
		fid	=> $fid,
		code	=> $type,
		message	=> $frozen,
	});

	my($msg_id) = $self->sqlSelect("LAST_INSERT_ID()");
	return $msg_id;
}

sub _get {
	my($self, $msg_id) = @_;
	my $table = $self->{_drop_table};
	my $cols  = $self->{_drop_cols};
	my $prime = $self->{_drop_prime};
	my $store = $self->{_drop_store};

	my $id_db = $self->sqlQuote($msg_id);

	my $data = $self->sqlSelectAll(
		$cols, $table, "$self->{_drop_prime}=$id_db"
	);

	$data = $data->[0];
	$data->[$store] = thaw($data->[$store]);
	# return scalar as scalar, not ref
	$data->[$store] = ${$data->[$store]} if ref($data->[$store]) eq 'SCALAR';
	return $data;
}

sub _gets {
	my($self, $count, $delete) = @_;
	my $table = $self->{_drop_table};
	my $cols  = $self->{_drop_cols};
	my $store = $self->{_drop_store};

	$count = 1 if $count =~ /\D/;
	my $other = "ORDER BY date ASC";
	$other .= " LIMIT $count" if $count;

	my $all = $self->sqlSelectAll(
		$cols, $table, '', $other
	);

	for my $data (@$all) {
		$data->[$store] = thaw($data->[$store]);
		$data->[$store] = ${$data->[$store]} if ref($data->[$store]) eq 'SCALAR';
	}

	return $all;
}

sub _delete {
	my($self, $id) = @_;
	my $table = $self->{_drop_table};
	my $prime = $self->{_drop_prime};
	my $id_db = $self->{_dbh}->quote($id);
	my $where = "$prime=$id_db";

	$self->sqlDo("DELETE FROM $table WHERE $where");
}


1;

__END__

