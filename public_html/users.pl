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

	my $op = $I{F}{op};
print STDERR "OP $I{F}{op}\n";

	if ($op eq "userlogin" && $I{U}{uid} != $I{anonymous_coward_uid}) {
		my $refer = $I{F}{returnto} || $I{rootdir};
		redirect($refer);
		return;
	}

	header("$I{sitename} Users");
	print <<EOT if $I{U}{uid} != $I{anonymous_coward_uid} && $op ne "userclose";
 [
	<A HREF="$ENV{SCRIPT_NAME}">User Info</A> |
	<A HREF="$ENV{SCRIPT_NAME}?op=edituser">Edit User Info</A> |
	<A HREF="$ENV{SCRIPT_NAME}?op=edithome">Customize Homepage</A> |
	<A HREF="$ENV{SCRIPT_NAME}?op=editcomm">Customize Comments</A> |
	<A HREF="$ENV{SCRIPT_NAME}?op=userclose">Logout</A>
 ]

EOT

	# and now the carnage begins
	if ($op eq "newuser") {
		newUser();

	} elsif ($op eq "edituser") {
		# the users_prefs table
		if ($I{U}{uid} != $I{anonymous_coward_uid}) {
			editUser($I{U}{nickname});
		} else {
			displayForm(); 
		}

	} elsif ($op eq "edithome" || $op eq "preferences") {
		# also known as the user_index table
		if ($I{U}{uid} != $I{anonymous_coward_uid}) {
			editHome($I{U}{nickname});
		} else {
			displayForm(); 
		}

	} elsif ($op eq "editcomm") {
		# also known as the user_comments table
		if ($I{U}{uid} != $I{anonymous_coward_uid}) {
			editComm($I{U}{nickname});
		} else {
			displayForm(); 
		}

	} elsif ($op eq "userinfo" || !$op) {
		if ($I{F}{nick}) {
			userInfo($I{F}{nick});
		} elsif ($I{U}{uid} == $I{anonymous_coward_uid}) {
			displayForm();
		} else {
			userInfo($I{U}{nickname});
		}

	} elsif ($op eq "saveuser") {
		saveUser($I{U}{uid});
		userInfo($I{U}{nickname});

	} elsif ($op eq "savecomm") {
		saveComm($I{U}{uid});
		userInfo($I{U}{nickname});

	} elsif ($op eq "savehome") {
		saveHome($I{U}{uid});
		userInfo($I{U}{nickname});

	} elsif ($op eq "sendpw") {
		mailPassword($I{U}{uid});

	} elsif ($op eq "mailpasswd") {
		mailPassword($I{dbobject}->getUserUID($I{F}{unickname}));

	} elsif ($op eq "suedituser" && $I{U}{aseclev} > 100) {
		editUser($I{F}{name});

	} elsif ($op eq "susaveuser" && $I{U}{aseclev} > 100) {
		saveUser($I{F}{uid}); 

	} elsif ($op eq "sudeluser" && $I{U}{aseclev} > 100) {
		delUser($I{F}{uid});

	} elsif ($op eq "userclose") {
		print "ok bubbye now.";
		displayForm();

	} elsif ($op eq "userlogin" && $I{U}{uid} != $I{anonymous_coward_uid}) {
		# print $query->redirect("$I{rootdir}/index.pl");
		userInfo($I{U}{nickname});

	} elsif ($op eq "preview") {
		previewSlashbox();

	} elsif ($I{U}{uid} != $I{anonymous_coward_uid}) {
		userInfo($I{F}{nick});

	} else {
		displayForm();
	}

	miniAdminMenu() if $I{U}{aseclev} > 100;
	$I{dbobject}->writelog("users", $I{U}{nickname});
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
	my ($title, $content, $url) = $I{dbobject}->getSectionBlocksByBid($I{F}{bid});
	my $cleantitle = $title;
	$cleantitle =~ s/<(.*?)>//g;

	titlebar("100%","Preview $cleantitle");
	print <<EOT;
What you see on the right hand side is a preview of the block thingee
labeled "$cleantitle".  If you select it from the
<A HREF="$I{rootdir}/users.pl?op=preferences">Preferences Page</A>,
you will have that little block added to the right hand side of your
<A HREF="$I{rootdir}/index.pl">Custom $I{sitename}</A> page.	 
Exciting?  Not really, but its a great way to waste time.

EOT
	print <<EOT if $I{U}{aseclev} > 999;
<P>Edit <A HREF="$I{rootdir}/admin.pl?op=blocked&bid=$I{F}{bid}">$I{F}{bid}</A>
EOT

	print qq!</TD><TD WIDTH="180" VALIGN="TOP">!;

	print portalbox($I{fancyboxwidth}, $title, $content, "", $url);
}

#################################################################
sub miniAdminMenu {
	print <<EOT;
<FORM ACTION="$ENV{SCRIPT_NAME}">
	<FONT SIZE="${\( $I{fontbase} + 1 )}"> [
		<A HREF="$I{rootdir}/admin.pl">Admin</A> |
		<INPUT TYPE="HIDDEN" NAME="op" VALUE="suedituser">
		<INPUT TYPE="TEXT" NAME="name" VALUE="$I{F}{nick}">
		<INPUT TYPE="SUBMIT" VALUE="Edit">
	</FONT> ]
</FORM>
EOT
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
		if($uid = $I{dbobject}->createUser($matchname, $I{F}{email}, $I{F}{newuser})) {
			titlebar("100%", "User $I{F}{newuser} created.");

			$I{F}{pubkey} = stripByMode($I{F}{pubkey}, "html");
			print <<EOT;

			<B>email</B>=$I{F}{email}<BR>
			<B>user id</B>=$uid<BR>
			<B>nick</B>=$I{F}{newuser}<BR>
			<B>passwd</B>=mailed to $I{F}{email}<BR>
			<P>Once you receive your password, you can log in and
			<A HREF="$I{rootdir}/users.pl">set your account up</A>

EOT

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
		print "Nickname was not found. No Password was mailed.<BR>\n"; 
		return;
	}
	my $user = $I{dbobject}->getUserInfoByUID($uid);

	my $msg = blockCache("newusermsg");
	$msg = prepBlock($msg);
	$msg = eval $msg;

	sendEmail($user->{realemail}, "$I{sitename} user password for $user->{nickname}", $msg) if $user->{nickname};
	print "Passwd for $user->{nickname} was just emailed.<BR>\n";
}

#################################################################
sub userInfo {
	my($nick) = @_;

	my $userbio = $I{dbobject}->getUserBio($nick);

	if (my($home, $email, $uid, $bio, $useclev, $karma) = @$userbio) {
		$bio = stripByMode($bio, "html");
		if ($I{U}{nickname} eq $nick) {
			my $points = $I{dbobject}->getUserPoints($uid);

			titlebar("95%", "Welcome back $nick ($uid)");
			print <<EOT;
<P>This is <B>your</B> User Info page.  There are thousands more, but this one is yours.
You most likely are not so interested in you, and probably would be most interested in
clicking the "Edit User Info" and "Customize..." links you see up top there so you can
customize $I{sitename}, change your password, or just click pretty widgets to kill time.
EOT

			# Users should be able to see their own points.
			if ($I{U}{uid} == $uid && $points > 0) {
				print <<EOT;
<P>You're a moderator with $points points. Please read the
<A HREF="$I{rootdir}/moderation.shtml">Moderator Guidelines</A> before you do any moderation.
<BR><P>
EOT
			}
			print <<EOT;
<CENTER><IMG SRC="$I{imagedir}/greendot.gif" WIDTH="75%" HEIGHT="1" ALIGN="CENTER"><BR></CENTER>
EOT

		} else {
			titlebar("95%", "User Info for $nick ($uid)");
		}

		print qq!<A HREF="$home">$home</A><BR><A HREF="mailto:$email">$email</A><BR>!;
		print "<B>Karma</B> $karma (mostly the sum of moderation done to users comments)<BR>"
			if $I{U}{aseclev} || $I{U}{uid} == $uid;
		print "<B>User Bio</B><BR>$bio<P>" if $bio;

		my($k) = $I{dbobject}->getUserPublicKey($uid);
		$k = stripByMode($k, "html");
		print "<B>Public Key</B><BR><PRE>\n$k</PRE><P>" if $k;

		$I{F}{min} = 0 unless $I{F}{min};

		my $comments = $I{dbobject}->getUserComments($uid, $I{F}{min}, $I{U});

		my $rows = @$comments;
		print "<B>$nick has posted $rows" 
			. " comments</B> (this only counts the last few weeks)<BR><P>";

		my $x;
		for (@$comments) {
			my($pid, $sid, $cid, $subj, $cdate, $pts) = @$_;
			$x++;
			my $r = $I{dbobject}->countComments($sid, $cid);
			my $replies = " Replies:$r" if $r;

			print <<EOT;
<BR><B>$x</B> <A HREF="$I{rootdir}/comments.pl?sid=$sid&cid=$cid">$subj</A> posted on $cdate (Score:$pts$replies)
<FONT SIZE="${\( $I{fontbase} + 2 )}">
EOT
			# This is ok, since with all luck we will not be hitting the DB
			my $story = $I{dbobject}->getStoryBySid($sid);

			if ($story) {
				my $href = $story->{writestatus} == 10
					? "$I{rootdir}/$story->{section}/$sid.shtml"
					: "$I{rootdir}/article.pl?sid=$sid";

				print qq!<BR>attached to <A HREF="$href">$story->{title}</A>!;
# $S->{section}/$sid.shtml
			} else {
				my $question = $I{dbobject}->getPollQuestionBySID($sid);
				print qq!<BR>attached to <A HREF="$I{rootdir}/pollBooth.pl?qid=$sid"> $question</A>!
					if $question;
			}
			print "</FONT>";
		}

	} else {
		print "$nick not found.";
	}
}

#################################################################
sub editKey {
	my $k = $I{dbobject}->getUserPublicKey($_[0]);
	printf qq!<P><B>Public Key</B><BR><TEXTAREA NAME="pubkey" ROWS="4" COLS="60">%s</TEXTAREA>!,
		stripByMode($k, 'literal');
}

#################################################################
sub editUser {
	my($name) = @_;
	my $user = $I{dbobject}->getUserEditInfo($name);

	return if $user->{uid} == $I{anonymous_coward_uid};

	titlebar("100%", "Editing $name ($user->{uid}) $user->{realemail}");
	print qq!<TABLE ALIGN="CENTER" WIDTH="95%" BGCOLOR="$I{bg}[2]"><TR><TD>!;

	$user->{homepage} ||= "http://";
 
	my $tempnick = $user->{nickname};
	$tempnick =~ s/ /+/g;
 
	print <<EOT;
You can automatically login by clicking
<A HREF="$I{rootdir}/index.pl?op=userlogin&upasswd=$user->{passwd}&unickname=$tempnick">This Link</A>
and Bookmarking the resulting page. This is totally insecure, but very convenient.

<FORM ACTION="$ENV{SCRIPT_NAME}" METHOD="POST">

	<B>Real Name</B> (optional)<BR>
		<INPUT TYPE="TEXT" NAME="realname" VALUE="$user->{realname}" SIZE="40"><BR>
		<INPUT TYPE="HIDDEN" NAME="uid" VALUE="$user->{uid}">
		<INPUT TYPE="HIDDEN" NAME="passwd" VALUE="$user->{passwd}">
		<INPUT TYPE="HIDDEN" NAME="name" VALUE="$user->{nickname}">

	<B>Real Email</B> (required but never displayed publicly. 
		This is where your passwd is mailed.  If you change your
		email, notification will be sent)<BR>
		<INPUT TYPE="TEXT" NAME="realemail" VALUE="$user->{realemail}" SIZE="40"><BR>

	<B>Fake Email</B> (optional:This email publicly displayed by
		your comments, you may spam proof it, leave it blank, 
		or just type in your address)<BR>
		<INPUT TYPE="TEXT" NAME="fakeemail" VALUE="$user->{fakeemail}" SIZE="40"><BR>

	<B>Homepage</B> (optional:you must enter a fully qualified URL!)<BR>
		<INPUT TYPE="TEXT" NAME="homepage" VALUE="$user->{homepage}" SIZE="60"><BR>

	<P><B>Headline Mailing List</B>
EOT

	my $description = $I{dbobject}->getDescriptions('maillist');
	createSelect('maillist', $description, $user->{maillist});

	printf <<EOT, stripByMode($user->{sig}, 'literal'), stripByMode($user->{bio}, 'literal');
	<P><B>Sig</B> (appended to the end of comments you post, 120 chars)<BR>
		<TEXTAREA NAME="sig" ROWS="2" COLS="60">%s</TEXTAREA>

	<P><B>Bio</B> (this information is publicly displayed on your
		user page.  255 chars)<BR>
		<TEXTAREA NAME="bio" ROWS="5" COLS="60" WRAP="virtual">%s</TEXTAREA>

EOT

	editKey($user->{uid});

  	print <<EOT;
	<P><B>Password</B> Enter new passwd twice to change it.
		(must be 6-20 chars long)<BR>
		<INPUT TYPE="PASSWORD" NAME="pass1" SIZE="20" MAXLENGTH="20">
		<INPUT TYPE="PASSWORD" NAME="pass2" SIZE="20" MAXLENGTH="20"><P>

</TD></TR></TABLE><P>

	<INPUT TYPE="SUBMIT" NAME="op" VALUE="saveuser">
	</FORM>
EOT

	# print "	<INPUT TYPE="SUBMIT" NAME="op" VALUE="susaveuser"> <INPUT TYPE="SUBMIT" NAME="op" VALUE="sudeluser">" if $I{U}{aseclev}> 499;
}

#################################################################
sub tildeEd {
	my($extid, $exsect, $exaid, $exboxes, $userspace) = @_;
	
	titlebar("100%", "Exclude Stories from the Homepage");

	print <<EOT;
<TABLE WIDTH="95%" BORDER="0" CELLPADDING="3" CELLSPACING="3" ALIGN="CENTER">
		<TR BGCOLOR="$I{bg}[3]">
			<TH><FONT COLOR="$I{fg}[3]" SIZE="${\( $I{fontbase} + 4 )}">Authors</FONT></TH>
			<TH><FONT COLOR="$I{fg}[3]" SIZE="${\( $I{fontbase} + 4 )}">Topics</FONT></TH>
			<TH><FONT COLOR="$I{fg}[3]" SIZE="${\( $I{fontbase} + 4 )}">Sections</FONT></TH>
		</TR><TR BGCOLOR="$I{bg}[2]"><TD VALIGN="TOP">
EOT

	# Customizable Authors Thingee
	my $aids = $I{dbobject}->getAuthorAids();
	for(@$aids) {
	# Ok, this is probably dumb
		my ($aid) = @$_;
		my $checked = ($exaid =~ /'$aid'/) ? ' CHECKED' : '';
		print qq!<INPUT TYPE="CHECKBOX" NAME="exaid_$aid"$checked>$aid<BR>\n!;
	}


	# Customizable Topic
	print qq!</TD><TD VALIGN="TOP"><MULTICOL COLS="3">!;
	my $topics = $I{dbobject}->getDescriptions('topics');
	while (my($tid, $alttext) = each %$topics) {
		my $checked = ($extid =~ /'$tid'/) ? ' CHECKED' : '';
		print qq!<INPUT TYPE="CHECKBOX" NAME="extid_$tid"$checked>$alttext<BR>\n! if $tid;
	}

	print "</MULTICOL></TD>";

	# Customizable Sections
	print '<TD VALIGN="TOP">';
	my $sections = $I{dbobject}->getDescriptions('sections');

	while (my($section,$title) = each %$sections) {
		my $checked = ($exsect =~ /'$section'/) ? " CHECKED" : "";
		print qq!<INPUT TYPE="CHECKBOX" NAME="exsect_$section"$checked>$title<BR>\n! if $section;
	}

	print "</TD>";

	print "</TD></TR></TABLE><P>";
	
	titlebar("100%", "Customize Slashboxes");

	$userspace = stripByMode($userspace, 'literal');
	print <<EOT;
<TABLE WIDTH="95%" BGCOLOR="$I{bg}[2]" ALIGN="CENTER" BORDER="0">
	<TR><TD>
	<P>Look ma, I'm configurable!
	<B>Important:</B> If you leave these all unchecked, it means you
	want the <I>default</I> selection of boxes.  If you start selecting
	boxes, remember to set <B>all</B> of them that you want because the 
	default selection will be <B>ignored</B>.  Default entries are bolded.

	<P><B>User Space</B> (check 'user space' below and whatever
	you place here will appear your custom $I{sitename})<BR>
		<TEXTAREA NAME="mylinks" rows=5 COLS="60" WRAP="VIRTUAL">$userspace</TEXTAREA>

	<P><MULTICOL COLS="3">
EOT

	my $sections_description = $I{dbobject}->getSectionblocks();
	for (@$sections_description) {
		my($bid,$title,$o) = @$_;
		my $checked = ($exboxes =~ /'$bid'/) ? " CHECKED" : "";
		$title =~ s/<(.*?)>//g;
		print "<B>" if $o > 0;
		print qq!<INPUT TYPE="CHECKBOX" NAME="exboxes_$bid"$checked>!
			. qq!<A HREF="$ENV{SCRIPT_NAME}?op=preview&bid=$bid">!;

		unless ($bid eq "srandblock") {
			print $title;
		} else {
			print "Semi-Random Box";
		}

		print "</A><BR>\n";
		print "</B>" if $o > 0;
	}


	print <<EOT;
	</MULTICOL><P>

	If you have reasonable suggestions for boxes that can be added
	here, or a problem with one of the boxes already here,
	email <A HREF="mailto:$I{adminmail}">$I{siteadmin_name}</A>.	

	<P>The preferred format is the Netscape RDF format that is
	rapidly becoming the de facto format for exchanging headlines
	between sites.
EOT
		
	print "<P></TD></TR></TABLE>";
}

#################################################################
sub editHome {
	my($name) = @_;

	my $user = $I{dbobject}->getUserEditInfo($name);

	return if $user->{uid} == $I{anonymous_coward_uid};

	titlebar("100%", "Customize $I{sitename}'s Display");

	print <<EOT;
	<FORM ACTION="$ENV{SCRIPT_NAME}" METHOD="POST">
	<TABLE ALIGN="CENTER" WIDTH="95%" BGCOLOR="$I{bg}[2]"><TR><TD>

		<B>Date/Time Format</B><NOBR>
EOT

	my $formats;
	$formats = $I{dbobject}->getDescriptions('dateformats');
	createSelect('tzformat', $formats, $user->{dfid});

	$formats = $I{dbobject}->getDescriptions('tzcodes');
	createSelect('tzcode', $formats, $user->{tzcode});

	print "</NOBR>";

	my $l_check = $user->{light}	? " CHECKED" : "";
	my $b_check = $user->{noboxes}	? " CHECKED" : "";
	my $i_check = $user->{noicons}	? " CHECKED" : "";
	my $w_check = $user->{willing}	? " CHECKED" : "";

	print <<EOT;

	<P><INPUT TYPE="CHECKBOX" NAME="light"$l_check>
	<B>Light</B> (reduce the complexity of $I{sitename}'s HTML for 
	AvantGo, Lynx, or slow connections)

	<P><INPUT TYPE="CHECKBOX" NAME="noboxes"$b_check>
	<B>Deactivate Slashboxes</B> (just the news ma'am)

	<P><INPUT TYPE="CHECKBOX" NAME="noicons"$i_check>
	<B>No Icons</B> (disable topic icon images on stories)

	<P><B>Maximum Stories</B> The default is 30.  The main
	column displays 1/3rd of these at minimum, and all of
	today's stories at maximum.<BR>
	<INPUT TYPE="TEXT" NAME="maxstories" SIZE="3" VALUE="$user->{maxstories}">

	<P><INPUT TYPE="CHECKBOX" NAME="willing"$w_check>
	<B>Willing to Moderate</B> By default all users are willing to
	<A HREF="$I{rootdir}/moderation.shtml"> Moderate</A>.
	Uncheck this if you aren't interested.

	</TD></TR></TABLE><P>
EOT

	tildeEd($user->{extid}, $user->{exsect}, $user->{exaid}, $user->{exboxes}, $user->{mylinks});

	print qq!\t<INPUT TYPE="SUBMIT" NAME="op" VALUE="savehome">\n!;
	print "\t</FORM>\n\n";
}

#################################################################
sub editComm {
	my($name) = @_;

	my $user = $I{dbobject}->getUserEditInfo($name);

	titlebar("100%", "Comment Options");

	print <<EOT;
	<FORM ACTION="$ENV{SCRIPT_NAME}" METHOD="POST">
	<TABLE ALIGN="CENTER" WIDTH="95%" BGCOLOR="$I{bg}[2]"><TR><TD>
EOT

	my $formats;

	print "<B>Display Mode</B>";
	$formats = $I{dbobject}->getDescriptions('commentmodes');
	createSelect('umode', $formats, $user->{mode});

	print "<P><B>Sort Order</B> (self explanatory?	I hope?)\n";
	$formats = $I{dbobject}->getDescriptions('sortcodes');
	createSelect('commentsort', $formats, $user->{commentsort});

	print "<P><B>Threshold</B>";
	$formats = $I{dbobject}->getDescriptions('threshcodes');
	createSelect('uthreshold', $formats, $user->{threshold});

	print <<EOT;
	<BR>(comments scored less than this setting will be ignored.
	Anonymous posts start at 0, logged in posts start
	at 1.  Moderators add and subtract points according to
	the <A HREF="$I{rootdir}/moderation.shtml">Guidelines</A>.
EOT

	print "<P><B>Highlight Threshold</B>";
	$formats = $I{dbobject}->getDescriptions('threshcodes');
	createSelect('highlightthresh', $formats, $user->{highlightthresh});

	print " <BR>(comments scoring this are displayed even after an article spills into index mode)";

	my $h_check = $user->{hardthresh}	? " CHECKED" : "";
	my $r_check = $user->{reparent}		? " CHECKED" : "";
	my $n_check = $user->{noscores}		? " CHECKED" : "";
	my $s_check = $user->{nosigs}		? " CHECKED" : "";

	print <<EOT;
	<P><B>Hard Thresholds</B> (Hides 'X Replies Below
	Current Threshold' Message from Threads)
	<INPUT TYPE="CHECKBOX" NAME="hardthresh"$h_check>

	<P><B>Reparent Highly Rated Comments</B> (causes comments
	to be displayed even if they are replies to comments
	under current threshold)
	<INPUT TYPE="CHECKBOX" NAME="reparent"$r_check>

	<P><B>Do Not Display Scores</B> (Hides score:
	They still <B>apply</B> you just don't see them.)
	<INPUT TYPE="CHECKBOX" NAME="noscores"$n_check>

	<P><B>Limit</B> only display this many comments.
	For best results, set this to a low number and sort by score.<BR>
	<INPUT TYPE="TEXT" NAME="commentlimit" SIZE="6" VALUE="$user->{commentlimit}">

	<P><B>Index Spill</B> (When an article has this many comments,
	it switches to indexed mode)<BR>
	<INPUT TYPE="TEXT" NAME="commentspill" VALUE="$user->{commentspill}" SIZE="3">

	<P><B>Small Comment Penalty</B> (Assign -1 to comments smaller
	than this many characters.  This might cause some comments
	to be rated -2 and hence rendered invisible!)<BR>
	<INPUT TYPE="TEXT" NAME="clsmall" VALUE="$user->{clsmall}" SIZE="6">

	<P><B>Long Comment Bonus </B> (Assign +1 to lengthy comments)<BR>
	<INPUT TYPE="TEXT" NAME="clbig" VALUE="$user->{clbig}" SIZE="6">

	<P><B>Max Comment Size</B> (Truncates long comments, and 
	adds a \"Read More\" link.  Set really big to disable)<BR>
	<INPUT TYPE="TEXT" NAME="maxcommentsize" SIZE="6" VALUE="$user->{maxcommentsize}">

	<P><B>Disable Sigs</B> (strip sig quotes from comments)
	<INPUT TYPE="CHECKBOX" NAME="nosigs"$s_check>

	<P><B>Comment Post Mode</B>
EOT

	$formats = $I{dbobject}->getDescriptions('postmodes');
	createSelect('posttype', $formats, $user->{posttype});

	print <<EOT;

	</TD></TR></TABLE><P>

	<INPUT TYPE="SUBMIT" NAME="op" VALUE="savecomm">
</FORM>
EOT

	# print qq! <INPUT TYPE="SUBMIT" NAME="op" VALUE="susaveuser"> <INPUT TYPE="SUBMIT" NAME="op" VALUE="sudeluser">! if $I{U}{aseclev}> 499;
}

#################################################################
sub saveUser {
	my $uid = $I{U}{aseclev} ? shift : $I{U}{uid};
	my $user  = $I{dbobject}->getUserInfoByUID($uid);

	$user->{nickname} = substr($user->{nickname}, 0, 20);
	return if $uid == $I{anonymous_coward_uid};

	print "<P>Saving $user->{nickname}<BR><P>";
	print <<EOT if $uid == $I{anonymous_coward_uid} || !$user->{nickname};
<P>Your browser didn't save a cookie properly.  This could mean you are behind a filter that
eliminates them, you are using a browser that doesn't support them, or you rejected it.
EOT

	# stripByMode _after_ fitting sig into schema, 120 chars
	$I{F}{sig}	 = stripByMode(substr($I{F}{sig}, 0, 120), 'html');
	$I{F}{fakeemail} = chopEntity(stripByMode($I{F}{fakeemail}, 'attribute'), 50);
	$I{F}{homepage}	 = "" if $I{F}{homepage} eq "http://";
	$I{F}{homepage}	 = fixurl($I{F}{homepage});

	# for the users table
	my $H = {
		sig		=> $I{F}{sig},
		homepage	=> $I{F}{homepage},
		fakeemail	=> $I{F}{fakeemail}
	};

	# for the users_info table
	my $H2 = {
		maillist	=> $I{F}{maillist},
		realname	=> $I{F}{realname},
		bio		=> $I{F}{bio}
	};


	if ($user->{realemail} ne $I{F}{realemail}) {
		$H->{realemail} = chopEntity(stripByMode($I{F}{realemail}, 'attribute'), 50);
		print "\nNotifying $user->{realemail} of the change to their account.<BR>\n";

		sendEmail($user->{realemail}, "$I{sitename} user email change for $user->{nickname}", <<EOT);
The user account $user->{nickname} on $I{sitename} had this email
associated with it.  A web user from $ENV{REMOTE_ADDR} has
just changed it to $I{F}{realemail}.

If this is wrong, well then we have a problem.	MOST LIKELY THIS IS NO
BIG DEAL.  It probably means you have a common nickname and someone else
wanted it.  They do not have your password, they are not going to sneak
up on you late at night and steal your children.  Only this email address
got this email.	 So do not sweat it unless your account suddenly dies
or something.
EOT
	}

	if ($I{F}{pass1} eq $I{F}{pass2} && length($I{F}{pass1}) > 5) {
		$H->{passwd} = $I{F}{pass1};
		print qq!Password Changed  (You'll need to <A HREF="$ENV{SCRIPT_NAME}">log back in</A> now.)<BR>!;

	} elsif ($I{F}{pass1} ne $I{F}{pass2}) {
		print "Passwords don't match. Password not changed.<BR>";

	} elsif (length $I{F}{pass1} < 6 && $I{F}{pass1}) {
		print "Password is too short and was not changed.<BR>";
	}

	# update the public key
	my $public_key = { uid => $uid, pubkey => $I{F}{pubkey} };
	$I{dbobject}->setUsersKey($uid, $public_key);

	# Update users with the $H thing we've been playing with for this whole damn sub
	$I{dbobject}->setUsers($uid, $H) if $uid != $I{anonymous_coward_uid};

	# Update users with the $H thing we've been playing with for this whole damn sub
	$I{dbobject}->setUsers($uid, $H2) if $uid != $I{anonymous_coward_uid};
}

#################################################################
sub saveComm {
	my $uid  = $I{U}{aseclev} ? shift : $I{U}{uid};
	my $name = $I{U}{aseclev} && $I{F}{name} ? $I{F}{name} : $I{U}{nickname};

	$name = substr($name, 0, 20);
	return if $uid == $I{anonymous_coward_uid};

	print "<P>Saving $name<BR><P>";
	print <<EOT if $uid == $I{anonymous_coward_uid} || !$name;
<P>Your browser didn't save a cookie properly. This could mean you are behind a filter that
eliminates them, you are using a browser that doesn't support them, or you rejected it.
EOT

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
	$I{dbobject}->setUsersComments($uid,$H) if $uid != $I{anonymous_coward_uid};
}

#################################################################
sub saveHome {
	my $uid  = $I{U}{aseclev} ? shift : $I{U}{uid};
	my $name = $I{U}{aseclev} && $I{F}{name} ? $I{F}{name} : $I{U}{nickname};

	$name = substr($name, 0, 20);
	return if $uid == $I{anonymous_coward_uid};

	print "<P>Saving $name<BR><P>";
	print <<EOT if $uid == $I{anonymous_coward_uid} || !$name;
<P>Your browser didn't save a cookie properly. This could mean you are behind a filter that
eliminates them, you are using a browser that doesn't support them, or you rejected it.
EOT

	my($extid, $exaid, $exsect) = "";
	my $exboxes = $I{dbobject}->getUserIndexExboxes($uid);

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

	# Take care of the preferences table

	# for users_index
	my $H = {
		extid		=> checkList($extid),
		exaid		=> checkList($exaid),
		exsect		=> checkList($exsect),
		exboxes		=> checkList($exboxes),
		maxstories	=> $I{F}{maxstories},
		noboxes		=> ($I{F}{noboxes} ? 1 : 0),
	};

	# for users_prefs
	my $H2 = {
		light		=> ($I{F}{light} ? 1 : 0),
		noicons		=> ($I{F}{noicons} ? 1 : 0),
		willing		=> ($I{F}{willing} ? 1 : 0),
	}; 

	
	if (defined $I{F}{tzcode} && defined $I{F}{tzformat}) {
		$H2->{tzcode} = $I{F}{tzcode};
		$H2->{dfid} = $I{F}{tzformat};
	}

	$H2->{mylinks} = $I{F}{mylinks} if $I{F}{mylinks};

	# If a user is unwilling to moderate, we should cancel all points, lest
	# they be preserved when they shouldn't be.
	my $users_comments = { points => 0 };
	if ($uid != $I{anonymous_coward_uid}) {
		$I{dbobject}->setUsersComments($uid, $users_comments)
			unless $I{F}{willing};
	}

	# Update users with the $H thing we've been playing with for this whole damn sub
	$I{dbobject}->setUsersIndex($uid, $H);

	# Update users with the $H thing we've been playing with for this whole damn sub
	$I{dbobject}->setUsersPrefrences($uid, $H2) if $uid != $I{anonymous_coward_uid};
}

#################################################################
sub displayForm {
	print <<EOT;
<TABLE WIDTH="100%" CELLPADDING="10"><TR><TD WIDTH="50%" VALIGN="TOP">

<P><FORM ACTION="$ENV{SCRIPT_NAME}" METHOD="POST">

EOT

	titlebar("100%", $I{F}{unickname} ? "Error Logging In" : "Login");

	print $I{F}{unickname} ? <<EOT1 : $I{allow_anonymous} ? <<EOT2 : <<EOT3;
	Danger, Will Robinson!  You didn't login!  You apparently put
	in the wrong password, or the wrong nickname, or else space 
	aliens have infested the server.  I'd suggest trying again,
	or clicking that mail password button if you forgot your password.
EOT1
	Logging in will allow you to post comments as yourself.  If you
	don't login, you will only be able to post as $I{anon_name}.
EOT2
	Logging in will allow you to post comments.  If you
	don't login, you will not be able to post.
EOT3

	$I{F}{unickname} ||= $I{F}{newuser};

	print <<EOT;

	<P><B>Nick:</B> (maximum 20 characters long)<BR>
	<INPUT TYPE="TEXT" NAME="unickname" SIZE="20" VALUE="$I{F}{unickname}"><BR>

	<B>Password:</B> (6-20 characters long)<BR>
	<INPUT TYPE="PASSWORD" NAME="upasswd" SIZE="20" MAXLENGTH="20"><BR>

	<INPUT TYPE="SUBMIT" NAME="op" VALUE="userlogin">
	<INPUT TYPE="SUBMIT" NAME="op" VALUE="mailpasswd">

	</TD><TD WIDTH="50%" VALIGN="TOP">
EOT

	titlebar("100%", $I{F}{newuser} ? "Duplicate Account!" : "I'm a New User!");
	print $I{F}{newuser} ? <<EOT1 : <<EOT2;
	Apparently you tried to register with a <B>duplicate nickname</B>,
	a <B>duplicate email address</B>, or an <B>invalid email</B>.  You
	can try another below, or use the form on the left to either login,
	or retrieve your forgotten password.
EOT1
	What? You don't have an account yet?  Well enter your preferred <B>nick</B> name here:
EOT2

	print <<EOT;
	(Note: only the characters <TT>0-9a-zA-Z_.+!*'(),-\$</TT>, plus space,
	are allowed in nicknames, and all others will be stripped out.)

	<INPUT TYPE="TEXT" NAME="newuser" SIZE="20" MAXLENGTH="20" VALUE="$I{F}{newuser}">
	<BR> and a <B>valid email address</B> address to send your registration
	information. This address will <B>not</B> be displayed on $I{sitename}.
	<INPUT TYPE="TEXT" NAME="email" SIZE="20" VALUE="$I{F}{email}"><BR>
	<INPUT TYPE="SUBMIT" NAME="op" VALUE="newuser"> Click the button to
	be mailed a password.<BR>

	</FORM>

</TD></TR></TABLE>

EOT
}

main();
# No kick the baby
#$I{dbh}->disconnect if $I{dbh};
1;
