#!/usr/bin/perl -w
# This code is a part of Slash, and is released under the GPL.
# Copyright 1997-2001 by Open Source Development Network. See README
# and COPYING for more information, or see http://slashcode.com/.
# $Id$

use strict;
use Date::Manip;
use Digest::MD5 'md5_hex';
use Slash;
use Slash::Display;
use Slash::Utility;

#################################################################
sub main {
	my $slashdb = getCurrentDB();
	my $constants = getCurrentStatic();
	my $curuser = getCurrentUser();
	my $form = getCurrentForm();

	my $suadmin_flag = $curuser->{seclev} >= 10000 ? 1 : 0 ;
	my $postflag = $ENV{REQUEST_METHOD} eq 'POST' ? 1 : 0 ;
	my $op = $form->{op};
	$op ||= 'userinfo';

	# my $note = [ split /\n+/, $form->{note} ] if defined $form->{note};
	my $note;

	if ($op eq 'userlogin' && !$curuser->{is_anon}) {
		my $refer = $form->{returnto} || $constants->{rootdir};
		# print STDERR "refer $refer\n";
		redirect($refer);
		return;

	} elsif ($op eq 'savepasswd') {
		$note = savePasswd($form->{uid});
		# change op to edituser and let fall through;
		# we need to have savePasswd set the cookie before
		# header() is called -- pudge
		$op = 'edituser';
	}

	header(getMessage('user_header'));
	print getMessage('note', { note => $note }) if defined $note;
	# print STDERR "note $note\n";
	print createMenu('users') if ! $curuser->{is_anon};

	my %ops = (
		admin		=> \&adminDispatch,
		userlogin	=> \&showInfo,
		userinfo	=> \&showInfo,
		saveuseradmin	=> \&saveUserAdmin,
		savehome	=> \&saveHome,
		savecomm	=> \&saveComm,
		saveuser	=> \&saveUser,
		changepasswd	=> \&changePasswd,
		edituser	=> \&editUser,
		edithome	=> \&editHome,
		editcomm	=> \&editComm,
		newuser		=> \&newUser,
		newuseradmin	=> \&newUserForm,
		previewbox	=> \&previewSlashbox,
		mailpasswd	=> \&mailPasswd,
		validateuser	=> \&validateUser,
		userclose	=> \&displayForm,
		newuserform	=> \&displayForm,
		mailpasswdform 	=> \&displayForm,
		displayform	=> \&displayForm,
		default		=> \&displayForm,
	);

	my $user_calls = {
		userinfo	=> 1,
		changepasswd	=> 1,
		userlogin 	=> 1,
		newuserform	=> 1,
		mailpasswdform	=> 1,
		displayform	=> 1,
		savehome	=> 1,
		saveuser	=> 1,
		savecomm	=> 1,
		edithome	=> 1,
		editcomm	=> 1,
		default		=> 1,
	};

	my $admin_calls = {
		saveuseradmin	=> 1,
		newuseradmin	=> 1,
		default		=> 1,
	};

	my $post_calls = {
		savepasswd	=> 1,
		saveuser	=> 1,
		savehome	=> 1,
		savecomm	=> 1,
		saveuseradmin	=> 1,
	};

	if ($curuser->{is_anon}) {
		$op = 'default' if $user_calls->{$op};

	} elsif (! $suadmin_flag) {
		$op = 'userinfo' if $admin_calls->{$op};
		# $op = 'userinfo' if $post_calls->{$op} ; # && ! $postflag ;
	}

	print STDERR "----------------\nOP $op\n-----------------\n";

	# here goes it
	$ops{$op}->();

	writeLog($curuser->{nickname});
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
		print getMessage('checklist_msg');
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
	my $curuser = getCurrentUser();
	my $suadmin_flag = $curuser->{seclev} >= 10000;
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
		}
	}
	# Duplicate User
	displayForm();
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

	my $user = $slashdb->getUser($uid, ['nickname', 'realemail']);

	unless ($uid) {
		print getMessage('mailpasswd_notmailed_msg');
		return;
	}

	my $newpasswd = $slashdb->getNewPasswd($uid);
	my $tempnick = fixparam($user->{nickname});

	my $emailtitle = getTitle('mailPassword_email_title', {
		nickname	=> $user->{nickname}
	}, 1);

	my $msg = getMessage('mailpasswd_msg', {
		newpasswd	=> $newpasswd,
		tempnick	=> $tempnick
	}, 1);

	doEmail($uid, $emailtitle, $msg) if $user->{nickname};
	print getMessage('mailpasswd_mailed_msg', { name => $user->{nickname} });
}

#################################################################
sub showInfo {
	my($id) = @_;

	my $slashdb = getCurrentDB();
	my $form = getCurrentForm();
	my $constants = getCurrentStatic();
	my $curuser = getCurrentUser();

	$form->{min} = 0 unless $form->{min};

	my $admin_flag = ($curuser->{seclev} >= 100) ? 1 : 0;
	my $title = '';
	my $comments;
	my $commentstruct = [];
	my $user = {};
	my $admin_block = '';

	my($points, $lastgranted, $nickmatch_flag, $uid, $nick);
	my($mod_flag, $karma_flag, $n) = (0, 0, 0);

	if ($form->{userfield_flag} eq 'uid') {
		$id ||= $form->{userfield};
		$user = $slashdb->getUser($id);
		$uid = $user->{uid};
		$nick = $user->{nickname};
		$admin_block = $admin_flag ? getUserAdmin($uid, 1, 1) : '';
		$comments = $slashdb->getCommentsByUID($uid, $form->{min});

	} elsif ($form->{userfield_flag} eq 'nickname') { 
		$id ||= $form->{userfield};
		$uid = $slashdb->getUserUID($id);
		$user = $slashdb->getUser($uid);
		$admin_block = $admin_flag ? getUserAdmin($id, 1, 1) : '';
		$comments = $slashdb->getCommentsByUID($uid, $form->{min});

	} elsif ($form->{userfield_flag} eq 'ip') {
		$id ||= $form->{userfield};
		$user->{ipid} = $id =~ /\d+\.\d+\.\d+\.?\d+?/ ?
		md5_hex($id) : $id;

		$user->{nonuid} = 1;
		$user->{fg} = $curuser->{fg};
		$user->{bg} = $curuser->{bg};

		$title = getTitle('user_netID_user_title', { id => $id, md5id => $user->{ipid}});
		$admin_block = $admin_flag ? getUserAdmin($user->{ipid}, 1, 0) : '';
		$comments = $slashdb->getCommentsByNetID($user->{ipid}, $form->{min});

	} elsif ($form->{userfield_flag} eq 'subnet') {
		$id ||= $form->{userfield};
		if ($id =~ /(\d+\.\d+\.\d+)\.?\d+?/) {
			$user->{subnetid} = $1 . ".0";
			$user->{subnetid} = md5_hex($user->{subnetid});
		} else {
			$user->{subnetid} = $id;
		}

		$user->{nonuid} = 1;
		$user->{fg} = $curuser->{fg};
		$user->{bg} = $curuser->{bg};

		$title = getTitle('user_netID_user_title', { id => $id, md5id => $user->{subnetid}});
		$admin_block = $admin_flag ? getUserAdmin($user->{subnetid}, 1, 0) : '';
		$comments = $slashdb->getCommentsBySubnetID($user->{subnetid}, $form->{min});

	} elsif ($form->{nick}) {
		$uid = $slashdb->getUserUID($form->{nick});
		$user = $slashdb->getUser($uid);
		$admin_block = $admin_flag ? getUserAdmin($uid, 1, 1) : '';
		$comments = $slashdb->getCommentsByUID($uid, $form->{min});

	} else {
		$user = $id ? $slashdb->getUser($id) : $curuser;
		$uid = $user->{uid};
		$admin_block = $admin_flag ? getUserAdmin($user->{uid}, 1, 1) : '';
		$comments = $slashdb->getCommentsByUID($user->{uid}, $form->{min});
	}

	for (@$comments) {
		my($pid, $sid, $cid, $subj, $cdate, $pts) = @$_;

		my $replies = $slashdb->countCommentsBySidPid($sid, $cid);

		# This is ok, since with all luck we will not be hitting the DB
		my $story = $slashdb->getStory($sid);
		my $question = $slashdb->getPollQuestion($sid, 'question');

		push @$commentstruct, {
			pid 		=> $pid,
			sid 		=> $sid,
			cid 		=> $cid,
			subj		=> $subj,
			cdate		=> $cdate,
			pts		=> $pts,
			story		=> $story,
			question	=> $question,
			replies		=> $replies,
		};
	}

	if ($user->{nonuid}) {
		slashDisplay('netIDInfo', {
			title			=> $title,
			id			=> $id,
			user			=> $user,
			commentstruct		=> $commentstruct || [],
			admin_flag		=> $admin_flag,
			admin_block		=> $admin_block,
		});

	} else {
		if (! defined $uid) {
			print getMessage('userinfo_nicknf_msg', { nick => $nick });
			return;
		}

		$karma_flag = 1 if $admin_flag;
		$nick = strip_literal($nick || $user->{nickname});

		if ($user->{uid} == $curuser->{uid}) {
			$karma_flag = 1;
			$nickmatch_flag = 1;
			$points = $user->{points};

			$mod_flag = 1 if $points > 0;

			if ($points) {
				$mod_flag = 1;
				$lastgranted = $slashdb->getUser($uid, 'lastgranted');
				if ($lastgranted) {
					$lastgranted = timeCalc(
						DateCalc($lastgranted,
						'+ ' . ($constants->{stir}+1) . ' days'),
						'%Y-%m-%d'
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
			useredit		=> $user,
			points			=> $points,
			lastgranted		=> $lastgranted,
			commentstruct		=> $commentstruct || [],
			nickmatch_flag		=> $nickmatch_flag,
			mod_flag		=> $mod_flag,
			karma_flag		=> $karma_flag,
			admin_block		=> $admin_block,
			admin_flag 		=> $admin_flag,
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

	# Since we are here, if the minimum values for the comment trigger and the
	# day trigger are -1, then they should be reset to 1.
	$constants->{min_expiry_comm} = $constants->{min_expiry_days} = 1;

	if ($user->{is_anon} || !length($user->{reg_id})) {
		if ($user->{is_anon}) {
			print getMessage('anon_validation_attempt');
			displayForm();

		} else {
			print getMessage('no_registration_needed') if !$user->{reg_id};
			showInfo($user->{uid});
		}
	# Maybe this should be taken care of in a more centralized location?
	} elsif ($user->{reg_id} eq $form->{id}) {
		# We have a user and the registration IDs match. We are happy!
		my($maxComm, $maxDays) =
			($constants->{max_expiry_comm}, $constants->{max_expiry_days});
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
		my $new_comment_expiry = ($maxComm > 0 && $userComm > $maxComm) ?
			$maxComm : $userComm *
				   (($user->{expiry_comm} < 0) ? $exp : 1);
		my $new_days_expiry = ($maxDays > 0 && $userDays > $maxDays) ?
			$maxDays : $userDays *
				   (($user->{expiry_days} < 0) ? $exp : 1);

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

	} elsif ($form->{edituser}) {
		editUser();

	} elsif ($form->{edithome}) {
		editHome();

	} elsif ($form->{editcomm}) {
		editComm();

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
		$aidref->{$aid}{checked} = ($exaid =~ /'$aid'/) ? ' CHECKED' : '';
	}

	my $topics = $slashdb->getDescriptions('topics');
	while (my($tid, $alttext) = each %$topics) {
		$tidref->{$tid}{checked} = ($extid =~ /'$tid'/) ? ' CHECKED' : '';
		$tidref->{$tid}{alttext} = $alttext;
	}

	my $sections = $slashdb->getDescriptions('sections');
	while (my($section, $title) = each %$sections) {
		$sectionref->{$section}{checked} = ($exsect =~ /'$section'/) ? ' CHECKED' : '';
		$sectionref->{$section}{title} = $title;
	}

	my $customize_title = getTitle('tildeEd_customize_title');

	my $tilded_customize_msg = getMessage('users_tilded_customize_msg',
		{ userspace => $userspace });

	my $sections_description = $slashdb->getSectionBlocks();

	$customize_title = getTitle('tildeEd_customize_title');  # repeated from above?

	for (@$sections_description) {
		my($bid, $title, $boldflag) = @$_;

		$section_descref->{$bid}{checked} = ($exboxes =~ /'$bid'/) ? ' CHECKED' : '';
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
	my $curuser = getCurrentUser();
	my $constants = getCurrentStatic();

	return if $curuser->{is_anon};

	my $user = {};
	my $title ;
	my $suadmin_flag = ($curuser->{seclev} >= 10000) ? 1 : 0;

	$user = $id eq '' ? $curuser : $slashdb->getUser($id);

	return if isAnon($user->{uid});

	print getMessage('note', { note => $form->{note}}) if $form->{note};

	$title = getTitle('changePasswd', { user_edit => $user});

	my $session = $slashdb->getDescriptions('session_login');
	my $session_select = createSelect('session_login', $session, $user->{session_login}, 1);

	slashDisplay('changePasswd', {
		useredit 		=> $user,
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
	my $curuser = getCurrentUser();
	my $constants = getCurrentStatic();

	my($user, $session) = ({}, {});
	my($admin_block, $title, $description, $maillist, $session_select);
	my $admin_flag = ($curuser->{seclev} >= 100) ? 1 : 0;

	return if $curuser->{is_anon};

	if ($form->{userfield} ) {
		$id ||= $form->{userfield};
		if ($form->{userfield_flag} eq 'nickname') {
			$user = $slashdb->getUser($slashdb->getUserUID($id));
		} elsif ($form->{userfield_flag} eq 'uid') {
			$user = $slashdb->getUser($id);
		} else {
			$user = $curuser;
		}
	} else {
		$user = $id eq '' ? $curuser : $slashdb->getUser($id);
	}
	return if isAnon($user->{uid}) && ! $admin_flag; 
	$admin_block = getUserAdmin() if $admin_flag;

	$user->{homepage} ||= "http://";

	$title = getTitle('editUser_title', { user_edit => $user});

	$description = $slashdb->getDescriptions('maillist');
	$maillist = createSelect('maillist', $description, $user->{maillist}, 1);

	$session = $slashdb->getDescriptions('session_login');
	$session_select = createSelect('session_login', $session, $user->{session_login}, 1);

	slashDisplay('editUser', {
		useredit 		=> $user,
		admin_flag		=> $admin_flag,
		title			=> $title,
		editkey 		=> editKey($user->{uid}),
		maillist 		=> $maillist,
		session 		=> $session_select,
		admin_block		=> $admin_block
	});
}

#################################################################
sub editHome {
	my($id) = @_;

	my $slashdb = getCurrentDB();
	my $form = getCurrentForm();
	my $curuser = getCurrentUser();

	my($formats, $title, $tzformat_select, $tzcode_select);
	my $user = {};
	#Is it a good idea to set this, this low (100)
	# no, it is not -- pudge
	my $admin_flag = ($curuser->{seclev} >= 1000) ? 1 : 0;
	my $admin_block = '';

	return if $curuser->{is_anon};

	if ($form->{userfield}) {
		$id ||= $form->{userfield};
		if ($form->{userfield_flag} eq 'nickname') {
			$user = $slashdb->getUser($slashdb->getUserUID($id));
		} elsif ($form->{userfield_flag} eq 'uid') {
			$user = $slashdb->getUser($id);
		} else {
			$user = $curuser;
		}
	} else {
		$user = $id eq '' ? $curuser : $slashdb->getUser($id);
	}

	return if isAnon($curuser->{uid});
	return if isAnon($user->{uid}) && ! $admin_flag;
	$admin_block = getUserAdmin() if $admin_flag;

	$title = getTitle('editHome_title');

	return if $curuser->{seclev} < 100 && $user->{is_anon};

	$formats = $slashdb->getDescriptions('dateformats');
	$tzformat_select = createSelect('tzformat', $formats, $user->{dfid}, 1);

	$formats = $slashdb->getDescriptions('tzcodes');
	$tzcode_select = createSelect('tzcode', [ keys %$formats ], $user->{tzcode}, 1);

	my $l_check = $user->{light}	? ' CHECKED' : '';
	my $b_check = $user->{noboxes}	? ' CHECKED' : '';
	my $i_check = $user->{noicons}	? ' CHECKED' : '';
	my $w_check = $user->{willing}	? ' CHECKED' : '';

	my $tilde_ed = tildeEd(
		$user->{extid}, $user->{exsect},
		$user->{exaid}, $user->{exboxes}, $user->{mylinks}
	);

	slashDisplay('editHome', {
		title			=> $title,
		admin_block		=> $admin_block,	
		user_edit		=> $user,
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
	my $curuser = getCurrentUser();
	my $user = {};
	my($formats, $commentmodes_select, $commentsort_select, $title,
		$uthreshold_select, $highlightthresh_select, $posttype_select);

	my $admin_block = '';

	my $admin_flag = ($curuser->{seclev} >= 100) ? 1 : 0;

	if ($form->{userfield}) {
		$id ||= $form->{userfield};
		if ($form->{userfield_flag} eq 'nickname') {
			$user = $slashdb->getUser($slashdb->getUserUID($id));
		} elsif ($form->{userfield_flag} eq 'uid') {
			$user = $slashdb->getUser($id);
		} else {
			$user = $slashdb->getCurrentUser();
		}
	} else {
		$user = $id eq '' ? $curuser : $slashdb->getUser($id);
	}

	return if isAnon($curuser->{uid});
	return if isAnon($user->{uid}) && ! $admin_flag;
	$admin_block = getUserAdmin() if $admin_flag;

	$title = getTitle('editComm_title');

	$formats = $slashdb->getDescriptions('commentmodes');
	$commentmodes_select = createSelect('umode', $formats, $user->{mode}, 1);

	$formats = $slashdb->getDescriptions('sortcodes');
	$commentsort_select = createSelect('commentsort', $formats, $user->{commentsort}, 1);

	$formats = $slashdb->getDescriptions('threshcodes');
	$uthreshold_select = createSelect('uthreshold', $formats, $user->{threshold}, 1);

	$formats = $slashdb->getDescriptions('threshcodes');
	$highlightthresh_select = createSelect('highlightthresh', $formats, $user->{highlightthresh}, 1);

	my $h_check = $user->{hardthresh}	? ' CHECKED' : '';
	my $r_check = $user->{reparent}		? ' CHECKED' : '';
	my $n_check = $user->{noscores}		? ' CHECKED' : '';
	my $s_check = $user->{nosigs}		? ' CHECKED' : '';

	$formats = $slashdb->getDescriptions('postmodes');
	$posttype_select = createSelect('posttype', $formats, $user->{posttype}, 1);

	slashDisplay('editComm', {
		title			=> $title,
		admin_block		=> $admin_block,
		user_edit		=> $user,
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
	my $curuser = getCurrentUser();
	my $constants = getCurrentStatic();

	return if $curuser->{seclev} < 100;

	my($users_table, $user) = ({}, {});
	my $save_success = 0;
	my $author_flag;
	my $note = '';

	my $id = $curuser->{seclev} >= 100 ? shift : $curuser->{uid};
	if (! $id) {
		$id = $form->{userfield} ? $form->{userfield} : $curuser->{uid};
	}

	if ($form->{userfield_flag} eq 'uid') {
		if ($id =~ /^\d+$/) {
			$user = $slashdb->getUser($id);
		} else {
			$note .= getMessage('saveuseradmin_uid_notnumeric', { field => $form->{userfield}, id => $id });
		}
	} elsif ($form->{userfield_flag} eq 'nickname') {
		$user = $slashdb->getUser($slashdb->getUserUID($id));

	} elsif ($form->{userfield_flag} eq 'ip') {
		$user->{uid} = $constants->{anonymous_coward_uid};
		$id = $id =~ /^\d+\.\d+\.\d+\.?\d+?$/ ? md5_hex($id) : $id;
		$user->{ipid} = $id;
		$user->{nonuid} = 1;

	} elsif ($form->{userfield_flag} eq 'subnet') {
		if ($id =~ /^(\d+\.\d+\.\d+\.)\.?\d+?/) {
			$id = $1 . ".0";
			$user->{subnetid} = md5_hex($id);
		} else {
			$user->{subnetid} = $id;
		}
		$user->{uid} = $constants->{anonymous_coward_uid};
		$user->{subnetid} = $id;
		$user->{nonuid} = 1;

	} else { # a bit redundant, I know
		$user = $curuser;
	}

	for my $formname ('comments', 'submit') {
		my $existing_reason = $slashdb->getReadOnlyReason($formname, $user);
		my $is_readonly_now = $slashdb->checkReadOnly($formname, $user) ? 1 : 0;

		my $keyname = "readonly_" . $formname;
		my $reason_keyname = $formname . "_ro_reason";
		$form->{$keyname} = $form->{$keyname} eq 'on' ? 1 : 0 ;
		$form->{$reason_keyname} ||= '';

		if ($form->{$keyname} != $is_readonly_now) {
			if ("$existing_reason" ne "$form->{$reason_keyname}") {
				$slashdb->setReadOnly($formname, $user, $form->{$keyname}, $form->{$reason_keyname});
			} else {
				$slashdb->setReadOnly($formname, $user, $form->{$keyname});
			}
		} elsif ("$existing_reason" ne "$form->{$reason_keyname}") {
                                $slashdb->setReadOnly($formname, $user, $form->{$keyname}, $form->{$reason_keyname});
		}

		# $note .= getMessage('saveuseradmin_notsaved', { field => $form->{userfield_flag}, id => $id });
	}

	$note .= getMessage('saveuseradmin_saved', { field => $form->{userfield_flag}, id => $id}) if $save_success;

	if ($curuser->{seclev} >= 100 && ($form->{userfield_flag} eq 'uid' ||
		$form->{userfield_flaq} eq 'nickname')) {

		$users_table->{seclev} = $form->{seclev};
		$users_table->{rtbl} = $form->{rtbl} eq 'on' ? 1 : 0 ;
		$users_table->{author} = $form->{author} ? 1 : 0 ;

		$slashdb->setUser($id, $users_table);
		$note .= getMessage('saveuseradmin_saveduser', { field => $form->{userfield_flag}, id => $id });

		#} else {
		#	$note .= getMessage('saveuseradmin_notsaveduser', { field => $form->{userfield_flag}, id => $id});
		#}
	}

	if (!$user->{nonuid}) {
		if ($form->{expired} eq 'on') {
			$slashdb->setExpired($user->{uid});

		} else {
			$slashdb->setUnexpired($user->{uid});
		}
	}

	print getMessage('note', { note => $note }) if defined $note;

	showInfo($id);
}

#################################################################
sub savePasswd {
	my $slashdb = getCurrentDB();
	my $form = getCurrentForm();
	my $curuser = getCurrentUser();
	my $constants = getCurrentStatic();
	my $uid;
	my($note, $author_flag, $user_fakeemail, $formname);
	my $user = {};

	my $users_table = {};
	my $suadmin_flag = $curuser->{seclev} >= 10000 ? 1 : 0;

	if ($curuser->{seclev} >= 100) {
		$uid = shift;
		if (! $uid) {
			$uid = $form->{uid} ? $form->{uid} : $curuser->{uid};
		}
	} else {
		$uid = ($curuser->{uid} == $form->{uid}) ? $form->{uid} : $curuser->{uid};
	}

	return if isAnon($uid);

	if ($form->{userfield_flag} eq 'uid') {
		if ($uid =~ /^\d+$/) {
			$user = $slashdb->getUser($uid);
			if ($form->{userfield} != $form->{uid}) {
				return();
			}
		}
	} elsif ($form->{userfield_flag} eq 'nickname') {
		if ($slashdb->getUserUID($form->{userfield}) == $form->{uid}) {
			$user = $slashdb->getUser($slashdb->getUserUID($uid));
		} else {
			return();
		}
	} else {
		$user = $slashdb->getUser($uid);
	}

	if (!$user->{nickname}) {
		$note .= getMessage('cookiemsg', 0, 1);
	}

	if ($form->{pass1} eq $form->{pass2} && length($form->{pass1}) > 5) {
		$note .= getMessage('saveuser_passchanged_msg', 0, 1);

		$users_table->{passwd} = $form->{pass1};
		if ($form->{uid} eq $curuser->{uid}) {
			setCookie('user', bakeUserCookie($uid, encryptPassword($users_table->{passwd})));
		}

	} elsif ($form->{pass1} ne $form->{pass2}) {
		$note .= getMessage('saveuser_passnomatch_msg', 0, 1);

	} elsif (length $form->{pass1} < 6 && $form->{pass1}) {
		$note .= getMessage('saveuser_passtooshort_msg', 0, 1);
	}

	$slashdb->setUser($uid, $users_table);

	return $note;
}

#################################################################
sub saveUser {
	my $slashdb = getCurrentDB();
	my $form = getCurrentForm();
	my $curuser = getCurrentUser();
	my $constants = getCurrentStatic();
	my $uid;

	if ($curuser->{seclev} >= 100) {
		$uid = shift;
		if (! $uid) {
			$uid = $form->{uid} ? $form->{uid} : $curuser->{uid};
		}
	} else {
		$uid = ($curuser->{uid} == $form->{uid}) ? $form->{uid} : $curuser->{uid};
	}

	return if isAnon($uid);

	my($note, $author_flag, $user_fakeemail, $formname);
	my $user = {};

	if ($form->{userfield_flag} eq 'uid') {
		if ($uid =~ /^\d+$/) {
			$user = $slashdb->getUser($uid);
			if ($form->{userfield} != $form->{uid}) {
				return();
			}
# 		} else {
# 			# this will never happen!  see isAnon() -- pudge
#   			my $note = getMessage('saveuseradmin_uid_notnumeric', { field => $form->{userfield}, id => $uid });
# 			return($note);
		}
	} elsif ($form->{userfield_flag} eq 'nickname') {
		if ($slashdb->getUserUID($form->{userfield}) == $form->{uid}) {
			$user = $slashdb->getUser($slashdb->getUserUID($uid));
		} else {
			return();
		}
	} else {
		$user = $slashdb->getUser($uid);
	}

	# We start with the 'Saved ...' message.
	$user->{nickname} = substr($user->{nickname}, 0, 20);

	$note .= getMessage('savenickname_msg', { nickname => $user->{nickname} }, 1);

	if (!$user->{nickname}) {
		$note .= getMessage('cookiemsg', 0, 1);
	}

	$user_fakeemail = ($user->{emaildisplay} == 1) ?
		$user->{fakeemail} : getArmoredEmail($uid);

	# Check to ensure that if a user is changing his email address, that
	# it doesn't already exist in the userbase.
	if ($user->{realemail} ne $form->{realemail}) {
		if ($slashdb->checkEmail($form->{realemail})) {
			$note = getMessage('emailexists_msg', 0, 1);
			return $note;
		}
	}

	for $formname ('comments', 'submit') {
		my $keyname = "readonly_" . $formname;
		my $reason_keyname = $formname . "_ro_reason";
		$form->{$keyname} = $form->{$keyname} eq 'on' ? 1 : 0 ;

		$form->{$reason_keyname} ||= '';

		$slashdb->setReadOnly(
			$formname, $user,
			$form->{$keyname},
			$form->{$reason_keyname}
		);

		# $stuff never used ... ?
		my $stuff = $slashdb->checkReadOnly($formname, $user);

	}

	# strip_mode _after_ fitting sig into schema, 120 chars
	$form->{sig}	 	= strip_html(substr($form->{sig}, 0, 120));
	$form->{homepage}	= '' if $form->{homepage} eq 'http://';
	$form->{homepage}	= fixurl($form->{homepage});
	$author_flag		= $form->{author} ? 1 : 0;
	# Do the right thing with respect to the chosen email display mode
	# and the options that can be displayed.
	my @email_choices = ('', $user_fakeemail, $form->{realemail});

	# for the users table
	my $users_table = {
		sig		=> $form->{sig},
		homepage	=> $form->{homepage},
		maillist	=> $form->{maillist},
		realname	=> $form->{realname},
		bio		=> $form->{bio},
		pubkey		=> $form->{pubkey},
		copy		=> $form->{copy},
		quote		=> $form->{quote},
		session_login	=> $form->{session_login},
		emaildisplay	=> $form->{emaildisplay},
		fakeemail	=> $email_choices[$form->{emaildisplay}],
	};

	# don't want undef, want to be empty string so they
	# will overwrite the existing record
	for (keys %$users_table) {
		$users_table->{$_} = '' unless defined $users_table->{$_};
	}

	if ($curuser->{seclev} >= 100) {
		$users_table->{seclev} = $form->{seclev};
		$users_table->{author} = $author_flag;
	}

	if ($user->{realemail} ne $form->{realemail}) {
		$users_table->{realemail} =
			chopEntity(strip_attribute($form->{realemail}), 50);

		$note .= getMessage('changeemail_msg', {
			realemail => $user->{realemail}
		}, 1);

		my $saveuser_emailtitle = getTitle('saveUser_email_title', {
			nickname  => $user->{nickname},
			realemail => $form->{realemail}
		}, 1);
		my $saveuser_email_msg = getMessage('saveuser_email_msg', {
			nickname  => $user->{nickname},
			realemail => $form->{realemail}
		}, 1);

		doEmail($uid, $saveuser_emailtitle, $saveuser_email_msg);
	}

	$slashdb->setUser($uid, $users_table);

	print getMessage('note', { note => $note}) if $note;

	editUser($uid);
}

#################################################################
sub saveComm {
	my $slashdb = getCurrentDB();
	my $curuser = getCurrentUser();
	my $form = getCurrentForm();
	my $uid;

	if ($curuser->{seclev} >= 100) {
		$uid = shift;
		if (! $uid) {
			$uid = $form->{uid} ? $form->{uid} : $curuser->{uid};
		}
	} else {
		$uid = ($curuser->{uid} == $form->{uid}) ? $form->{uid} : $curuser->{uid};
	}
	return if isAnon($uid);

	my $name = $curuser->{seclev} && $form->{name} ? $form->{name} : $curuser->{nickname};

	$name = substr($name, 0, 20);

	my $savename = getMessage('savename_msg', { name => $name });
	print $savename;

	if (isAnon($uid) || !$name) {
		print getMessage('cookiemsg');
	}

	# Take care of the lists
	# Enforce Ranges for variables that need it
	$form->{commentlimit} = 0 if $form->{commentlimit} < 1;
	$form->{commentspill} = 0 if $form->{commentspill} < 1;

	# for users_comments
	my $users_comments_table = {
		clbig		=> $form->{clbig},
		clsmall		=> $form->{clsmall},
		commentlimit	=> $form->{commentlimit},
		commentsort	=> $form->{commentsort},
		commentspill	=> $form->{commentspill},
		displaytags	=> $form->{displaytags},
		highlightthresh	=> $form->{highlightthresh},
		maxcommentsize	=> $form->{maxcommentsize},
		mode		=> $form->{umode},
		posttype	=> $form->{posttype},
		threshold	=> $form->{uthreshold},
		domaintags	=> $form->{domaintags},
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
	my $curuser = getCurrentUser();
	my $form = getCurrentForm();
	my $uid;

	if ($curuser->{seclev} >= 100) {
		$uid = shift;
		if (! $uid) {
			$uid = $form->{uid} ? $form->{uid} : $curuser->{uid};
		}
	} else {
		$uid = ($curuser->{uid} == $form->{uid}) ? $form->{uid} : $curuser->{uid};
	}
	return if isAnon($uid);

	my $name = $curuser->{seclev} && $form->{name} ? $form->{name} : $curuser->{nickname};

	$name = substr($name, 0, 20);
	return if isAnon($uid);

	# users_cookiemsg
	if (isAnon($uid) || !$name) {
		my $cookiemsg = getMessage('cookiemsg');
		print $cookiemsg;
	}

	my($extid, $exaid, $exsect) = '';
	my $exboxes = $slashdb->getUser($uid, 'exboxes');

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

	# Update users with the $users_index_table thing we've been playing with for this whole damn sub
	$slashdb->setUser($uid, $users_index_table);

	editHome($uid);
}

#################################################################
sub displayForm {
	my $curuser = getCurrentUser();
	my $form = getCurrentForm();
	my $slashdb = getCurrentDB();
	my $constants = getCurrentStatic();

	my $op = $form->{op};
	my $suadmin_flag = $curuser->{seclev} >= 10000 ? 1 : 0;

	$op ||= 'displayform';

	my $ops = {
		displayform 	=> 'loginForm',
		mailpasswdform 	=> 'sendPasswdForm',
		newuserform	=> 'newUserForm',
		userclose	=> 'loginForm',
		userlogin	=> 'loginForm'
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
		$msg2 = getMessage('dispform_new_msg_2') 
	} elsif ($op eq 'displayform' || $op eq 'userlogin') { 
		$msg2 = getMessage('newuserform_msg') 
	}

	slashDisplay($ops->{$op}, {
		newnick		=> fixNickname($form->{newusernick}),
		suadmin_flag 	=> $suadmin_flag,
		title 		=> $title,
		title2 		=> $title2,
		logged_in	=> isAnon($curuser->{uid}) ? 0 : 1,
		msg1 		=> $msg1,
		msg2 		=> $msg2
	});
}

#################################################################
# this groups all the messages together in
# one template, called "users-messages"
sub getMessage {
	my($value, $hashref, $nocomm) = @_;
	$hashref ||= {};
	$hashref->{value} = $value;
	return slashDisplay('messages', $hashref,
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
	my($id, $form_flag, $seclev_field) = @_;

	my $slashdb	= getCurrentDB();
	my $curuser	= getCurrentUser();
	my $form	= getCurrentForm();
	my $constants	= getCurrentStatic();

	my($checked, $uidstruct, $readonly, $readonly_reasons) = ({}, {}, {}, {});
	my($user, $userfield, $uidlist, $iplist, $authors, $author_flag, $author_select);
	my $userinfo_flag = ($form->{op} eq 'userinfo' || $form->{userinfo} || $form->{saveuseradmin}) ? 1 : 0;
	my $authoredit_flag = ($curuser->{seclev} >= 10000) ? 1 : 0; 

	if ($form->{userfield_flag} eq 'uid') {
		if (! isAnon($id)) {
			$user = $slashdb->getUser($id);
		} else {
			$user->{nonuid} = 1;
		}
		$userfield = $user->{uid};
		$checked->{uid} = ' CHECKED';
		$checked->{expired} = $slashdb->checkExpired($user->{uid}) ? ' CHECKED' : '';
		$iplist = $slashdb->getNetIDList($user->{uid});

	} elsif ($form->{userfield_flag} eq 'nickname') {
		$user = $slashdb->getUser($slashdb->getUserUID($id));
		$userfield = $user->{nickname};
		$checked->{nickname} = ' CHECKED';
		$checked->{expired} = $slashdb->checkExpired($user->{uid}) ? ' CHECKED' : '';
		$iplist = $slashdb->getNetIDList($user->{uid});

	} elsif ($form->{userfield_flag} eq 'ip') {
		$id = $id =~ /^\d+\.\d+\.\d+\.?\d+?$/ ? md5_hex($id) : $id;
		$user->{ipid} = $id;
		$user->{nonuid} = 1;
		$userfield = $id;
		$checked->{ip} = ' CHECKED';
		$uidlist = $slashdb->getUIDList('ipid', $user->{ipid});

	} elsif ($form->{userfield_flag} eq 'subnet') {
		if ($id =~ /^(\d+\.\d+\.\d+\.)\.?\d+?/) {
			$id = $1 . ".0";
			$user->{subnetid} = md5_hex($id);
		} else {
			$user->{subnetid} = $id;
		}

		$user->{nonuid} = 1;
		$userfield = $id;
		$checked->{subnet} = ' CHECKED';
		$uidlist = $slashdb->getUIDList('subnetid', $user->{subnetid});

	} else {
		$user = $id ? $slashdb->getUser($id) : $curuser; 
		$userfield = $user->{uid};
		$checked->{uid} = ' CHECKED';
		$iplist = $slashdb->getNetIDList($user->{uid});
	}

	$authors = $slashdb->getDescriptions('authors');

	$author_select = $authoredit_flag
		? createSelect('authoruid', $authors, $user->{uid}, 1)
		: '';
	$author_select =~ s/\s{2,}//g;

	for my $formname ('comments', 'submit') {
		$readonly->{$formname} = $slashdb->checkReadOnly($formname, $user) ? ' CHECKED' : '';
		$readonly_reasons->{$formname} = $slashdb->getReadOnlyReason($formname, $user) if $readonly->{$formname};
	}

	for (@$uidlist) {
		$uidstruct->{$_->[0]} = $slashdb->getUser($_->[0], 'nickname');
	}

	$user->{author} = ($user->{author} == 1) ? ' CHECKED' : '';
	$user->{rtbl} = ($user->{rtbl} == 1) ? ' CHECKED' : '';

	return slashDisplay('getUserAdmin', {
		useredit		=> $user,
		userinfo_flag		=> $userinfo_flag,
		userfield		=> $userfield,
		iplist			=> $iplist,
		uidstruct		=> $uidstruct,
		seclev_field		=> $seclev_field,
		checked 		=> $checked,
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
