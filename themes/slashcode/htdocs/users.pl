#!/usr/bin/perl -w
# This code is a part of Slash, and is released under the GPL.
# Copyright 1997-2001 by Open Source Development Network. See README
# and COPYING for more information, or see http://slashcode.com/.
# $Id$

use strict;
use Date::Manip qw(UnixDate DateCalc);
use Digest::MD5 'md5_hex';
use Slash;
use Slash::Display;
use Slash::Utility;

#################################################################
sub main {
	my $slashdb = getCurrentDB();
	my $constants = getCurrentStatic();
	my $user = getCurrentUser();
	my $form = getCurrentForm();
	my $formname = $0;
	$formname =~ s/.*\/(\w+)\.pl/$1/;
	my $formkeyid = getFormkeyId($user->{uid});

	my $error_flag = 0;
	my $formkey = $form->{formkey};

	my $suadmin_flag = $user->{seclev} >= 10000 ? 1 : 0 ;
	my $postflag = $user->{state}{post};
	my $op = lc($form->{op});

	# savepasswd is a special case, because once it's called, you
	# have to reload the form, and you don't want to do any checks if
	# you've just saved.
	my $savepass_flag = $op eq 'savepasswd' ? 1 : 0 ;

	# my $note = [ split /\n+/, $form->{note} ] if defined $form->{note};

	my $note;

	my $ops = {
		admin		=>  {
			function 	=> \&adminDispatch,
			seclev		=> 100,
			formname	=> $formname,
			checks		=> [],
		},
		userlogin	=>  {
			function	=> \&showInfo,
			seclev		=> 1,
			formname	=> $formname,
			checks		=> [],
		},
		userinfo	=>  {
			function	=> \&showInfo,
			#I made this change, not all sites are going to care. -Brian
			seclev		=> $constants->{users_show_info_seclev},
			formname	=> $formname,
			checks		=> [],
		},
		display	=>  {
			function	=> \&showInfo,
			#I made this change, not all sites are going to care. -Brian
			seclev		=> $constants->{users_show_info_seclev},
			formname	=> $formname,
			checks		=> [],
		},
		savepasswd	=> {
			function	=> \&savePasswd,
			seclev		=> 1,
			post		=> 1,
			formname	=> $formname,
			checks		=>
			[ qw (max_post_check valid_check
				formkey_check regen_formkey) ],
		},
		saveuseradmin	=> {
			function	=> \&saveUserAdmin,
			seclev		=> 10000,
			post		=> 1,
			formname	=> $formname,
			checks		=> [],
		},
		savehome	=> {
			function	=> \&saveHome,
			seclev		=> 1,
			post		=> 1,
			formname	=> $formname,
			checks		=>
			[ qw (valid_check
				formkey_check regen_formkey) ],
		},
		savecomm	=> {
			function	=> \&saveComm,
			seclev		=> 1,
			post		=> 1,
			formname	=> $formname,
			checks		=>
			[ qw (valid_check
				formkey_check regen_formkey) ],
		},
		saveuser	=> {
			function	=> \&saveUser,
			seclev		=> 1,
			post		=> 1,
			formname	=> $formname,
			checks		=>
			[ qw (valid_check
				formkey_check regen_formkey) ],
		},
		changepasswd	=> {
			function	=> \&changePasswd,
			seclev		=> 1,
			formname	=> $formname,
			checks		=> $savepass_flag ? [] :
			[ qw (generate_formkey) ],
		},
		edituser	=> {
			function	=> \&editUser,
			seclev		=> 1,
			formname	=> $formname,
			checks		=>
			[ qw (generate_formkey) ],
		},
		authoredit	=> {
			function	=> \&editUser,
			seclev		=> 10000,
			formname	=> $formname,
			checks		=> [],
		},
		edithome	=> {
			function	=> \&editHome,
			seclev		=> 1,
			formname	=> $formname,
			checks		=>
			[ qw (generate_formkey) ],
		},
		editcomm	=> {
			function	=> \&editComm,
			seclev		=> 1,
			formname	=> $formname,
			checks		=>
			[ qw (generate_formkey) ],
		},
		newuser		=> {
			function	=> \&newUser,
			seclev		=> 0,
			formname	=> $formname,
			checks		=>
			[ qw (max_post_check valid_check
				interval_check formkey_check regen_formkey) ],
		},
		newuseradmin	=> {
			function	=> \&newUserForm,
			seclev		=> 10000,
			formname	=> $formname,
			checks		=> [],
		},
		previewbox	=> {
			function	=> \&previewSlashbox,
			seclev		=> 0,
			formname	=> $formname,
			checks		=> [],
		},
		mailpasswd	=> {
			function	=> \&mailPasswd,
			seclev		=> 0,
			formname	=> $formname,
			checks		=> ['generate_formkey'],
		},
		validateuser	=> {
			function	=> \&validateUser,
			seclev		=> 1,
			formname	=> $formname,
			checks		=> ['regen_formkey'],
		},
		userclose	=>  {
			function	=> \&displayForm,
			seclev		=> 0,
			formname	=> $formname,
			checks		=> [],
		},
		newuserform	=> {
			function	=> \&displayForm,
			seclev		=> 0,
			formname	=> $formname,
			checks		=>
			[ qw (max_post_check generate_formkey) ],
		},
		mailpasswdform 	=> {
			function	=> \&displayForm,
			seclev		=> 0,
			formname	=> $formname,
			checks		=>
			[ qw (max_post_check generate_formkey) ],
		},
		displayform	=> {
			function	=> \&displayForm,
			seclev		=> 0,
			formname	=> $formname,
			checks		=>
			[ qw (generate_formkey) ],
		},
		listreadonly => {
			function	=> \&listReadOnly,
			seclev		=> 100,
			formname	=> $formname,
			checks		=> [],
		},
		topabusers 	=> {
			function	=> \&topAbusers,
			seclev		=> 100,
			formname	=> $formname,
			checks		=> [],
		},
		listabuses 	=> {
			function	=> \&listAbuses,
			seclev		=> 100,
			formname	=> $formname,
			checks		=> [],
		},
	} ;
	$ops->{default} = $ops->{displayform};

	if ($form->{op} && ! defined $ops->{$op}) {
		$note .= getError('bad_op', { op => $form->{op}}, 0, 1);
		$op = isAnon($user->{uid}) ? 'userlogin' : 'userinfo'; 
	}

	if ($op eq 'userlogin' && ! isAnon($user->{uid})) {
		my $refer = $form->{returnto} || $constants->{rootdir};
		redirect($refer);
		return;

	} elsif ($op eq 'savepasswd') {
		my $error_flag = 0;
		if ($user->{seclev} < 100) {
			for my $check (@{$ops->{savepasswd}{checks}}) {
				# the only way to save the error message is to pass by ref
				# $note and add the message to note (you can't print it out
				#  before header is called)
				$error_flag = formkeyHandler($check, $formname, $formkeyid, $formkey, \$note);
				last if $error_flag;
			}
		}

		if (! $error_flag) {
			$error_flag = savePasswd(\$note) ;
		}
		# change op to edituser and let fall through;
		# we need to have savePasswd set the cookie before
		# header() is called -- pudge
		if ($user->{seclev} < 100 && ! $error_flag) {
			# why assign to an unused variable? -- pudge
			$slashdb->updateFormkey($formkey, length($ENV{QUERY_STRING}));
		}
		$op = $error_flag ? 'changepasswd' : 'userinfo';
		$form->{userfield} = $form->{uid};
	}

	header(getMessage('user_header'));
	print getMessage('note', { note => $note }) if defined $note;
	print createMenu($formname) if ! $user->{is_anon};


	$op = 'userinfo' if (! $form->{op} && ($form->{uid} || $form->{nick}));
	$op ||= isAnon($user->{uid}) ? 'userlogin' : 'userinfo';

	if ($user->{is_anon} && $ops->{$op}{seclev} > 0) {
		$op = 'default';
	} elsif ($user->{seclev} < $ops->{$op}{seclev}) {
		$op = 'userinfo';
	}

	if ($ops->{$op}{post} && !$postflag) {
		$op = isAnon($user->{uid}) ? 'default' : 'userinfo';
	}

	if ($user->{seclev} < 100) {
		for my $check (@{$ops->{$op}{checks}}) {
			last if $op eq 'savepasswd';
			$error_flag = formkeyHandler($check, $formname, $formkeyid, $formkey);
			$ops->{$op}{update_formkey} = 1 if $check eq 'formkey_check';
			last if $error_flag;
		}
	}

	errorLog("users.pl error_flag '$error_flag'") if $error_flag;

	# call the method
	$ops->{$op}{function}->() if ! $error_flag;

	if ($ops->{$op}{update_formkey} && $user->{seclev} < 100 && ! $error_flag) {
		# successful save action, no formkey errors, update existing formkey
		# why assign to an unused variable? -- pudge
		my $updated = $slashdb->updateFormkey($formkey, length($ENV{QUERY_STRING}));
	}
	# if there were legit error levels returned from the save methods
	# I would have it clear the formkey in case of an error, but that
	# needs to be sorted out later
	# else { resetFormkey($formkey); }

	writeLog($user->{nickname});
	footer();
}

#################################################################
sub checkList {
	my $string = shift;
	$string = substr($string, 0, -1);

	$string =~ s/[^\w,-]//g;
	my @e = split m/,/, $string;
	$string = sprintf "'%s'", join "','", @e;

	if (length($string) > 254) {
		print getError('checklist_err');
		$string = substr($string, 0, 255);
		$string =~ s/,'??\w*?$//g;
	} elsif (length $string < 3) {
		$string = '';
	}

	return $string;
}

#################################################################
sub previewSlashbox {
	my $slashdb = getCurrentDB();
	my $constants = getCurrentStatic();
	my $user = getCurrentUser();
	my $form = getCurrentForm();

	my $block = $slashdb->getBlock($form->{bid}, ['title', 'block', 'url']);
	my $is_editable = $user->{seclev} >= 1000;

	my $title = getTitle('previewslashbox_title', { blocktitle => $block->{title} });
	slashDisplay('previewSlashbox', {
		width		=> '100%',
		title		=> $title,
		block 		=> $block,
		is_editable	=> $is_editable,
	});

	print portalbox($constants->{fancyboxwidth}, $block->{title},
		$block->{block}, '', $block->{url});
}

#################################################################
sub newUserForm {
	my $user = getCurrentUser();
	my $suadmin_flag = $user->{seclev} >= 10000;
	my $title = getTitle('newUserForm_title');
	slashDisplay('newUserForm', { title => $title, suadmin_flag => $suadmin_flag})
}

#################################################################
sub newUser {
	my $slashdb = getCurrentDB();
	my $form = getCurrentForm();
	my $title;

	# Check if User Exists
	$form->{newusernick} = fixNickname($form->{newusernick});
	(my $matchname = lc $form->{newusernick}) =~ s/[^a-zA-Z0-9]//g;

	if ($matchname ne '' && $form->{newusernick} ne '' && $form->{email} =~ /\@/) {
		my $uid;
		my $rootdir = getCurrentStatic('rootdir', 'value');

		if ($uid = $slashdb->createUser($matchname, $form->{email}, $form->{newusernick})) {

			$title = getTitle('newUser_title');

			$form->{pubkey} = strip_html($form->{pubkey}, 1);
			print getMessage('newuser_msg', { title => $title, uid => $uid });
			mailPasswd($uid);

			return;
		} else {
			print getError('duplicate_user', { nick => $form->{usernick}});
			return;
		}
	} else {
		print getError('duplicate_user', { nick => $form->{usernick}});
			return;
	}
}

#################################################################
sub mailPasswd {
	my($uid) = @_;

	my $slashdb = getCurrentDB();
	my $form = getCurrentForm();

	if (! $uid) {
		if ($form->{unickname} =~ /\@/) {
			$uid = $slashdb->getUserEmail($form->{unickname});

		} elsif ($form->{unickname} =~ /^\d+$/) {
			$uid = $form->{unickname};

		} else {
			$uid = $slashdb->getUserUID($form->{unickname});
		}
	}

	unless ($uid) {
		print getError('mailpasswd_notmailed_err');
		return;
	}
	my $user_edit = $slashdb->getUser($uid, ['nickname', 'realemail']);
	my $newpasswd = $slashdb->getNewPasswd($uid);
	my $tempnick = fixparam($user_edit->{nickname});

	my $emailtitle = getTitle('mailPassword_email_title', {
		nickname	=> $user_edit->{nickname}
	}, 1);

	my $msg = getMessage('mailpasswd_msg', {
		newpasswd	=> $newpasswd,
		tempnick	=> $tempnick
	}, 1);

	doEmail($uid, $emailtitle, $msg) if $user_edit->{nickname};
	print getMessage('mailpasswd_mailed_msg', { name => $user_edit->{nickname} });
}

#################################################################
# arhgghgh. I love torture. I love pain. This subroutine satisfies
# these needs of mine
sub showInfo {
	my($id) = @_;

	my $slashdb = getCurrentDB();
	my $form = getCurrentForm();
	my $constants = getCurrentStatic();
	my $user = getCurrentUser();

	my $admin_flag = ($user->{is_admin}) ? 1 : 0;
	my($title, $admin_block, $fieldkey) = ('', '', '');
	my $comments;
	my $commentcount = 0;
	my $commentstruct = [];
	my $requested_user = {};

	my($points, $lastgranted, $nickmatch_flag, $uid, $nick);
	my($mod_flag, $karma_flag, $n) = (0, 0, 0);

	if (! $id && ! $form->{userfield}) {
		if ($form->{uid} && ! $id) {
			$fieldkey = 'uid';
			($uid, $id) = ($form->{uid}, $form->{uid});
			$requested_user = $slashdb->getUser($id);
			$nick = $requested_user->{nickname};

		} elsif ($form->{nick} && ! $id) {
			$fieldkey = 'nickname';
			($nick, $id) = ($form->{nick}, $form->{nick});
			$uid = $slashdb->getUserUID($id);
			$requested_user = $slashdb->getUser($uid);

		} else {
			$fieldkey = 'uid';
			($id, $uid) = ($user->{uid}, $user->{uid});
			$requested_user = $slashdb->getUser($uid);
		}
	} elsif ($user->{is_admin}) {
		$id ||= $form->{userfield} ? $form->{userfield} : $user->{uid};
		if ($id =~ /^\d+$/) {
			$fieldkey = 'uid';
			$requested_user = $slashdb->getUser($id);
			$uid = $requested_user->{uid};
			$nick = $requested_user->{nickname};
			if ((my $conflict_id = $slashdb->getUserUID($id)) && ($form->{userfield} ne $form->{uid})) {
				slashDisplay('showInfoConflict', { op => 'userinfo', id => $uid, nick => $nick, conflict_id => $conflict_id});
				return(1);
			}

		} elsif (length($id) == 32) {
			$fieldkey = 'ipid';
			$requested_user->{nonuid} = 1;
			$requested_user->{ipid} = $id;

		} elsif ($id =~ /^(\d+\.\d+.\d+\.0)$/) {
			$fieldkey = 'subnetid';
			$requested_user->{nonuid} = $1;
			$requested_user->{subnetid} = md5_hex($1);

		} elsif ($id =~ /^([\d+\.]+)$/) {
			$fieldkey = 'ipid';
			$requested_user->{nonuid} = 1;
			$id ||= $1;
			$requested_user->{ipid} = md5_hex($1);
		}
	} else {
		$fieldkey = 'uid';
		($id, $uid) = ($user->{uid}, $user->{uid});
		$requested_user = $slashdb->getUser($uid);
	}

	if ($requested_user->{nonuid}) {
		$requested_user->{fg} = $user->{fg};
		$requested_user->{bg} = $user->{bg};

		my $netid = $requested_user->{ipid} ? $requested_user->{ipid} : $requested_user->{subnetid} ;

		$title = getTitle('user_netID_user_title', {
			id => $id,
			md5id => $netid,
		});

		$admin_block = getUserAdmin($netid, $fieldkey, 1, 0) if $admin_flag;

		$commentcount = $requested_user->{ipid} ?
			$slashdb->countCommentsByIPID($netid) :
			$slashdb->countCommentsBySubnetID($netid);

		if ($commentcount) {
			$comments = $requested_user->{ipid} ?
				$slashdb->getCommentsByNetID(
					$netid, $constants->{user_comment_display_default}
				) :
				$slashdb->getCommentsBySubnetID(
					$netid, $constants->{user_comment_display_default}
				);
		}

	} else {
		$admin_block = $admin_flag ? getUserAdmin($id, $fieldkey, 1, 1) : '';

		$commentcount =
			$slashdb->countCommentsByUID($requested_user->{uid});
		$comments = $slashdb->getCommentsByUID(
			$requested_user->{uid},
			$constants->{user_comment_display_default}
		) if $commentcount;
	}

	for (@$comments) {
		my($pid, $sid, $cid, $subj, $cdate, $pts) = @$_;

		my $type;
		# This works since $sid is numeric.
		my $replies = $slashdb->countCommentsBySidPid($sid, $cid);

		# This is ok, since with all luck we will not be hitting the DB
		# ...however, the "sid" parameter here must be the string
		# based SID from either the "stories" table or from
		# pollquestions.
		my($discussion) = $slashdb->getDiscussion($sid);

		if ($discussion->{url} =~ /journal/i) {
			$type = 'journal';
		} elsif ($discussion->{url} =~ /poll/i) {
			$type = 'poll';
		} else {
			$type = 'story';
		}

		push @$commentstruct, {
			pid 		=> $pid,
			url		=> $discussion->{url},
			type 		=> $type,
			disc_title	=> $discussion->{title},
			sid 		=> $sid,
			cid 		=> $cid,
			subj		=> $subj,
			cdate		=> $cdate,
			pts		=> $pts,
			replies		=> $replies,
		};
	}
	my $storycount =
		$slashdb->countStoriesBySubmitter($requested_user->{uid})
	unless $requested_user->{nonuid};
	my $stories = $slashdb->getStoriesBySubmitter(
		$requested_user->{uid},
		$constants->{user_submitter_display_default}
	) unless !$storycount || $requested_user->{nonuid};

	if ($requested_user->{nonuid}) {
		slashDisplay('netIDInfo', {
			title			=> $title,
			id			=> $id,
			user			=> $requested_user,
			commentstruct		=> $commentstruct || [],
			admin_flag		=> $admin_flag,
			admin_block		=> $admin_block,
		});

	} else {
		if (! defined $uid && defined $nick && ! $requested_user->{nonuid}) {
			print getError('userinfo_nicknf_err', { nick => $nick });
			return;
		}

		$karma_flag = 1 if $admin_flag;
		$nick = strip_literal($nick || $requested_user->{nickname});

		if ($requested_user->{uid} == $user->{uid}) {
			$karma_flag = 1;
			$nickmatch_flag = 1;
			$points = $requested_user->{points};

			$mod_flag = 1 if $points > 0;

			if ($points) {
				$mod_flag = 1;
				$lastgranted = $slashdb->getUser($uid, 'lastgranted');
				if ($lastgranted) {
					$lastgranted = timeCalc(
						UnixDate(DateCalc($lastgranted,
							'+ ' . ($constants->{stir}+1) . ' days'
						), "%C"), '%Y-%m-%d'
					);
				}
			}

			$title = getTitle('userInfo_main_title', { nick => $nick, uid => $uid });

		} else {
			$title = getTitle('userInfo_user_title', { nick => $nick, uid => $uid });
		}

		slashDisplay('userInfo', {
			title			=> $title,
			nick			=> $nick,
			useredit		=> $requested_user,
			points			=> $points,
			lastgranted		=> $lastgranted,
			commentstruct		=> $commentstruct || [],
			commentcount		=> $commentcount,
			nickmatch_flag		=> $nickmatch_flag,
			mod_flag		=> $mod_flag,
			karma_flag		=> $karma_flag,
			admin_block		=> $admin_block,
			admin_flag 		=> $admin_flag,
			stories 		=> $stories,
			storycount 		=> $storycount,
		});
	}
}

#####################################################################
sub validateUser {
	my $user = getCurrentUser();
	my $form = getCurrentForm();
	my $slashdb = getCurrentDB();
	my $constants = getCurrentStatic();

	# If we aren't expiring accounts in some way, we don't belong here.
	if (! allowExpiry()) {
		displayForm();
		return;
	}

	# Since we are here, if the minimum values for the comment trigger and
	# the day trigger are -1, then they should be reset to 1.
	$constants->{min_expiry_comm} = $constants->{min_expiry_days} = 1
		if $constants->{min_expiry_comm} <= 0 ||
		   $constants->{min_expiry_days} <= 0;

	if ($user->{is_anon} || $user->{registered}) {
		if ($user->{is_anon}) {
			print getError('anon_validation_attempt');
			displayForm();
			return;
		} else {
			print getMessage('no_registration_needed')
				if !$user->{reg_id};
			showInfo($user->{uid});
			return;
		}
	# Maybe this should be taken care of in a more centralized location?
	} elsif ($user->{reg_id} eq $form->{id}) {
		# We have a user and the registration IDs match. We are happy!
		my($maxComm, $maxDays) = ($constants->{max_expiry_comm},
					  $constants->{max_expiry_days});
		my($userComm, $userDays) =
			($user->{user_expiry_comm}, $user->{user_expiry_days});

		# Ensure both $userComm and $userDays aren't -1 (expiry has
		# just been turned on).
		$userComm = $constants->{min_expiry_comm}
			if $userComm < $constants->{min_expiry_comm};
		$userDays = $constants->{min_expiry_days}
			if $userDays < $constants->{min_expiry_days};

		my $exp = $constants->{expiry_exponent};

		# Increment only the trigger that was used.
		my $new_comment_expiry = ($maxComm > 0 && $userComm > $maxComm)
			? $maxComm
			: $userComm * (($user->{expiry_comm} < 0)
				? $exp
				: 1
		);
		my $new_days_expiry = ($maxDays > 0 && $userDays > $maxDays)
			? $maxDays
			: $userDays * (($user->{expiry_days} < 0)
				? $exp
				: 1
		);

		# Reset re-registration triggers for user.
		$slashdb->setUser($user->{uid}, {
			'expiry_comm'		=> $new_comment_expiry,
			'expiry_days'		=> $new_days_expiry,
			'user_expiry_comm'	=> $new_comment_expiry,
			'user_expiry_days'	=> $new_days_expiry,
		});

		# Handles rest of re-registration process.
		setUserExpired($user->{uid}, 0);
	}

	slashDisplay('regResult');
}

#################################################################
sub editKey {
	my($uid) = @_;

	my $slashdb = getCurrentDB();

	my $pubkey = $slashdb->getUser($uid, 'pubkey');
	my $editkey = slashDisplay('editKey', { pubkey => $pubkey }, 1);
	return $editkey;
}

#################################################################
sub adminDispatch {
	my $form = getCurrentForm();

	if ($form->{op} eq 'authoredit') {
		editUser($form->{authoruid});

	} elsif ($form->{saveuseradmin}) {
		saveUserAdmin();

	} elsif ($form->{userinfo}) {
		showInfo();

	} elsif ($form->{uid}) {
		if ($form->{edituser}) {
			editUser();

		} elsif ($form->{edithome}) {
			editHome();

		} elsif ($form->{editcomm}) {
			editComm();

		} elsif ($form->{changepasswd}) {
			changePasswd();
		}

	} else {
		showInfo();
	}
}

#################################################################
sub tildeEd {
	my($extid, $exsect, $exaid, $exboxes, $userspace) = @_;

	my $slashdb = getCurrentDB();
	my $constants = getCurrentStatic();
	my($aidref, $tidref, $sectionref, $section_descref, $tilde_ed, $tilded_msg_box);

	# users_tilded_title
	my $title = getTitle('tildeEd_title');

	# Customizable Authors Thingee
	my $aids = $slashdb->getAuthorNames();
	my $n = 0;
	for my $aid (@$aids) {
		$aidref->{$aid}{checked} = ($exaid =~ /'\Q$aid\E'/) ? ' CHECKED' : '';
	}

	my $topics = $slashdb->getDescriptions('topics');
	while (my($tid, $alttext) = each %$topics) {
		$tidref->{$tid}{checked} = ($extid =~ /'\Q$tid\E'/) ?
			' CHECKED' : '';
		$tidref->{$tid}{alttext} = $alttext;
	}

	my $sections = $slashdb->getDescriptions('sections');
	while (my($section, $title) = each %$sections) {
		$sectionref->{$section}{checked} =
			($exsect =~ /'\Q$section\E'/) ? ' CHECKED' : '';
		$sectionref->{$section}{title} = $title;
	}

	my $customize_title = getTitle('tildeEd_customize_title');

	my $tilded_customize_msg = getMessage('users_tilded_customize_msg',
		{ userspace => $userspace });

	my $sections_description = $slashdb->getSectionBlocks();

	# repeated from above?
	$customize_title = getTitle('tildeEd_customize_title');

	for (sort { lc $b->[1] cmp lc $a->[1]} @$sections_description) {
		my($bid, $title, $boldflag) = @$_;

		$section_descref->{$bid}{checked} = ($exboxes =~ /'$bid'/) ?
			' CHECKED' : '';
		$section_descref->{$bid}{boldflag} = $boldflag > 0;
		$title =~ s/<(.*?)>//g;
		$section_descref->{$bid}{title} = $title;
	}

	my $tilded_box_msg = getMessage('tilded_box_msg');
	$tilde_ed = slashDisplay('tildeEd', {
		title			=> $title,
		tilded_box_msg		=> $tilded_box_msg,
		aidref			=> $aidref,
		tidref			=> $tidref,
		sectionref		=> $sectionref,
		section_descref		=> $section_descref,
		userspace		=> $userspace,
		customize_title		=> $customize_title,
	}, 1);

	return($tilde_ed);
}

#################################################################
sub changePasswd {
	my($id) = @_;

	my $form = getCurrentForm();
	my $slashdb = getCurrentDB();
	my $user = getCurrentUser();
	my $constants = getCurrentStatic();

	# return if (! $user->{is_admin} && $id != $user->{uid});

	my $user_edit = {};
	my $title ;
	my $suadmin_flag = ($user->{seclev} >= 10000) ? 1 : 0;

	if ($form->{userfield}) {
		$id ||= $form->{userfield};
		if ($id =~ /^\d+$/) {
			$user_edit = $slashdb->getUser($id);
		} else {
			$user_edit = $slashdb->getUser($slashdb->getUserUID($id));
		}
	} else {
		$user_edit = $id eq '' ? $user : $slashdb->getUser($id);
		$id = $user_edit->{uid};
	}

	# print getMessage('note', { note => $form->{note}}) if $form->{note};

	$title = getTitle('changePasswd_title', { user_edit => $user_edit });

	my $session = $slashdb->getDescriptions('session_login');
	my $session_select = createSelect('session_login', $session, $user_edit->{session_login}, 1);

	slashDisplay('changePasswd', {
		useredit 		=> $user_edit,
		admin_flag		=> $suadmin_flag,
		title			=> $title,
		session 		=> $session_select,
	});
}

#################################################################
sub editUser {
	my($id) = @_;

	my $form = getCurrentForm();
	my $slashdb = getCurrentDB();
	my $user = getCurrentUser();
	my $constants = getCurrentStatic();

	my($user_edit, $session) = ({}, {});
	my($admin_block, $title, $session_select);
	my $admin_flag = ($user->{is_admin}) ? 1 : 0;
	my $fieldkey;

	if ($form->{userfield}) {
		$id ||= $form->{userfield};
		if ($form->{userfield} =~ /^\d+$/) {
			$user_edit = $slashdb->getUser($id);
			$fieldkey = 'uid';
		} else {
			$user_edit = $slashdb->getUser($slashdb->getUserUID($id));
			$fieldkey = 'nickname';
		}
	} else {
		$user_edit = $id eq '' ? $user : $slashdb->getUser($id);
		$fieldkey = 'uid';
		$id = $user_edit->{uid};
	}
	return if isAnon($user_edit->{uid}) && ! $admin_flag;

	$admin_block = getUserAdmin($id, $fieldkey, 1, 1) if $admin_flag;
	$user_edit->{homepage} ||= "http://";

	$title = getTitle('editUser_title', { user_edit => $user_edit});

	$session = $slashdb->getDescriptions('session_login');
	$session_select = createSelect('session_login', $session, $user_edit->{session_login}, 1);

	slashDisplay('editUser', {
		useredit 		=> $user_edit,
		admin_flag		=> $admin_flag,
		title			=> $title,
		editkey 		=> editKey($user_edit->{uid}),
		session 		=> $session_select,
		admin_block		=> $admin_block
	});
}

#################################################################
sub editHome {
	my($id) = @_;

	my $slashdb = getCurrentDB();
	my $form = getCurrentForm();
	my $user = getCurrentUser();

	my($formats, $title, $tzformat_select, $tzcode_select);
	my $user_edit = {};
	my $fieldkey;

	my $admin_flag = ($user->{is_admin}) ? 1 : 0;
	my $admin_block = '';

	if ($form->{userfield}) {
		$id ||= $form->{userfield};
		if ($form->{userfield} =~ /^\d+$/) {
			$user_edit = $slashdb->getUser($id);
			$fieldkey = 'uid';
		} else {
			$user_edit = $slashdb->getUser($slashdb->getUserUID($id));
			$fieldkey = 'nickname';
		}
	} else {
		$user_edit = $id eq '' ? $user : $slashdb->getUser($id);
		$fieldkey = 'uid';
	}

	return if isAnon($user_edit->{uid}) && ! $admin_flag;
	$admin_block = getUserAdmin($id, $fieldkey, 1, 1) if $admin_flag;

	$title = getTitle('editHome_title');

	return if $user->{seclev} < 100 && $user_edit->{is_anon};

	$formats = $slashdb->getDescriptions('dateformats');
	$tzformat_select = createSelect('tzformat', $formats, $user_edit->{dfid}, 1);

	$formats = $slashdb->getDescriptions('tzcodes');
	$tzcode_select =
		createSelect('tzcode', [ keys %$formats ], $user_edit->{tzcode}, 1);

	my $l_check = $user_edit->{light}	? ' CHECKED' : '';
	my $b_check = $user_edit->{noboxes}	? ' CHECKED' : '';
	my $i_check = $user_edit->{noicons}	? ' CHECKED' : '';
	my $w_check = $user_edit->{willing}	? ' CHECKED' : '';

	my $tilde_ed = tildeEd(
		$user_edit->{extid}, $user_edit->{exsect},
		$user_edit->{exaid}, $user_edit->{exboxes}, $user_edit->{mylinks}
	);

	slashDisplay('editHome', {
		title			=> $title,
		admin_block		=> $admin_block,
		user_edit		=> $user_edit,
		tzformat_select		=> $tzformat_select,
		tzcode_select		=> $tzcode_select,
		l_check			=> $l_check,
		b_check			=> $b_check,
		i_check			=> $i_check,
		w_check			=> $w_check,
		tilde_ed		=> $tilde_ed
	});
}

#################################################################
sub editComm {
	my($id) = @_;

	my $slashdb = getCurrentDB();
	my $form = getCurrentForm();
	my $user = getCurrentUser();
	my $user_edit = {};
	my($formats, $commentmodes_select, $commentsort_select, $title,
		$uthreshold_select, $highlightthresh_select, $posttype_select);

	my $admin_block = '';
	my $fieldkey;

	my $admin_flag = $user->{is_admin} ? 1 : 0;

	if ($form->{userfield}) {
		$id ||= $form->{userfield};
		if ($form->{userfield} =~ /^\d+$/) {
			$user_edit = $slashdb->getUser($id);
			$fieldkey = 'uid';
		} else {
			$user_edit = $slashdb->getUser($slashdb->getUserUID($id));
			$fieldkey = 'nickname';
		}
	} else {
		$user_edit = $id eq '' ? $user : $slashdb->getUser($id);
		$fieldkey = 'uid';
	}

	return if isAnon($user_edit->{uid}) && ! $admin_flag;
	$admin_block = getUserAdmin($id, $fieldkey, 1, 1) if $admin_flag;

	$title = getTitle('editComm_title');

	$formats = $slashdb->getDescriptions('commentmodes');
	$commentmodes_select=createSelect('umode', $formats, $user_edit->{mode}, 1);

	$formats = $slashdb->getDescriptions('sortcodes');
	$commentsort_select = createSelect(
		'commentsort', $formats, $user_edit->{commentsort}, 1
	);

	$formats = $slashdb->getDescriptions('threshcodes');
	$uthreshold_select = createSelect(
		'uthreshold', $formats, $user_edit->{threshold}, 1
	);

	$formats = $slashdb->getDescriptions('threshcodes');
	$highlightthresh_select = createSelect(
		'highlightthresh', $formats, $user_edit->{highlightthresh}, 1
	);

	my $h_check = $user_edit->{hardthresh}	? ' CHECKED' : '';
	my $r_check = $user_edit->{reparent}		? ' CHECKED' : '';
	my $n_check = $user_edit->{noscores}		? ' CHECKED' : '';
	my $s_check = $user_edit->{nosigs}		? ' CHECKED' : '';

	$formats = $slashdb->getDescriptions('postmodes');
	$posttype_select = createSelect(
		'posttype', $formats, $user_edit->{posttype}, 1
	);

	slashDisplay('editComm', {
		title			=> $title,
		admin_block		=> $admin_block,
		user_edit		=> $user_edit,
		h_check			=> $h_check,
		r_check			=> $r_check,
		n_check			=> $n_check,
		s_check			=> $s_check,
		commentmodes_select	=> $commentmodes_select,
		commentsort_select	=> $commentsort_select,
		highlightthresh_select	=> $highlightthresh_select,
		uthreshold_select	=> $uthreshold_select,
		posttype_select		=> $posttype_select,
	});
}

#################################################################
sub saveUserAdmin {
	my $slashdb = getCurrentDB();
	my $form = getCurrentForm();
	my $user = getCurrentUser();
	my $constants = getCurrentStatic();

	my($user_edits_table, $user_edit) = ({}, {});
	my $save_success = 0;
	my $author_flag;
	my $note = '';
	my $id;
	my $user_editfield_flag;

	if ($form->{uid}) {
		$user_editfield_flag = 'uid';
		$id = $form->{uid};
		$user_edit = $slashdb->getUser($id);

	} elsif ($form->{subnetid}) {
		$user_editfield_flag = 'subnetid';
		$user_edit->{uid} = $constants->{anonymous_coward_uid};
		($id, $user_edit->{subnetid})  = ($form->{subnetid}, $form->{subnetid});
		$user_edit->{nonuid} = 1;

	} elsif ($form->{ipid}) {
		$user_editfield_flag = 'ipid';
		($id, $user_edit->{ipid})  = ($form->{ipid}, $form->{ipid});
		$user_edit->{subnetid} = $1 . "0" ;
		$user_edit->{subnetid} = md5_hex($user_edit->{subnetid});
		$user_edit->{uid} = $constants->{anonymous_coward_uid};
		$user_edit->{nonuid} = 1;

	} else { # a bit redundant, I know
		$user_edit = $user;
	}

	for my $formname ('comments', 'submit') {
		my $existing_reason = $slashdb->getReadOnlyReason($formname, $user_edit);
		my $is_readonly_now = $slashdb->checkReadOnly($formname, $user_edit) ? 1 : 0;

		my $keyname = "readonly_" . $formname;
		my $reason_keyname = $formname . "_ro_reason";
		$form->{$keyname} = $form->{$keyname} eq 'on' ? 1 : 0 ;
		$form->{$reason_keyname} ||= '';

		if ($form->{$keyname} != $is_readonly_now) {
			if ("$existing_reason" ne "$form->{$reason_keyname}") {
				$slashdb->setReadOnly($formname, $user_edit, $form->{$keyname}, $form->{$reason_keyname});
			} else {
				$slashdb->setReadOnly($formname, $user_edit, $form->{$keyname});
			}
		} elsif ("$existing_reason" ne "$form->{$reason_keyname}") {
			$slashdb->setReadOnly($formname, $user_edit, $form->{$keyname}, $form->{$reason_keyname});
		}

		# $note .= getError('saveuseradmin_notsaved', { field => $user_editfield_flag, id => $id });
	}

	$note .= getMessage('saveuseradmin_saved', { field => $user_editfield_flag, id => $id}) if $save_success;

	if ($user->{is_admin} && ($user_editfield_flag eq 'uid' ||
		$user_editfield_flag eq 'nickname')) {

		$user_edits_table->{seclev} = $form->{seclev};
		$user_edits_table->{rtbl} = $form->{rtbl} eq 'on' ? 1 : 0 ;
		$user_edits_table->{author} = $form->{author} ? 1 : 0 ;

		$slashdb->setUser($id, $user_edits_table);
		$note .= getMessage('saveuseradmin_saveduser', { field => $user_editfield_flag, id => $id });
	}

	if (!$user_edit->{nonuid}) {
		if ($form->{expired} eq 'on') {
			$slashdb->setExpired($user_edit->{uid});

		} else {
			$slashdb->setUnexpired($user_edit->{uid});
		}
	}

	print getMessage('note', { note => $note }) if defined $note;

	showInfo($id);
}

#################################################################
sub savePasswd {
	my($note) = @_;

	my $slashdb = getCurrentDB();
	my $form = getCurrentForm();
	my $user = getCurrentUser();
	my $constants = getCurrentStatic();

	my $error_flag = 0;
	my $user_edit = {};
	my $uid;

	my $user_edits_table = {};

	if ($user->{is_admin}) {
		$uid = $form->{uid} ? $form->{uid} : $user->{uid};
	} else {
		$uid = ($user->{uid} == $form->{uid}) ? $form->{uid} : $user->{uid};
	}

	$user_edit = $slashdb->getUser($uid);

	if (!$user_edit->{nickname}) {
		$$note .= getError('cookie_err', { titlebar => 0}, 0, 1);
		$error_flag++;
	}

	if ($form->{pass1} ne $form->{pass2}) {
		$$note .= getError('saveuser_passnomatch_err', { titlebar => 0},  0, 1);
		$error_flag++;
	}

	if (length $form->{pass1} < 6 && $form->{pass1}) {
		$$note .= getError('saveuser_passtooshort_err', { titlebar => 0} , 0, 1);
		$error_flag++;
	}

	if (! $error_flag) {
		$user_edits_table->{passwd} = $form->{pass1};
		$user_edits_table->{session_login} => $form->{session_login};
		if ($form->{uid} eq $user->{uid}) {
			setCookie('user', bakeUserCookie($uid, encryptPassword($user_edits_table->{passwd})));
		}

		$slashdb->setUser($uid, $user_edits_table) ;
		$$note .= getMessage('saveuser_passchanged_msg', { nick => $user_edit->{nickname}, uid => $user_edit->{uid}}, 0, 1);
		
	}

	return $error_flag;
}

#################################################################
sub saveUser {
	my $slashdb = getCurrentDB();
	my $form = getCurrentForm();
	my $user = getCurrentUser();
	my $constants = getCurrentStatic();
	my $uid;
	my $user_editfield_flag;

	if ($user->{is_admin}) {
		$uid = $form->{uid} ? $form->{uid} : $user->{uid} if !$uid;
	} else {
		$uid = ($user->{uid} == $form->{uid}) ?
			$form->{uid} : $user->{uid};
	}
	my $user_edit = $slashdb->getUser($uid);

	my($note, $author_flag, $formname);

	$note .= getMessage('savenickname_msg', {
		nickname => $user_edit->{nickname},
	}, 1);

	if (!$user_edit->{nickname}) {
		$note .= getError('cookie_err', 0, 1);
	}

	# Check to ensure that if a user is changing his email address, that
	# it doesn't already exist in the userbase.
	if ($user_edit->{realemail} ne $form->{realemail}) {
		if ($slashdb->checkEmail($form->{realemail})) {
			$note = getError('emailexists_err', 0, 1);
			return $note;
		}
	}

	for $formname ('comments', 'submit') {
		my $keyname = "readonly_" . $formname;
		my $reason_keyname = $formname . "_ro_reason";
		$form->{$keyname} = $form->{$keyname} eq 'on' ? 1 : 0 ;

		$form->{$reason_keyname} ||= '';

		$slashdb->setReadOnly(
			$formname, $user_edit,
			$form->{$keyname},
			$form->{$reason_keyname}
		);
	}

	# strip_mode _after_ fitting sig into schema, 120 chars
	$form->{sig}	 	= strip_html(substr($form->{sig}, 0, 120));
	$form->{homepage}	= '' if $form->{homepage} eq 'http://';
	$form->{homepage}	= fixurl($form->{homepage});
	$author_flag		= $form->{author} ? 1 : 0;

	# for the users table
	my $user_edits_table = {
		sig		=> $form->{sig},
		homepage	=> $form->{homepage},
		realname	=> $form->{realname},
		bio		=> $form->{bio},
		pubkey		=> $form->{pubkey},
		copy		=> $form->{copy},
		quote		=> $form->{quote},
		session_login	=> $form->{session_login},
	};

	# don't want undef, want to be empty string so they
	# will overwrite the existing record
	for (keys %$user_edits_table) {
		$user_edits_table->{$_} = '' unless defined $user_edits_table->{$_};
	}

	if ($user->{is_admin}) {
		$user_edits_table->{seclev} = $form->{seclev};
		$user_edits_table->{author} = $author_flag;
	}

	if ($user_edit->{realemail} ne $form->{realemail}) {
		$user_edits_table->{realemail} =
			chopEntity(strip_attribute($form->{realemail}), 50);

		$note .= getMessage('changeemail_msg', {
			realemail => $user_edit->{realemail}
		}, 1);

		my $saveuser_emailtitle = getTitle('saveUser_email_title', {
			nickname  => $user_edit->{nickname},
			realemail => $form->{realemail}
		}, 1);
		my $saveuser_email_msg = getMessage('saveuser_email_msg', {
			nickname  => $user_edit->{nickname},
			realemail => $form->{realemail}
		}, 1);

		doEmail($uid, $saveuser_emailtitle, $saveuser_email_msg);
	}

	$slashdb->setUser($uid, $user_edits_table);

	print getMessage('note', { note => $note}) if $note;

	editUser($uid);
}


#################################################################
sub saveComm {
	my $slashdb = getCurrentDB();
	my $user = getCurrentUser();
	my $form = getCurrentForm();
	my($uid, $user_fakeemail);

	if ($user->{is_admin}) {
		$uid = $form->{uid} ? $form->{uid} : $user->{uid};
	} else {
		$uid = ($user->{uid} == $form->{uid}) ?
			$form->{uid} : $user->{uid};
	}

	# Do the right thing with respect to the chosen email display mode
	# and the options that can be displayed.
	my $user_edit = $slashdb->getUser($uid);
	my $new_fakeemail = '';		# at emaildisplay 0, don't show any email address
	if ($form->{emaildisplay}) {
		$new_fakeemail = getArmoredEmail($uid)	if $form->{emaildisplay} == 1;
		$new_fakeemail = $user_edit->{realemail}	if $form->{emaildisplay} == 2;
	}

	my $name = $user->{seclev} && $form->{name} ?
		$form->{name} : $user->{nickname};

	my $savename = getMessage('savename_msg', { name => $name });
	print $savename;

	print getError('cookie_err') if isAnon($uid) || !$name;

	# Take care of the lists
	# Enforce Ranges for variables that need it
	$form->{commentlimit} = 0 if $form->{commentlimit} < 1;
	$form->{commentspill} = 0 if $form->{commentspill} < 1;

	# This has NO BEARING on the table the data goes into now.
	# setUser() does the right thing based on the key name.
	my $users_comments_table = {
		clbig		=> $form->{clbig},
		clsmall		=> $form->{clsmall},
		commentlimit	=> $form->{commentlimit},
		commentsort	=> $form->{commentsort},
		commentspill	=> $form->{commentspill},
		domaintags	=> $form->{domaintags},
		emaildisplay	=> $form->{emaildisplay},
		fakeemail	=> $new_fakeemail,
		highlightthresh	=> $form->{highlightthresh},
		maxcommentsize	=> $form->{maxcommentsize},
		mode		=> $form->{umode},
		posttype	=> $form->{posttype},
		threshold	=> $form->{uthreshold},
		nosigs		=> ($form->{nosigs}     ? 1 : 0),
		reparent	=> ($form->{reparent}   ? 1 : 0),
		noscores	=> ($form->{noscores}   ? 1 : 0),
		hardthresh	=> ($form->{hardthresh} ? 1 : 0),
	};

	# Update users with the $users_comments_table hash ref
	$slashdb->setUser($uid, $users_comments_table);

	editComm($uid);
}

#################################################################
sub saveHome {
	my $slashdb = getCurrentDB();
	my $user = getCurrentUser();
	my $form = getCurrentForm();
	my $uid;
	my($extid, $exaid, $exsect) = '';

	if ($user->{is_admin}) {
		$uid = $form->{uid} ? $form->{uid} : $user->{uid} ;
	} else {
		$uid = ($user->{uid} == $form->{uid}) ?
			$form->{uid} : $user->{uid};
	}
	my $edit_user = $slashdb->getUser($uid);

	my $name = $user->{seclev} && $form->{name} ?
		$form->{name} : $user->{nickname};

	$name = substr($name, 0, 20);

	# users_cookiemsg
	if (isAnon($uid) || !$name) {
		my $cookiemsg = getError('cookie_err');
		print $cookiemsg;
	}

	my $exboxes = $edit_user->{exboxes};

	$exboxes =~ s/'//g;
	my @b = split m/,/, $exboxes;

	foreach (@b) {
		$_ = '' unless $form->{"exboxes_$_"};
	}

	$exboxes = sprintf "'%s',", join "','", @b;
	$exboxes =~ s/'',//g;

	for my $k (keys %{$form}) {
		if ($k =~ /^extid_(.*)/)	{ $extid  .= "'$1'," }
		if ($k =~ /^exaid_(.*)/)	{ $exaid  .= "'$1'," }
		if ($k =~ /^exsect_(.*)/)	{ $exsect .= "'$1'," }
		if ($k =~ /^exboxes_(.*)/) {
			# Only Append a box if it doesn't exist
			my $box = $1;
			$exboxes .= "'$box'," unless $exboxes =~ /'$box'/;
		}
	}

	$form->{maxstories} = 66 if $form->{maxstories} > 66;
	$form->{maxstories} = 1 if $form->{maxstories} < 1;

	my $users_index_table = {
		extid		=> checkList($extid),
		exaid		=> checkList($exaid),
		exsect		=> checkList($exsect),
		exboxes		=> checkList($exboxes),
		maxstories	=> $form->{maxstories},
		noboxes		=> ($form->{noboxes} ? 1 : 0),
		light		=> ($form->{light} ? 1 : 0),
		noicons		=> ($form->{noicons} ? 1 : 0),
		willing		=> ($form->{willing} ? 1 : 0),
	};

	if (defined $form->{tzcode} && defined $form->{tzformat}) {
		$users_index_table->{tzcode} = $form->{tzcode};
		$users_index_table->{dfid}   = $form->{tzformat};
	}

	$users_index_table->{mylinks} = $form->{mylinks} || '';

	# If a user is unwilling to moderate, we should cancel all points, lest
	# they be preserved when they shouldn't be.
	my $users_comments = { points => 0 };
	unless (isAnon($uid)) {
		$slashdb->setUser($uid, $users_comments)
			unless $form->{willing};
	}

	# Update users with the $users_index_table thing we've been playing with
	# for this whole damn sub
	$slashdb->setUser($uid, $users_index_table);

	editHome($uid);
}

#################################################################
sub listReadOnly {
	my $slashdb = getCurrentDB();

	my $readonlylist = $slashdb->getReadOnlyList();

	slashDisplay('listReadOnly', {
		readonlylist => $readonlylist,
	});

}

#################################################################
sub topAbusers {
	my $slashdb = getCurrentDB();

	my $topabusers = $slashdb->getTopAbusers();

	slashDisplay('topAbusers', {
		topabusers => $topabusers,
	});
}

#################################################################
sub listAbuses {
	my $user = getCurrentUser();
	my $form = getCurrentForm();
	my $slashdb = getCurrentDB();
	my $constants = getCurrentStatic();

	my $abuses = $slashdb->getAbuses($form->{key}, $form->{abuseid});

	slashDisplay('listAbuses', {
		abuseid	=> $form->{abuseid},
		abuses	=> $abuses,
	});
}

#################################################################
sub displayForm {
	my $user = getCurrentUser();
	my $form = getCurrentForm();
	my $slashdb = getCurrentDB();
	my $constants = getCurrentStatic();

	my $op = $form->{op};
	my $suadmin_flag = $user->{seclev} >= 10000 ? 1 : 0;

	$op ||= 'displayform';

	my $ops = {
		displayform 	=> 'loginForm',
		edithome	=> 'loginForm',
		editicomm	=> 'loginForm',
		edituser	=> 'loginForm',
		mailpasswdform 	=> 'sendPasswdForm',
		newuserform	=> 'newUserForm',
		userclose	=> 'loginForm',
		userlogin	=> 'loginForm',
		default		=> 'loginForm'
	};

	my($title, $title2, $msg1, $msg2) = ('', '', '', '');

	if ($form->{op} eq 'userclose') {
		$title = getMessage('userclose');

	} elsif ($op eq 'displayForm') {
		$title = $form->{unickname}
			? getTitle('displayForm_err_title')
			: getTitle('displayForm_title');
	} elsif ($op eq 'mailpasswdform') {
		$title = getTitle('mailPasswdForm_title');
	} elsif ($op eq 'newuserform') {
		$title = getTitle('newUserForm_title');
	} else {
		$title = getTitle('displayForm_title');
	}

	$form->{unickname} ||= $form->{newusernick};

	if ($form->{newusernick}) {
		$title2 = getTitle('displayForm_dup_title');
	} else {
		$title2 = getTitle('displayForm_new_title');
	}

	$msg1 = getMessage('dispform_new_msg_1');
	if (! $form->{newusernick} && $op eq 'newuserform') {
		$msg2 = getMessage('dispform_new_msg_2');
	} elsif ($op eq 'displayform' || $op eq 'userlogin') {
		$msg2 = getMessage('newuserform_msg');
	}

	slashDisplay($ops->{$op}, {
		newnick		=> fixNickname($form->{newusernick}),
		suadmin_flag 	=> $suadmin_flag,
		title 		=> $title,
		title2 		=> $title2,
		logged_in	=> isAnon($user->{uid}) ? 0 : 1,
		msg1 		=> $msg1,
		msg2 		=> $msg2
	});
}

#################################################################
# this groups all the messages together in
# one template, called "messages;users;default"
sub getMessage {
	my($value, $hashref, $nocomm) = @_;
	$hashref ||= {};
	$hashref->{value} = $value;
	return slashDisplay('messages', $hashref,
		{ Return => 1, Nocomm => $nocomm });
}

#################################################################
# this groups all the errors together in
# one template, called "errors;users;default"
sub getError {
	my($value, $hashref, $nocomm) = @_;
	$hashref ||= {};
	$hashref->{value} = $value;
	return slashDisplay('errors', $hashref,
		{ Return => 1, Nocomm => $nocomm });
}

#################################################################
# this groups all the titles together in
# one template, called "users-titles"
sub getTitle {
	my($value, $hashref, $nocomm) = @_;
	$hashref ||= {};
	$hashref->{value} = $value;
	return slashDisplay('titles', $hashref,
		{ Return => 1, Nocomm => $nocomm });
}

#################################################################
# getUserAdmin - returns a block of text
# containing fields for admin users
sub getUserAdmin {
	my($id, $field, $form_flag, $seclev_field) = @_;

	my $slashdb	= getCurrentDB();
	my $user	= getCurrentUser();
	my $form	= getCurrentForm();
	my $constants	= getCurrentStatic();

	my($checked, $uidstruct, $readonly, $readonly_reasons);
	my($user_edit, $user_editfield, $uidlist, $iplist, $authors, $author_flag, $author_select, $topabusers);
	my $user_editinfo_flag = ($form->{op} eq 'userinfo' || $form->{userinfo} || $form->{saveuseradmin}) ? 1 : 0;
	my $authoredit_flag = ($user->{seclev} >= 10000) ? 1 : 0;

	if ($field eq 'uid') {
		if (! isAnon($id)) {
			$user_edit = $slashdb->getUser($id);
		} else {
			$user_edit->{nonuid} = 1;
		}
		$user_editfield = $user_edit->{uid};
		$checked->{expired} = $slashdb->checkExpired($user_edit->{uid}) ? ' CHECKED' : '';
		$iplist = $slashdb->getNetIDList($user_edit->{uid});

	} elsif ($field eq 'nickname') {
		$user_edit = $slashdb->getUser($slashdb->getUserUID($id));
		$user_editfield = $user_edit->{nickname};
		$checked->{expired} = $slashdb->checkExpired($user_edit->{uid}) ? ' CHECKED' : '';
		$iplist = $slashdb->getNetIDList($user_edit->{uid});

	} elsif ($field eq 'ipid') {
		$id = $id =~ /^\d+\.\d+\.\d+\.?\d+?$/ ? md5_hex($id) : $id;
		$user_edit->{ipid} = $id;
		$user_edit->{nonuid} = 1;
		$user_editfield = $id;
		$uidlist = $slashdb->getUIDList('ipid', $user_edit->{ipid});

	} elsif ($field eq 'subnetid') {
		if ($id =~ /^(\d+\.\d+\.\d+\.)\.?\d+?/) {
			$id = $1 . ".0";
			$user_edit->{subnetid} = md5_hex($id);
		} else {
			$user_edit->{subnetid} = $id;
		}

		$user_edit->{nonuid} = 1;
		$user_editfield = $id;
		$uidlist = $slashdb->getUIDList('subnetid', $user_edit->{subnetid});

	} else {
		$user_edit = $id ? $slashdb->getUser($id) : $user;
		$user_editfield = $user_edit->{uid};
		$checked->{uid} = ' CHECKED';
		$iplist = $slashdb->getNetIDList($user_edit->{uid});
	}

	$authors = $slashdb->getDescriptions('authors');

	$author_select = $authoredit_flag
		? createSelect('authoruid', $authors, $user_edit->{uid}, 1)
		: '';
	$author_select =~ s/\s{2,}//g;

	for my $formname ('comments', 'submit') {
		$readonly->{$formname} = $slashdb->checkReadOnly($formname, $user_edit) ? ' CHECKED' : '';
		$readonly_reasons->{$formname} = $slashdb->getReadOnlyReason($formname, $user_edit) if $readonly->{$formname};
	}

	for (@$uidlist) {
		$uidstruct->{$_->[0]} = $slashdb->getUser($_->[0], 'nickname');
	}

	$user_edit->{author} = ($user_edit->{author} == 1) ? ' CHECKED' : '';
	$user_edit->{rtbl} = ($user_edit->{rtbl} == 1) ? ' CHECKED' : '';

	return slashDisplay('getUserAdmin', {
		useredit		=> $user_edit,
		userinfo_flag		=> $user_editinfo_flag,
		userfield		=> $user_editfield,
		iplist			=> $iplist,
		uidstruct		=> $uidstruct,
		seclev_field		=> $seclev_field,
		checked 		=> $checked,
		topabusers		=> $topabusers,
		author_select		=> $author_select,
		form_flag		=> $form_flag,
		readonly		=> $readonly,
		readonly_reasons 	=> $readonly_reasons,
		authoredit_flag 	=> $authoredit_flag
	}, 1);
}

#################################################################
sub fixNickname {
	local($_) = @_;
	s/\s+/ /g;
	s/[^ a-zA-Z0-9\$_.+!*'(),-]+//g;
	$_ = substr($_, 0, 20);
	return $_;
}

createEnvironment();
main();

1;
