#!/usr/bin/perl -w

###############################################################################
# users.pl - this code is for user creation and  administration 
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
use Slash;
use Slash::DB;
use Slash::Display;
use Slash::Utility;

#################################################################
sub main {
	getSlash();
	my $slashdb = getCurrentDB();
	my $user = getCurrentUser();
	my $form = getCurrentForm();
	my $constants = getCurrentStatic();

	my ($rootdir) = $constants->{rootdir};

	my $op = $form->{op};

	if ($op eq "userlogin" && !$user->{is_anon}) {
		my $refer = $form->{returnto} || $constants->{rootdir};
		redirect($refer);
		return;
	} elsif ($op eq "saveuser") {
		my $note = saveUser($user->{uid});
		redirect($ENV{SCRIPT_NAME} . "?op=edituser&note=$note");
		return;
	}

	my $note;
	if ($form->{note}) {
		for (split /\n+/, $form->{note}) {
			$note .= sprintf "<H2>%s</H2>\n", stripByMode($_, 'literal');
		}
	}

	my $sitename = getCurrentStatic('sitename');
	header("$sitename Users");

	if (!$user->{is_anon} && $op ne 'userclose') {
		print createMenu('users');
	}
	# and now the carnage begins
	if ($op eq "newuser") {
		newUser();

	} elsif ($op eq "edituser") {
		# the users_prefs table
		if (!$user->{is_anon}) {
			editUser($user->{uid});
		} else {
			displayForm(); 
		}

	} elsif ($op eq "edithome" || $op eq "preferences") {
		# also known as the user_index table
		if (!$user->{is_anon}) {
			editHome($user->{uid});
		} else {
			displayForm(); 
		}

	} elsif ($op eq "editcomm") {
		# also known as the user_comments table
		if (!$user->{is_anon}) {
			editComm($user->{uid});
		} else {
			displayForm(); 
		}

	} elsif ($op eq "userinfo" || !$op) {
		if ($form->{nick}) {
			userInfo($slashdb->getUserUID($form->{nick}), $form->{nick});
		} elsif ($user->{is_anon}) {
			displayForm();
		} else {
			userInfo($user->{uid}, $user->{nickname});
		}

	} elsif ($op eq "savecomm") {
		saveComm($user->{uid});
		userInfo($user->{uid}, $user->{nickname});

	} elsif ($op eq "savehome") {
		saveHome($user->{uid});
		userInfo($user->{uid}, $user->{nickname});

	} elsif ($op eq "sendpw") {
		mailPassword($user->{uid});

	} elsif ($op eq "mailpasswd") {
		mailPassword($slashdb->getUserUID($form->{unickname}));

	} elsif ($op eq "suedituser" && $user->{aseclev} > 100) {
		editUser($slashdb->getUserUID($form->{name}));

	} elsif ($op eq "susaveuser" && $user->{aseclev} > 100) {
		saveUser($form->{uid}); 

	} elsif ($op eq "sudeluser" && $user->{aseclev} > 100) {
		delUser($form->{uid});

	} elsif ($op eq "userclose") {
		print "ok bubbye now.";
		displayForm();

	} elsif ($op eq "userlogin" && !$user->{is_anon}) {
		userInfo($user->{uid}, $user->{nickname});

	} elsif ($op eq "preview") {
		previewSlashbox();

	} elsif (!$user->{is_anon}) {
		userInfo($slashdb->getUserUID($form->{nick}), $form->{nick});

	} else {
		displayForm();
	}

	miniAdminMenu() if $user->{aseclev} > 100;
	$slashdb->writeLog("users", $user->{nickname});

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
		my $msg = getMessage('checklist_msg');
		# print "You selected too many options<BR>";
		print $msg;
		$string = substr($string, 0, 255);
		$string =~ s/,'??\w*?$//g;
	} elsif (length $string < 3) {
		$string = "";
	}

	return $string;
}

#################################################################
sub previewSlashbox {
	my $slashdb = getCurrentDB();
	my $user = getCurrentUser();
	my $form = getCurrentForm();
	my $constants = getCurrentStatic();

	my $section = $slashdb->getSection($form->{bid});
	my $cleantitle = $section->{title};
	$cleantitle =~ s/<(.*?)>//g;

	my $is_editable = 1 if $user->{aseclev} > 999;

	my $title = getTitle('previewslashbox_title',{ cleantitle => $cleantitle });
	slashDisplay('users-previewSlashbox', {
		width		=> '100%',
		title		=> $title,
		cleantitle 	=> $cleantitle,
		is_editable	=> $is_editable,
		
	});

	print portalbox($constants->{fancyboxwidth}, $section->{title},
		$section->{content}, "", $section->{url});
}

#################################################################
sub miniAdminMenu {
	slashDisplay('users-miniAdminMenu');
}

#################################################################
sub newUser {

	my $slashdb = getCurrentDB();
	my $form = getCurrentForm();

	my $title = "";

	# Check if User Exists
	$form->{newuser} =~ s/\s+/ /g;
	$form->{newuser} =~ s/[^ a-zA-Z0-9\$_.+!*'(),-]+//g;
	$form->{newuser} = substr($form->{newuser}, 0, 20);

	(my $matchname = lc $form->{newuser}) =~ s/[^a-zA-Z0-9]//g;


	if ($matchname ne '' && $form->{newuser} ne '' && $form->{email} =~ /\@/) {
		my $uid;
		my $rootdir = getCurrentStatic('rootdir','value');
		if ($uid = $slashdb->createUser($matchname, $form->{email}, $form->{newuser})) {
			$title = getTitle('newUser_title');

			$form->{pubkey} = stripByMode($form->{pubkey}, "html");
			my $newuser_msg = getMessage('newuser_msg', {title => $title});
			print $newuser_msg;
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
	my $user = getCurrentUser();

	my $user_email = $slashdb->getUser($uid, ['nickname','realemail']);

	unless ($uid) {
		print getMessage('mailpasswd_notmailed_msg');
		return;
	}

	my $newpasswd = $slashdb->getNewPasswd($uid);
	my $tempnick = fixparam($user_email->{nickname});

	my $emailtitle = getTitle('mailPassword_email_title',{nickname => $user_email->{nickname}},1);

	my $msg = getMessage('mailpasswd_msg',{newpasswd => $newpasswd, tempnick => $tempnick},1);

	sendEmail($user_email->{realemail}, $emailtitle, $msg) if $user_email->{nickname};
	print getMessage('mailpasswd_mailed_msg', {name => $user_email->{nickname}});
}

#################################################################
sub userInfo {
	my($uid, $nick) = @_;

	if (! defined $uid) {
		print getMessage('userinfo_nicknf_msg', { nick => $nick });
		return;
	}

	my $slashdb = getCurrentDB();
	my $form = getCurrentForm();
	my $user = getCurrentUser();
	my $constants = getCurrentStatic();

	my $userbio = $slashdb->getUser($uid);

	$userbio->{bio} = stripByMode($userbio->{bio}, "html");

	my $title = "";
	my $commentstruct = {};
	my ($question, $points, $nickmatch_flag,$rows);
	my ($mod_flag,$karma_flag,$n) = (0,0,0);

	$form->{min} = 0 unless $form->{min};

 	$karma_flag = 1 if ($userbio->{aseclev} || $userbio->{uidbio} == $uid) ; 

	my $public_key = $userbio->{pubkey};
	if($public_key) {
		$public_key = stripByMode($public_key, "html");
	}


	if ($userbio->{nickname} eq $nick) {
		$nickmatch_flag = 1;
		$points = $userbio->{points};

		$title = getTitle('userInfo_main_title',{ nick => $nick, uid => $uid});

		$mod_flag = 1 if ($userbio->{uid} == $uid && $points > 0) ; 

		$title = getTitle('userinfo_user_title',{ nick => $nick, uid => $uid});
	}

	# my $comments = $slashdb->getUserComments($uid, $form->{min}, $userbio);
	my $comments = $slashdb->getCommentsByUID($uid, $form->{min}, $userbio);
	$rows = @$comments;

	for (@$comments) {
		my($pid, $sid, $cid, $subj, $cdate, $pts) = @$_;

		my $replies = $slashdb->countComments($sid, $cid);

		# This is ok, since with all luck we will not be hitting the DB
		my $story = $slashdb->getStory($sid);

		if ($story) {
			my $href = $story->{writestatus} == 10
				? "$constants->{rootdir}/$story->{section}/$sid.shtml"
				: "$constants->{rootdir}/article.pl?sid=$sid";

		} else {
			$question = $slashdb->getPollQuestion($sid, 'question');
		}

		$commentstruct->[$n] = {
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

		$n++;
	}

	slashDisplay('users-userInfo',{
		title			=> $title,
		uid			=> $uid,
		nick			=> $nick,
		fakeemail		=> $userbio->{fakeemail},
		homepage		=> $userbio->{homepage},
		bio			=> $userbio->{bio},
		points			=> $points,
		public_key		=> $public_key,
		rows			=> $rows,
		commentstruct		=> $commentstruct,
		nickmatch_flag		=> $nickmatch_flag,
		mod_flag		=> $mod_flag,
		karma_flag		=> $karma_flag,
	} );
}

#################################################################
sub editKey {
	my($uid) = @_;

	my $slashdb = getCurrentDB();

	my $user = $slashdb->getUser($uid, ['pubkey']);

	my $key = stripByMode($user->{key}, 'literal');
	my $editkey = slashDisplay('users-editKey',{ key => $key }, 1);	
	return $editkey;
}

#################################################################
sub editUser {
	my($uid) = @_;

	my $slashdb = getCurrentDB();

	my @values = qw(
		realname realemail fakeemail homepage nickname
		passwd sig seclev bio maillist
	);

	my $user_edit = $slashdb->getUser($uid, \@values);

	$user_edit->{uid} = $uid;
	$user_edit->{homepage} ||= "http://";

	return if isAnon($user_edit->{uid});

	my $title = getTitle('editUser_title',{ user_edit => $user_edit });

	my $tempnick = fixparam($user_edit->{nickname});
	my $temppass = fixparam($user_edit->{passwd});
 
	my $description = $slashdb->getDescriptions('maillist');
	createSelect('maillist', $description, $user_edit->{maillist});

	slashDisplay('users-editUser',{ 
			user_edit 	=> $user_edit, 
			title		=> $title,
			temppass	=> $temppass,
			tempnick	=> $tempnick,	
			bio 		=> stripByMode($user_edit->{bio}), 
			sig 		=> stripByMode($user_edit->{sig}),
			editkey 	=> editKey($user_edit->{uid}) }
	);
}

#################################################################
sub tildeEd {
	my($extid, $exsect, $exaid, $exboxes, $userspace) = @_;
	
	my $slashdb = getCurrentDB();
	my $constants = getCurrentStatic();
	my $aidref = {};
	my $tidref = {};
	my $sectionref = {};
	my $section_descref = {};
	my ($tilde_ed,$tilded_msg_box);

	# users_tilded_title
	my $title = getTitle('tildeEd_title');

	# Customizable Authors Thingee
	my $aids = $slashdb->getAuthorAids();
	my $n = 0;
	for(@$aids) {
		my ($aid) = @$_;
		$aidref->{$aid}{checked} = ($exaid =~ /'$aid'/) ? ' CHECKED' : '';
	}

	my $topics = $slashdb->getDescriptions('topics');

	while (my($tid, $alttext) = each %$topics) {
		$tidref->{$tid}{checked} = ($extid =~ /'$tid'/) ? ' CHECKED' : '';
		$tidref->{$tid}{alttext} = $alttext;
		print STDERR "topic checked $tidref->{$tid}{checked}  alttext $tidref->{$tid}{alttext}\n";
	}

	my $sections = $slashdb->getDescriptions('sections');

	while (my($section,$title) = each %$sections) {
		$sectionref->{$section}{checked} = ($exsect =~ /'$section'/) ? " CHECKED" : "";
		$sectionref->{$section}{title} = $title;
		print STDERR "section checked $sectionref->{$section}{checked} title $sectionref->{$section}{title}\n";
	}

	my $customize_title = getTitle('tildeEd_customize_title');

	$userspace = stripByMode($userspace, 'literal');

	my $tilded_customize_msg = getMessage('users_tilded_customize_msg',{ userspace => $userspace});

	my $sections_description = $slashdb->getSectionBlocks();

	$customize_title = getTitle('tildeEd_customize_title');

	for (@$sections_description) {
		my($bid, $title, $boldflag) = @$_;
		print STDERR "bid $bid title $title boldflag $boldflag\n";

		$section_descref->{$bid}{checked} = ($exboxes =~ /'$bid'/) ? " CHECKED" : "";
		$section_descref->{$bid}{srandflag} = 1 if $bid eq "srandblock";
		$section_descref->{$bid}{boldflag} = 1 if $boldflag > 0;
		$title =~ s/<(.*?)>//g;
		$section_descref->{$bid}{title} = $title;
		print STDERR "section_descref check $section_descref->{$bid}{checked} srandflag $section_descref->{$bid}{srandflag} title $section_descref->{$bid}{title} BOLDFLAG $section_descref->{$bid}{boldflag}\n";
	}

	my $tilded_box_msg = getMessage('tilded_box_msg');

	$tilde_ed = slashDisplay('users-tildeEd', { 
			title			=> $title,
			tilded_box_msg		=> $tilded_box_msg,
			aidref			=> $aidref,
			tidref			=> $tidref,
			sectionref		=> $sectionref,
			section_descref		=> $section_descref,
			userspace		=> $userspace,
			customize_title		=> $customize_title,
			}, 1
	);

	return($tilde_ed);
}

#################################################################
sub editHome {
	my($uid) = @_;

	my $slashdb = getCurrentDB();
	my $user = getCurrentUser();

	my @values = qw(
		realname realemail fakeemail homepage nickname
		passwd sig seclev bio maillist dfid tzcode maxstories
		extid exsect exaid exboxes mylinks
	);

	my $user_edit = $slashdb->getUser($uid, \@values);

	return if isAnon($user->{uid});

	my $title = getTitle('editHome_title'); 

	my $formats;
	$formats = $slashdb->getDescriptions('dateformats');
	my $tzformat_select = createSelect('tzformat', $formats, $user->{dfid}, 1);

	$formats = $slashdb->getDescriptions('tzcodes');
	my $tzcode_select = createSelect('tzcode', $formats, $user->{tzcode}, 1);

	my $l_check = $user->{light}	? " CHECKED" : "";
	my $b_check = $user->{noboxes}	? " CHECKED" : "";
	my $i_check = $user->{noicons}	? " CHECKED" : "";
	my $w_check = $user->{willing}	? " CHECKED" : "";

	my $tilde_ed = tildeEd(
		$user->{extid}, $user->{exsect},
		$user->{exaid}, $user->{exboxes}, $user->{mylinks}
	);

	slashDisplay('users-editHome', {
			title			=> $title,
			user_edit		=> $user_edit,
			tzformat_select		=> $tzformat_select,
			tzcode_select		=> $tzcode_select,
			l_check			=> $l_check,			
			b_check			=> $b_check,			
			i_check			=> $i_check,			
			w_check			=> $w_check,			
			tilde_ed		=> $tilde_ed
			}
	);

}

#################################################################
sub editComm {
	my($uid) = @_;

	my $slashdb = getCurrentDB();
	my ($formats, $commentmodes_select, $commentsort_select, $uthreshold_select, $highlightthresh_select, $posttype_select);

	my @values = qw(realname realemail fakeemail homepage nickname passwd sig seclev bio maillist);
	my $user_edit = $slashdb->getUser($uid, \@values);

	$user_edit->{uid} = $uid;

	my $title = getTitle('editComm_title');

	$formats = $slashdb->getDescriptions('commentmodes');
	$commentmodes_select = createSelect('umode', $formats, $user_edit->{mode}, 1);

	$formats = $slashdb->getDescriptions('sortcodes');
	$commentsort_select = createSelect('commentsort', $formats, $user_edit->{commentsort}, 1);

	$formats = $slashdb->getDescriptions('threshcodes');
	$uthreshold_select = createSelect('uthreshold', $formats, $user_edit->{threshold}, 1);

	$formats = $slashdb->getDescriptions('threshcodes');
	$highlightthresh_select = createSelect('highlightthresh', $formats, $user_edit->{highlightthresh}, 1);

	my $h_check = $user_edit->{hardthresh}	? " CHECKED" : "";
	my $r_check = $user_edit->{reparent}	? " CHECKED" : "";
	my $n_check = $user_edit->{noscores}	? " CHECKED" : "";
	my $s_check = $user_edit->{nosigs}	? " CHECKED" : "";

	$formats = $slashdb->getDescriptions('postmodes');
	$posttype_select = createSelect('posttype', $formats, $user_edit->{posttype}, 1);

	slashDisplay('users-editComm', {
			title			=> $title,
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
			}
	);

}

#################################################################
sub saveUser {
	my $slashdb = getCurrentDB();
	my $form = getCurrentForm();
	my $user = getCurrentUser();
	my $constants = getCurrentStatic();

	my $uid = $user->{aseclev} ? shift : $user->{uid};
	my $user_email  = $slashdb->getUser($uid, ['nickname', 'realemail']);
	my $note;

	$user_email->{nickname} = substr($user_email->{nickname}, 0, 20);
	return if isAnon($uid);

	$note = getMessage('savenickname_msg',{ nickname => $user_email->{nickname}},1);

	if(! $user_email->{nickname}) {
		$note .= getMessage('cookiemsg',{},1);
	}

	# stripByMode _after_ fitting sig into schema, 120 chars
	$form->{sig}	 	= stripByMode(substr($form->{sig}, 0, 120), 'html');
	$form->{fakeemail} 	= chopEntity(stripByMode($form->{fakeemail}, 'attribute'), 50);
	$form->{homepage}	= "" if $form->{homepage} eq "http://";
	$form->{homepage}	= fixurl($form->{homepage});

	# for the users table
	my $users_table = {
		sig		=> $form->{sig},
		homepage	=> $form->{homepage},
		fakeemail	=> $form->{fakeemail},
		maillist	=> $form->{maillist},
		realname	=> $form->{realname},
		bio		=> $form->{bio},
		pubkey		=> $form->{pubkey}
	};

	if ($user_email->{realemail} ne $form->{realemail}) {
		$users_table->{realemail} = chopEntity(stripByMode($form->{realemail}, 'attribute'), 50);

		$note .= getMessage('changeemail_msg',{ realemail => $user_email->{realemail}},1);

		my $saveuser_emailtitle = getTitle('saveUser_email_title', {nickname => $user_email->{nickname}},1);
		my $saveuser_email_msg = getMessage('saveuser_email_msg',{ nickname => $user_email->{nickname} },1);
		sendEmail($user_email->{realemail}, $saveuser_emailtitle, $saveuser_email_msg);
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

	return fixparam($note);
}

#################################################################
sub saveComm {
	my $user = getCurrentUser();
	my $form = getCurrentForm();

	my $uid  = $user->{aseclev} ? shift : $user->{uid};
	my $name = $user->{aseclev} && $form->{name} ? $form->{name} : $user->{nickname};

	my $slashdb = getCurrentDB();

	$name = substr($name, 0, 20);
	return if isAnon($uid);

	my $savename = getMessage('savename_msg', {name => $name});
	print $savename;

	if (isAnon($uid) || !$name) {
		my $cookiemsg = getMessage('cookiemsg');
		print $cookiemsg;
	}

	# Take care of the lists
	# Enforce Ranges for variables that need it
	$form->{commentlimit} = 0 if $form->{commentlimit} < 1;
	$form->{commentspill} = 0 if $form->{commentspill} < 1;

	# for users_comments
	my $users_comments_table = {
		clbig		=> $form->{clbig},
		clsmall		=> $form->{clsmall},
		mode		=> $form->{umode},
		posttype	=> $form->{posttype},
		commentsort	=> $form->{commentsort},
		threshold	=> $form->{uthreshold},
		commentlimit	=> $form->{commentlimit},
		commentspill	=> $form->{commentspill},
		maxcommentsize	=> $form->{maxcommentsize},
		highlightthresh	=> $form->{highlightthresh},
		nosigs		=> ($form->{nosigs}     ? 1 : 0),
		reparent	=> ($form->{reparent}   ? 1 : 0),
		noscores	=> ($form->{noscores}   ? 1 : 0),
		hardthresh	=> ($form->{hardthresh} ? 1 : 0),
	};

	# Update users with the $users_comments_table hash ref 
	$slashdb->setUser($uid, $users_comments_table);
}

#################################################################
sub saveHome {
	my $user = getCurrentUser();
	my $form = getCurrentForm();

	my $uid  = $user->{aseclev} ? shift : $user->{uid};
	my $name = $user->{aseclev} && $form->{name} ? $form->{name} : $user->{nickname};

	my $slashdb = getCurrentDB();

	$name = substr($name, 0, 20);
	return if isAnon($uid);

	# users_cookiemsg
	if (isAnon($uid) || !$name) {
		my $cookiemsg = getMessage('cookiemsg');
		print $cookiemsg;
	}

	my($extid, $exaid, $exsect) = "";
	my $exboxes = $slashdb->getUser($uid, ['exboxes']);

	$exboxes =~ s/'//g;
	my @b = split m/,/, $exboxes;

	foreach (@b) {
		$_ = "" unless $form->{"exboxes_$_"};
	}

	$exboxes = sprintf "'%s',", join "','", @b;
	$exboxes =~ s/'',//g;

	foreach my $k (keys %{$form}) {
		if ($k =~ /^extid_(.*)/)	{ $extid  .= "'$1'," }
		if ($k =~ /^exaid_(.*)/)	{ $exaid  .= "'$1'," }
		if ($k =~ /^exsect_(.*)/)	{ $exsect .="'$1',"  }
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

	$users_index_table->{mylinks} = $form->{mylinks} if $form->{mylinks};

	# If a user is unwilling to moderate, we should cancel all points, lest
	# they be preserved when they shouldn't be.
	my $users_comments = { points => 0 };
	unless (isAnon($uid)) {
		$slashdb->setUser($uid, $users_comments)
			unless $form->{willing};
	}

	# Update users with the $H thing we've been playing with for this whole damn sub
	$slashdb->setUser($uid, $users_index_table);
}

#################################################################
sub displayForm {

	my $user = getCurrentUser();
	my $form = getCurrentForm();
	my $slashdb = getCurrentDB();
	my $constants = getCurrentStatic();
	my $allow_anonymous = $constants->{allow_anonymous};

	my ($title,$title2) = ('','');

	$title = $form->{unickname}? getTitle('displayForm_err_title') : getTitle('displayForm_title');

	$form->{unickname} ||= $form->{newuser};

	if($form->{newuser}) {
		$title2 = getTitle('displayForm_dup_title');
	} else {
		$title2 = getTitle('displayForm_new_title');
	}

	my $msg = getMessage('dispform_new_msg_1');

	$msg .= getMessage('dispform_new_msg_2') if ! $form->{newuser};

	slashDisplay('users-displayForm', {
			title 		=> $title,
			title2 		=> $title2,
			msg 		=> $msg
		}
	);
}

#################################################################
# this groups all the messages together in
# one template, called "users-messages"
sub getMessage {
	my($value, $hashref,$nocomm) = @_;
	$hashref ||= {};
	$hashref->{value} = $value;
	return slashDisplay('users-messages', $hashref, 1, $nocomm);
}
#################################################################
# this groups all the titles together in
# one template, called "users-titles"
sub getTitle {
	my($value, $hashref,$nocomm) = @_;
	$hashref ||= {};
	$hashref->{value} = $value;
	return slashDisplay('users-titles', $hashref, 1, $nocomm);
}

main();

1;
