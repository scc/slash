#!/usr/bin/perl -w

###############################################################################
# comments.pl - this code displays comments for a particular story id 
#
# Copyright (C) 1997 Rob "CmdrTaco" Malda
# malda@slashdot.org
#
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License
# as published by the Free Software Foundation; either version 2
# of the License, or (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program; if not, write to the Free Software
# Foundation, Inc., 59 Temple Place - Suite 330, Boston, MA  02111-1307, USA.
#
#
#  $Id$
###############################################################################
use strict;
use Date::Manip;
use Compress::Zlib;
use HTML::Entities;
use Slash;
use Slash::Display;
use Slash::Utility;


##################################################################
sub main {
	my $dbslash = getCurrentDB();
	my $constants = getCurrentStatic();
	my $form = getCurrentForm();
	my $user = getCurrentUser();
	my $id = getFormkeyId($user->{uid});

	my $stories;
	#This is here to save a function call, even though the
	# function can handle the situation itself
	$stories = $dbslash->getNewStory($form->{sid},
				['section', 'title', 'commentstatus']);
	$stories->{'title'} ||= "Comments";

	my $SECT = $dbslash->getSection($stories->{'section'});

	$form->{pid} ||= "0";
	
	header("$SECT->{title}: $stories->{'title'}", $SECT->{section});

	if ($user->{uid} < 1 && length($form->{upasswd}) > 1) {
		slashDisplay('errors', {
			type		=> 'login error',
		});
		$form->{op} = "Preview";
	}

	if ($form->{op} eq "Submit") {
		submitComment($form, $user, $dbslash, $constants)
			if checkSubmission("comments",
					   $constants->{post_limit},
					   $constants->{max_posts_allowed},
					   $id);

	} elsif ($form->{op} eq "Edit" || $form->{op} eq "post" ||
			 $form->{op} eq "Preview" || $form->{op} eq "Reply") {

		if ($form->{op} eq 'Reply') {
			$form->{formkey} = $dbslash->getFormkey();
			$dbslash->insertFormkey("comments", $id, $form->{sid});	
		} else {
			$dbslash->updateFormkeyId('comments',
				$form->{formkey},
				$constants->{anonymous_coward_uid},
				$user->{uid},
				$form->{'rlogin'},
				$form->{upasswd}
			);
		}

		editComment($id, $form, $user, $dbslash, $constants);

	} elsif ($form->{op} eq "delete" && $user->{seclev}) {
		titlebar("99%", "Delete $form->{cid}");

		my $delCount = deleteThread($form->{sid}, $form->{cid}, $user, $dbslash);
		$dbslash->createCommentCount($delCount);

	} elsif ($form->{op} eq "moderate") {
		titlebar("99%", "Moderating $form->{sid}");
		moderate($form, $user, $dbslash, $constants);
		printComments($form->{sid}, $form->{pid}, $form->{cid});

	} elsif ($form->{op} eq "Change") {
		if (defined $form->{'savechanges'} && !$user->{is_anon}) {
			$dbslash->setUser($user->{uid}, {
				threshold	=> $user->{threshold}, 
				mode		=> $user->{mode},
				commentsort	=> $user->{commentsort}
			});
		}
		printComments($form->{sid}, $form->{cid}, $form->{cid});

	} elsif ($form->{cid}) {
		printComments($form->{sid}, $form->{cid}, $form->{cid});

	} elsif ($form->{sid}) {
		printComments($form->{sid}, $form->{pid});
	} else {
		commentIndex($dbslash);
	}

	writeLog('comments', $form->{sid}) unless $form->{ssi};

	footer();
}


##################################################################
# Index of recent discussions: Used if comments.pl is called w/ no
# parameters
sub commentIndex {
	my ($dbslash) = @_;

	titlebar("90%", "Several Active Discussions");
	my $discussions = $dbslash->getDiscussions();
	slashDisplay('discussion_list', {
		discussions => $discussions,
	});
}


##################################################################
# Welcome to one of the ancient beast functions.  The comment editor
# is the form in which you edit a comment.
sub editComment {
	my($id, $form, $user, $dbslash, $constants, $error_message) = @_;

	my $formkey_earliest = time() - $constants->{formkey_timeframe};

	# Get the comment we may be responding to. Remember to turn off 
	# moderation elements for this instance of the comment. 
	my $reply = $dbslash->getCommentReply($form->{sid}, $form->{pid});
	$reply->{no_moderation} = 1;

	if (!$constants->{allow_anonymous} && $user->{is_anon}) {
		slashDisplay('errors', {
			type	=> 'no anonymous posting',
		});
	    return;
	}

	my $mp = $constants->{max_posts_allowed};
	my $previewForm;
	# Don't munge the current error_message if there already is one.
	if (! $dbslash->checkTimesPosted('comments',$mp,$id,$formkey_earliest)) {
		$error_message ||= slashDisplay('errors', {
			type		=> 'max posts',
			max_posts 	=> $mp,
		}, 1);
	} else {
		$previewForm = previewForm($form, $user) if ($form->{postercomment});
		if ($previewForm =~ s/^ERROR: //) {
			$error_message ||= $previewForm;
			$previewForm = '';
		}
	}

	if ($form->{pid} && !$form->{postersubj}) { 
		$form->{postersubj} = $reply->{subject};
		$form->{postersubj} =~ s/^Re://i;
		$form->{postersubj} =~ s/\s\s/ /g;
		$form->{postersubj} = "Re:$form->{postersubj}";
	} 

	my $formats = $dbslash->getDescriptions('postmodes');

	my $formatSelect = ($form->{posttype}) ?
		createSelect('posttype', $formats, $form->{posttype}, 1) :
		createSelect('posttype', $formats, $user->{posttype}, 1);

	my $approvedtags =
		join "\n", map { "\t\t\t&lt;$_&gt;" } @{$constants->{approvedtags}};

	slashDisplay('edit_comment', {
		approved_tags => $approvedtags,
		error_message => $error_message,
		format_select => $formatSelect,
		preview => $previewForm,
		reply => $reply,
	});
}


##################################################################
# Validate comment, looking for errors
sub validateComment {
	my($form, $user, $preview, $comm, $subj) = @_;
	$comm ||= $form->{postercomment};
	$subj ||= $form->{postersubj};

	my $dbslash = getCurrentDB();
	my $constants = getCurrentStatic();

	if (isTroll($user, $constants, $dbslash)) {
		my $err_msg = slashDisplay('errors', {
			type 		=> 'troll message',
		}, 1);
		return(undef, undef, $err_msg);
	}

	if (!$constants->{allow_anonymous} && ($user->{uid} < 1 || $form->{postanon})) { 
		my $err_msg = slashDisplay('errors', {
			type	=> 'anonymous disallowed', 
		}, 1);
		return(undef, undef, $err_msg);
	}

	unless ($$comm && $$subj) {
		my $err_msg = slashDisplay('errors', {
			type	=> 'no body',
		}, 1);
		return(undef, undef, $err_msg);
	}

	$subj =~ s/\(Score(.*)//i;
	$subj =~ s/Score:(.*)//i;

	unless (defined($$comm = balanceTags($$comm, 1))) {
		my $err_msg = slashDisplay('errors', {
			type =>	'nesting_toodeep',
		}, 1);
		editComment('', $form, $user, $dbslash, $constants, $err_msg), return unless $preview;
		return(undef, undef, $err_msg);
	}

	my $dupRows = $dbslash->countComments($form->{sid}, '', $form->{postercomment});

	if ($dupRows || !$form->{sid}) { 
		my $err_msg = slashDisplay('errors', {
			type	=> 'validation error',
			dups	=> $dupRows,
		});
		editComment('', $form, $user, $dbslash, $constants, $err_msg), return unless $preview;
		return (undef, undef, $err_msg);
	}

	if (length($form->{postercomment}) > 100) {
		local $_ = $form->{postercomment};
		my($w, $br); # Words & BRs
		$w++ while m/\w/g;
		$br++ while m/<BR>/gi;

		# Should the naked '7' be converted to a Slash Variable for return by
		# getCurrentStatic(). 	- Cliff
		if (($w / ($br + 1)) < 7) {
			my $err_msg = slashDisplay('errors', {
				type	=> 'low words-per-line',
				ratio 	=> $w / ($br + 1),
			}, 1);
			editComment('', $form, $user, $dbslash, $constants, $err_msg), return unless $preview;
			return (undef, undef, $err_msg);
		}
	}

	# here begins the troll detection code - PMG 160200
	# hash ref from db containing regex, modifier (gi,g,..),field to be
	# tested, ratio of field (this makes up the {x,} in the regex, minimum
	# match (hard minimum), minimum length (minimum length of that comment
	# has to be to be tested), err_message message displayed upon failure
	# to post if regex matches contents. make sure that we don't select new
	# filters without any regex data.
	my $filters = $dbslash->getContentFilters();
	my @filterMatch = (0, '');
	for (@$filters) {
		my($number_match, $regex);
		my $raw_regex		= $_->[1];
		my $modifier		= 'g' if $_->[2] =~ /g/;
		my $case		= 'i' if $_->[2] =~ /i/;
		my $field		= $_->[3];
		my $ratio		= $_->[4];
		my $minimum_match	= $_->[5];
		my $minimum_length	= $_->[6];
		my $err_message		= $_->[7];
		my $maximum_length	= $_->[8];
		my $isTrollish		= 0;
		my $text_to_test	= decode_entities($form->{$field});
		$text_to_test		=~ s/\xA0/ /g;
		$text_to_test		=~ s/\<br\>/\n/gi;

		next if ($minimum_length && length($text_to_test) < $minimum_length);
		next if ($maximum_length && length($text_to_test) > $maximum_length);

		if ($minimum_match) {
			$number_match = "{$minimum_match,}";
		} elsif ($ratio > 0) {
			$number_match = "{" . int(length($text_to_test) * $ratio) . ",}";
		}

		$regex = $raw_regex . $number_match;
		my $tmp_regex = $regex;


		$regex = $case eq 'i' ? qr/$regex/i : qr/$regex/;

		if ($modifier eq 'g') {
			$isTrollish = 1 if $text_to_test =~ /$regex/g;
		} else {
			$isTrollish = 1 if $text_to_test =~ /$regex/;
		}

		if ((length($text_to_test) >= $minimum_length)
			&& $minimum_length && $isTrollish) {

			if (((length($text_to_test) <= $maximum_length)
				&& $maximum_length) || $isTrollish) {

				my $err_msg = slashDisplay('errors', {
					type		=> 'filter message',
					err_message => $err_message,
				}, 1);

				editComment('', $form, $user, $dbslash, $constants, $err_msg), return
					unless $preview;
				@filterMatch = (1, $err_msg);
				last;
			}

		} elsif ($isTrollish) {
			my $err_msg = slashDisplay('errors', {
				type		=> 'filter message',
				err_message => $err_message,
			}, 1);

			editComment('', $form, $user, $dbslash, $constants, $err_msg), return unless $preview;
			@filterMatch = (1, $err_msg);
			last;
		}
	}

	# interpolative hash ref. Got these figures by testing out
	# several paragraphs of text and saw how each compressed
	# the key is the ratio it should compress, the array lower,upper
	# for the ratio. These ratios are _very_ conservative
	# a comment has to be absolute shit to trip this off
	if (!$filterMatch[0]) {
		my $limits = {
			1.3 => [10,19],
			1.1 => [20,29],
			.8 => [30,44],
			.5 => [45,99],
			.4 => [100,199],
			.3 => [200,299],
			.2 => [300,399],
			.1 => [400,1000000],
		};

		# Ok, one list ditch effort to skew out the trolls!
		if (length($form->{postercomment}) >= 10) {
			for (keys %$limits) {
				# DEBUG
				# print "ratio $_ lower $limits->{$_}->[0] upper $limits->{$_}->[1]<br>\n";
				# if it's within lower to upper
				if (length($form->{postercomment}) >= $limits->{$_}->[0] &&
					length($form->{postercomment}) <= $limits->{$_}->[1]) {

					# if is >= the ratio, then it's most likely a
					# troll comment
					if ((length(compress($form->{postercomment})) /
					     length($form->{postercomment})) <= $_) {
	
						# blammo luser
						my $err_msg = slashDisplay('errors', {
							type	=> 'compress filter',
							ratio	=> $_,
						}, 1);
						editComment('', $form, $user, $dbslash, $constants, $err_msg), return
							unless $preview;
						@filterMatch = (1, $err_msg);
					}

				}
			}
		}
	}
	
	# Return error condition...
	return (undef, undef, $filterMatch[1]) if $filterMatch[0];

	# ...otherwise return data.
	return ($comm, $subj);
}

##################################################################
# Previews a comment for submission
sub previewForm {
	my($form, $user) = @_;

	$user->{sig} = "" if $form->{postanon};

	my $tempComment = strip_mode($form->{postercomment}, $form->{posttype});
	my $tempSubject = strip_nohtml($form->{postersubj}, $user->{seclev});
	my $error_message;

	($tempComment, $tempSubject, $error_message) =
		validateComment($form, $user, 1, $tempComment, $tempSubject);

	return "ERROR: $error_message" if $error_message;

	my $preview = {
		nickname	=> $form->{postanon} ?
			getCurrentAnonymousCoward('nickname') : $user->{nickname},
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
		$previewForm = slashDisplay('preview_comment', {
			preview => $preview,
		}, 1);	
	}
	$user->{mode} = $tm;

	return $previewForm;
}


##################################################################
# Saves the Comment
sub submitComment {
	my ($form, $user, $dbslash, $constants) = @_;
	my $error_message;

	$form->{postersubj} = strip_nohtml($form->{postersubj});
	$form->{postercomment} = strip_mode($form->{postercomment}, $form->{posttype});

	($form->{postercomment}, $form->{postersubj}, $error_message) =
		validateComment($form, $user);

	return if $error_message || (!$form->{postercomment} && !$form->{postersubj});

	titlebar("95%", "Submitted Comment");

	my $pts = 0;

	if (!$user->{is_anon} && !$form->{postanon} ) {
		$pts = $user->{defaultpoints};
		$pts-- if $user->{karma} < $constants->{badkarma};
		$pts++ if $user->{karma} > $constants->{goodkarma} && !$form->{nobonus};
		# Enforce proper ranges on comment points.
		my ($minScore,$maxScore)=($constants->{comment_minscore},$constants->{comment_maxscore});
		$pts = $minScore if $pts < $minScore;
		$pts = $maxScore if $pts > $maxScore;
	}

	# It would be nice to have an arithmatic if right here
	my $maxCid = $dbslash->createComment($form, $user, $pts, $constants->{anonymous_coward_uid});

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
		slashDisplay('comment_submitted');
		undoModeration($form->{sid}, $user, $dbslash, $constants);
		printComments($form->{sid}, $maxCid, $maxCid);

		unless ($dbslash->getDiscussion($form->{sid}, 'title')) {
			$dbslash->setDiscussion($form->{sid}, { title => $form->{postersubj}}) if $form->{sid};
		}

		my $tc = $dbslash->getVar('totalComments');
		$dbslash->setVar('totalComments', ++$tc);

		if ($dbslash->getStory($form->{sid},'writestatus') == 0) {
			$dbslash->setStory($form->{sid}, { writestatus => 1 });
		}

		$dbslash->setUser($user->{uid}, { -totalcomments => 'totalcomments+1' });

		$dbslash->formSuccess($form->{formkey}, $maxCid, length($form->{postercomment}));
	}
}




##################################################################
# Handles moderation
# gotta be a way to simplify this -Brian
sub moderate {
	my ($form, $user, $dbslash, $constants) = @_;
	my $totalDel = 0;
	my $hasPosted;

	unless($user->{seclev} > 99 && $constants->{authors_unlimited}) {
		$hasPosted = $dbslash->countComments($form->{sid}, '','', $user->{uid});
	}

	slashDisplay('moderation_header');

	# Handle Deletions, Points & Reparenting
	for (sort keys %{$form}) {
		if (/^del_(\d+)$/) { # && $user->{points}) {
			my $delCount = deleteThread($form->{sid}, $1, $user, $dbslash);
			$totalDel += $delCount;
			$dbslash->setStoriesCount($form->{sid}, $delCount);

		} elsif (!$hasPosted && /^reason_(\d+)$/) {
			moderateCid($form->{sid}, $1, $form->{"reason_$1"}, $user, $dbslash, $constants);
		}
	}

	slashDisplay('moderation_footer');

	if ($hasPosted && !$totalDel) {
		slashDisplay('errors', {
			type	=> 'already posted',
		});
	} elsif ($user->{seclev} && $totalDel) {
		my $count = $dbslash->countComments($form->{sid});
		slashDisplay('deleted_message', {
			total_deleted => $totalDel,
			comment_count => $count,
		});
	}
}


##################################################################
# Handles moderation
# Moderates a specific comment
sub moderateCid {
	my($sid, $cid, $reason, $user, $dbslash, $constants) = @_;
	# Check if $userid has seclev and Credits
	return unless $reason;

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
		$dbslash->getComments($sid, $cid);

	my $dispArgs = {
		cid	=> $cid,
		sid	=> $sid,
		subject => $subj,
		reason	=> $constants->{reasons}[$reason],
		points	=> $user->{points},
	};
	
	unless ($user->{seclev} > 99 && $superAuthor) {
		my $mid = $dbslash->getModeratorLogID($cid, $sid, $user->{uid});
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
	if ($scorecheck < $constants->{comment_minscore} || 
	    $scorecheck > $constants->{comment_maxscore})
	{
		# We should still log the attempt for M2, but marked as
		# 'inactive' so we don't mistakenly undo it.
		$dbslash->setModeratorLog($cid, $sid, $user->{uid}, $val, $modreason);
		$dispArgs->{type} = 'score limit';
		slashDisplay('moderation', $dispArgs);
		return;
	}

	if ($dbslash->setCommentCleanup($val, $sid, $reason, $modreason, $cid)) {
		# Update points for display due to possible change in above line.
		$dispArgs->{points} = $user->{points};
		$dispArgs->{type} = 'moderated';
		slashDisplay('moderation', $dispArgs);
	}
}


##################################################################
# Given an SID & A CID this will delete a comment, and all its replies
sub deleteThread {
	my($sid, $cid, $user, $dbslash, $level, $deleted) = @_;
	$level ||= 0;

	my $delCount = 1;
	my @delList if !$level;
	$deleted = \@delList if !$level;

	return unless $user->{seclev} > 100;

	my $delkids = $dbslash->getCommentCid($sid, $cid);

	# Delete children of $cid.
	push @{$deleted}, $cid;
	for (@{$delkids}) {
		my ($cid) = @{$_};
		push @{$deleted}, $cid;
		$delCount += deleteThread($sid, $cid, $user, $dbslash, $level + 1, $deleted);
	}
	# And now delete $cid.
	$dbslash->deleteComment($sid, $cid);

	if (!$level) {
		slashDisplay('deleted_cids', {
			sid => $sid,
			count => $delCount,
			comments_deleted => $deleted,
		});
	}
	return $delCount;
}


##################################################################
# If you moderate, and then post, all your moderation is undone.
sub undoModeration {
	my($sid, $user, $dbslash, $constants) = @_;
	return if !$user->{is_anon} || ($user->{seclev} > 99 && $constants->{authors_unlimited});

	my $removed = $dbslash->unsetModeratorlog($user->{uid}, $sid,
		$constants->{comment_maxscore}, $constants->{comment_minscore});

	slashDisplay('undo_moderation', {
		removed => $removed,
	});
}


##################################################################
# Troll Detection: essentially checks to see if this IP or UID has been
# abusing the system in the last 24 hours.
# 1=Troll 0=Good Little Goober
# This maybe should go into DB package -Brian
sub isTroll {
	my ($user, $constants, $dbslash) = @_;
	return if $user->{seclev} > 99;

	my($badIP, $badUID) = (0, 0);
	return 0 if !$user->{is_anon} && $user->{karma} > -1;

	# Anonymous only checks HOST
	my $downMods = $constants->{down_moderations};
	$badIP = $dbslash->getTrollAddress();
	return 1 if $badIP < $downMods;

	unless ($user->{is_anon}) {
		$badUID = $dbslash->getTrollUID();
	}

	return 1 if $badUID < $downMods;
	return 0;
}

createEnvironment();
main();
1;
