#!/usr/bin/perl -w
# This code is a part of Slash, and is released under the GPL.
# Copyright 1997-2001 by Open Source Development Network. See README
# and COPYING for more information, or see http://slashcode.com/.
# $Id$

use strict;
use Date::Manip;
use HTML::Entities;
use Slash;
use Slash::Display;
use Slash::Utility;

use constant MSG_CODE_COMMENT_MODERATE	=> 3;
use constant MSG_CODE_COMMENT_REPLY	=> 4;

##################################################################
sub main {
	my $slashdb = getCurrentDB();
	my $constants = getCurrentStatic();
	my $form = getCurrentForm();
	my $user = getCurrentUser();
	my $id = getFormkeyId($user->{uid});

	my %ops = (
		default			=> \&displayComments,
		index			=> \&commentIndex,
		moderate		=> \&moderate,
		reply			=> \&reply,
		Reply			=> \&reply,
		Edit			=> \&edit,
		edit			=> \&edit,
		post			=> \&edit,
		creatediscussion	=> \&createDiscussion,
		Preview			=> \&edit,
		preview			=> \&edit,
		submit			=> \&submitComment,
		Submit			=> \&submitComment,
	);

	# maybe do an $op = lc($form->{'op'}) to make it simpler?
	# just a thought.  -- pudge

	my $stories;
	#This is here to save a function call, even though the
	# function can handle the situation itself
	$stories = $slashdb->getNewStory($form->{sid},
				['section', 'title', 'commentstatus']);
	$stories->{'title'} ||= "Comments";

	my $SECT = $slashdb->getSection($stories->{'section'});

	$form->{pid} ||= "0";

	header("$SECT->{title}: $stories->{'title'}", $SECT->{section});

	if ($user->{is_anon} && length($form->{upasswd}) > 1) {
		slashDisplay('errors', {
			type	=> 'login error',
		});
		$form->{op} = "Preview";
	}
	my $op = $form->{'op'};
	$op = 'default' unless $ops{$op};
	$ops{$op}->($form, $slashdb, $user, $constants, $id);

	writeLog($form->{sid});

	footer();
}

##################################################################
sub edit {
	my($form, $slashdb, $user, $constants, $id) = @_;

	$slashdb->updateFormkeyId('comments',
		$form->{formkey},
		$constants->{anonymous_coward_uid},
		$user->{uid},
		$form->{'rlogin'},
		$form->{upasswd}
	);
	editComment($id);
}

##################################################################
sub reply {
	my($form, $slashdb, $user, $constants, $id) = @_;

	$form->{formkey} = getFormkey();
	$slashdb->createFormkey("comments", $id, $form->{sid});
	editComment($id);
}

##################################################################
sub delete {
	my($form, $slashdb, $user, $constants, $id) = @_;

	titlebar("99%", "Delete $form->{cid}");

	my $delCount = deleteThread($form->{sid}, $form->{cid});
	# This does not exist in the API. Once
	# I know what it was supposed to do I can
	# create it. -Brian
	$slashdb->setStoryCount($delCount);
}

##################################################################
sub change {
	my($form, $slashdb, $user, $constants, $id) = @_;

	if (defined $form->{'savechanges'} && !$user->{is_anon}) {
		$slashdb->setUser($user->{uid}, {
			threshold	=> $user->{threshold},
			mode		=> $user->{mode},
			commentsort	=> $user->{commentsort}
		});
	}
	printComments($form->{sid}, $form->{cid}, $form->{cid});
}

##################################################################
sub displayComments {
	my($form, $slashdb, $user, $constants, $id) = @_;

	if ($form->{cid}) {
		printComments($form->{sid}, $form->{cid}, $form->{cid});
	} elsif ($form->{sid}) {
		printComments($form->{sid}, $form->{pid});
	} else {
		commentIndex(@_);
	}
}


##################################################################
# Index of recent discussions: Used if comments.pl is called w/ no
# parameters
sub commentIndex {
	my($form, $slashdb, $user, $constants, $id) = @_;

	titlebar("90%", "Several Active Discussions");
	if($form->{all}) {
		my $discussions = $slashdb->getDiscussions();
		slashDisplay('discuss_list', {
			discussions	=> $discussions,
		});
	} else {
		my $discussions = $slashdb->getStoryDiscussions();
		slashDisplay('discuss_list', {
			discussions	=> $discussions,
		});
	}

	if($user->{seclev} >= $constants->{discussion_create_seclev}) {
		slashDisplay('discussioncreate');
	}
}

##################################################################
# Yep, I changed the l33t method of adding discussions.
# "The Slash job, keeping trolls on their toes"
# -Brian
sub createDiscussion {
	my($form, $slashdb, $user, $constants, $id) = @_;

	if ($user->{seclev} >= $constants->{discussion_create_seclev}) {
		$form->{url} ||= $ENV{HTTP_REFERER};
		$slashdb->createDiscussion('', $form->{title},
			$slashdb->getTime(), $form->{url}, $form->{topic}, 1
		);
	}

	commentIndex(@_);
}

##################################################################
# Welcome to one of the ancient beast functions.  The comment editor
# is the form in which you edit a comment.
sub editComment {
	my($id, $error_message) = @_;

	my $slashdb = getCurrentDB();
	my $constants = getCurrentStatic();
	my $user = getCurrentUser();
	my $form = getCurrentForm();

	my $formkey_earliest = time() - $constants->{formkey_timeframe};

	# Get the comment we may be responding to. Remember to turn off
	# moderation elements for this instance of the comment.
	my $reply = $slashdb->getCommentReply($form->{sid}, $form->{pid});
	$reply->{no_moderation} = 1;

	if (!$constants->{allow_anonymous} && $user->{is_anon}) {
		slashDisplay('errors', {
			type	=> 'no anonymous posting',
		});
		return;
	}

	my $max_posts = $constants->{max_posts_allowed};
	my $preview;
	# Don't munge the current error_message if there already is one.
	if (! $slashdb->checkTimesPosted('comments', $max_posts, $id, $formkey_earliest)) {
		$error_message ||= slashDisplay('errors', {
			type		=> 'max posts',
			max_posts 	=> $max_posts,
		}, 1);
	} elsif ($form->{postercomment}) {
		$preview = previewForm(\$error_message);
	}

	if ($form->{pid} && !$form->{postersubj}) {
		$form->{postersubj} = $reply->{subject};
		$form->{postersubj} =~ s/^Re://i;
		$form->{postersubj} =~ s/\s\s/ /g;
		$form->{postersubj} = "Re:$form->{postersubj}";
	}

	my $formats = $slashdb->getDescriptions('postmodes');

	my $format_select = $form->{posttype}
		? createSelect('posttype', $formats, $form->{posttype}, 1)
		: createSelect('posttype', $formats, $user->{posttype}, 1);

	my $approved_tags =
		join "\n", map { "\t\t\t&lt;$_&gt;" } @{$constants->{approvedtags}};

	slashDisplay('edit_comment', {
		error_message	=> $error_message,
		format_select	=> $format_select,
		preview		=> $preview,
		reply		=> $reply,
	});
}


##################################################################
# Validate comment, looking for errors
sub validateComment {
	my($comm, $subj, $error_message, $preview) = @_;
	my $slashdb = getCurrentDB();
	my $constants = getCurrentStatic();
	my $user = getCurrentUser();
	my $form = getCurrentForm();

	my $form_success = 1;
	my $message = '';

	$$comm ||= $form->{postercomment};
	$$subj ||= $form->{postersubj};

	if ($slashdb->checkReadOnly('comments')) {
		$$error_message = slashDisplay('errors', {
			type =>	'readonly',
		}, 1);
		$form_success = 0;
		editComment('', $$error_message), return unless $preview;
	}

	if (isTroll($user, $constants, $slashdb)) {
		$$error_message = slashDisplay('errors', {
			type	=> 'troll message',
		}, 1);
		return;
	}

	if (!$constants->{allow_anonymous} && ($user->{is_anon} || $form->{postanon})) {
		$$error_message = slashDisplay('errors', {
			type	=> 'anonymous disallowed',
		}, 1);
		return;
	}

	unless ($$comm && $$subj) {
		$$error_message = slashDisplay('errors', {
			type	=> 'no body',
		}, 1);
		return;
	}

	$$subj =~ s/\(Score(.*)//i;
	$$subj =~ s/Score:(.*)//i;

	unless (defined($$comm = balanceTags($$comm, 1))) {
		$$error_message = slashDisplay('errors', {
			type =>	'nesting_toodeep',
		}, 1);
		editComment('', $$error_message), return unless $preview;
		return;
	}

	my $dupRows = $slashdb->findCommentsDuplicate($form->{sid}, $$comm);

	if ($dupRows || !$form->{sid}) {
		$$error_message = slashDisplay('errors', {
			type	=> 'validation error',
			dups	=> $dupRows,
		});
		editComment('', $$error_message), return unless $preview;
		return;
	}

	if (length($$comm) > 100) {
		local $_ = $$comm;
		my($w, $br); # Words & BRs
		$w++ while m/\w/g;
		$br++ while m/<BR>/gi;

		# Should the naked '7' be converted to a Slash Variable for return by
		# getCurrentStatic(). 	- Cliff
		if (($w / ($br + 1)) < 7) {
			$$error_message = slashDisplay('errors', {
				type	=> 'low words-per-line',
				ratio 	=> $w / ($br + 1),
			}, 1);
			editComment('', $$error_message), return unless $preview;
			return;
		}
	}


	# test comment and subject using filterOk. If the filter is
	# matched against the content, display an error with the
	# particular message for the filter that was matched
	my $fields = {
			postersubj 	=> 	$$subj,
			postercomment 	=>	$$comm,
	};

	for (keys %$fields) {
		# run through filters
		if (! filterOk('comments', $_, $fields->{$_}, \$message)) {
			$$error_message = slashDisplay('errors', {
					type		=> 'filter message',
					err_message	=> $message,
			}, 1);

			$form_success = 0;
			editComment('', $$error_message), return unless $preview;
			last;
		}
		# run through compress test
		if (! compressOk('comments', $_, $fields->{$_})) {
			# blammo luser
			$$error_message = slashDisplay('errors', {
				type	=> 'compress filter',
				ratio	=> $_,
			}, 1);
			editComment('', $$error_message), return unless $preview;
			$form_success = 0;
			last;
		}

	}


	# Return false if error condition...
	return if ! $form_success;

	# ...otherwise return true.
	return 1;
}


##################################################################
# Previews a comment for submission
sub previewForm {
	my($error_message) = @_;
	my $form = getCurrentForm();
	my $user = getCurrentUser();

	$user->{sig} = "" if $form->{postanon};

	my $tempComment = strip_mode($form->{postercomment}, $form->{posttype});
	my $tempSubject = strip_nohtml($form->{postersubj});

	validateComment(\$tempComment, \$tempSubject, $error_message, 1) or return;

	my $preview = {
		nickname	=> $form->{postanon}
					? getCurrentAnonymousCoward('nickname')
					: $user->{nickname},
		pid		=> $form->{pid},
		homepage	=> $form->{postanon} ? '' : $user->{homepage},
		fakeemail	=> $form->{postanon} ? '' : $user->{fakeemail},
		'time'		=> 'Soon',
		subject		=> $tempSubject,
		comment		=> $tempComment,
	};

	my $tm = $user->{mode};
	$user->{mode} = 'archive';
	my $previewForm;
	if ($tempSubject && $tempComment) {
		$previewForm = slashDisplay('preview_comm', {
			preview => $preview,
		}, 1);
	}
	$user->{mode} = $tm;

	return $previewForm;
}


##################################################################
# Saves the Comment
sub submitComment {
	my($form, $slashdb, $user, $constants, $id) = @_;
	my $error_message;

	unless (checkFormPost("comments",
		$constants->{post_limit},
		$constants->{max_posts_allowed},
		$id,
		\$error_message)) {
		print $error_message;
		return;
	}

	$form->{postersubj} = strip_nohtml($form->{postersubj});
	$form->{postercomment} = strip_mode($form->{postercomment}, $form->{posttype});

	validateComment(\$form->{postercomment}, \$form->{postersubj}, \$error_message)
		or return;

	return if $error_message || !$form->{postercomment} || !$form->{postersubj};

	$form->{postercomment} = addDomainTags($form->{postercomment});

	# this has to be a template -- pudge
	titlebar("95%", "Submitted Comment");

	my $pts = 0;

	if (!$user->{is_anon} && !$form->{postanon}) {
		$pts = $user->{defaultpoints};
		$pts-- if $user->{karma} < $constants->{badkarma};
		$pts++ if $user->{karma} > $constants->{goodkarma} && !$form->{nobonus};
		# Enforce proper ranges on comment points.
		my($minScore, $maxScore) = ($constants->{comment_minscore}, $constants->{comment_maxscore});
		$pts = $minScore if $pts < $minScore;
		$pts = $maxScore if $pts > $maxScore;
	}

	# It would be nice to have an arithmatic if right here
	my $maxCid = $slashdb->createComment($form, $user, $pts, $constants->{anonymous_coward_uid});

	$slashdb->setUser($user->{uid}, 'expiry_comm', {
		'-expiry_comm'	=> 'expiry_comm-1',
	}) if allowExpiry();

	if ($maxCid == -1) {
		# What vars should be accessible here?
		slashDisplay('errors', {
			type	=> 'submission error',
		});
	} elsif (!$maxCid) {
		# What vars should be accessible here?
		#	- $maxCid?
		# What are the odds on this happening? Hmmm if it is we should
		# increase the size of int we used for cid.
		slashDisplay('errors', {
			type	=> 'maxcid exceeded',
		});
	} else {
		slashDisplay('comment_submit');
		undoModeration($form->{sid});
		printComments($form->{sid}, $maxCid, $maxCid);

		my $tc = $slashdb->getVar('totalComments', 'value');
		$slashdb->setVar('totalComments', ++$tc);

		my $sid;
		if ($sid = $slashdb->getDiscussion($form->{sid}, 'sid')) {
			if ($slashdb->getStory($sid, 'writestatus') == 0) {
				$slashdb->setStory($sid, { writestatus => 1 });
			}
		}

		$slashdb->setUser($user->{uid}, { -totalcomments => 'totalcomments+1' });

		$slashdb->formSuccess($form->{formkey}, $maxCid, length($form->{postercomment}));

		my $messages = getObject('Slash::Messages') if $form->{pid};
		if ($form->{pid} && $messages) {
			my $parent = $slashdb->getCommentReply($form->{sid}, $form->{pid});
			my $users  = $messages->checkMessageCodes(MSG_CODE_COMMENT_REPLY, [$parent->{uid}]);
			if (@$users) {
				my $reply = $slashdb->getCommentReply($form->{sid}, $maxCid);
				my $story = $slashdb->getStory($form->{sid});
				my $data  = {
					template_name	=> 'reply_msg',
					subject		=> { template_name => 'reply_msg_subj' },
					reply		=> $reply,
					parent		=> $parent,
					story		=> $story,
				};

				$messages->create($users->[0], MSG_CODE_COMMENT_REPLY, $data);
			}
		}
	}
}


##################################################################
# Handles moderation
# gotta be a way to simplify this -Brian
sub moderate {
	my($form, $slashdb, $user, $constants, $id) = @_;

	my $total_deleted = 0;
	my $hasPosted;

	titlebar("99%", "Moderating $form->{sid}");

	unless ($user->{seclev} > 99 && $constants->{authors_unlimited}) {
		$hasPosted = $slashdb->countCommentsBySidUID($form->{sid}, $user->{uid});
	}

	slashDisplay('mod_header');

	# Handle Deletions, Points & Reparenting
	for (sort keys %{$form}) {
		if (/^del_(\d+)$/) { # && $user->{points}) {
			my $delCount = deleteThread($form->{sid}, $1);
			$total_deleted += $delCount;
			$slashdb->setStoryCount($form->{sid}, $delCount);

		} elsif (!$hasPosted && /^reason_(\d+)$/) {
			moderateCid($form->{sid}, $1, $form->{$_});
		}
	}

	slashDisplay('mod_footer');

	if ($hasPosted && !$total_deleted) {
		slashDisplay('errors', {
			type	=> 'already posted',
		});
	} elsif ($user->{seclev} && $total_deleted) {
		slashDisplay('del_message', {
			total_deleted	=> $total_deleted,
			comment_count	=> $slashdb->countCommentsBySid($form->{sid}),
		});
	}
	printComments($form->{sid}, $form->{pid}, $form->{cid});
}


##################################################################
# Handles moderation
# Moderates a specific comment
sub moderateCid {
	my($sid, $cid, $reason) = @_;
	# Check if $userid has seclev and Credits
	return unless $reason;

	my $slashdb = getCurrentDB();
	my $constants = getCurrentStatic();
	my $user = getCurrentUser();

	my $superAuthor = $constants->{authors_unlimited};

	if ($user->{points} < 1) {
		unless ($user->{seclev} > 99 && $superAuthor) {
			slashDisplay('errors', {
				type	=> 'no points',
			});
			return;
		}
	}

	my($cuid, $ppid, $subj, $points, $oldreason) =
		$slashdb->getComments($sid, $cid);

	my $dispArgs = {
		cid	=> $cid,
		sid	=> $sid,
		subject => $subj,
		reason	=> $constants->{reasons}[$reason],
		points	=> $user->{points},
	};

	unless ($user->{seclev} > 99 && $superAuthor) {
		my $mid = $slashdb->getModeratorLogID($cid, $sid, $user->{uid});
		if ($mid) {
			$dispArgs->{type} = 'already moderated';
			slashDisplay('moderation', $dispArgs);
			return;
		}
	}

	my $modreason = $reason;
	my $val = "-1";
	if ($reason == 9) { # Overrated
		$val = "-1";
		$val = "+0" if $points < 0;
		$reason = $oldreason;
	} elsif ($reason == 10) { # Underrated
		$val = "+1";
		$val = "+0" if $points > 1;
		$reason = $oldreason;
	} elsif ($reason > $constants->{badreasons}) {
		$val = "+1";
	}
	# Add moderation value to display arguments.
	$dispArgs->{'val'} = $val;

	my $scorecheck = $points + $val;
	# If the resulting score is out of comment score range, no further
	# actions need be performed.
	if (	$scorecheck < $constants->{comment_minscore} ||
		$scorecheck > $constants->{comment_maxscore})
	{
		# We should still log the attempt for M2, but marked as
		# 'inactive' so we don't mistakenly undo it.
		$slashdb->setModeratorLog($cid, $sid, $user->{uid}, $val, $modreason);
		$dispArgs->{type} = 'score limit';
		slashDisplay('moderation', $dispArgs);
		return;
	}

	if ($slashdb->setCommentCleanup($val, $sid, $reason, $modreason, $cid)) {
		# Update points for display due to possible change in above line.
		$dispArgs->{points} = $user->{points};
		$dispArgs->{type} = 'moderated';
		slashDisplay('moderation', $dispArgs);

		my $messages = getObject('Slash::Messages');
		if ($messages) {
			my $comment = $slashdb->getCommentReply($sid, $cid);
			my $users   = $messages->checkMessageCodes(MSG_CODE_COMMENT_MODERATE, [$comment->{uid}]);
			if (@$users) {
				my $story = $slashdb->getStory($sid);
				my $data  = {
					template_name	=> 'mod_msg',
					subject		=> { template_name => 'mod_msg_subj' },
					comment		=> $comment,
					story		=> $story,
					moderation	=> {
						user	=> $user,
						value	=> $val,
						reason	=> $modreason,
					}
				};
				$messages->create($users->[0], MSG_CODE_COMMENT_MODERATE, $data);
			}
		}
	}
}


##################################################################
# Given an SID & A CID this will delete a comment, and all its replies
sub deleteThread {
	my($sid, $cid, $level, $comments_deleted) = @_;
	my $slashdb = getCurrentDB();
	my $user = getCurrentUser();

	$level ||= 0;

	my $count = 1;
	my @delList;
	$comments_deleted = \@delList if !$level;

	return unless $user->{seclev} > 100;

	my $delkids = $slashdb->getCommentCid($sid, $cid);

	# Delete children of $cid.
	push @{$comments_deleted}, $cid;
	for (@{$delkids}) {
		my($cid) = @{$_};
		push @{$comments_deleted}, $cid;
		$count += deleteThread($sid, $cid, $level + 1, $comments_deleted);
	}
	# And now delete $cid.
	$slashdb->deleteComment($sid, $cid);

	if (!$level) {
		slashDisplay('deleted_cids', {
			sid			=> $sid,
			count			=> $count,
			comments_deleted	=> $comments_deleted,
		});
	}
	return $count;
}


##################################################################
# If you moderate, and then post, all your moderation is undone.
sub undoModeration {
	my($sid) = @_;
	my $slashdb = getCurrentDB();
	my $constants = getCurrentStatic();
	my $user = getCurrentUser();

	if ($sid !~ /^\d+$/) {
		$sid = $slashdb->getDiscussionBySid($sid, 'header');
	} 

	return if !$user->{is_anon} || ($user->{seclev} > 99 && $constants->{authors_unlimited});

	my $removed = $slashdb->unsetModeratorlog($user->{uid}, $sid,
		$constants->{comment_maxscore}, $constants->{comment_minscore});

	slashDisplay('undo_mod', {
		removed	=> $removed,
	});
}


##################################################################
# Troll Detection: essentially checks to see if this IP or UID has been
# abusing the system in the last 24 hours.
# 1=Troll 0=Good Little Goober
# This maybe should go into DB package -Brian
sub isTroll {
	my $slashdb = getCurrentDB();
	my $constants = getCurrentStatic();
	my $user = getCurrentUser();

	return if $user->{seclev} > 99;

	my($badIP, $badUID) = (0, 0);
	return 0 if !$user->{is_anon} && $user->{karma} > -1;

	# Anonymous only checks HOST
	my $downMods = $constants->{down_moderations};
	$badIP = $slashdb->getTrollAddress();
	return 1 if $badIP < $downMods;

	unless ($user->{is_anon}) {
		$badUID = $slashdb->getTrollUID();
	}

	return 1 if $badUID < $downMods;
	return 0;
}

##################################################################
createEnvironment();
main();
1;
