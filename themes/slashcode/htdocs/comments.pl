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
	my $formkeyid = getFormkeyId($user->{uid});
	my $error_flag = 0;

	# post and edit don't look like they're used anywhere
	my %ops = (
		default			=> \&displayComments,
		index			=> \&commentIndex,
		moderate		=> \&moderate,
		reply			=> \&editComment,
		Reply			=> \&editComment,
		Edit			=> \&editComment,
		edit			=> \&editComment,
		post			=> \&editComment,
		creatediscussion	=> \&createDiscussion,
		Preview			=> \&editComment,
		preview			=> \&editComment,
		submit			=> \&submitComment,
		Submit			=> \&submitComment,
	);

	my $formkey_form = { 
		edit		=> 1, 
		default		=> 1,
		index		=> 1,
		reply		=> 1,
	};

	my $formname = {
		edit			=> 'comments',
		post			=> 'comments',
		reply			=> 'comments',
		submit 			=> 'comments',
		creatediscussion 	=> 'discussions',
		index			=> 'discussions',
		default			=> 'discussions',
	};


	my $max_post_check = {
		edit			=> 1,
		reply			=> 1,
		submit 			=> 1,
		creatediscussion	=> 1,
	};

	my $formkey_check = { 
		submit 			=> 1,
		creatediscussion	=> 1,
	};

	my $interval_check = {
		submit 			=> 1,
		creatediscussion	=> 1,
	};

	my $response_check = { 
		submit 			=> 1,
	};
	
	my $updateFormkeyID = {
		edit		=> 1,
		post		=> 1,
		preview		=> 1,
	};


	# maybe do an $op = lc($form->{'op'}) to make it simpler?
	# just a thought.  -- pudge
	# Not a bad idea actually --Brian
	# why's that? The ops are already lowercase, and should be. --Patrick
	# there are four ops above that are just upper
	# case aliases to the lower case versions -- pudge
	# yeah, I missed that - I'm so used to users

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
	my $op = lc($form->{'op'});
	$op = 'default' unless $ops{$op};

	# authors shouldn't jump thourh formkey hoops? right?	
	if ($user->{seclev} < 100) {
		if ($max_post_check->{$op} ) { 
			if ( my $maxposts = $slashdb->checkMaxPosts($formname->{$op}, $formkeyid)) {

				$slashdb->createAbuse( ( getError('formabuse_maxposts', {
									no_error_comment 	=> 1,
									type 			=> 'formabuse_maxposts', 
									formname		=> $formname->{$op},
									maxposts 		=> $maxposts, 
									}, 1)),
								$formname->{$op},
								$ENV{QUERY_STRING},
								$user->{uid},
								$user->{ipid},
								$user->{subnetid} 
					) if $formkey_check->{$op} ;

				my $timeframe_string = intervalString($constants->{formkey_timeframe});

				print getError("$formname->{$op} max posts", {
							max_posts => $maxposts,
							timeframe => $timeframe_string 
				});
	
				$error_flag++;
			}
		}

		if ($formkey_check->{$op} && ! $error_flag) {
			if (! $slashdb->validFormkey($formname->{$op}, $formkeyid)) {	
				$slashdb->createAbuse( getError('formabuse_invalidformkey', {
									no_error_comment	=> 1,
									formname		=> $formname->{$op},
									formkey 		=> $form->{formkey},
									}, 1),
						$formname->{$op},
						$ENV{QUERY_STRING},
						$user->{uid},
						$user->{ipid},
						$user->{subnetid} 
				);

				print getError('invalid formkey', {
						formkey => $form->{formkey}
				});

				$error_flag++;
			}
		}

		if ($interval_check->{$op} && ! $error_flag) {
			# check interval from this attempt to last successful post
			if ( my $interval = $slashdb->checkPostInterval($formname->{$op}, $formkeyid)) {	
				my $speed_limit_key = $formname->{$op} . '_speed_limit';
				my $limit_string = intervalString($constants->{$speed_limit_key});
				my $interval_string = intervalString($interval);

				print getError("$formname->{$op} post limit", {
					limit 		=> 	$limit_string,
					interval 	=> 	$interval_string
				});
				$error_flag++;
			}
		}
			
		if ($response_check->{$op} && ! $error_flag) {
			# check response time
			if ( my $response_time = $slashdb->checkResponseTime($formname->{$op}, $formkeyid)) {
				my $response_limit_key = $formname->{$op} . '_response_limit';
				my $limit_string = intervalString($constants->{$response_limit_key});
				my $response_string = intervalString($response_time);
				# make sure you have the error message for the form
				print getError("$formname->{$op} response limit", {
					limit		=> 	$limit_string,
					response 	=> 	$response_string
				});
				$error_flag++;
			}
		}
		if ($formkey_check->{$op} && ! $error_flag) {
			# check if form already used
			unless (  my $increment_val = $slashdb->updateFormkeyVal($form->{formkey})) {	
				my $interval_string = intervalString( time() - $slashdb->getFormkeyTs($form->{formkey},1) );
		
				print getError('used form', {
					interval	=>	$interval_string
				});
		
				$slashdb->createAbuse( getError('formabuse_usedform', {
							no_error_comment 	=> 1,
							formname		=> $formname->{$op},
							formkey 		=> $form->{formkey}
							}, 1),
					$formname->{$op},
					$ENV{QUERY_STRING},
					$user->{uid},
					$user->{ipid},
					$user->{subnetid} 
				);
				$error_flag++;
			}
		}

		if ($updateFormkeyID->{$op}) {
			$slashdb->updateFormkeyId($formname->{$op},
				$form->{formkey},
				$constants->{anonymous_coward_uid},
				$user->{uid},
				$form->{'rlogin'},
				$form->{upasswd}
			);
		}

		if ($formkey_form->{$op}) {
			my $sid = $form->{sid};
			$sid ||= 'discussions'; 
			$slashdb->createFormkey($formname->{$op}, $formkeyid, $sid);
		}
	} 
	

	if (! $error_flag) {
		$ops{$op}->($form, $slashdb, $user, $constants, $formkeyid);
		# do something with updated? ummm.

		if ( $formkey_check->{$op}) {
			if ($formname->{$op} eq 'comments')  { 
				my $updated = $slashdb->updateFormkey($form->{formkey}, $form->{maxCid}, length($form->{postercomment})); 
			} else {
				my $updated = $slashdb->updateFormkey($form->{formkey}, '', length($form->{title})); 
			}
		}
	}

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
sub delete {
	my($form, $slashdb, $user, $constants, $formkeyid) = @_;

	titlebar("99%", "Delete $form->{cid}");

	my $delCount = deleteThread($form->{sid}, $form->{cid});
	# This does not exist in the API. Once I know what it was
	# supposed to do I can create it. -Brian
	# Looks OK now. - Jamie
	$slashdb->setDiscussionDelCount($delCount);
}

##################################################################
sub change {
	my($form, $slashdb, $user, $constants, $formkeyid) = @_;

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
	my($form, $slashdb, $user, $constants, $formkeyid) = @_;

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
	my($form, $slashdb, $user, $constants, $formkeyid) = @_;

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
	my($form, $slashdb, $user, $constants, $formkeyid) = @_;

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
	my($formkeyid, $error_message) = @_;

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

	if ($form->{postercomment}) {
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
	my($form, $slashdb, $user, $constants, $formkeyid) = @_;

	my $error_message;

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

	# It would be nice to have an arithmetic if right here
	my $maxCid = $slashdb->createComment(
		$form, 
		$user, 
		$pts, 
		$constants->{anonymous_coward_uid}
	);

	# make the formkeys happy
	$form->{maxCid} = $maxCid;

	$slashdb->setUser($user->{uid}, {
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

		$slashdb->setDiscussionFlagsBySid([$form->{sid}], 1, ["hitparade_dirty"]);

		$slashdb->setUser($user->{uid}, {
			-totalcomments => 'totalcomments+1',
		});

		# successful submission		
		# my $updated = $slashdb->updateFormkey($form->{formkey}, $maxCid, length($form->{postercomment})); 
		# yeah, ok, I should do something with $updated

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
	my($form, $slashdb, $user, $constants, $formkeyid) = @_;

	my $sid = $form->{sid};
	my $was_touched = 0;

	if (! $constants->{allow_moderation}) {
		print getData('no_moderation');
		return;
	}

	my $total_deleted = 0;
	my $hasPosted;

	titlebar("99%", "Moderating $sid");

	$hasPosted = $slashdb->countCommentsBySidUID($sid, $user->{uid})
		unless $user->{seclev} > 99 && $constants->{authors_unlimited};

	slashDisplay('mod_header');

	# Handle Deletions, Points & Reparenting
	for my $key (sort keys %{$form}) {
		if ($user->{seclev} > 100 and $key =~ /^del_(\d+)$/) {
			$total_deleted += deleteThread($sid, $1);
		} elsif (!$hasPosted and $key =~ /^reason_(\d+)$/) {
			$was_touched ||= moderateCid($sid, $1, $form->{$key});
		}
	}
	$slashdb->setDiscussionDelCount($sid, $total_deleted);
	$was_touched = 1 if $total_deleted;

	slashDisplay('mod_footer');

	if ($hasPosted && !$total_deleted) {
		print getError('already posted');

	} elsif ($user->{seclev} && $total_deleted) {
		slashDisplay('del_message', {
			total_deleted	=> $total_deleted,
			comment_count	=> $slashdb->countCommentsBySid($sid),
		});
	}
	printComments($sid, $form->{pid}, $form->{cid});

	if ($was_touched) {
		$slashdb->setDiscussionFlagsBySid([$sid], 1, ["hitparade_dirty"]);
	}
}


##################################################################
# Handles moderation
# Moderates a specific comment. Returns whether the comment score changed.
sub moderateCid {
	my($sid, $cid, $reason) = @_;
	return 0 unless $reason;

	my $slashdb = getCurrentDB();
	my $constants = getCurrentStatic();
	my $user = getCurrentUser();

	my $comment_changed = 0;
	my $superAuthor = $constants->{authors_unlimited};

	if ($user->{points} < 1) {
		unless ($user->{seclev} > 99 && $superAuthor) {
			print getError('no points');
			return 0;
		}
	}

	# $ppid is unused in this context.
	# XXX We can't get host_name anymore, it's no longer stored.  Check
	# the logic here. - Jamie
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

	unless ($user->{seclev} > 99 and $superAuthor) {
		my $mid = $slashdb->getModeratorLogID($cid, $user->{uid});
		if ($mid) {
			$dispArgs->{type} = 'already moderated';
			slashDisplay('moderation', $dispArgs);
			return 0;
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
		$comment_changed = $slashdb->setCommentCleanup($cid, $val, $reason);
		if (!$comment_changed) {
			# This shouldn't happen;  the only way we believe it
			# could is if $val is 0, the comment is already at
			# min or max score, the user's already modded this
			# comment, or some other reason making this mod invalid.
			# This is really just here as a safety check.
			$dispArgs->{type} = 'logic error';
			slashDisplay('moderation', $dispArgs);
			return 0;
		}

		# We know things actually changed, so update points for
		# display and send a message if appropriate.
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
	return $comment_changed;
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
	# XXX Brian, check out deleteComment(); we should change its interface
	# to accept only the $cid, because it doesn't need the $sid.  Right?
	# - Jamie 2001/07/08
	$slashdb->deleteComment($cid);

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
