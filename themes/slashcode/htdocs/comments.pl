#!/usr/bin/perl -w
# This code is a part of Slash, and is released under the GPL.
# Copyright 1997-2001 by Open Source Development Network. See README
# and COPYING for more information, or see http://slashcode.com/.
# $Id$

use strict;
#use Date::Manip;  # is this needed?  -- pudge
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
	my $postflag = $user->{state}{post};

	my $op = lc($form->{op});

	my($formkey, $stories);

	######################################################
	#
	# this really should be in the db... all the op stuff...
	#
	# the formkey checks are handled by formkeyHandler. Formkey handler 
	# is called:
	#	$error_flag = 
	#		formkeyHandler($check, $formname, $formkeyid, $formkey);
	#
	# 		example of what the args would actually be:
	#
	# 		formkeyHandler('max_post_check','comments', 3, 'xd2i2u3o2u45');
	# 
	# in the case such as in users, where you have to check the formkey 
	# on 'savepasswd', which happens before "header" is called, you need 
	# to save the error message into "$note"
	#
	#	$error_flag = 
	#		formkeyHandler($check, $formname, $formkeyid, $formkey, \$note);
	#  
	# This way, since '$note' is being passwd, note gets the error message from the 
	# formkey checks (if there's and error) but won't print the error, which happens
	# by default without that 5th argument.
	# 
	# These are the major checks that formkeyHandler deals with:
	# 
	# generate_formkey - generates the formkey by populating $form->{formkey} 
	# which automagically shows up in the form
	# no message in formkeyErrors
	# 
	# max_read_check - checks how many times the form has been access
	# and returns and error if that number has been exceded
	# calls checkMaxReads
	# the var for the form is max_<formname>_viewings (just make sure it matches 
	# the message in formkeyErrors is triggered by '<formname>_maxreads' 
	# 
	# max_post_check - checks how many times formkeyid has successfully 
	# posted and returns and error if that number has been exceded
	# calls checkMaxPosts
	# the var for the form is max_<formname>_allowed (just make sure it matches 
	# the message in formkeyErrors is triggered by '<formname>_maxposts' 
	#
	# interval_check - checks the interval between last successful post
	# calls checkPostInterval
	# the var for the form is <forname>_speed_limit 
	# (check hashref in checkPostInterval) to make sure
	# the message in formkeyErrors is triggered by '<formname>_speed'
	# 
	# response_check - check the response between reply and post (only
	# used on comments so far)
	# calls checkResponseTime
	# the var is <formname>_response_limit (check hashref in checkResponseTime) 
	# the message in formkeyErrors is triggered by '<formname>_response'
	# 
	# valid_check - checks whether a formkey is valid
	# calls validFormkey
	# not form specific, no var
	# the message in formkeyErrors is triggered by 'valid', no need to add 
	# another message per form
	#
	# formkey_check - updates the formkey val to indicate the formkey has
	# been used
	# calls updateFormkeyVal
	# not form specific, just keys on the formkey itself
	# the message in formkeyErrors is triggered by 'usedform' no need to add
	# another message per form 
	#
	# regen_formkey - creates a new formkey in the case with functions that 
	# regenerate a form after submitting (without going through the op hashref)
	# just need to check the calling function and see if it generates a new form
	# outside the op hashref
	# calls createFormkey which populates $form->{formkey}
	#
	# generate_formkey - creates a new formkey. make sure this is the last call 
	# if your checking max_post_check, update_formkeyid 
	# calls createFormkey which populates $form->{formkey}
	# if you want the formkey in the form, you'll need to put
	# <INPUT TYPE="HIDDEN" NAME="FORMKEY" VALUE="[% form.formkey %]">
	# in the template for the form that you want it to be in
	# 
	# update_formkeyid - some forms require the formkey id to be updated
	# as in the case with comments where a user might reply as anon and 
	# then log in and then post
	# calls updateFormkeyID
	# 
	# note: post and edit don't look like they're used anywhere
	#
	######################################################
	my $ops	= {
		# there will only be a discussions creation form if 
		# the user is anon, or if there's an sid, therefore, we don't want 
		# a formkey if it's not a form 
		default		=> { 
			function		=> \&displayComments,
			seclev			=> 0,
			formname		=> 'discussions',
			checks			=> ($form->{sid} || isAnon($user->{uid})) ? [] : ['generate_formkey'],
		},
		change		=> { 
			function		=> \&change,
			seclev			=> 0,
			formname		=> 'discussions',
			checks			=> ($form->{sid} || isAnon($user->{uid})) ? [] : ['generate_formkey'],
		},
		'index'			=> {
			function		=> \&commentIndex,
			seclev			=> 0,
			formname 		=> 'discussions',
			checks			=> ($form->{sid} || isAnon($user->{uid})) ? [] : ['generate_formkey'],
		},
		creator_index			=> {
			function		=> \&commentIndexCreator,
			seclev			=> 0,
			formname 		=> 'discussions',
			checks			=> [],
		},
		moderate		=> {
			function		=> \&moderate,
			seclev			=> 1,
			post			=> 1,
			formname		=> 'moderate',
			checks			=> ['generate_formkey'],	
		},
		creatediscussion	=> {
			function		=> \&createDiscussion,
			seclev			=> 1,
			post			=> 1,
			formname 		=> 'discussions',
			checks			=> 
			[ qw ( max_post_check valid_check interval_check 
				formkey_check regen_formkey ) ],
		},
		reply			=> {
			function		=> \&editComment,
			formname 		=> 'comments',
			seclev			=> 0,
			checks			=> 
			[ qw ( max_post_check generate_formkey ) ],
		},
		edit 			=> {
			function		=> \&editComment,
			seclev			=> 0,
			formname 		=> 'comments',
			checks			=> 
			[ qw ( max_post_check update_formkeyid generate_formkey ) ],
		},
		preview			=> {
			function		=> \&editComment,
			seclev			=> 0,
			formname 		=> 'comments',
			checks			=> 
			[ qw ( max_post_check update_formkeyid ) ], 
		},
		post 			=> {
			function		=> \&editComment,
			seclev			=> 0,
			formname 		=> 'comments',
			checks			=> 
			[ qw ( update_formkeyid max_post_check generate_formkey	) ],
		},
		submit			=> {
			function		=> \&submitComment,
			seclev			=> 0,
			post			=> 1,
			formname 		=> 'comments',
			checks			=> 
			[ qw ( max_post_check valid_check interval_check response_check 
				formkey_check ) ],
		},
	};
	
	# This is here to save a function call, even though the
	# function can handle the situation itself
	my $discussion;
	if ($form->{sid}) {
		# SID compatibility
		if ($form->{sid} !~ /^\d+$/) {
			$discussion = $slashdb->getDiscussionBySid($form->{sid});
		} else {
			$discussion = $slashdb->getDiscussion($form->{sid});
		}
	}

	$form->{pid} ||= "0";

	header($discussion ? $discussion->{'title'} : 'Comments');

	if ($user->{is_anon} && length($form->{upasswd}) > 1) {
		print getError('login error');
		$op = 'preview';
	}
	$op = 'default' if ( ($user->{seclev} < $ops->{$op}{seclev}) || ! $ops->{$op}{function});
	$op = 'default' if (! $postflag && $ops->{$op}{post});

	print STDERR "OP $op\n" if $constants->{DEBUG};
	if ($constants->{DEBUG}) {
		for(keys %{$form}) {
			print STDERR "FORM key $_ value $form->{$_}\n";
		}
	}

	# authors shouldn't jump through formkey hoops? right?	
	if ($user->{seclev} < 100) {
		$formkey = $form->{formkey};

		# this is needed for formkeyHandler to print the correct messages 
		# yeah, the next step is to loop through the array of $ops->{$op}{check}
		for my $check (@{$ops->{$op}{checks}}) {
			$ops->{$op}{update_formkey} = 1 if $check eq 'formkey_check';
			my $formname = $ops->{$op}{formname}; 
			$error_flag = formkeyHandler($check, $formname, $formkeyid, $formkey);

			last if $error_flag;
		}
	} 

	if (! $error_flag) {
		# CALL THE OP
		my $retval = $ops->{$op}{function}->($form, $slashdb, $user, $constants, $formkeyid, $discussion);

		# this has to happen - if this is a form that you updated the formkey val ('formkey_check')
		# you need to call updateFormkey to update the timestamp (time of successful submission) and
		# note: maxCid and length aren't really required - this is legacy from when formkeys was 
		# comments specific, but it can't hurt to put some sort of length in there.. perhaps
		# the length of the primary field in your form would be a good choice.
		if ($ops->{$op}{update_formkey}) {
			if($retval) {
				my $field_length= $form->{postercomment} ? 
					length($form->{postercomment}) : length($form->{postercomment});

				# do something with updated? ummm.
				my $updated = $slashdb->updateFormkey($formkey, $field_length); 

			# updateFormkeyVal updated the formkey before the function call, 
			# but the form somehow had an error in the function it called 
			# unrelated to formkeys so reset the formkey because this is 
			# _not_ a successful submission
			} else {
				my $updated = $slashdb->resetFormkey($formkey);
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

	$slashdb->setDiscussionDelCount($form->{sid}, $delCount);
	$slashdb->setStory($form->{sid}, { writestatus => 'dirty' });
}

##################################################################
sub change {
	my($form, $slashdb, $user, $constants, $formkeyid, $discussion) = @_;

	if (defined $form->{'savechanges'} && !$user->{is_anon}) {
		$slashdb->setUser($user->{uid}, {
			threshold	=> $user->{threshold},
			mode		=> $user->{mode},
			commentsort	=> $user->{commentsort}
		});
	}
	displayComments(@_);
}

##################################################################
sub displayComments {
	my($form, $slashdb, $user, $constants, $formkeyid, $discussion) = @_;

	if ($form->{cid}) {
		printComments($discussion, $form->{cid}, $form->{cid});
	} elsif ($form->{sid}) {
		printComments($discussion, $form->{pid});
	} else {
		commentIndex(@_);
	}
}


##################################################################
# Index of recent discussions: Used if comments.pl is called w/ no
# parameters
sub commentIndex {
	my($form, $slashdb, $user, $constants, $formkeyid) = @_;

	titlebar("90%", getData('active_discussions'));
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
# Index of recent discussions: Used if comments.pl is called w/ no
# parameters
sub commentIndexCreator {
	my($form, $slashdb, $user, $constants, $formkeyid) = @_;

	my($uid, $nickname);
	if($form->{uid} or $form->{nick}) {
		$uid = $form->{uid} ? $form->{uid} : $slashdb->getUserUID($form->{nick});
		$nickname = $slashdb->getUser($uid, 'nickname');
	} else {
		$nickname	= $user->{nickname};
		$uid	= $user->{uid};
	}

	titlebar("90%", getData('user_discussion', { name => $nickname}));
	my $discussions = $slashdb->getDiscussionsByCreator($uid);
	if(@$discussions) {
		slashDisplay('discuss_list', {
			discussions	=> $discussions,
			supress_create	=> 1,
		});
	} else {
		print getData('users_no_discussions');
	}
}

##################################################################
# Yep, I changed the l33t method of adding discussions.
# "The Slash job, keeping trolls on their toes"
# -Brian
sub createDiscussion {
	my($form, $slashdb, $user, $constants, $formkeyid) = @_;

	if ($user->{seclev} >= $constants->{discussion_create_seclev}) {
		$form->{url}   = fixurl($form->{url} || $ENV{HTTP_REFERER});
		$form->{title} = strip_nohtml($form->{title});


		# for now, use the postersubj filters; problem is,
		# the error messages can come out a bit funny.
		# oh well.  -- pudge
		my($error, $err_message, $id);
		if (! filterOk('comments', 'postersubj', $form->{title}, \$err_message)) {
			$error = getError('filter message', {
				err_message	=> $err_message
			});
		} elsif (! compressOk('comments', 'postersubj', $form->{title})) {
			$error = getError('compress filter', {
				ratio	=> 'postersubj',
			});
		} else {
			$id = $slashdb->createDiscussion(
				$form->{title}, $form->{url}, $form->{topic}, 1
			);
		}

		my $formats = $slashdb->getDescriptions('postmodes');
		my $postvar = $form->{posttype} ? $form : $user;
		my $format_select = createSelect(
			'posttype', $formats, $postvar->{posttype}, 1
		);

		# Update form with the new SID for comment creation and other
		# variables necessary. See "edit_comment;misc;default".
		my $newform = {
			sid	=> $id,
			pid	=> 0, 
			title	=> $form->{title},
			formkey => $form->{formkey},
		};
		# We COULD drop ID from the call below, but not right now.
		slashDisplay('newdiscussion', { 
			error 		=> $error, 
			form		=> $newform,
			format_select	=> $format_select,
			id 		=> $id,
		});
	} else {
		slashDisplay('newdiscussion', {
			error => getError('seclevtoolow'),
		});
	}

	commentIndex(@_);
}

##################################################################
# Welcome to one of the ancient beast functions.  The comment editor
# is the form in which you edit a comment.
sub editComment {
	my($form, $slashdb, $user, $constants, $formkeyid, $discussion, $error_message) = @_;

	print STDERR "ERROR MESSAGE $error_message OP $form->{op}\n";

	# Why is this here? It's not referred to again in this scope.
	# - Cliff 7/26/01
	my $formkey_earliest = time() - $constants->{formkey_timeframe};
	my $preview;
	my $error_flag = 0;

	# Get the comment we may be responding to. Remember to turn off
	# moderation elements for this instance of the comment.
	my $reply = $slashdb->getCommentReply($form->{sid}, $form->{pid});

	if (!$constants->{allow_anonymous} && $user->{is_anon}) {
		print getError('no anonymous posting');
		return;
	}

	if (lc($form->{op}) ne 'reply' || $form->{op} eq 'preview' || ($form->{postersubj} && $form->{postercomment})) {
		$preview = previewForm(\$error_message) or $error_flag++;
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
		error_message 	=> $error_message,
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
	print STDERR "ERROR MESSAGE beginning of validate comment $$error_message\n";

	my $form_success = 1;
	my $message = '';

	$$comm ||= $form->{postercomment};
	$$subj ||= $form->{postersubj};

	if ($slashdb->checkReadOnly('comments')) {
		$$error_message = getError('readonly');
		$form_success = 0;
		# editComment('', $$error_message), return unless $preview;
		return unless $preview;
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
		print STDERR "NO BODY MESSAGE $$error_message\n";
		return;
	}

	$$subj =~ s/\(Score(.*)//i;
	$$subj =~ s/Score:(.*)//i;

	unless (defined($$comm = balanceTags($$comm, 1))) {
		$$error_message = getError('nesting_toodeep');
		# editComment('', $$error_message), return unless $preview;
		return unless $preview;
	}

	my $dupRows = $slashdb->findCommentsDuplicate($form->{sid}, $$comm);

	if ($dupRows || !$form->{sid}) {
		$$error_message = getError('validation error', {
			dups	=> $dupRows,
		});
		# editComment('', $$error_message), return unless $preview;
		return unless $preview;
		# return;
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
		#	editComment('', $$error_message), return unless $preview;
			return unless $preview;
		#	return;
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
		#	editComment('', $$error_message), return unless $preview;
			return unless $preview;
			last;
		}
		# run through compress test
		if (! compressOk('comments', $_, $fields->{$_})) {
			# blammo luser
			$$error_message = getError('compress filter', {
					ratio	=> $_,
			});
			#editComment('', $$error_message), return unless $preview;
			return unless $preview;
			$form_success = 0;
			last;
		}

	}


	$$error_message ||= '';
	print STDERR "ERROR MESSAGE end of validate comment $$error_message\n";
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
	my($form, $slashdb, $user, $constants, $formkeyid, $discussion) = @_;

	my $error_message;

	$form->{postersubj} = strip_nohtml($form->{postersubj});
	$form->{postercomment} = strip_mode($form->{postercomment}, $form->{posttype});

	unless (validateComment(\$form->{postercomment}, \$form->{postersubj}, \$error_message)) {
		editComment(@_, $error_message);
		return(0);
	}

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
		return(0);

	} elsif (!$maxCid) {
		# What vars should be accessible here?
		#	- $maxCid?
		# What are the odds on this happening? Hmmm if it is we should
		# increase the size of int we used for cid.
		print getError('maxcid exceeded');
		return(0);
	} else {
		slashDisplay('comment_submit');
		undoModeration($form->{sid});
		printComments($discussion, $maxCid, $maxCid);

		my $tc = $slashdb->getVar('totalComments', 'value');
		$slashdb->setVar('totalComments', ++$tc);

		# This is for stories. If a sid is only a number
		# then it belongs to discussions, if it has characters
		# in it then it belongs to stories and we should
		# update to help with stories/hitparade.
		# -Brian
		if ($form->{sid} !~ /^\d+$/) {
			$slashdb->setStory($form->{sid}, { writestatus => 'dirty' });
		}

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
				my $reply	= $slashdb->getCommentReply($form->{sid}, $maxCid);
				my $discussion	= $slashdb->getDiscussion($form->{sid});
				my $data    = {
					template_name	=> 'reply_msg',
					subject		=> { template_name => 'reply_msg_subj' },
					reply		=> $reply,
					parent		=> $parent,
					discussion	=> $discussion,
				};

				$messages->create($users->[0], MSG_CODE_COMMENT_REPLY, $data);
			}
		}
	}
	return(1);
}


##################################################################
# Handles moderation
# gotta be a way to simplify this -Brian
sub moderate {
	my($form, $slashdb, $user, $constants, $formkeyid, $discussion) = @_;

	my $sid = $form->{sid};
	my $was_touched = 0;

	if (! $constants->{allow_moderation}) {
		print getData('no_moderation');
		return;
	}

	my $total_deleted = 0;
	my $hasPosted;

	# The content here should also probably go into a template.
	titlebar("99%", "Moderating...");

	$hasPosted = $slashdb->countCommentsBySidUID($sid, $user->{uid})
		unless $user->{seclev} > 99 && $constants->{authors_unlimited};

	slashDisplay('mod_header');

	# Handle Deletions, Points & Reparenting
	for my $key (sort keys %{$form}) {
		if ($user->{seclev} > 100 and $key =~ /^del_(\d+)$/) {
			$total_deleted += deleteThread($sid, $1);
		} elsif (!$hasPosted and $key =~ /^reason_(\d+)$/) {
			$was_touched += moderateCid($sid, $1, $form->{$key});
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
	printComments($discussion, $form->{pid}, $form->{cid});

	if ($was_touched) {
		# This is for stories. If a sid is only a number
		# then it belongs to discussions, if it has characters
		# in it then it belongs to stories and we should
		# update to help with stories/hitparade.
		# -Brian
		if ($form->{sid} !~ /^\d+$/) {
			$slashdb->setStory($form->{sid}, { writestatus => 'dirty' });
		}
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
		$comment_changed =
			$slashdb->setCommentCleanup($cid, $val, $reason);
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
				my $discussion = $slashdb->getDiscussion($sid);
				my $data  = {
					template_name	=> 'mod_msg',
					subject		=> {
						template_name => 'mod_msg_subj'
					},
					comment		=> $comment,
					discussion	=> $discussion,
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
