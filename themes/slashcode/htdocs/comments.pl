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

use constant COMMENTS_OPEN 	=> 0;
use constant COMMENTS_RECYCLE 	=> 1;
use constant COMMENTS_READ_ONLY => 2;

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
	# Not a bad idea actually --Brian
	# why's that? The ops are already lowercase, and should be. --Patrick

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
		print getError('login error');
		$form->{op} = "Preview";
	}
	my $op = $form->{'op'};
	$op = 'default' unless $ops{$op};
	$ops{$op}->($form, $slashdb, $user, $constants, $id);

	writeLog($form->{sid});

	footer();
}

#################################################################
# this groups all the errors together in
# one template, called "errors;comments;default"
sub getError {
	my($value, $hashref, $nocomm) = @_;
	$hashref ||= {};
	$hashref->{value} = $value;
	return slashDisplay('errors', $hashref,
		{ Return => 1, Nocomm => $nocomm });
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

	# arghg - you don't need to do this - it's in 'createFormkey' --Patrick
	# $form->{formkey} = getFormkey();

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
	if ($form->{all}) {
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
}

##################################################################
# Yep, I changed the l33t method of adding discussions.
# "The Slash job, keeping trolls on their toes"
# -Brian
sub createDiscussion {
	my($form, $slashdb, $user, $constants, $id) = @_;

	if ($user->{seclev} >= $constants->{discussion_create_seclev}) {
		$form->{url} ||= $ENV{HTTP_REFERER};
		$slashdb->createDiscussion($form->{title},
			$form->{url}, $form->{topic}, 1
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
	my $preview;

	# Get the comment we may be responding to. Remember to turn off
	# moderation elements for this instance of the comment.
	my $reply = $slashdb->getCommentReply($form->{sid}, $form->{pid});

	if (!$constants->{allow_anonymous} && $user->{is_anon}) {
		print getError('no anonymous posting');
		return;
	}

	# check if user has  max comments successfully posted
	if (my $maxposts = $slashdb->checkMaxPosts('comments', $id)) {
                my $timeframe_string = intervalString($constants->{formkey_timeframe});
		print getError('max posts', {
				max_posts => $maxposts,
				timeframe => $timeframe_string 
		});
                return;

	} elsif ($form->{postercomment}) {
		$preview = previewForm(\$error_message);
	}

	if ($form->{pid} && !$form->{postersubj}) {
		$form->{postersubj} = decode_entities($reply->{subject});
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
		$$error_message = getError('readonly');
		$form_success = 0;
		editComment('', $$error_message), return unless $preview;
	}

	if (isTroll($user, $constants, $slashdb)) {
		$$error_message = getError('troll message');
		return;
	}

	if (!$constants->{allow_anonymous} && ($user->{is_anon} || $form->{postanon})) {
		$$error_message = getError('anonymous disallowed');
		return;
	}

	unless ($$comm && $$subj) {
		$$error_message = getError('no body');
		return;
	}

	$$subj =~ s/\(Score(.*)//i;
	$$subj =~ s/Score:(.*)//i;

	unless (defined($$comm = balanceTags($$comm, 1))) {
		$$error_message = getError('nesting_toodeep');
		editComment('', $$error_message), return unless $preview;
		return;
	}

	my $dupRows = $slashdb->findCommentsDuplicate($form->{sid}, $$comm);

	if ($dupRows || !$form->{sid}) {
		$$error_message = getError('validation error', {
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
			$$error_message = getError('low words-per-line', {
				ratio 	=> $w / ($br + 1),
			});
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
			$$error_message = getError('filter message', {
					err_message	=> $message,
			});

			$form_success = 0;
			editComment('', $$error_message), return unless $preview;
			last;
		}
		# run through compress test
		if (! compressOk('comments', $_, $fields->{$_})) {
			# blammo luser
			$$error_message = getError('compress filter', {
					ratio	=> $_,
			});
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
# A note, right now form->{sid} is a discussion id, not a
# story id.
sub submitComment {
	my($form, $slashdb, $user, $constants, $id) = @_;

	my $error_message;

	# check the max posts
	if (my $maxposts = $slashdb->checkMaxPosts('comments', $id)) {
                $slashdb->createAbuse( ( getError('formabuse_maxposts', {
				no_error_comment 	=> 	1,
				type 			=> 	'formabuse_maxposts', 
				maxposts 		=> 	$maxposts 
				}, 1)),
			'comments',
			$ENV{QUERY_STRING},
			$user->{uid},
			$user->{ipid},
			$user->{subnetid} 
		);
                        
                my $timeframe_string = intervalString($constants->{formkey_timeframe});
		print getError('max posts', {
				timeframe => $timeframe_string 
		});
                return;
        }

	# verify a valid formkey
	if (! $slashdb->validFormkey('comments', $id)) {	
		$slashdb->createAbuse( getError('formabuse_invalidformkey', {
					no_error_comment	=> 1,
					formkey 		=> $form->{formkey},
					}, 1),
				'comments',
				$ENV{QUERY_STRING},
				$user->{uid},
				$user->{ipid},
				$user->{subnetid} 
		);

		print getError('invalid formkey', {
			formkey => $form->{formkey}
		});

		return;
	}
	
	# check response time
	if ( my $response_time = $slashdb->checkResponseTime('comments', $id)) {
		my $limit_string = intervalString($constants->{comments_response_limit});
		my $response_string = intervalString($response_time);
		print getError('response limit', {
			limit		=> 	$limit_string,
			response 	=> 	$response_string
		});
		return;
	}

	# check interval from this attempt to last successful post
	if ( my $interval = $slashdb->checkPostInterval('comments', $id)) {	
		my $limit_string = intervalString($constants->{comments_speed_limit});
		my $interval_string = intervalString($interval);

		print getError('post limit', {
			limit 		=> 	$limit_string,
			interval 	=> 	$interval_string
		});
		return;
	}

	# check if form already used
	unless (  my $increment_val = $slashdb->updateFormkeyVal($form->{formkey})) {	
		my $interval_string = intervalString( time() - $slashdb->getFormkeyTs($form->{formkey},1) );

		print getError('used form', {
			interval	=>	$interval_string
		});

		$slashdb->createAbuse( getError('formabuse_usedform', {
					no_error_comment 	=> 1,
					formkey 		=> $form->{formkey}
					}, 1),
			'comments',
			$ENV{QUERY_STRING},
			$user->{uid},
			$user->{ipid},
			$user->{subnetid} 
		);
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
	my $maxCid = $slashdb->createComment(
		$form, 
		$user, 
		$pts, 
		$constants->{anonymous_coward_uid}
	);

	$slashdb->setUser($user->{uid}, 'expiry_comm', {
		'-expiry_comm'	=> 'expiry_comm-1',
	}) if allowExpiry();

	if ($maxCid == -1) {
		# What vars should be accessible here?
		print getError('submission error');

	} elsif (!$maxCid) {
		# What vars should be accessible here?
		#	- $maxCid?
		# What are the odds on this happening? Hmmm if it is we should
		# increase the size of int we used for cid.
		print getError('maxcid exceeded');
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

		$slashdb->setUser($user->{uid}, {
			-totalcomments => 'totalcomments+1',
		});

		# successful submission		
		my $updated = $slashdb->updateFormkey($form->{formkey}, $maxCid, length($form->{postercomment})); 
		# yeah, ok, I should do something with $updated

		my $messages = getObject('Slash::Messages') if $form->{pid};
		if ($form->{pid} && $messages) {
			my $parent = $slashdb->getCommentReply($form->{sid}, $form->{pid});
			my $users  = $messages->checkMessageCodes(MSG_CODE_COMMENT_REPLY, [$parent->{uid}]);
			if (@$users) {
				my $reply = $slashdb->getCommentReply($form->{sid}, $maxCid);
				my $story = $slashdb->getStory($sid);
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

	if (! $constants->{allow_moderation}) {
		print getData('no_moderation');
		return;
	}

	my $total_deleted = 0;
	my $hasPosted;

	titlebar("99%", "Moderating $form->{sid}");

	$hasPosted = $slashdb->countCommentsBySidUID($form->{sid}, $user->{uid})
		unless $user->{seclev} > 99 && $constants->{authors_unlimited};

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
		print getError('already posted');

	} elsif ($user->{seclev} && $total_deleted) {
		slashDisplay('del_message', {
			total_deleted	=> $total_deleted,
			comment_count	=>
				$slashdb->countCommentsBySid($form->{sid}),
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
			print getError('no points');
			return;
		}
	}

	# $ppid is unused in this context.
	my($cuid, $ppid, $subj, $points, $oldreason, $host_name) =
		$slashdb->getComments($sid, $cid);
	# Do not allow moderation of anonymous comments with the same IP
	# as the current user.
	return if $host_name eq $ENV{REMOTE_ADDR} &&
		  $cuid == $constants->{anonymous_coward_uid};

	my $dispArgs = {
		cid	=> $cid,
		sid	=> $sid,
		subject => $subj,
		reason	=> $reason,
		points	=> $user->{points},
	};

	unless ($user->{seclev} > 99 && $superAuthor) {
		my $mid = $slashdb->getModeratorLogID($cid, $user->{uid});
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
		$reason = $oldreason;
	} elsif ($reason == 10) { # Underrated
		$val = "+1";
		$reason = $oldreason;
	} elsif ($reason > $constants->{badreasons}) {
		$val = "+1";
	}
	# Add moderation value to display arguments.
	$dispArgs->{'val'} = $val;

	my $scorecheck = $points + $val;
	my $active = 1;
	# If the resulting score is out of comment score range, no further
	# actions need be performed.
	if (	$scorecheck < $constants->{comment_minscore} ||
		$scorecheck > $constants->{comment_maxscore})
	{
		# We should still log the attempt for M2, but marked as
		# 'inactive' so we don't mistakenly undo it. Mods get modded
		# even if the action didn't "really" happen.
		#
		$active = 0;
		$dispArgs->{type} = 'score limit';
	}

	# Write the proper records to the moderatorlog.
	$slashdb->setModeratorLog(
		$sid,		# So we can undoModeration()
		$cid, 		# CID to identify the actual comment (UNIQUE!)
		$user->{uid}, 	# The moderator
		$val, 		# The value of the moderation.
		$modreason,	# Unadjusted moderation reason.
		$active		# Was it valid (since we do M2 invalid mods).
	);	

	# Increment moderators total mods and deduct their point for playing.
	# Word of note, if we are HERE, then the user either has points, or
	# is an author (and 'author_unlimited' is set) so point checks SHOULD
	# be unnecessary here.
	$user->{points}-- if $user->{points} > 0;
	$user->{totalmods}++;
	$slashdb->setUser($user->{uid}, {
		totalmods 	=> $user->{totalmods},
		points		=> $user->{points},
	});

	if ($active) {
		# Adjust comment posters karma and moderation stats.
		if ($cuid != $constants->{anonymous_coward_uid}) {
			my $cuser = $slashdb->getUser($cuid);
			my $newkarma = $cuser->{karma} + $val;
			$cuser->{downmods}++ if $val < 0;
			$cuser->{upmods}++ if $val > 0;
			$cuser->{karma} = $newkarma 
				if $newkarma <= $constants->{maxkarma} &&
				   $newkarma >= $constants->{minkarma};
			$slashdb->setUser($cuid, {
				karma		=> $newkarma,
				upmods		=> $cuser->{upmods},
				downmods	=> $cuser->{downmods},
			});
		}

		# Make sure our changes get propagated back to the comment.
		# Note that we use the ADJUSTED reason value, $reason.
		$slashdb->setCommentCleanup($cid, $val, $reason);

		# Update points for display as they have most likely changed.
		$dispArgs->{points} = $user->{points};
		$dispArgs->{type} = 'moderated';

		# Send messages regarding this moderation to user who posted
		# comment if the havey that bit set.
		my $messages = getObject('Slash::Messages');
		if ($messages) {
			my $comment = $slashdb->getCommentReply($sid, $cid);
			my $users   = $messages->checkMessageCodes(
				MSG_CODE_COMMENT_MODERATE, [$comment->{uid}]
			);
			if (@$users) {
				my $story = $slashdb->getStory($sid);
				my $data  = {
					template_name	=> 'mod_msg',
					subject		=> {
						template_name => 'mod_msg_subj'
					},
					comment		=> $comment,
					story		=> $story,
					moderation	=> {
						user	=> $user,
						value	=> $val,
						reason	=> $modreason,
					},
				};
				$messages->create(
					$users->[0],
					MSG_CODE_COMMENT_MODERATE,
					$data
				);
			}
		}
	}

	# Now display the template with the moderation results.
	slashDisplay('moderation', $dispArgs);
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

	my $delkids = $slashdb->getCommentChildren($cid);

	# Delete children of $cid.
	push @{$comments_deleted}, $cid;
	for (@{$delkids}) {
		my($cid) = @{$_};
		push @{$comments_deleted}, $cid;
		$count += deleteThread($sid, $cid, $level+1, $comments_deleted);
	}
	# And now delete $cid.
	$slashdb->deleteComment($sid, $cid);

	if (!$level) {
		# SID remains for display purposes, only.
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

	# We abandon this operation if:
	#	1) Moderation is off
	#	2) The user is anonymous (they aren't allowed to anyway).
	#	3) The user is an author with a high enough security level
	#	   and that option is turned on.
	return if !$constants->{allow_moderation} || $user->{is_anon} ||
		  ( $user->{seclev} > 99 && $constants->{authors_unlimited} &&
		    $user->{author} );

	if ($sid !~ /^\d+$/) {
		$sid = $slashdb->getDiscussionBySid($sid, 'header');
	}
	my $removed = $slashdb->unsetModeratorlog($user->{uid}, $sid);

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
