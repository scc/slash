package Slash::Search;

use strict;
use Slash::DB::Utility;

$Slash::Search::VERSION = '0.01';
@Slash::Search::ISA = qw( Slash::DB::Utility );

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
	my $self = shift;
	my $keywords = shift;
	my @columns = @_;

	my @words = split m/ /, $keywords;
	my $sql;
	my $x = 0;

	foreach my $w (@words) {
		next if length $w < 3;
		last if $x++ > 3;
		foreach my $c (@columns) {
			$sql .= "+" if $sql;
			$sql .= "($c LIKE " . $self->{_dbh}->quote("%$w%") . ")";
		}
	}
	# void context, does nothing?
	$sql = "0" unless $sql;
	$sql .= " as kw";
	return $sql;
};


####################################################################################
sub find {
	my($self) = @_;
	# select comment ID, comment Title, Author, Email, link to comment
	# and SID, article title, type and a link to the article
	my $form = getCurrentForm();
	my $threshold = getCurrentUser('threshold');
	my $sqlquery = "SELECT section, newstories.sid, aid, title, pid, subject, writestatus," .
		getDateFormat("time","d") . ",".
		getDateFormat("date","t") . ",
		uid, cid, ";

	$sqlquery .= "	  " . $self->_keysearch->($self, $form->{query}, "subject", "comment") if $form->{query};
	$sqlquery .= "	  1 as kw " unless $form->{query};
	$sqlquery .= "	  FROM newstories, comments
			 WHERE newstories.sid=comments.sid ";
	$sqlquery .= "     AND newstories.sid=" . $self->{_dbh}->quote($form->{sid}) if $form->{sid};
	$sqlquery .= "     AND points >= $threshold ";
	$sqlquery .= "     AND section=" . $self->{_dbh}->quote($form->{section}) if $form->{section};
	$sqlquery .= " ORDER BY kw DESC, date DESC, time DESC LIMIT $form->{min},20 ";


	my $cursor = $self->{_dbh}->prepare($sqlquery);
	$cursor->execute;

	my $search = $cursor->fetchall_arrayref;
	return $search;
}

####################################################################################
sub findUsers {
	my($self, $form, @users_to_ignore) = @_;
	# userSearch REALLY doesn't need to be ordered by keyword since you
	# only care if the substring is found.
	my $sqlquery = "SELECT fakeemail,nickname,uid ";
	$sqlquery .= " FROM users";
	$sqlquery .= " WHERE uid not $users_to_ignore[1]" if $users_to_ignore[1];
	shift @users_to_ignore;
	for my $user (@users_to_ignore) {
		$sqlquery .= " AND uid not $user";
	}
	if ($form->{query}) {
		my $kw = $self->_keysearch->($self, $form->{query}, 'nickname', 'ifnull(fakeemail,"")');
		$kw =~ s/as kw$//;
		$kw =~ s/\+/ OR /g;
		$sqlquery .= "AND ($kw) ";
	}
	$sqlquery .= "ORDER BY uid LIMIT $form->{min}, $form->{max}";
	my $sth = $self->{_dbh}->prepare($sqlquery);
	$sth->execute;

	my $users = $sth->fetchall_arrayref;

	return $users;
}

####################################################################################
sub findStory {
	my($self, $form) = @_;
	my $sqlquery = "SELECT aid,title,sid," . getDateFormat("time","t") .
		", commentcount,section ";
	$sqlquery .= "," . $self->_keysearch->($self, $form->{query}, "title", "introtext") . " "
		if $form->{query};
	$sqlquery .= "	,0 " unless $form->{query};

	if ($form->{query} || $form->{topic}) {
		$sqlquery .= "  FROM stories ";
	} else {
		$sqlquery .= "  FROM newstories ";
	}

	$sqlquery .= $form->{section} ? <<EOT : 'WHERE displaystatus >= 0';
WHERE ((displaystatus = 0 and "$form->{section}"="")
        OR (section="$form->{section}" and displaystatus>=0))
EOT

	$sqlquery .= "   AND time<now() AND writestatus>=0 AND displaystatus>=0";
	$sqlquery .= "   AND aid=" . $self->{_dbh}->quote($form->{author})
		if $form->{author};
	$sqlquery .= "   AND section=" . $self->{_dbh}->quote($form->{section})
		if $form->{section};
	$sqlquery .= "   AND tid=" . $self->{_dbh}->quote($form->{topic})
		if $form->{topic};

	$sqlquery .= " ORDER BY ";
	$sqlquery .= " kw DESC, " if $form->{query};
	$sqlquery .= " time DESC LIMIT $form->{min},$form->{max}";

	my $cursor = $self->{_dbh}->prepare($sqlquery);
	$cursor->execute;
	my $stories = $cursor->fetchall_arrayref;

	return $stories;
}

#################################################################
sub DESTROY {
	my ($self) = @_;
	$self->{_dbh}->disconnect;
}

1;
__END__
# Below is the stub of documentation for your module. You better edit it!

=head1 NAME

Slash::Search - Perl extension for blah blah blah

=head1 SYNOPSIS

  use Slash::Search;

=head1 DESCRIPTION

Stub documentation for Slash::Search was created by h2xs. It looks like the
author of the extension was negligent enough to leave the stub
unedited.

Blah blah blah.

=head1 AUTHOR

Brian Aker, brian@tangent.org

=head1 SEE ALSO

perl(1). Slash(3)

=cut
