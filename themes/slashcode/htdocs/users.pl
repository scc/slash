#!/usr/bin/perl -w
# This code is a part of Slash, and is released under the GPL.
# Copyright 1997-2001 by Open Source Development Network. See README
# and COPYING for more information, or see http://slashcode.com/.
$Id$

use strict;
use Date::Manip;
use Slash;
use Slash::Display;
use Slash::Utility;
use Digest::MD5 'md5_hex';

#################################################################
sub main {
	my $slashdb = getCurrentDB();
	my $constants = getCurrentStatic();
	my $user = getCurrentUser();
	my $curuser = getCurrentUser();
	my $form = getCurrentForm();

	my $suadminflag = $curuser->{seclev} >= 10000 ? 1 : 0 ;
	my $postflag = $ENV{REQUEST_METHOD} eq 'POST' ? 1 : 0 ;
	my $op = $form->{op};

	if ( $suadminflag ) {
		if ( $form->{userfield_flag} eq 'uid') {
			$user = $slashdb->getUser($form->{userfield});

		} elsif ( $form->{userfield_flag} eq 'nickname') {
			$user = $slashdb->getUser(getUserUID($form->{userfield}));
		} else {
			$user = getCurrentUser();
		}

	} elsif ( $form->{uid} ) {
		$user = $slashdb->getUser($form->{uid});
		if ($user->{uid} != $curuser->{uid}) {
			displayForm();
			return();
		}
	} else {
		$user = getCurrentUser();
	}

	my $uid = $user->{uid};

	if ($op eq 'userlogin' && !$curuser->{is_anon}) {
		my $refer = $form->{returnto} || $constants->{rootdir};
		print STDERR "refer $refer\n";
		redirect($refer);
		return;

	} # elsif ($op eq 'saveuser') {
	# 	saveUser($form->{uid});
	# 	$op = 'edituser';
	# }

	header(getMessage('user_header'));

	print createMenu('users') if ! $curuser->{is_anon};

	my %ops = (
		userlogin	=> \&userInfo,
		userinfo	=> \&userInfo,
		saveuseradmin	=> \&saveUserAdmin,
		savehome	=> \&saveHome,
		savecomm	=> \&saveComm,
		saveuser	=> \&saveUser,
		edituser	=> \&editUser,
		edithome	=> \&editHome,
		editcomm	=> \&editComm,
		newuser		=> \&newUser,
		newuseradmin	=> \&newUserForm,
		previewbox	=> \&previewSlashbox,
		mailpasswd	=> \&mailPassword,
		validateuser	=> \&validateUser,
		userclose	=> \&displayForm,
		default		=> \&displayForm,
	);

	my $user_calls = { 
		userinfo	=> 1,
		userlogin 	=> 1,
		savehome	=> 1,
		savecomm	=> 1,
		saveuser	=> 1,
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
		savehome	=> 1,
		savecomm	=> 1,
		saveuser	=> 1,
		saveuseradmin	=> 1,
	};

	if ($curuser->{is_anon}) {
		$op = 'default' if $user_calls->{$op};

	} elsif (! $suadminflag) {
		$op = 'userinfo' if $admin_calls->{$op};
		# $op = 'userinfo' if $post_calls->{$op} ; # && ! $postflag ;
	}
		
	print STDERR "----------------\nOP $op\n-----------------\n";
	############################################
	# Ok, I hate this, and so do you. I'm going to put 
	# this piece of devil's cake into a dispatch hash
	# I did away with OP, but realised I can resurrect OP 
	# and make it the primary "op" (in the dispatch hash)
	# and have subroutine specific logic in whatever sub gets 
	# called instead of all at the begining
	# so, don't flame me yet. Patg, your friend
	# 
	# Update: 6/8/01 Patg
	# I'm gonna commit this. This is the last time this if/else 
	# will be in the code. I've stripped everything down to single 
	# actions in preparation for having the dispatch hash work
	# note: saving a password logs you out. This will be addressed
	# there will be some other kinks too as it's far from done or perfect
	# 
	# seclev independent actions
	############################################
	if ($op eq 'newuser') {
		newUser();

	} elsif ($op eq 'mailpasswd') {
		mailPassword();

	} elsif ($op eq 'userclose') {
		displayForm();

	} elsif ($op eq 'userlogin') {
		userInfo($user->{uid});

	} elsif ($form->{validateuser}) {
		validateUser();

	} elsif ($op eq 'previewbox') {
		previewSlashbox();

	# su admin actions
	############################################
	} elsif ($suadminflag) { 
		if ($op eq 'newuseradmin') {
			newUserForm();

		} elsif ($op eq 'edituser') {
			editUser();

		} elsif ($op eq 'userinfo') {
			userInfo($user->{uid});

		} elsif ($op eq 'admin') {
			adminDispatch();

		} elsif ($op eq 'authoredit') {
			adminDispatch();

		} elsif ($op eq 'edithome') {
			editHome($user->{uid});

		} elsif ($op eq 'editcomm') {
			editComm($user->{uid});

		} elsif ($op eq 'saveuser') {
			saveUser();

		} elsif ($op eq 'saveuseradmin') {
			saveUserAdmin();
		} elsif ($op eq 'savecomm') {
			saveComm($user->{uid});

		} elsif ($op eq 'savehome') {
			saveHome($user->{uid});

		} else {
			userInfo($user->{uid});
		} 
	# regular user admin
	############################################
	} elsif (! ($curuser->{is_anon}))  { 

		if ($op eq 'userinfo') {
			userInfo();

		} elsif ($op eq 'edituser') {
			editUser();

		} elsif ($op eq 'edithome') {
			editHome();

		} elsif ($op eq 'editcomm') {
			editComm();

		} elsif ($op eq 'saveuser') {
			saveUser();

		} elsif ($op eq 'userinfo') {
			userInfo();

		} elsif ($op eq 'savecomm') {
			saveComm();

		} elsif ($op eq 'savehome') {
			saveHome();

		} else {
			userInfo();

		}

	# this would be what an AC gets
	############################################
	} else {
		displayForm();

	}

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
	slashDisplay('newUserForm')
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
			mailPassword($uid);

			return;
		}
	}
	# Duplicate User
	displayForm();
}


#################################################################
sub mailPassword {
	my($uid) = @_;

	my $slashdb = getCurrentDB();
	my $form = getCurrentForm();

	if (! $uid ) {
		$uid = $slashdb->getUserUID($form->{unickname});
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
	my($id, $note) = @_;

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

	my($points, $lastgranted, $nickmatch_flag, $uid,$nick);
	my($mod_flag, $karma_flag, $n) = (0, 0, 0);

	if ($form->{userfield_flag} eq 'uid') {
		$user = $slashdb->getUser($id);
		$uid = $user->{uid};
		$nick = $user->{nickname};
		$admin_block = $admin_flag ? getUserAdmin($uid, 1, 1) : '';

	} elsif ($form->{userfield_flag} eq 'nickname' || $form->{nick}) {
		$nick = $form->{nick} ? $form->{nick} : $id;
		$uid = $slashdb->getUserUID($nick);
		$user = $slashdb->getUser($uid);
		$admin_block = $admin_flag ? getUserAdmin($uid, 1, 1) : '';

	} elsif ( $form->{userfield_flag} eq 'ip') {
		$user->{ipid} = $id =~ /\d+\.\d+\.\d+\.?\d+?/ ? 
		md5_hex($id) : $id;

		$user->{nonid} = 1;

		print getMessage('userinfo_netID_msg', { id => $user->{ipid}});
		$title = getTitle('user_netID_user_title', { id => $id, md5id => $user->{ipid}});
		$admin_block = $admin_flag ? getUserAdmin($user->{ipid}, 1, 0) : '';
		$comments = $slashdb->getCommentsByNetID($user->{ipid}, $form->{min});

	} elsif ($form->{userfield_flag} eq 'subnet') {
		if ($id =~ /(\d+\.\d+\.\d+)\.?\d+?/) {
			$user->{subnetid} = $1 . ".0";
			$user->{subnetid} = md5_hex($user->{subnetid});
		} else {
			$user->{subnetid} = $id;
		}

		$user->{nonid} = 1;

		print getMessage('userinfo_netID_msg', { id => $user->{subnetid}});
		$title = getTitle('user_netID_user_title', { id => $id, md5id => $user->{subnetid}});
		$admin_block = $admin_flag ? getUserAdmin($user->{subnetid}, 1, 0) : '';
		$comments = $slashdb->getCommentsByNetID($user->{subnetid}, $form->{min});

	} else {
		$user = $curuser;
		$uid = $curuser->{uid};
		$nick = $curuser->{nickname};
		$admin_block = $admin_flag ? getUserAdmin($curuser->{uid}, 1, 1) : '';

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
	
	if ($user->{nonid}) {
		slashDisplay('netIDInfo', {
			title			=> $title,
			id			=> $id,
			edituser		=> $user,
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
		$nick = $nick ? strip_literal($nick) : $user->{nickname};

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
			userbio			=> $user,
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

#################################################################
sub netIDInfo {
	my($id) = @_;

	my $slashdb = getCurrentDB();
	my $form = getCurrentForm();
	my $constants = getCurrentStatic();
	my $curuser = getCurrentUser();

	return if ($curuser->{is_anon} || $curuser->{seclev} < 100);

	if (! $id ) {
		$id = $form->{userfield} ? $form->{userfield} : $curuser->{uid};
	}

	my $admin_flag = ($curuser->{seclev} >= 100) ? 1 : 0;
	my $title = '';
	my $comments;
	my $commentstruct = [];
	my $edituser = {};
	my $admin_block = '';

	$form->{min} = 0 unless $form->{min};

	if ( $form->{userfield_flag} eq 'ip') {
		$edituser->{ipid} = $id =~ /\d+\.\d+\.\d+\.?\d+?/ ? 
		md5_hex($id) : $id;

		print getMessage('userinfo_netID_msg', { id => $edituser->{ipid}});
		$title = getTitle('user_netID_user_title', { id => $id, md5id => $edituser->{ipid}});
		$admin_block = getUserAdmin($edituser->{ipid}, 1, 0);
		$comments = $slashdb->getCommentsByNetID($edituser->{ipid}, $form->{min});
	} elsif ($form->{userfield_flag} eq 'subnet') {
		if ($id =~ /(\d+\.\d+\.\d+)\.?\d+?/) {
			$edituser->{subnetid} = $1 . ".0";
			$edituser->{subnetid} = md5_hex($edituser->{subnetid});
		} else {
			$edituser->{subnetid} = $id;
		}
		print getMessage('userinfo_netID_msg', { id => $edituser->{subnetid}});
		$title = getTitle('user_netID_user_title', { id => $id, md5id => $edituser->{subnetid}});
		$admin_block = getUserAdmin($edituser->{subnetid}, 1, 0);
		$comments = $slashdb->getCommentsByNetID($edituser->{subnetid}, $form->{min});
	} else { 
			$edituser = getCurrentUser();
			print getMessage('userinfo_netID_msg', { id => $edituser->{ipid}});

			$title = getTitle('user_netID_user_title', { id => $edituser->{uid}, md5id => $edituser->{ipid}});
			$admin_block = getUserAdmin($edituser->{uid}, 1, 0);
			$comments = $slashdb->getCommentsByNetID($edituser->{ipid}, $form->{min});
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

	slashDisplay('netIDInfo', {
		title			=> $title,
		id			=> $id,
		edituser		=> $edituser,
		commentstruct		=> $commentstruct || [],
		admin_flag		=> $admin_flag,
		admin_block		=> $admin_block,
	});

}
#################################################################
sub userInfo {
	my ($id) = @_;

	my $slashdb = getCurrentDB();
	my $form = getCurrentForm();
	my $constants = getCurrentStatic();
	my $curuser = getCurrentUser();

	my $user = {};
	my ($nick, $uid);

	if ( ! $id ) {
		$id = $form->{userfield} ? $form->{userfield} : $curuser->{uid};
	}

	if ( $form->{userfield_flag} eq 'uid' ) {
		$user = $slashdb->getUser($id);
		$uid = $user->{uid};
		$nick = $user->{nickname};

	} elsif ( $form->{userfield_flag} eq 'nickname' ) { 
		$nick = $id;
		$uid = $slashdb->getUserUID($id);
		$user = $slashdb->getUser($uid);

	} elsif ( $form->{nick} ) {
		$nick = $form->{nick};
		$uid = $slashdb->getUserUID($nick);
		$user = $slashdb->getUser($uid);

	} else {
		$user = $curuser;
		$uid = $curuser->{uid};
		$nick = $curuser->{nickname};
	}

	$nick = $nick ? strip_literal($nick) : $user->{nickname};

	if (! defined $uid) {
		print getMessage('userinfo_nicknf_msg', { nick => $nick });
		return;
	}

	my $admin_flag = ($curuser->{seclev} >= 100) ? 1 : 0;
	my $admin_block = $admin_flag ? getUserAdmin($user->{uid}, 1, 1) : '';

	my($title, $commentstruct, $points, $lastgranted, $nickmatch_flag);
	my($mod_flag, $karma_flag, $n) = (0, 0, 0);

	$form->{min} = 0 unless $form->{min};

 	$karma_flag = 1 if $user->{seclev} || $user->{uid} == $uid;

	if ($user->{uid} == $curuser->{uid}) {
		$nickmatch_flag = 1;
		$points = $user->{points};
		if ($points) {
			$lastgranted = $slashdb->getUser($uid, 'lastgranted');
			if ($lastgranted) {
				$lastgranted = timeCalc(
					DateCalc($lastgranted,
					'+ ' . ($constants->{stir}+1) . ' days'),
					'%Y-%m-%d'
				);
			}
		}

		$mod_flag = 1 if $user->{uid} == $uid && $points > 0;
		$title = getTitle('userInfo_main_title', { nick => $nick, uid => $uid });

	} else {
		$title = getTitle('userInfo_user_title', { nick => $nick, uid => $uid });
	}

	my $comments = $slashdb->getCommentsByUID($uid, $form->{min});

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

	slashDisplay('userInfo', {
		title			=> $title,
		nick			=> $nick,
		userbio			=> $user,
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

	if ($user->{is_anon} || !length($user->{reg_id})) {
		if ($user->{is_anon}) {
			print getMessage('anon_validation_attempt');
			displayForm();
			
		} else {
			print getMessage('no_registration_needed') if !$user->{reg_id};
			userInfo($user->{uid});
		}
	# Maybe this should be taken care of in a more centralized location?
	} elsif ($user->{reg_id} eq $form->{id}) {
		# We have a user and the registration IDs match. We are happy!
		my($maxComm, $maxDays) = ($constants->{max_expiry_comm},
			$constants->{max_expiry_days} );

		my($userComm, $userDays) = ($user->{user_expiry_comm},
			$user->{user_expiry_days});		

		my $exp = $constants->{expiry_exponent};

		# Increment only the trigger that was used.
		my $new_comment_expiry = ($userComm > $maxComm) ?
			$maxComm : $userComm * (($user->{expiry_comm} < 0) ? $exp : 1);
		my $new_days_expiry = ($userDays > $maxDays) ?
			$maxDays : $userDays * (($user->{expiry_days} < 0) ? $exp : 1);
	
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

		if ($form->{userfield_flag} eq 'ip' || $form->{userfield_flag} eq 'subnet') {
			netIDInfo();

		} elsif ($form->{op} eq 'authoredit') {	
			editUser($form->{authoruid});

		} elsif ( $form->{userinfo}) {
			userInfo();

		} elsif ( $form->{edituser}) {
			editUser();

		} elsif ( $form->{edithome}) {
			editHome();

		} elsif ( $form->{editcomm}) {
			editComm();
		}
}

#################################################################
sub editUser {
	my($id) = @_;
	
	print STDERR "editUser id $id\n";

	my $form = getCurrentForm();
	my $slashdb = getCurrentDB;	
	my $curuser = getCurrentUser();
	my $constants = getCurrentStatic();


	return if $curuser->{is_anon};

	if (! $id) {
		$id = $form->{userfield} ? $form->{userfield} : getCurrentUser('uid');	
	}

	my $uid;
	my $user = {};
	my ($admin_block, $title);

	if ($form->{userfield_flag} eq 'nickname') {
		$uid = $slashdb->getUserUID($id);
		$user = $slashdb->getUser($uid);

	} elsif ($form->{userfield_flag} eq 'uid') {
		$uid = $id;
		$user = $slashdb->getUser($uid);

	} else {
		$user = $slashdb->getUser($id); 
	}

	return if $user->{is_anon} && $curuser->{seclev} < 100;

	$user->{homepage} ||= "http://";

	return if isAnon($user->{uid});

	print getMessage('note', { note => $form->{note}}) if $form->{note};	

	$title = getTitle('editUser_title', { user_edit => $user});

	my $tempnick = fixparam($user->{nickname});
	my $temppass = fixparam($user->{passwd});

	my $description = $slashdb->getDescriptions('maillist');
	my $maillist = createSelect('maillist', $description, $user->{maillist}, 1);

	my $session = $slashdb->getDescriptions('session_login');
	my $session_select = createSelect('session_login', $session, $user->{session_login}, 1);

	my $admin_flag = ($curuser->{seclev} >= 100) ? 1 : 0; 

	$admin_block = getUserAdmin($user->{uid}, 0, 1) if $admin_flag;

	slashDisplay('editUser', {
		user_edit 		=> $user,
		admin_flag		=> $admin_flag,
		title			=> $title,
		editkey 		=> editKey($user->{uid}),
		maillist 		=> $maillist,
		session 		=> $session_select,
		admin_block		=> $admin_block
	});
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
sub editHome {
	my($uid) = @_;

	my $slashdb = getCurrentDB();
	my $form = getCurrentForm();	
	my $curuser = getCurrentUser();

	my($formats, $title, $tzformat_select, $tzcode_select);
	my $user = {};

	return if $curuser->{is_anon};

	if (! $uid) {
		$uid = $form->{userfield} ? $form->{userfield} : getCurrentUser('uid');	
	}

	$user = $slashdb->getUser($uid);

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
	my($uid) = @_;

	my $slashdb = getCurrentDB();
	my $form = getCurrentForm();	
	my $curuser = getCurrentUser();

	if (! $uid) {
		$uid = $form->{userfield} ? $form->{userfield} : $curuser->{uid};	
	}

	return if isAnon($curuser->{uid});

	my($formats, $commentmodes_select, $commentsort_select,
		$uthreshold_select, $highlightthresh_select, $posttype_select);

	my $user = $slashdb->getUser($uid);
	my $title = getTitle('editComm_title');

	$formats = $slashdb->getDescriptions('commentmodes');
	$commentmodes_select = createSelect('umode', $formats, $user->{mode}, 1);

	$formats = $slashdb->getDescriptions('sortcodes');
	$commentsort_select = createSelect('commentsort', $formats, $user->{commentsort}, 1);

	$formats = $slashdb->getDescriptions('threshcodes');
	$uthreshold_select = createSelect('uthreshold', $formats, $user->{threshold}, 1);

	$formats = $slashdb->getDescriptions('threshcodes');
	$highlightthresh_select = createSelect('highlightthresh', $formats, $user->{highlightthresh}, 1);

	my $h_check = $user->{hardthresh}	? ' CHECKED' : '';
	my $r_check = $user->{reparent}	? ' CHECKED' : '';
	my $n_check = $user->{noscores}	? ' CHECKED' : '';
	my $s_check = $user->{nosigs}	? ' CHECKED' : '';

	$formats = $slashdb->getDescriptions('postmodes');
	$posttype_select = createSelect('posttype', $formats, $user->{posttype}, 1);

	slashDisplay('editComm', {
		title			=> $title,
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

	my $id = $curuser->{seclev} >= 100 ? shift : $curuser->{uid};
	if (! $id) {
		$id = $form->{userfield} ? $form->{userfield} : $curuser->{uid};	
	}

	my $edituser = {};
	my $save_success = 0;
	my $note = '';

	if($form->{userfield_flag} eq 'uid') {
		if ($id =~ /^\d+$/) {
			$edituser = $slashdb->getUser($id);
		} else {
			$note .= getMessage('saveuseradmin_uid_notnumeric', { field => $form->{userfield}, id => $id });
		}
	}
	elsif($form->{userfield_flag} eq 'nickname') {
		$edituser = $slashdb->getUser(getUserUID($id));
	}
	elsif($form->{userfield_flag} eq 'ip') {
		$edituser->{uid} = $constants->{anonymous_coward_uid};
		$id = $id =~ /^\d+\.\d+\.\d+\.?\d+?$/ ? md5_hex($id) : $id;
		$edituser->{ipid} = $id;
	}
	elsif($form->{userfield_flag} eq 'subnet') {
		if ( $id =~ /^(\d+\.\d+\.\d+\.)\.?\d+?/) {
			$id = $1 . ".0";
			$edituser->{subnetid} = md5_hex($id);
		} else {
			$edituser->{subnetid} = $id;
		}
		$edituser->{uid} = $constants->{anonymous_coward_uid};
		$edituser->{subnetid} = $id;
	} else { # a bit redundant, I know
		$edituser = $curuser;
	}

	my($author_flag);
	my $users_table = {};

	for my $formname ( 'comments', 'submit') {
		my $keyname = "readonly_" . $formname;
		my $reason_keyname = $formname . "_ro_reason";
		$form->{$keyname} = $form->{$keyname} eq 'on' ? 1 : 0 ;

		$form->{$reason_keyname} ||= '';

		if ( ($slashdb->setReadOnly($formname, $edituser, $form->{$keyname}, $form->{$reason_keyname})) ) {  
			$save_success++;
		} 
		# 	$note .= getMessage('saveuseradmin_notsaved', { field => $form->{userfield_flag}, id => $id });
	}

	$author_flag = $form->{author} ? 1 : 0;

	$note .= getMessage('saveuseradmin_saved', { field => $form->{userfield_flag}, id => $id} ) if $save_success;

	if ($edituser->{seclev} >= 100 && ($form->{userfield_flag} eq 'uid'  || 
		$form->{userfield_flaq} eq 'nickname') && $save_success) {

		$users_table->{seclev} = $form->{seclev}; 
		$users_table->{author} = $author_flag; 
		if (($slashdb->setUser($id, $users_table))) {
			$note .= getMessage('saveuseradmin_saveduser', { field => $form->{userfield_flag}, id => $id });
		} else {
			$note .= getMessage('saveuseradmin_notsaveduser', { field => $form->{userfield_flag}, id => $id});
		}
	}

	print getMessage('note', { note => $note } ) if defined $note;

	userInfo($id);
}

#################################################################
sub saveUser {
	my $slashdb = getCurrentDB();
	my $form = getCurrentForm();
	my $curuser = getCurrentUser();
	my $constants = getCurrentStatic();
	my $uid;
	print STDERR "saveUser\n";

	if ($curuser->{seclev} >= 100) {
		$uid = shift;
		if (! $uid ) {
			$uid = $form->{uid} ? $form->{uid} : $curuser->{uid};
		}
	} else {
		$uid = ($curuser->{uid} == $form->{uid}) ? $form->{uid} : $curuser->{uid};
	}

	return if isAnon($uid);

	my($note, $author_flag, $user_fakeemail, $formname);
	my $user = {};

	if ( $form->{userfield_flag} eq 'uid') {
		if ( $uid =~ /^\d+$/) {
			$user = $slashdb->getUser($uid);
			if ($form->{userfield} != $form->{uid}) {
				return();
			}
		} else {
			print getMessage('saveuseradmin_uid_notnumeric', { field => $form->{userfield}, id => $uid });
			return();
		}
	} elsif ( $form->{userfield_flag} eq 'nickname') {
		if (getUserUID($form->{userfield}) == $form->{uid}) {
			$user = $slashdb->getUser(getUserUID($uid));
		} else {
			return();
		}
	} else {
		$user = $slashdb->getUser($uid);
	}

	# We start with the 'Saved ...' message.
	$user->{nickname} = substr($user->{nickname}, 0, 20);

	$note = getMessage('savenickname_msg', 
	{ nickname => $user->{nickname} }, 1);

	if (!$user->{nickname}) {
		$note .= getMessage('cookiemsg', 0, 1);
	}

	$user_fakeemail = ($user->{emaildisplay} == 1) ?
		$user->{fakeemail} : getArmoredEmail($uid);

	# Check to insure that if a user is changing his email address, that
	# it doesn't already exist in the userbase.
	if ($user->{realemail} ne $form->{realemail}) {
		if ($slashdb->checkEmail($form->{realemail})) {
			$note = getMessage('emailexists_msg', 0, 1);
			return fixparam($note);
		}
	}

	for $formname ( 'comments', 'submit') {
		my $keyname = "readonly_" . $formname;
		my $reason_keyname = $formname . "_ro_reason";
		$form->{$keyname} = $form->{$keyname} eq 'on' ? 1 : 0 ;

		$form->{$reason_keyname} ||= '';

		$slashdb->setReadOnly($formname, 
					$user, 
					$form->{$keyname}, 
					$form->{$reason_keyname} 
		);

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

	delete $users_table->{passwd};
	if ($form->{pass1} eq $form->{pass2} && length($form->{pass1}) > 5) {
		$note .= getMessage('saveuser_passchanged_msg');

		$users_table->{passwd} = $form->{pass1};
		setCookie('user', bakeUserCookie($uid, encryptPassword($users_table->{passwd})));

	} elsif ($form->{pass1} ne $form->{pass2}) {
		$note .= getMessage('saveuser_passnomatch_msg');

	} elsif (length $form->{pass1} < 6 && $form->{pass1}) {
		$note .= getMessage('saveuser_passtooshort_msg');
	}

	$slashdb->setUser($uid, $users_table);

	print STDERR "note $note\n";
	print STDERR "passwd $form->{pass1} passwd2 $form->{pass2}\n";
	print STDERR "calling editUser($uid)\n";

	print getMessage('note', { note => $note } ) if defined $note;

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
		if (! $uid ) {
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
		if (! $uid ) {
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

	foreach my $k (keys %{$form}) {
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

	my($title, $title2, $msg1, $msg2) = ('','','','');

	if ($form->{op} eq 'userclose') {
		$title = getMessage('userclose');

	} else {
		$title = $form->{unickname}
			? getTitle('displayForm_err_title')
			: getTitle('displayForm_title');
	}

	$form->{unickname} ||= $form->{newusernick};

	if ($form->{newusernick}) {
		$title2 = getTitle('displayForm_dup_title');
	} else {
		$title2 = getTitle('displayForm_new_title');
	}

	$msg1 = getMessage('dispform_new_msg_1');
	$msg2 = getMessage('dispform_new_msg_2') if ! $form->{newusernick};

	slashDisplay('displayForm', {
		newnick		=> fixNickname($form->{newusernick}),
		title 		=> $title,
		title2 		=> $title2,
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

	my $edituser;

	my $checked = {};
	my $authors;

	my ($formname, $author_select ) = ('', '');

	my $authoredit_flag = ($curuser->{seclev} >= 10000) ? 1 : 0; 

	my ($readonly, $readonly_reasons) = ({},{});
	my $author_flag = '';

	if ($form->{userfield_flag} eq 'uid') {
		if ($id && $id =~ /^\d+$/ && $id != $constants->{anonymous_coward_uid}) {
			$edituser = $slashdb->getUser($id);	
		} else {
			$edituser->{nonuid} = 1;
		} 
		$edituser->{id} = $edituser->{uid};
		$checked->{uid} = ' CHECKED';
	} 
	elsif ( $form->{userfield_flag} eq 'nick') {
		$edituser = $slashdb->getUser(getUserUID($id));
		$edituser->{id} = $edituser->{nick};
		$checked->{nickname} = ' CHECKED';

	} 
	elsif( $form->{userfield_flag} eq 'ip') {
		$id = $id =~ /^\d+\.\d+\.\d+\.?\d+?$/ ? md5_hex($id) : $id;
		$edituser->{ipid} = $id;
		$edituser->{nonuid} = 1;
		$edituser->{id} = $id;
		$checked->{ip} = ' CHECKED';
	}	
	elsif( $form->{userfield_flag} eq 'subnet') {
		if ( $id =~ /^(\d+\.\d+\.\d+\.)\.?\d+?/) {
			$id = $1 . ".0";
			$edituser->{subnetid} = md5_hex($id);
		} else {
			$edituser->{subnetid} = $id;
		}

		$edituser->{nonuid} = 1;
		$edituser->{id} = $id;
		$checked->{subnet} = ' CHECKED';
	} else {	
		$edituser = getCurrentUser();
		$edituser->{id} = $edituser->{uid};
		$checked->{uid} = ' CHECKED';
	}

	$authors = $slashdb->getDescriptions('authors');

	$author_select = createSelect('authoruid', $authors, $edituser->{uid}, 1) if $authoredit_flag;
	$author_select =~ s/\s{2,}//g;

	for $formname ('comments', 'submit') {
		$readonly->{$formname} = $slashdb->checkReadOnly($formname, $edituser) ? ' CHECKED' : '';
		$readonly_reasons->{$formname} = $slashdb->getReadOnlyReason($formname, $edituser);
	}

	$author_flag = ($edituser->{author} == 1) ? ' CHECKED' : ''; 

	return slashDisplay('getUserAdmin', {
		edituser		=> $edituser,
		seclev_field		=> $seclev_field,
		checked 		=> $checked,
		author_select		=> $author_select,
		author_flag 		=> $author_flag,
		form_flag		=> $form_flag,
		readonly		=> $readonly,
		readonly_reasons 	=> $readonly_reasons,
		authoredit_flag 	=> $authoredit_flag }, 
		1 
	);
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
