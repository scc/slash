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
use vars '%I';
use Slash;
use Slash::DB;
use Slash::Utility;

#################################################################
sub main {
	*I = getSlashConf();
	getSlash();
	my $user = getCurrentUser();

	my $op = $I{F}{op};
print STDERR "OP $I{F}{op}\n";

	if ($op eq "userlogin" && !$user->{is_anon}) {
		my $refer = $I{F}{returnto} || $I{rootdir};
		redirect($refer);
		return;
	} elsif ($op eq "saveuser") {
		my $note = saveUser($I{U}{uid});
		redirect($ENV{SCRIPT_NAME} . "?op=edituser&note=$note");
		return;
	}

	my $note;
	if ($I{F}{note}) {
		for (split /\n+/, $I{F}{note}) {
			$note .= sprintf "<H2>%s</H2>\n", stripByMode($_, 'literal');
		}
	}

	header("$I{sitename} Users");

	if (!$user->{is_anon} && $op ne "userclose") {
		my $menu = getCurrentMenu('user');
		createMenu($menu);
	}
	# and now the carnage begins
	if ($op eq "newuser") {
		newUser();

	} elsif ($op eq "edituser") {
		# the users_prefs table
		if (!$user->{is_anon}) {
			editUser($I{U}{uid});
		} else {
			displayForm(); 
		}

	} elsif ($op eq "edithome" || $op eq "preferences") {
		# also known as the user_index table
		if (!$user->{is_anon}) {
			editHome($I{U}{uid});
		} else {
			displayForm(); 
		}

	} elsif ($op eq "editcomm") {
		# also known as the user_comments table
		if (!$user->{is_anon}) {
			editComm($I{U}{uid});
		} else {
			displayForm(); 
		}

	} elsif ($op eq "userinfo" || !$op) {
		if ($I{F}{nick}) {
			userInfo($I{dbobject}->getUserUID($I{F}{nick}), $I{F}{nick});
		} elsif ($user->{is_anon}) {
			displayForm();
		} else {
			userInfo($I{U}{uid}, $I{U}{nickname});
		}

	} elsif ($op eq "savecomm") {
		saveComm($I{U}{uid});
		userInfo($I{U}{uid}, $I{U}{nickname});

	} elsif ($op eq "savehome") {
		saveHome($I{U}{uid});
		userInfo($I{U}{uid}, $I{U}{nickname});

	} elsif ($op eq "sendpw") {
		mailPassword($I{U}{uid});

	} elsif ($op eq "mailpasswd") {
		mailPassword($I{dbobject}->getUserUID($I{F}{unickname}));

	} elsif ($op eq "suedituser" && $I{U}{aseclev} > 100) {
		editUser($I{dbobject}->getUserUID($I{F}{name}));

	} elsif ($op eq "susaveuser" && $I{U}{aseclev} > 100) {
		saveUser($I{F}{uid}); 

	} elsif ($op eq "sudeluser" && $I{U}{aseclev} > 100) {
		delUser($I{F}{uid});

	} elsif ($op eq "userclose") {
		print "ok bubbye now.";
		displayForm();

	} elsif ($op eq "userlogin" && !$user->{is_anon}) {
		userInfo($I{U}{uid}, $I{U}{nickname});

	} elsif ($op eq "preview") {
		previewSlashbox();

	} elsif (!$user->{is_anon}) {
		userInfo($I{dbobject}->getUserUID($I{F}{nick}), $I{F}{nick});

	} else {
		displayForm();
	}

	miniAdminMenu() if $I{U}{aseclev} > 100;
	writeLog("users", $I{U}{nickname});
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
		print "You selected too many options<BR>";
		$string = substr($string, 0, 255);
		$string =~ s/,'??\w*?$//g;
	} elsif (length $string < 3) {
		$string = "";
	}

	return $string;
}

#################################################################
sub previewSlashbox {
	my $section = $I{dbobject}->getSection($I{F}{bid});
	my $cleantitle = $section->{'title'};
	$cleantitle =~ s/<(.*?)>//g;

	my $title = eval prepBlock $I{dbobject}->getBlock('users_previewslashbox_title','block');
	titlebar("100%",$title);
	my $preview = eval prepBlock $I{dbobject}->getBlock('users_preview_slashbox','block');
	print $preview;
	if ($I{U}{aseclev} > 999) {
		my $url = eval prepBlock $I{dbobject}->getBlock('users_preview_slashbox_edit','block');
		print $url;
	}
	my $tdtag = $I{dbobject}->getBlock('users_preview_slashbox_tdt','block');
	print $tdtag;

	print portalbox($I{fancyboxwidth}, $section->{'title'},
		$section->{'content'}, "", $section->{'url'});
}

#################################################################
sub miniAdminMenu {
# userpage_miniadminmenu
	my $miniadminmenu = eval prepBlock $I{dbobject}->getBlock('users_miniadminmenu','block');
	print $miniadminmenu;
}

#################################################################
sub newUser {
	# Check if User Exists

	$I{F}{newuser} =~ s/\s+/ /g;
	$I{F}{newuser} =~ s/[^ a-zA-Z0-9\$_.+!*'(),-]+//g;
	$I{F}{newuser} = substr($I{F}{newuser}, 0, 20);

	(my $matchname = lc $I{F}{newuser}) =~ s/[^a-zA-Z0-9]//g;


	if ($matchname ne '' && $I{F}{newuser} ne '' && $I{F}{email} =~ /\@/) {
		my $uid;
		if ($uid = $I{dbobject}->createUser($matchname, $I{F}{email}, $I{F}{newuser})) {
			titlebar("100%", "User $I{F}{newuser} created.");

			$I{F}{pubkey} = stripByMode($I{F}{pubkey}, "html");
			my $newusermsg = eval prepBlock $I{dbobject}->getBlock('users_newusermsg','block');
			print $newusermsg;
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
	unless ($uid) {
		my $msg = $I{dbobject}->getBlock('users_mailpasswd_notmailed','block');
		print $msg;
		return;
	}

	my $user_email = $I{dbobject}->getUser($uid, qw(nickname realemail));
	my $newpasswd = $I{dbobject}->getNewPasswd($uid);
	my $tempnick = fixparam($user_email->{nickname});

	my $msg = eval prepBlock $I{dbobject}->getBlock('users_mailpasswdmsg','block');

	my $emailtitle = eval prepBlock $I{dbobject}->getBlock('users_mailpasswd_emailtitle','block');
	sendEmail($user_email->{realemail}, $emailtitle, $msg) if $user_email->{nickname};
	my $mailed = eval prepBlock $I{dbobject}->getBlock('users_mailpasswd_mailed','block');
	print $mailed;
}

#################################################################
sub userInfo {
	my($uid, $nick) = @_;
	unless (defined $uid) {
		my $msg = eval prepBlock $I{dbobject}->getBlock('userpage_userinfo_nicknf','block');
		print $msg;
		return;
	}

	my @values = qw(homepage fakeemail bio seclev karma nickname);
	my $userbio = $I{dbobject}->getUser($uid, \@values);

	$userbio->{'bio'} = stripByMode($userbio->{'bio'}, "html");
	if ($I{U}{nickname} eq $nick) {
		my $points = $I{dbobject}->getUser($uid, 'points');

		my $title = eval prepBlock $I{dbobject}->getBlock('users_userinfo_maintitle','block');
		titlebar("95%", $title);

		my $userinfo_msg = $I{dbobject}->getBlock('users_userinfo_msg','block');
		print $userinfo_msg;

		# Users should be able to see their own points.
		if ($I{U}{uid} == $uid && $points > 0) {
			my $userinfo_modmsg = eval prepBlock $I{dbobject}->getBlock('users_userinfo_modmsg','block');
			print $userinfo_modmsg;
		}

		my $userinfo_grndot= eval prepBlock $I{dbobject}->getBlock('users_userinfo_grndot','block');
		print $userinfo_grndot;

	} else {
		my $userinfo_usertitle = eval prepBlock $I{dbobject}->getBlock('users_userinfo_usertitle','block');
		titlebar("95%", $userinfo_usertitle);
	}

		my $userinfo_homepage = eval prepBlock $I{dbobject}->getBlock('users_userinfo_homepage','block');
		print $userinfo_homepage;
	if ($I{U}{aseclev} || $I{U}{uid} == $uid) { 
		my $userinfo_karma = eval prepBlock $I{dbobject}->getBlock('users_userinfo_karma','block');
		print $userinfo_karma;
	}	
	if ($userbio->{'bio'}) {
		my $userinfo_bio = eval prepBlock $I{dbobject}->getBlock('users_userinfo_bio','block');
		print $userinfo_bio;
	}

	my($k) = $I{dbobject}->getUser($uid, 'pubkey');

	if($k) {
		$k = stripByMode($k, "html");
		my $userinfo_pubkey = eval prepBlock $I{dbobject}->getBlock('users_userinfo_pubkey','block');
		print $userinfo_pubkey;
	}

	$I{F}{min} = 0 unless $I{F}{min};

	my $comments = $I{dbobject}->getUserComments($uid, $I{F}{min}, $I{U});

	my $rows = @$comments;

	my $userinfo_posted = eval prepBlock $I{dbobject}->getBlock('users_userinfo_posted','block');
	print $userinfo_posted;

	my $x;
	for (@$comments) {
		my($pid, $sid, $cid, $subj, $cdate, $pts) = @$_;
		$x++;
		my $r = $I{dbobject}->countComments($sid, $cid);

		my $replies = '';
		if($r) {
			$replies = eval prepBlock $I{dbobject}->getBlock('users_userinfo_replies','block');
		}

		# userpage_userinfo_score
		my $userinfo_score = eval prepBlock $I{dbobject}->getBlock('users_userinfo_score','block');
		print $userinfo_score;

		# This is ok, since with all luck we will not be hitting the DB
		my $story = $I{dbobject}->getStory($sid);

		if ($story) {
			my $href = $story->{writestatus} == 10
				? "$I{rootdir}/$story->{section}/$sid.shtml"
				: "$I{rootdir}/article.pl?sid=$sid";

			# userpage_userinfo_story
			my $userinfo_story = eval prepBlock $I{dbobject}->getBlock('users_userinfo_story','block');
			print $userinfo_story;
		} else {
			# userpage_userinfo_poll
			my $question = $I{dbobject}->getPollQuestion($sid, 'question');
			if($question) {
				my $userinfo_poll = eval prepBlock $I{dbobject}->getBlock('users_userinfo_poll','block');
				print $userinfo_poll;
			}	
		}
	}
}

#################################################################
sub editKey {
	my($uid) = @_;

	my $k = $I{dbobject}->getUser($uid, 'pubkey');

	# users_editkey (static)
	my $editkey = $I{dbobject}->getBlock('users_editkey','block');
	printf $editkey,stripByMode($k, 'literal');
}

#################################################################
sub editUser {
	my($uid) = @_;

	my @values = qw(
		realname realemail fakeemail homepage nickname
		passwd sig seclev bio maillist
	);
	my $user_edit = $I{dbobject}->getUser($uid, \@values);
	$user_edit->{uid} = $uid;

	return if isAnon($user_edit->{uid});

	my $edituser_title = eval prepBlock $I{dbobject}->getBlock('users_edituser_title','block');
	titlebar("100%", $edituser_title);

	my $edituser_table= eval prepBlock $I{dbobject}->getBlock('users_edituser_table','block');
	print $edituser_table;

	$user_edit->{homepage} ||= "http://";
 
	my $tempnick = fixparam($user_edit->{nickname});
	my $temppass = fixparam($user_edit->{passwd});
 
	my $edituser_mainform = eval prepBlock $I{dbobject}->getBlock('users_edituser_mainform','block');
	print $edituser_mainform;

	my $description = $I{dbobject}->getDescriptions('maillist');
	createSelect('maillist', $description, $user_edit->{maillist});

	# users_edituser_sigbio
	my $edituser_sigbio = $I{dbobject}->getBlock('users_edituser_sigbio','block');
	printf $edituser_sigbio, stripByMode($user_edit->{sig}, 'literal'), stripByMode($user_edit->{bio}, 'literal');

	editKey($user_edit->{uid});

	my $edituser_passwd = $I{dbobject}->getBlock('users_edituser_passwd','block');
	print $edituser_passwd; 
}

#################################################################
sub tildeEd {
	my($extid, $exsect, $exaid, $exboxes, $userspace) = @_;
	
	# users_tilded_title
	my $tilded_title = $I{dbobject}->getBlock('users_tilded_title','block');
	titlebar("100%", $tilded_title);

	my $tilded_menu = eval prepBlock $I{dbobject}->getBlock('users_tilded_menu','block');
	print $tilded_menu;

	# Customizable Authors Thingee
	my $tilded_exaid_code = prepBlock $I{dbobject}->getBlock('users_tilded_exaid','block');
	my $tilded_exaid = '';
	my $aids = $I{dbobject}->getAuthorAids();
	for(@$aids) {
	# Ok, this is probably dumb
		my ($aid) = @$_;
		my $checked = ($exaid =~ /'$aid'/) ? ' CHECKED' : '';
		my $tilded_exaid = eval $tilded_exaid_code;
		print $tilded_exaid;
	}

	# Customizable Topic
	my $tilded_topicsbegin = $I{dbobject}->getBlock('users_tilded_topicsbegin','block');
	print $tilded_topicsbegin;

	my $topics = $I{dbobject}->getDescriptions('topics');
	my $tilded_topics_code = prepBlock $I{dbobject}->getBlock('users_tilded_topics','block');
	my $tilded_topics = '';
	while (my($tid, $alttext) = each %$topics) {
		my $checked = ($extid =~ /'$tid'/) ? ' CHECKED' : '';
		$tilded_topics = eval $tilded_topics_code;
		print $tilded_topics;
	}

	my $tilded_topicsend = $I{dbobject}->getBlock('users_tilded_topicsend','block');
	print $tilded_topicsend;

	my $sections = $I{dbobject}->getDescriptions('sections');

	# users_tilded_sectionex
	my $tilded_sectionex_code = prepBlock $I{dbobject}->getBlock('users_tilded_sectionex','block');
	my $tilded_sectionex = '';
	while (my($section,$title) = each %$sections) {
		my $checked = ($exsect =~ /'$section'/) ? " CHECKED" : "";
		$tilded_sectionex = eval $tilded_sectionex_code;
		print $tilded_sectionex;
	}

	my $tilded_endtable1 = $I{dbobject}->getBlock('users_tilded_endtable1','block'); 
	print $tilded_endtable1;
	
	my $tilded_customizetitle = $I{dbobject}->getBlock('users_tilded_customizetitle','block'); 
	titlebar("100%", $tilded_customizetitle);

	$userspace = stripByMode($userspace, 'literal');

	# users_tilded_customizemsg
	my $tilded_customizemsg = eval prepBlock $I{dbobject}->getBlock('users_tilded_customizemsg','block');
	print $tilded_customizemsg;

	my $sections_description = $I{dbobject}->getSectionBlocks();
	my $tilded_exboxes_code = prepBlock $I{dbobject}->getBlock('users_tilded_exboxes','block');
	my $tilded_exboxes = '';
	for (@$sections_description) {
		my($bid, $title, $o) = @$_;
		my $checked = ($exboxes =~ /'$bid'/) ? " CHECKED" : "";
		$title =~ s/<(.*?)>//g;
		print "<B>" if $o > 0;
		$tilded_exboxes = eval $tilded_exboxes_code;
		print $tilded_exboxes;

		unless ($bid eq "srandblock") {
			print $title;
		} else {
			my $tilded_rand = eval prepBlock $I{dbobject}->getBlock('users_tilded_rand','block');
			print $tilded_rand;
		}

		print "</A><BR>\n";
		print "</B>" if $o > 0;
	}


	# users_tilded_boxmsg
	my $tilded_boxmsg = eval prepBlock $I{dbobject}->getBlock('users_tilded_boxmsg','block');
	print $tilded_boxmsg;
}

#################################################################
sub editHome {
	my($uid) = @_;

	# If you are seeing problems, check to see if I have
	# missed a key -- brian
	# added the ones needed for tildeEd() -- pudge
	my @values = qw(
		realname realemail fakeemail homepage nickname
		passwd sig seclev bio maillist dfid tzcode maxstories
		extid exsect exaid exboxes mylinks
	);

	my $user_edit = $I{dbobject}->getUser($uid, \@values);

	return if isAnon($user_edit->{uid});

	my $edithome_title = eval prepBlock $I{dbobject}->getBlock('users_edithome_title','block');
	titlebar("100%", $edithome_title);

	my $edithome_startform = eval prepBlock $I{dbobject}->getBlock('users_edithome_startform','block');
	print $edithome_startform;

	my $formats;
	$formats = $I{dbobject}->getDescriptions('dateformats');
	createSelect('tzformat', $formats, $user_edit->{dfid});

	$formats = $I{dbobject}->getDescriptions('tzcodes');
	createSelect('tzcode', $formats, $user_edit->{tzcode});

	print "</NOBR>";

	my $l_check = $user_edit->{light}	? " CHECKED" : "";
	my $b_check = $user_edit->{noboxes}	? " CHECKED" : "";
	my $i_check = $user_edit->{noicons}	? " CHECKED" : "";
	my $w_check = $user_edit->{willing}	? " CHECKED" : "";

	my $edithome_formbody = eval prepBlock $I{dbobject}->getBlock('users_edithome_formbody','block');
	print $edithome_formbody;

	tildeEd(
		$user_edit->{extid}, $user_edit->{exsect},
		$user_edit->{exaid}, $user_edit->{exboxes}, $user_edit->{mylinks}
	);

	my $edithome_formend = $I{dbobject}->getBlock('users_edithome_formend','block');
	print $edithome_formend;
}

#################################################################
sub editComm {
	my($uid) = @_;

	my @values = qw(realname realemail fakeemail homepage nickname passwd sig seclev bio maillist);
	my $user_edit = $I{dbobject}->getUser($uid, \@values);
	$user_edit->{uid} = $uid;

	my $editcomm_title= $I{dbobject}->getBlock('users_editcomm_title','block');
	titlebar("100%", $editcomm_title);

	my $editcomm_startform = eval prepBlock $I{dbobject}->getBlock('users_editcomm_startform','block');
	print $editcomm_startform;

	my $formats;

	my $editcomm_dispmode = $I{dbobject}->getBlock('users_editcomm_dispmode','block');
	print $editcomm_dispmode;
	$formats = $I{dbobject}->getDescriptions('commentmodes');
	createSelect('umode', $formats, $user_edit->{mode});

	my $editcomm_sortord = $I{dbobject}->getBlock('users_editcomm_sortord','block');
	print $editcomm_sortord;

	$formats = $I{dbobject}->getDescriptions('sortcodes');
	createSelect('commentsort', $formats, $user_edit->{commentsort});

	my $editcomm_thres = $I{dbobject}->getBlock('users_editcomm_thres','block');
	print $editcomm_thres;

	$formats = $I{dbobject}->getDescriptions('threshcodes');
	createSelect('uthreshold', $formats, $user_edit->{threshold});

	my $editcomm_guidelines = eval prepBlock $I{dbobject}->getBlock('users_editcomm_guidelines','block');
	print $editcomm_guidelines;

	my $editcomm_hithres = $I{dbobject}->getBlock('users_editcomm_hithres','block');
	print $editcomm_hithres;

	$formats = $I{dbobject}->getDescriptions('threshcodes');
	createSelect('highlightthresh', $formats, $user_edit->{highlightthresh});

	my $editcomm_scoring = $I{dbobject}->getBlock('users_editcomm_scoring','block');
	print $editcomm_scoring;

	my $h_check = $user_edit->{hardthresh}	? " CHECKED" : "";
	my $r_check = $user_edit->{reparent}	? " CHECKED" : "";
	my $n_check = $user_edit->{noscores}	? " CHECKED" : "";
	my $s_check = $user_edit->{nosigs}	? " CHECKED" : "";

	my $editcomm_form = eval prepBlock $I{dbobject}->getBlock('users_editcomm_form','block');
	print $editcomm_form;

	$formats = $I{dbobject}->getDescriptions('postmodes');
	createSelect('posttype', $formats, $user_edit->{posttype});

	my $editcomm_formend = $I{dbobject}->getBlock('users_editcomm_formend','block');
	print $editcomm_formend;

}

#################################################################
sub saveUser {
	my $uid = $I{U}{aseclev} ? shift : $I{U}{uid};
	my $user_email  = $I{dbobject}->getUser($uid, 'nickname', 'realemail');
	my $note;

	$user_email->{nickname} = substr($user_email->{nickname}, 0, 20);
	return if isAnon($uid);

	# $note = "Saving $user_email->{nickname}.\n";
	$note = eval prepBlock $I{dbobject}->getBlock('users_savenickname','block');

	if(! $user_email->{nickname}) {
		$note .= $I{dbobject}->getBlock('users_saveuser_note','block');
	}

	# stripByMode _after_ fitting sig into schema, 120 chars
	$I{F}{sig}	 = stripByMode(substr($I{F}{sig}, 0, 120), 'html');
	$I{F}{fakeemail} = chopEntity(stripByMode($I{F}{fakeemail}, 'attribute'), 50);
	$I{F}{homepage}	 = "" if $I{F}{homepage} eq "http://";
	$I{F}{homepage}	 = fixurl($I{F}{homepage});

	# for the users table
	my $H = {
		sig		=> $I{F}{sig},
		homepage	=> $I{F}{homepage},
		fakeemail	=> $I{F}{fakeemail},
		maillist	=> $I{F}{maillist},
		realname	=> $I{F}{realname},
		bio		=> $I{F}{bio},
		pubkey		=> $I{F}{pubkey}
	};

	if ($user_email->{realemail} ne $I{F}{realemail}) {
		$H->{realemail} = chopEntity(stripByMode($I{F}{realemail}, 'attribute'), 50);

		$note .= eval prepBlock $I{dbobject}->getBlock('users_saveuser_changeemail','block');

		my $saveuser_emailtitle = eval prepBlock $I{dbobject}->getBlock('users_saveuser_emailtitle','block');
		my $saveuser_emailmsg = eval prepBlock $I{dbobject}->getBlock('users_saveuser_emailmsg','block');
		sendEmail($user_email->{realemail}, $saveuser_emailtitle, $saveuser_emailmsg);
	}

	delete $H->{passwd};
	if ($I{F}{pass1} eq $I{F}{pass2} && length($I{F}{pass1}) > 5) {
		$note .= $I{dbobject}->getBlock('users_saveuser_passchanged','block');

		$H->{passwd} = $I{F}{pass1};
		# check for DB error before setting cookie?  -- pudge
		setCookie('user', bakeUserCookie($uid, encryptPassword($H->{passwd})));

	} elsif ($I{F}{pass1} ne $I{F}{pass2}) {
		$note .= $I{dbobject}->getBlock('users_saveuser_passnotmatch','block');

	} elsif (length $I{F}{pass1} < 6 && $I{F}{pass1}) {
		$note .= $I{dbobject}->getBlock('users_saveuser_passtooshort','block');
	}

	# Update users with the $H thing we've been playing with for this whole damn sub
	$I{dbobject}->setUser($uid, $H);

	return fixparam($note);
}

#################################################################
sub saveComm {
	my $uid  = $I{U}{aseclev} ? shift : $I{U}{uid};
	my $name = $I{U}{aseclev} && $I{F}{name} ? $I{F}{name} : $I{U}{nickname};

	$name = substr($name, 0, 20);
	return if isAnon($uid);

	my $savename = eval prepBlock $I{dbobject}->getBlock('users_savename','block');
	print $savename;

	if (isAnon($uid) || !$name) {
		my $cookiemsg = $I{dbobject}->getBlock('users_cookiemsg','block');
		print $cookiemsg;
	}

	# Take care of the lists
	# Enforce Ranges for variables that need it
	$I{F}{commentlimit} = 0 if $I{F}{commentlimit} < 1;
	$I{F}{commentspill} = 0 if $I{F}{commentspill} < 1;

	# for users_comments
	my $H = {
		clbig		=> $I{F}{clbig},
		clsmall		=> $I{F}{clsmall},
		mode		=> $I{F}{umode},
		posttype	=> $I{F}{posttype},
		commentsort	=> $I{F}{commentsort},
		threshold	=> $I{F}{uthreshold},
		commentlimit	=> $I{F}{commentlimit},
		commentspill	=> $I{F}{commentspill},
		maxcommentsize	=> $I{F}{maxcommentsize},
		highlightthresh	=> $I{F}{highlightthresh},
		nosigs		=> ($I{F}{nosigs}     ? 1 : 0),
		reparent	=> ($I{F}{reparent}   ? 1 : 0),
		noscores	=> ($I{F}{noscores}   ? 1 : 0),
		hardthresh	=> ($I{F}{hardthresh} ? 1 : 0),
	};

	# Update users with the $H thing we've been playing with for this whole damn sub
	$I{dbobject}->setUser($uid, $H);
}

#################################################################
sub saveHome {
	my $uid  = $I{U}{aseclev} ? shift : $I{U}{uid};
	my $name = $I{U}{aseclev} && $I{F}{name} ? $I{F}{name} : $I{U}{nickname};

	$name = substr($name, 0, 20);
	return if isAnon($uid);

	# users_savename
	my $savename = eval prepBlock $I{dbobject}->getBlock('users_savename','block');
	print $savename;

	# print "<P>Saving $name<BR><P>";
	# users_cookiemsg
	if (isAnon($uid) || !$name) {
		my $cookiemsg = $I{dbobject}->getBlock('users_cookiemsg','block');
		print $cookiemsg;
	}

	my($extid, $exaid, $exsect) = "";
	my $exboxes = $I{dbobject}->getUser($uid, 'exboxes');

	$exboxes =~ s/'//g;
	my @b = split m/,/, $exboxes;

	foreach (@b) {
		$_ = "" unless $I{F}{"exboxes_$_"};
	}

	$exboxes = sprintf "'%s',", join "','", @b;
	$exboxes =~ s/'',//g;

	foreach my $k (keys %{$I{F}}) {
		if ($k =~ /^extid_(.*)/)	{ $extid  .= "'$1'," }
		if ($k =~ /^exaid_(.*)/)	{ $exaid  .= "'$1'," }
		if ($k =~ /^exsect_(.*)/)	{ $exsect .="'$1',"  }
		if ($k =~ /^exboxes_(.*)/) { 
			# Only Append a box if it doesn't exist
			my $box = $1;
			$exboxes .= "'$box'," unless $exboxes =~ /'$box'/;
		}
	}

	$I{F}{maxstories} = 66 if $I{F}{maxstories} > 66;
	$I{F}{maxstories} = 1 if $I{F}{maxstories} < 1;

	my $H = {
		extid		=> checkList($extid),
		exaid		=> checkList($exaid),
		exsect		=> checkList($exsect),
		exboxes		=> checkList($exboxes),
		maxstories	=> $I{F}{maxstories},
		noboxes		=> ($I{F}{noboxes} ? 1 : 0),
		light		=> ($I{F}{light} ? 1 : 0),
		noicons		=> ($I{F}{noicons} ? 1 : 0),
		willing		=> ($I{F}{willing} ? 1 : 0),
	};
	
	if (defined $I{F}{tzcode} && defined $I{F}{tzformat}) {
		$H->{tzcode} = $I{F}{tzcode};
		$H->{dfid}   = $I{F}{tzformat};
	}

	$H->{mylinks} = $I{F}{mylinks} if $I{F}{mylinks};

	# If a user is unwilling to moderate, we should cancel all points, lest
	# they be preserved when they shouldn't be.
	my $users_comments = { points => 0 };
	unless (isAnon($uid)) {
		$I{dbobject}->setUser($uid, $users_comments)
			unless $I{F}{willing};
	}

	# Update users with the $H thing we've been playing with for this whole damn sub
	$I{dbobject}->setUser($uid, $H);
}

#################################################################
sub displayForm {
	my $dispform_header = eval prepBlock $I{dbobject}->getBlock('users_dispform_header','block');
	print $dispform_header;

	my $dispform_login = $I{dbobject}->getBlock('users_dispform_login','block'); 
	my $dispform_loginerr = $I{dbobject}->getBlock('users_dispform_loginerr','block'); 

	print $I{F}{unickname} ? $dispform_loginerr : $dispform_login;
	titlebar("100%", $I{F}{unickname} ? $dispform_loginerr : $dispform_login);

	# $I{F}{unickname} ? "Error Logging In" : "Login";
	# titlebar("100%", $I{F}{unickname} ? "Error Logging In" : "Login");

	# users_dispform_loginmsg1,users_dispform_loginmsg2,users_dispform_loginmsg3
	if ($I{F}{unickname}) { 
		my $msg = $I{dbobject}->getBlock('users_dispform_loginmsg1','block');
		print $msg;

		if($I{allow_anonymous}) {
			my $msg = eval prepBlock $I{dbobject}->getBlock('users_dispform_loginmsg2','block');
			print $msg;
		} else {
			my $msg = $I{dbobject}->getBlock('users_dispform_loginmsg3','block');
			print $msg;
		}
	}

	$I{F}{unickname} ||= $I{F}{newuser};

	my $form1 = eval prepBlock $I{dbobject}->getBlock('users_dispform_form1','block');
	print $form1 ;

	my $title = '';
	if($I{F}{newuser}) {
		$title = $I{dbobject}->getBlock('users_dispform_duptitle','block');
	} else {
		$title = $I{dbobject}->getBlock('users_dispform_newtitle','block');
	}
	titlebar("100%", $title);

	# titlebar("100%", $I{F}{newuser} ? "Duplicate Account!" : "I'm a New User!");
	# users_dispform_newmsg1: users_dispform_newmsg2

	my $form2= $I{dbobject}->getBlock('users_dispform_newmsg1','block');
	$form2 .= $I{dbobject}->getBlock('users_dispform_newmsg2','block') if ! $I{F}{newuser};
	$form2 .= eval prepBlock $I{dbobject}->getBlock('users_dispform_form2','block');

	print $form2;


#	print $I{F}{newuser} ? <<EOT1 : <<EOT2;
#	Apparently you tried to register with a <B>duplicate nickname</B>,
#	a <B>duplicate email address</B>, or an <B>invalid email</B>.  You
#	can try another below, or use the form on the left to either login,
#	or retrieve your forgotten password.
#EOT1
#	What? You don't have an account yet?  Well enter your preferred <B>nick</B> name here:
#EOT2

	# users_dispform_form2
#	print <<EOT;
#	(Note: only the characters <TT>0-9a-zA-Z_.+!*'(),-\$</TT>, plus space,
#	are allowed in nicknames, and all others will be stripped out.)

#	<INPUT TYPE="TEXT" NAME="newuser" SIZE="20" MAXLENGTH="20" VALUE="$I{F}{newuser}">
#	<BR> and a <B>valid email address</B> address to send your registration
#	information. This address will <B>not</B> be displayed on $I{sitename}.
#	<INPUT TYPE="TEXT" NAME="email" SIZE="20" VALUE="$I{F}{email}"><BR>
#	<INPUT TYPE="SUBMIT" NAME="op" VALUE="newuser"> Click the button to
#	be mailed a password.<BR>

#	</FORM>

#</TD></TR></TABLE>

#EOT
}

main();
# No kick the baby
#$I{dbh}->disconnect if $I{dbh};
1;
