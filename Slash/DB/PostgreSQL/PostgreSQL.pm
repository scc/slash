package Slash::DB::PostgreSQL;
use strict;
use Slash::DB::Utility;
use Slash::Utility;
use URI ();

@Slash::DB::PostgreSQL::ISA = qw( Slash::DB::Utility );
($Slash::DB::PostgreSQL::VERSION) = ' $Revision$ ' =~ /\$Revision:\s+([^\s]+)/;

# BENDER: I hate people who love me.  And they hate me.

########################################################
sub deleteUser {
	my($self, $uid) = @_;
	$self->setUser($uid, {
		bio		=> '',
		nickname	=> 'deleted user',
		matchname	=> 'deleted user',
		realname	=> '',
		realemail	=> '',
		fakeemail	=> '',
		newpasswd	=> '',
		homepage	=> '',
		passwd		=> '',
		sig		=> '',
		seclev		=> 0
	});
	$self->sqlDo("DELETE FROM users_param WHERE uid=$uid");
}

########################################################
# Get user info from the users table.
sub getUserAuthenticate {
	my($self, $user, $passwd, $kind) = @_;
	my($uid, $cookpasswd, $newpass, $dbh, $user_db,
		$cryptpasswd, @pass);

	return unless $user && $passwd;

	# if $kind is 1, then only try to auth password as plaintext
	# if $kind is 2, then only try to auth password as encrypted
	# if $kind is undef or 0, try as encrypted
	#	(the most common case), then as plaintext
	my($EITHER, $PLAIN, $ENCRYPTED) = (0, 1, 2);
	$kind ||= 0;


	# RECHECK LOGIC!!  -- pudge

	$dbh = $self->{_dbh};
	$user_db = $dbh->quote($user);
	$cryptpasswd = encryptPassword($passwd);
	@pass = $self->sqlSelect(
		'uid,passwd,newpasswd',
		'users',
		"uid=$user_db"
	);

	# try ENCRYPTED -> ENCRYPTED
	if ($kind == $EITHER || $kind == $ENCRYPTED) {
		if ($passwd eq $pass[1]) {
			$uid = $pass[0];
			$cookpasswd = $passwd;
		}
	}

	# try plaintext -> ENCRYPTED
	if (($kind == $EITHER || $kind == $PLAIN) && !defined $uid) {
		if ($cryptpasswd eq $pass[1]) {
			$uid = $pass[0];
			$cookpasswd = $cryptpasswd;
		}
	}

	# try newpass?
	if (($kind == $EITHER || $kind == $PLAIN) && !defined $uid) {
		if ($passwd eq $pass[2]) {
			$self->sqlUpdate('users', {
				newpasswd	=> '',
				passwd		=> $cryptpasswd
			}, "uid=$user_db");
			$uid = $pass[0];
			$cookpasswd = $cryptpasswd;
			$newpass = 1;
		}
	}

	return wantarray ? ($uid, $cookpasswd, $newpass) : $uid;
}

#################################################################
# Replication issue. This needs to be a two-phase commit.
sub createUser {
	my($self, $matchname, $email, $newuser) = @_;
	return unless $matchname && $email && $newuser;

	my($cnt) = $self->sqlSelect(
		"matchname","users",
		"matchname=" . $self->{_dbh}->quote($matchname)
	) || $self->sqlSelect(
		"realemail","users",
		" realemail=" . $self->{_dbh}->quote($email)
	);
	return 0 if ($cnt);

	$self->sqlInsert("users", {
		realemail	=> $email,
		nickname	=> $newuser,
		matchname	=> $matchname,
		passwd		=> encryptPassword(changePassword())
	});
	my($uid) = $self->sqlSelect('uid', 'users', 'nickname=' . 
			$self->{_dbh}->quote($newuser)
			);

	return $uid;
}


########################################################
sub countUsersIndexExboxesByBid {
	my($self, $bid) = @_;
	my($count) = $self->sqlSelect("count(*)", "users",
		qq!exboxes like "%'$bid'%" !
	);

	return $count;
}

########################################################
sub getCommentReply {
	my($self, $time, $sid, $pid) = @_;
	my $reply = $self->sqlSelectHashref("$time, subject,comments.points as points,
		comment,realname,nickname,
		fakeemail,homepage,cid,sid,users.uid as uid",
		"comments,users",
		"sid=" . $self->{_dbh}->quote($sid) . "
		AND cid=" . $self->{_dbh}->quote($pid) . "
		AND users.uid=comments.uid"
	);

	return $reply;
}

########################################################
sub getCommentsForUser {
	my($self, $sid, $cid) = @_;
	my $user = getCurrentUser();
	my $form = getCurrentForm();
	my $sql = "SELECT cid," . getDateFormat('date', 'time') . ",
				subject,comment,
				nickname,homepage,fakeemail,
				users.uid as uid,sig,
				comments.points as points,pid,sid,
				lastmod, reason
			   FROM comments,users
			  WHERE sid=" . $self->{_dbh}->quote($sid) . "
			    AND comments.uid=users.uid";
	$sql .= "	    AND (";
	$sql .= "		comments.uid=$user->{uid} OR " unless $user->{is_anon};
	$sql .= "		cid=$cid OR " if $cid;
	$sql .= "		comments.points >= " . $self->{_dbh}->quote($user->{threshold}) . " OR " if $user->{hardthresh};
	$sql .= "		  1=1 )   ";
	$sql .= "	  ORDER BY ";
	$sql .= "comments.points DESC, " if $user->{commentsort} eq '3';
	$sql .= " cid ";
	$sql .= ($user->{commentsort} == 1 || $user->{commentsort} == 5) ? 'DESC' : 'ASC';


	my $thisComment = $self->{_dbh}->prepare_cached($sql) or errorLog($sql);
	$thisComment->execute or errorLog($sql);
	my(@comments);
	while (my $comment = $thisComment->fetchrow_hashref){
		push @comments, $comment;
	}
	return \@comments;
}


########################################################
# What an ugly method
sub getSubmissionForUser {
	my($self, $dateformat) = @_;
	my $form = getCurrentForm();
	my $user = getCurrentUser();
	my $sql = "SELECT subid,subj,date_format($dateformat,'m/d  H:i'),tid,note,email,name,section,comment,submissions.uid,karma FROM submissions,users_info";
	$sql .= "  WHERE submissions.uid=users_info.uid AND $form->{del}=del AND (";
	$sql .= $form->{note} ? "note=" . $self->{_dbh}->quote($form->{note}) : "isnull(note)";
	$sql .= "		or note=' ' " unless $form->{note};
	$sql .= ")";
	$sql .= "		and tid='$form->{tid}' " if $form->{tid};
	$sql .= "         and section=" . $self->{_dbh}->quote($user->{section}) if $user->{section};
	$sql .= "         and section=" . $self->{_dbh}->quote($form->{section}) if $form->{section};
	$sql .= "	  ORDER BY time";

	my $cursor = $self->{_dbh}->prepare($sql);
	$cursor->execute;

	my $submission = $cursor->fetchall_arrayref;

	return $submission;
}


########################################################
sub getNewstoryTitle {
	my($self, $storyid, $sid) = @_;
	my($title) = $self->sqlSelect("title", "newstories",
	      "sid=" . $self->{_dbh}->quote($sid)
	);

	return $title;
}



########################################################
sub saveStory {
	my($self) = @_;
	my $form = getCurrentForm();
	my $constants = getCurrentStatic();
	$self->sqlInsert('storiestuff', { sid => $form->{sid} });
	$self->sqlInsert('discussions', {
		sid	=> $form->{sid},
		title	=> $form->{title},
		ts	=> $form->{'time'},
		url	=> "$constants->{rootdir}/article.pl?sid=$form->{sid}"
	});


	# If this came from a submission, update submission and grant
	# Karma to the user
	my $suid;
	if ($form->{subid}) {
		my($suid) = $self->sqlSelect(
			'uid','submissions',
			'subid=' . $self->{_dbh}->quote($form->{subid})
		);

		# i think i got this right -- pudge
 		my($userkarma) = $self->sqlSelect('karma', 'users_info', "uid=$suid");
 		my $newkarma = (($userkarma + $constants->{submission_bonus})
 			> $constants->{maxkarma})
 				? $constants->{maxkarma}
 				: "karma+$constants->{submission_bonus}";
 		$self->sqlUpdate('users_info', { -karma => $newkarma }, "uid=$suid")
 			if $suid != $constants->{anonymous_coward_uid};

		$self->sqlUpdate('users_info',
			{ -karma => 'karma + 3' },
			"uid=$suid"
		) if $suid != $constants->{anonymous_coward_uid};

		$self->sqlUpdate('submissions',
			{ del=>2 },
			'subid=' . $self->{_dbh}->quote($form->{subid})
		);
	}

	$self->sqlInsert('stories',{
		sid		=> $form->{sid},
		uid		=> $form->{aid},
		tid		=> $form->{tid},
		dept		=> $form->{dept},
		'time'		=> $form->{'time'},
		title		=> $form->{title},
		section		=> $form->{section},
		bodytext	=> $form->{bodytext},
		introtext	=> $form->{introtext},
		writestatus	=> $form->{writestatus},
		relatedtext	=> $form->{relatedtext},
		displaystatus	=> $form->{displaystatus},
		commentstatus	=> $form->{commentstatus}
	});
	$self->saveExtras($form);
}


##################################################################
# Should this really be in here?
sub getDay {
	my($self) = @_;
	my($now) = $self->sqlSelect('to_days(now())');

	return $now;
}


########################################################
sub setUser {
	_genericSet('users', 'uid', @_);
#	my($self, $uid, $hashref) = @_;
#	my(@param, %update_tables, $cache);
#	my $tables = [qw(
#		users users_comments users_index
#		users_info users_prefs
#	)];
#
#	# special cases for password, exboxes
#	if (exists $hashref->{passwd}) {
#		# get rid of newpasswd if defined in DB
#		$hashref->{newpasswd} = '';
#		$hashref->{passwd} = encryptPassword($hashref->{passwd});
#	}
#
#	# hm, come back to exboxes later -- pudge
#	if (0 && exists $hashref->{exboxes}) {
#		if (ref $hashref->{exboxes} eq 'ARRAY') {
#			$hashref->{exboxes} = sprintf("'%s'", join "','", @{$hashref->{exboxes}});
#		} elsif (ref $hashref->{exboxes}) {
#			$hashref->{exboxes} = '';
#		} # if nonref scalar, just let it pass
#	}
#
#	$cache = _genericGetCacheName($self, $tables);
#
#	for (keys %$hashref) {
#		(my $clean_val = $_) =~ s/^-//;
#		my $key = $self->{$cache}{$clean_val};
#		if ($key) {
#			push @{$update_tables{$key}}, $_;
#		} else {
#			push @param, [$_, $hashref->{$_}];
#		}
#	}
#
#	for my $table (keys %update_tables) {
#		my %minihash;
#		for my $key (@{$update_tables{$table}}){
#			$minihash{$key} = $hashref->{$key}
#				if defined $hashref->{$key};
#		}
#		$self->sqlUpdate($table, \%minihash, 'uid=' . $uid, 1);
#	}
#	# What is worse, a select+update or a replace?
#	# I should look into that.
#	for (@param)  {
#		$self->sqlDo("REPLACE INTO users_param values ('', $uid, '$_->[0]', '$_->[1]')");
#	}
}

########################################################
# Now here is the thing. We want getUser to look like
# a generic, despite the fact that it is not :)
sub getUser {
	my $answer = _genericGet('users', 'uid', @_);
	return $answer;
#	my($self, $id, $val) = @_;
#	my $answer;
#	# The sort makes sure that someone will always get the cache if
#	# they have the same tables
#	my $cache = "_cache_user";
#
#	if (ref($val) eq 'ARRAY') {
#		my($values, %tables, @param, $where, $table);
#		for (@$val) {
#			(my $clean_val = $_) =~ s/^-//;
#			if ($self->{$cache}{$clean_val}) {
#				$tables{$self->{$cache}{$_}} = 1;
#				$values .= "$_,";
#			} else {
#				push @param, $_;
#			}
#		}
#		chop($values);
#
#		for (keys %tables) {
#			$where .= "$_.uid=$id AND ";
#		}
#		$where =~ s/ AND $//;
#
#		$table = join ',', keys %tables;
#		$answer = $self->sqlSelectHashref($values, $table, $where);
#		for (@param) {
#			my $val = $self->sqlSelect('value', 'users_param', "uid=$id AND name='$_'");
#			$answer->{$_} = $val;
#		}
#
#	} elsif ($val) {
#		(my $clean_val = $val) =~ s/^-//;
#		my $table = $self->{$cache}{$clean_val};
#		if ($table) {
#			($answer) = $self->sqlSelect($val, $table, "uid=$id");
#		} else {
#			($answer) = $self->sqlSelect('value', 'users_param', "uid=$id AND name='$val'");
#		}
#
#	} else {
#		my($where, $table, $append);
#		for (@$tables) {
#			$where .= "$_.uid=$id AND ";
#		}
#		$where =~ s/ AND $//;
#
#		$table = join ',', @$tables;
#		$answer = $self->sqlSelectHashref('*', $table, $where);
#		$append = $self->sqlSelectAll('name,value', 'users_param', "uid=$id");
#		for (@$append) {
#			$answer->{$_->[0]} = $_->[1];
#		}
#	}
#
#	return $answer;
}

########################################################
# This could be optimized by not making multiple calls
# to getKeys or by fixing getKeys() to return multiple
# values
sub _genericGetCacheName {
	my($self, $tables) = @_;
	my $cache = '_' . join ('_', sort(@$tables), 'cache');
	unless (keys %{$self->{$cache}}) {
		for my $table (@$tables) {
			my $keys = $self->getKeys($table);
			for (@$keys) {
				$self->{$cache}{$_} = $table;
			}
		}
	}
	return $cache;
}

########################################################
# Now here is the thing. We want setUser to look like
# a generic, despite the fact that it is not :)
# We assum most people called set to hit the database
# and just not the cache (if one even exists)
sub _genericSet {
	my($table, $table_prime, $self, $id, $value) = @_;
	$self->sqlUpdate($table, $value, $table_prime . '=' . $self->{_dbh}->quote($id));

	my $table_cache= '_' . $table . '_cache';
	return unless (keys %{$self->{$table_cache}});
	my $table_cache_time= '_' . $table . '_cache_time';
	$self->{$table_cache_time} = time();
	for (keys %$value) {
		$self->{$table_cache}{$id}{$_} = $value->{$_};
	}
}

########################################################
# You can use this to reset cache's in a timely
# manner :)
sub _genericCacheRefresh {
	my($self, $table,  $expiration) = @_;
	return unless $expiration;
	my $table_cache = '_' . $table . '_cache';
	my $table_cache_time = '_' . $table . '_cache_time';
	my $table_cache_full = '_' . $table . '_cache_full';
	return unless $self->{$table_cache_time};
	my $time = time();
	my $diff = $time - $self->{$table_cache_time};

	if ($diff > $expiration) {
	print STDERR "TIME:$diff:$expiration:$time:$self->{$table_cache_time}:\n";
		$self->{$table_cache} = {};
		$self->{$table_cache_time} = 0;
		$self->{$table_cache_full} = 0;
	}
}

########################################################
# This is protected and don't call it from your
# scripts directly.
sub _genericGetCache {
	return _genericGet(@_) unless getCurrentStatic('cache_enabled');

	my($table, $table_prime, $self, $id, $values, $cache_flag) = @_;
	my $table_cache = '_' . $table . '_cache';
	my $table_cache_time= '_' . $table . '_cache_time';

	my $type;
	if (ref($values) eq 'ARRAY') {
		$type = 0;
	} else {
		$type  = $values ? 1 : 0;
	}

	if ($type) {
		return $self->{$table_cache}{$id}{$values}
			if (keys %{$self->{$table_cache}{$id}} and !$cache_flag);
	} else {
		if (keys %{$self->{$table_cache}{$id}} && !$cache_flag) {
			my %return = %{$self->{$table_cache}{$id}};
			return \%return;
		}
	}

	# Lets go knock on the door of the database
	# and grab the data's since it is not cached
	# On a side note, I hate grabbing "*" from a database
	# -Brian
	$self->{$table_cache}{$id} = {};
	my $answer = $self->sqlSelectHashref('*', $table, "$table_prime=" . $self->{_dbh}->quote($id));
	$self->{$table_cache}{$id} = $answer;

	$self->{$table_cache_time} = time();

	if ($type) {
		return $self->{$table_cache}{$id}{$values};
	} else {
		if ($self->{$table_cache}{$id}) {
			my %return = %{$self->{$table_cache}{$id}};
			return \%return;
		} else {
			return;
		}
	}
}

########################################################
# This is protected and don't call it from your
# scripts directly.
sub _genericClearCache {
	my($table, $self) = @_;
	my $table_cache= '_' . $table . '_cache';

	$self->{$table_cache} = {};
}

########################################################
# This is protected and don't call it from your
# scripts directly.
sub _genericGet {
	my($table, $table_prime, $self, $id, $val) = @_;
	my($answer, $type);
	my $id_db = $self->{_dbh}->quote($id);

	if (ref($val) eq 'ARRAY') {
		my $values = join ',', @$val;
		$answer = $self->sqlSelectHashref($values, $table, "$table_prime=$id_db");
	} elsif ($val) {
		($answer) = $self->sqlSelect($val, $table, "$table_prime=$id_db");
	} else {
		$answer = $self->sqlSelectHashref('*', $table, "$table_prime=$id_db");
	}

	return $answer;
}

########################################################
# This is protected and don't call it from your
# scripts directly.
sub _genericGetsCache {
	return _genericGets(@_) unless getCurrentStatic('cache_enabled');

	my($table, $table_prime, $self, $cache_flag) = @_;
	my $table_cache= '_' . $table . '_cache';
	my $table_cache_time= '_' . $table . '_cache_time';
	my $table_cache_full= '_' . $table . '_cache_full';

	if (keys %{$self->{$table_cache}} && $self->{$table_cache_full} && !$cache_flag) {
		my %return = %{$self->{$table_cache}};
		return \%return;
	}

	# Lets go knock on the door of the database
	# and grab the data since it is not cached
	# On a side note, I hate grabbing "*" from a database
	# -Brian
	$self->{$table_cache} = {};
	my $sth = $self->sqlSelectMany('*', $table);
	while (my $row = $sth->fetchrow_hashref) {
		$self->{$table_cache}{ $row->{$table_prime} } = $row;
	}
	$self->{$table_cache_full} = 1;
	$sth->finish;
	$self->{$table_cache_time} = time();

	my %return = %{$self->{$table_cache}};
	return \%return;
}

########################################################
# This is protected and don't call it from your
# scripts directly.
sub _genericGets {
	my($table, $table_prime, $self) = @_;

	# Lets go knock on the door of the database
	# and grab the data since it is not cached
	# On a side note, I hate grabbing "*" from a database
	# -Brian
	my %return;
	my $sth = $self->sqlSelectMany('*', $table);
	while (my $row = $sth->fetchrow_hashref) {
		$return{ $row->{$table_prime} } = $row;
	}
	$sth->finish;

	return \%return;
}

1;

__END__

=head1 NAME

Slash::DB::PostgreSQL - PostgreSQL Interface for Slashcode

=head1 SYNOPSIS

  use Slash::DB::PostgreSQL;

=head1 DESCRIPTION

No documentation yet. Sue me.

=head1 AUTHOR

Brian Aker, brian@tangent.org

Chris Nandor, pudge@pobox.com

=head1 SEE ALSO

Slash(3). Slash::DB(3)

=cut
