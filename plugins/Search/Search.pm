# This code is a part of Slash, and is released under the GPL.
# Copyright 1997-2001 by Open Source Development Network. See README
# and COPYING for more information, or see http://slashcode.com/.
# $Id$

package Slash::Search;

use strict;
use Slash::DB::Utility;
use vars qw($VERSION);
use base 'Slash::DB::Utility';

($VERSION) = ' $Revision$ ' =~ /\$Revision:\s+([^\s]+)/;

# BENDER: The laws of science be a harsh mistress.

#################################################################
sub new {
	my($class, $user) = @_;
	my $self = {};

	bless($self, $class);
	$self->{virtual_user} = $user;
	$self->sqlConnect();

	return $self;
}

#################################################################
# Private method used by the search methods
sub _keysearch {
	my($self, $keywords, $columns) = @_;

	my @words = split m/ /, $keywords;
	my $sql;
	my $x = 0;
	my $latch = 0;

	for my $word (@words) {
		next if length $word < 3;
		last if $x++ > 3;
		$sql .= " AND " if $sql;
		$sql .= " ( ";
		$latch = 0;
		for (@$columns) {
			$sql .= " OR " if $latch;
			$sql .= "$_ LIKE " . $self->sqlQuote("%$word%"). " ";
			$latch++;
		}
		$sql .= " ) ";
	}
	# void context, does nothing?
	$sql = "0" unless $sql;

	return qq|($sql)|;
};


####################################################################################
# This has been changed. Since we no longer delete comments
# it is safe to have this run against stories.
sub findComments {
	my($self, $form, $start, $limit) = @_;
	# select comment ID, comment Title, Author, Email, link to comment
	# and SID, article title, type and a link to the article
	my $sql;
	$limit = " LIMIT $start, $limit" if $limit;

	my $key = $self->_keysearch($form->{query}, ['subject', 'comment']);

	# Welcome to the join from hell -Brian
	$sql = "SELECT section, stories.sid,";
	$sql .= " stories.uid as author, discussions.title as title, pid, subject, stories.flags as flags, time, date, comments.uid as uid, comments.cid as cid ";

	$sql .= "	  FROM stories, comments, comment_text, discussions WHERE ";

	$sql .= " stories.sid = discussions.sid ";
	$sql .= " AND comments.sid = discussions.id ";
	$sql .= " AND comments.cid = comment_text.cid ";
	$sql .= "	  AND $key "
			if $form->{query};

	$sql .= "     AND stories.sid=" . $self->sqlQuote($form->{sid})
			if $form->{sid};
	$sql .= "     AND points >= $form->{threshold} "
			if $form->{threshold};
	$sql .= "     AND section=" . $self->sqlQuote($form->{section})
			if $form->{section};
	$sql .= " ORDER BY date DESC, time DESC $limit ";


	my $cursor = $self->{_dbh}->prepare($sql);
	$cursor->execute;

	my $search = $cursor->fetchall_arrayref;
	return $search;
}

####################################################################################
sub findUsers {
	my($self, $form, $start, $limit, $users_to_ignore) = @_;
	# userSearch REALLY doesn't need to be ordered by keyword since you
	# only care if the substring is found.
	my $sql;
	$limit = " LIMIT $start, $limit" if $limit;

	$sql .= 'SELECT fakeemail,nickname,users.uid ';
	$sql .= ' FROM users ';
	$sql .= ' WHERE seclev > 0 ';
	my $x = 0;
	if ($users_to_ignore) {
		for my $user (@$users_to_ignore) {
			$sql .= ' AND ' if $x != 0;
			$sql .= " nickname != " .  $self->sqlQuote($user);
			$x++;
		}
	}

	if ($form->{query}) {
		$sql .= ' AND ';
		my $kw = $self->_keysearch($form->{query}, ['nickname', 'ifnull(fakeemail,"")']);
		$kw =~ s/as kw$//;
		$kw =~ s/\+/ OR /g;
		$sql .= " ($kw) ";
	}
	$sql .= " ORDER BY users.uid $limit";
	my $sth = $self->{_dbh}->prepare($sql);
	$sth->execute;

	my $users = $sth->fetchall_arrayref;

	return $users;
}

####################################################################################
sub findStory {
	my($self, $form, $start, $limit) = @_;
	$start ||= 0;

	my $story_table = getCurrentStatic('mysql_heap_table') ? 'story_heap' : 'stories';
	my $columns = "nickname, title, $story_table.sid as sid, time, commentcount, section";
	my $tables = "$story_table, story_text, users, discussions";
	my $other = " ORDER BY time DESC";
	$other .= " LIMIT $start, $limit" if $limit;

	# The big old searching WHERE clause, fear it
	my $key = $self->_keysearch($form->{query}, ['title', 'introtext']);
	my $where = "$story_table.sid = story_text.sid AND $story_table.uid = users.uid";
	$where .= " AND $key" if $form->{query};
	if ($form->{section}) { 
		$where .= " AND ((displaystatus = 0 and '$form->{section}' = '')";
		$where .= " OR (section = '$form->{section}' AND displaystatus >= 0))";
	} else {
		$where .= " AND displaystatus >= 0";
	}
	$where .= " AND time < now() AND NOT FIND_IN_SET('delete_me', flags) ";
	$where .= " AND $story_table.uid=" . $self->sqlQuote($form->{author})
		if $form->{author};
	$where .= " AND section=" . $self->sqlQuote($form->{section})
		if $form->{section};
	$where .= " AND tid=" . $self->sqlQuote($form->{topic})
		if $form->{topic};
	
	my $sql = "SELECT $columns FROM $tables WHERE $where $other";

	my $cursor = $self->{_dbh}->prepare($sql);
	$cursor->execute;
	my $stories = $cursor->fetchall_arrayref;

	return $stories;
}

#################################################################
sub DESTROY {
	my($self) = @_;
	$self->{_dbh}->disconnect unless $ENV{GATEWAY_INTERFACE};
}

1;
# Below is the stub of documentation for your module. You better edit it!

=head1 NAME

Slash::Search - Slash Search module

=head1 SYNOPSIS

	use Slash::Search;

=head1 DESCRIPTION

Slash search module.

Blah blah blah.

=head1 SEE ALSO

Slash(3).

=cut
