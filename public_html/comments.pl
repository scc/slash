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
	if ($form->{sid}) {
		$stories = $dbslash->getNewStory($form->{sid},
				['section', 'title', 'commentstatus']);
	} else {
		$stories->{'title'} = "Comments";
	}
	my $SECT = $dbslash->getSection($stories->{'section'});

	$form->{pid} ||= "0";
	
	header("$SECT->{title}: $stories->{'title'}", $SECT->{section});

	if ($user->{uid} < 1 && length($form->{upasswd}) > 1) {
		slashDisplay('comments-error', {
			type		=> 'login error',
		});
		$form->{op} = "Preview";
	}

	$dbslash->createDiscussions($form->{sid}) unless ($form->{sid});

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
		$dbslash->setCommentCount($delCount);
#		print "Deleted $delCount items from story $form->{sid}\n";

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
		commentIndex($dbslash, $constants);
	}

	writeLog('comments', $form->{sid}) unless $form->{ssi};

	footer();
}


##################################################################
# Index of recent discussions: Used if comments.pl is called w/ no
# parameters
sub commentIndex {
	my ($db, $c) = @_;

	titlebar("90%", "Several Active Discussions");
	my $discussions = $db->getDiscussions();
	slashDisplay('comments-discussion_list', {
		discussions => $discussions,
	});
}


##################################################################
# Welcome to one of the ancient beast functions.  The comment editor
# is the form in which you edit a comment.
sub editComment {
	my($id, $f, $u, $db, $c, $error_message) = @_;

	my $formkey_earliest = time() - $c->{formkey_timeframe};

	# Get the comment we may be responding to. Remember to turn off 
	# moderation elements for this instance of the comment. 
	my $reply = $db->getCommentReply($f->{sid}, $f->{pid});
	$reply->{no_moderation} = 1;

	if (!$c->{allow_anonymous} && $u->{is_anon}) {
		slashDisplay('comments-error', {
			type	=> 'no anonymous posting',
		});
	    return;
	}

	my $mp = $c->{max_posts_allowed};
	my $previewForm;
	# Don't munge the current error_message if there already is one.
	if (! $db->checkTimesPosted('comments',$mp,$id,$formkey_earliest)) {
		$error_message ||= slashDisplay('comments-errors', {
			type		=> 'max posts',
			max_posts 	=> $mp,
		}, 1);
	} else {
		$previewForm = previewForm($f, $u) if ($f->{postercomment});
		if ($previewForm =~ s/^ERROR: //) {
			$error_message ||= $previewForm;
			$previewForm = '';
		}
	}

	if ($f->{pid} && !$f->{postersubj}) { 
		$f->{postersubj} = $reply->{subject};
		$f->{postersubj} =~ s/^Re://i;
		$f->{postersubj} =~ s/\s\s/ /g;
		$f->{postersubj} = "Re:$f->{postersubj}";
	} 

	my $formats = $db->getDescriptions('postmodes');

	my $formatSelect = ($f->{posttype}) ?
		createSelect('posttype', $formats, $f->{posttype}, 1) :
		createSelect('posttype', $formats, $u->{posttype}, 1);

	my $approvedtags =
		join "\n", map { "\t\t\t&lt;$_&gt;" } @{$c->{approvedtags}};

	slashDisplay('comments-edit_comment', {
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
	my($f, $u, $preview, $comm, $subj) = @_;
	$comm ||= $f->{postercomment};
	$subj ||= $f->{postersubj};

	my $db = getCurrentDB();
	my $c = getCurrentStatic();

	if (isTroll($u, $c, $db)) {
		my $err_msg = slashDisplay('comments-errors', {
			type 		=> 'troll message',
		}, 1);
		return (undef, undef, $err_msg);
	}

	if (!$c->{allow_anonymous} && ($u->{uid} < 1 || $f->{postanon})) { 
		my $err_msg = slashDisplay('comments-errors', {
			type	=> 'anonymous disallowed', 
		}, 1);
		return (undef, undef, $err_msg);
	}

	unless ($comm && $subj) {
		my $err_msg = slashDisplay('comments-errors', {
			type	=> 'no body',
		}, 1);
		return (undef, undef, $err_msg);
	}

	$subj =~ s/\(Score(.*)//i;
	$subj =~ s/Score:(.*)//i;

	{  # fix unclosed tags
		my(%tags, @stack, $match, %lone, $tag, $close, $whole);

		# set up / get preferences
		if ($c->{lonetags}) {
			$match = join '|', @{$c->{approvedtags}};
		} else {
			$c->{lonetags} = [qw(BR P LI)];
			$match = join '|', grep !/^(?:BR|P|LI)$/,
				@{$c->{approvedtags}};
		}
		%lone = map { ($_, 1) } @{$c->{lonetags}};

		# If the quoted slash in the next line bothers you, then feel free to
		# remove it. It's just there to prevent broken syntactical highlighting
		# on certain editors (vim AND xemacs).  -- Cliff
		# maybe you should use a REAL editor, like BBEdit.  :) -- pudge 
		while ($comm =~ m|(<(\/?)($match)\b[^>]*>)|igo) { # loop over tags
			($tag, $close, $whole) = ($3, $2, $1);

			if ($close) {
				if (@stack && $tags{$tag}) {
					# Close the tag on the top of the stack
					if ($stack[-1] eq $tag) {
						$tags{$tag}--;
						pop @stack;

					# Close tag somewhere else in stack
					} else {
						my $p = pos($comm) - length($whole);
						if (exists $lone{$stack[-1]}) {
							pop @stack;
						} else {
							substr($comm, $p, 0) = "</$stack[-1]>";
						}
						pos($comm) = $p;  # don't remove this from stack, go again
					}

				} else {
					# Close tag not on stack; just delete it
					my $p = pos($comm) - length($whole);
					$comm =~ s|^(.{$p})\Q$whole\E|$1|si;
					pos($comm) = $p;
				}


			} else {
				$tags{$tag}++;
				push @stack, $tag;

				if (($tags{UL} + $tags{OL} + $tags{BLOCKQUOTE}) > 4) {
					my $err_msg = slashDisplay('comments-errors', {
						type =>	'nesting_toodeep',
					}, 1);
					return (undef, undef, $err_msg);
				}
			}

		}

		$comm =~ s/\s+$//;

		# add on any unclosed tags still on stack
		$comm .= join '', map { "</$_>" } grep {! exists $lone{$_}} reverse @stack;

	}

	my $dupRows = $db->countComments($f->{sid}, '', $f->{postercomment});

	if ($dupRows || !$f->{sid}) { 
		my $err_msg = slashDisplay('comments-errors', {
			type	=> 'validation error',
			dups	=> $dupRows,
		});
		editComment('', $f, $u, $db, $c, $err_msg), return unless $preview;
		return (undef, undef, $err_msg);
	}

	if (length($f->{postercomment}) > 100) {
		local $_ = $f->{postercomment};
		my($w, $br); # Words & BRs
		$w++ while m/\w/g;
		$br++ while m/<BR>/gi;

		# Should the naked '7' be converted to a Slash Variable for return by
		# getCurrentStatic(). 	- Cliff
		if (($w / ($br + 1)) < 7) {
			my $err_msg = slashDisplay('comments-error', {
				type	=> 'low words-per-line',
				ratio 	=> $w / ($br + 1),
			}, 1);
			editComment('', $f, $u, $db, $c, $err_msg), return unless $preview;
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
	my $filters = $db->getContentFilters();
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
		
		next if ($minimum_length && length($f->{$field}) < $minimum_length);
		next if ($maximum_length && length($f->{$field}) > $maximum_length);

		if ($minimum_match) {
			$number_match = "{$minimum_match,}";
		} elsif ($ratio > 0) {
			$number_match = "{" . int(length($f->{$field}) * $ratio) . ",}";
		}

		$regex = $raw_regex . $number_match;
		my $tmp_regex = $regex;


		$regex = $case eq 'i' ? qr/$regex/i : qr/$regex/;

		if ($modifier eq 'g') {
			$isTrollish = 1 if $f->{$field} =~ /$regex/g;
		} else {
			$isTrollish = 1 if $f->{$field} =~ /$regex/;
		}

		if ((length($f->{$field}) >= $minimum_length)
			&& $minimum_length && $isTrollish) {

			if (((length($f->{$field}) <= $maximum_length)
				&& $maximum_length) || $isTrollish) {

				my $err_msg = slashDisplay('comments-errors', {
					type		=> 'filter message',
					err_message => $err_message,
				}, 1);

				editComment('', $f, $u, $db, $c, $err_msg), return
					unless $preview;
				@filterMatch = (1, $err_msg);
				last;
			}

		} elsif ($isTrollish) {
			my $err_msg = slashDisplay('comments-errors', {
				type		=> 'filter message',
				err_message => $err_message,
			}, 1);

			editComment('', $f, $u, $db, $c, $err_msg), return unless $preview;
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
		if (length($f->{postercomment}) >= 10) {
			for (keys %$limits) {
				# DEBUG
				# print "ratio $_ lower $limits->{$_}->[0] upper $limits->{$_}->[1]<br>\n";
				# if it's within lower to upper
				if (length($f->{postercomment}) >= $limits->{$_}->[0] &&
					length($f->{postercomment}) <= $limits->{$_}->[1]) {

					# if is >= the ratio, then it's most likely a
					# troll comment
					if ((length(compress($f->{postercomment})) /
					     length($f->{postercomment})) <= $_) {
	
						# blammo luser
						my $err_msg = slashDisplay('comments-error', {
							type	=> 'compress filter',
							ratio	=> $_,
						}, 1);
						editComment('', $f, $u, $db, $c, $err_msg), return
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
		$previewForm = slashDisplay('comments-preview_comment', {
			preview => $preview,
		}, 1);	
	}
	$user->{mode} = $tm;

	return $previewForm;
}


##################################################################
# Saves the Comment
sub submitComment {
	my ($f, $u, $db, $c) = @_;
	my $error_message;

	$f->{postersubj} = strip_nohtml($f->{postersubj});
	$f->{postercomment} = strip_mode($f->{postercomment}, $f->{posttype});

	($f->{postercomment}, $f->{postersubj}, $error_message) =
		validateComment($f, $u);

	return if $error_message || (!$f->{postercomment} && !$f->{postersubj});

	titlebar("95%", "Submitted Comment");

	my $pts = 0;

	if (!$u->{is_anon} && !$f->{postanon} ) {
		$pts = $u->{defaultpoints};
		$pts-- if $u->{karma} < $c->{badkarma};
		$pts++ if $u->{karma} > $c->{goodkarma} && !$f->{nobonus};
		# Enforce proper ranges on comment points.
		my ($minScore,$maxScore)=($c->{comment_minscore},$c->{comment_maxscore});
		$pts = $minScore if $pts < $minScore;
		$pts = $maxScore if $pts > $maxScore;
	}

	# It would be nice to have an arithmatic if right here
	my $maxCid = $db->setComment($f, $u, $pts, $c->{anonymous_coward_uid});
	if ($maxCid == -1) {
		# What vars should be accessible here?
		slashDisplay('comments-error', {
			type	=> 'submission error',
		});
	} elsif (!$maxCid) {
		# What vars should be accessible here?
		#	- $maxCid?
		slashDisplay('comments-error', {
			type	=> 'maxcid exceeded',
		});
	} else {
		slashDisplay('comments-comment_submitted');
		undoModeration($f->{sid}, $u, $db, $c);
		printComments($f->{sid}, $maxCid, $maxCid);
	}
}


##################################################################
# Handles moderation
# gotta be a way to simplify this -Brian
sub moderate {
	my ($f, $u, $db, $c) = @_;
	my $totalDel = 0;
	my $hasPosted;

	unless($u->{seclev} > 99 && $c->{authors_unlimited}) {
		$hasPosted = $db->countComments($f->{sid}, '','', $u->{uid});
	}

	slashDisplay('comments-moderation_header');

	# Handle Deletions, Points & Reparenting
	for (sort keys %{$f}) {
		if (/^del_(\d+)$/) { # && $user->{points}) {
			my $delCount = deleteThread($f->{sid}, $1, $u, $db);
			$totalDel += $delCount;
			$db->setStoriesCount($f->{sid}, $delCount);

		} elsif (!$hasPosted && /^reason_(\d+)$/) {
			moderateCid($f->{sid}, $1, $f->{"reason_$1"}, $u, $db, $c);
		}
	}

	slashDisplay('comments-moderation_footer');

	if ($hasPosted && !$totalDel) {
		slashDisplay('comments-errors', {
			type	=> 'already posted',
		});
	} elsif ($u->{seclev} && $totalDel) {
		my $count = $db->countComments($f->{sid});
		slashDisplay('comments-deleted_message', {
			total_deleted => $totalDel,
			comment_count => $count,
		});
	}
}


##################################################################
# Handles moderation
# Moderates a specific comment
sub moderateCid {
	my($sid, $cid, $reason, $u, $db, $c) = @_;
	# Check if $uid has seclev and Credits
	return unless $reason;

	my $superAuthor = $c->{authors_unlimited};
	
	if ($u->{points} < 1) {
		unless ($u->{seclev} > 99 && $superAuthor) {
			slashDisplay('comments-errors', {
				type	=> 'no points',
			});
			return;
		}
	}

	my($cuid, $ppid, $subj, $points, $oldreason) = 
		$db->getComments($sid, $cid);

	my $dispArgs = {
		cid	=> $cid,
		sid	=> $sid,
		subject => $subj,
		reason	=> $c->{reasons}[$reason],
		points	=> $u->{points},
	};
	
	unless ($u->{seclev} > 99 && $superAuthor) {
		my $mid = $db->getModeratorLogID($cid, $sid, $u->{uid});
		if ($mid) {
			$dispArgs->{type} = 'already moderated';
			slashDisplay('comments-moderation', $dispArgs);
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
	} elsif ($reason > $c->{badreasons}) {
		$val = "+1";
	}
	# Add moderation value to display arguments.
	$dispArgs->{'val'} = $val;

	my $scorecheck = $points + $val;
	# If the resulting score is out of comment score range, no further
	# actions need be performed.
	if ($scorecheck < $c->{comment_minscore} || 
	    $scorecheck > $c->{comment_maxscore})
	{
		# We should still log the attempt for M2, but marked as
		# 'inactive' so we don't mistakenly undo it.
		$db->setModeratorLog($cid, $sid, $u->{uid}, $val, $modreason);
		$dispArgs->{type} = 'score limit';
		slashDisplay('comments-moderation', $dispArgs);
		return;
	}

	if ($db->setCommentCleanup($val, $sid, $reason, $modreason, $cid)) {
		# Update points for display due to possible change in above line.
		$dispArgs->{points} = $u->{points};
		$dispArgs->{type} = 'moderated';
		slashDisplay('comments-moderation', $dispArgs);
	}
}


##################################################################
# Given an SID & A CID this will delete a comment, and all its replies
sub deleteThread {
	my($sid, $cid, $u, $db, $level, $deleted) = @_;
	$level ||= 0;

	my $delCount = 1;
	my @delList if !$level;
	$deleted = \@delList if !$level;

	return unless $u->{seclev} > 100;

	my $delkids = $db->getCommentCid($sid, $cid);

	# Delete children of $cid.
	push @{$deleted}, $cid;
	for (@{$delkids}) {
		my ($cid) = @{$_};
		push @{$deleted}, $cid;
		$delCount += deleteThread($sid, $cid, $u, $db, $level + 1, $deleted);
	}
	# And now delete $cid.
	$db->deleteComment($sid, $cid);

	if (!$level) {
		slashDisplay('comments-deleted_cids', {
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
	my($sid, $u, $db, $c) = @_;
	return if !$u->{is_anon} || ($u->{seclev} > 99 && $c->{authors_unlimited});

	my $removed = $db->unsetModeratorlog($u->{uid}, $sid,
		$c->{comment_maxscore}, $c->{comment_minscore});

	slashDisplay('comments-undo_moderation', {
		removed => $removed,
	});
}


##################################################################
# Troll Detection: essentially checks to see if this IP or UID has been
# abusing the system in the last 24 hours.
# 1=Troll 0=Good Little Goober
# This maybe should go into DB package -Brian
sub isTroll {
	my ($user, $constants, $db) = @_;
	return if $user->{seclev} > 99;

	my($badIP, $badUID) = (0, 0);
	return 0 if !$user->{is_anon} && $user->{karma} > -1;

	# Anonymous only checks HOST
	my $downMods = $constants->{down_moderations};
	$badIP = $db->getTrollAddress();
	return 1 if $badIP < $downMods;

	unless ($user->{is_anon}) {
		$badUID = $db->getTrollUID();
	}

	return 1 if $badUID < $downMods;
	return 0;
}

createEnvironment();
main();
1;
