package Slash;

###############################################################################
# Slash.pm  (aka, the BEAST)
# This is the primary perl module for the slash engine.
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
use strict;  # ha ha ha ha ha!
use Apache;
use Apache::SIG ();
use CGI ();
use DBI;
use Data::Dumper;  # the debuggerer's best friend
use Date::Manip;
use File::Spec::Functions;
use HTML::Entities;
use Mail::Sendmail;
use URI;

use Slash::DB;
use Slash::Utility;
BEGIN {
	# this is the worst damned warning ever, so SHUT UP ALREADY!
	$SIG{__WARN__} = sub { warn @_ unless $_[0] =~ /Use of uninitialized value/ };

	require Exporter;
	use vars qw($VERSION @ISA @EXPORT @EXPORT_OK %EXPORT_TAGS %I $CRLF);
	$VERSION = '1.0.8';
	@ISA	 = 'Exporter';
	@EXPORT  = qw(
		sqlSelectMany sqlSelect sqlSelectHash sqlSelectAll approveTag
		sqlSelectHashref sqlUpdate sqlInsert sqlReplace sqlConnect
		sqlTableExists sqlSelectColumns getSlash linkStory getSection
		selectTopic selectSection fixHref
		getsid getsiddir getWidgetBlock
		anonLog pollbooth stripByMode header footer pollItem
		prepEvalBlock prepBlock formLabel
		titlebar fancybox portalbox printComments displayStory
		sendEmail getOlderStories selectStories timeCalc
		getEvalBlock dispStory lockTest getSlashConf
		dispComment linkComment redirect fixurl fixparam chopEntity
		getFormkeyId checkSubmission errorMessage createSelect getFormkey
	);
	$CRLF = "\015\012";
}

# Not needed I believe....
#getSlashConf();


###############################################################################
#
# Let's get this party Started
#

# Load in config for proper SERVER_NAME.  If you do not want to use SERVER_NAME,
# adjust here and in slashdotrc.pl
sub getSlashConf {
#	my $serv = exists $Slash::home{lc $ENV{SERVER_NAME}}
#		? lc $ENV{SERVER_NAME}
#		: 'DEFAULT';
#
#	require($Slash::home{$serv} ? catfile($Slash::home{$serv}, 'slashdotrc.pl')
#		: 'slashdotrc.pl');
#
#	$serv = exists $Slash::conf{lc $ENV{SERVER_NAME}}
#		? lc $ENV{SERVER_NAME}
#		: 'DEFAULT';

	my $constants = getCurrentStatic();
	#*I = $Slash::conf{$constants->{basedomain}};
	#Yes this is ugly and should go away
	#Just as soon as the last of %I is gone, this is gone
	for (keys %$constants) {
		$I{$_} = $constants->{$_};
	}

	return \%I;
}


# Blank variables, get $I{r} (apache) $I{query} (CGI) $I{U} (User) and $I{F} (Form)
# Handles logging in and printing HTTP headers
sub getSlash {
	# We should pull 'r' out of %I
	for (qw[r query F U SETCOOKIE]) {
		undef $I{$_} if $I{$_};
	}

	# what do we do about when this is called from the command line,
	# so there is no Apache?  cf. prog2file in slashd, when index.pl
	# is called without Apache -- pudge
	# Seperate method? -Brian
	# Or maybe we don't need it... -Brian

	#Ok, I hate single character variables, but 'r' is a bit
	#of a tradition in apache stuff -Brian
	my $r = Apache->request;
	$I{r} = $r;
	my $cfg = Apache::ModuleConfig->get($r, 'Slash::Apache');
	my $user_cfg = Apache::ModuleConfig->get($r, 'Slash::Apache::User');

	$I{dbobject} = $cfg->{'dbslash'} || Slash::DB->new('slash');
	$I{query} = new CGI;

	# %I legacy
	$I{F} = $user_cfg->{'form'};
	my $user = getUser($ENV{REMOTE_USER});
	$I{currentMode} = $user->{mode};
	# When we can move this method into Slash::Apache::User
	# this can go away
	$user_cfg->{'user'} = $user;
	# %I legacy
	$I{U} = $user;

	return 1;
}

########################################################
# createSelect()
# Pass it a hashref and a default value and it generates
# a select menu. I am really questioning in my head
# the existance of this method. We could probably get
# rid of it and use something from CGI.pm (we already
# use it, so we might as well make full use of it)
# -Brian
sub createSelect {
	my ($label, $hashref, $default) = @_;
	print qq!\n<SELECT name="$label">\n!;

	while(my($code, $name) = each %$hashref) {
		my $selected = ($default eq $code) ? ' SELECTED' : '';
		print qq!\t<OPTION value="$code"$selected>$name</OPTION>\n!;
	}
	print "</SELECT>\n";
}


########################################################
sub selectTopic {
	my($name, $tid) = @_;

	my $html_to_display = qq!<SELECT NAME="$name">\n!;
	my $topicbank = $I{dbobject}->getTopics();
	foreach my $thistid (sort keys %$topicbank) {
		my $topic = $I{dbobject}->getTopics($thistid);
		my $selected = $topic->{tid} eq $tid ? ' SELECTED' : '';
		$html_to_display .= qq!\t<OPTION VALUE="$topic->{tid}"$selected>$topic->{alttext}</OPTION>\n!;
	}
	$html_to_display .= "</SELECT>\n";
	print $html_to_display;
}

########################################################
# Drop down list of available sections (based on admin seclev)
sub selectSection {
	my($name, $section, $SECT) = @_;
	my $sectionBank = $I{dbobject}->getSectionBank();

	if ($SECT->{isolate}) {
		print qq!<INPUT TYPE="hidden" NAME="$name" VALUE="$section">\n!;
		return;
	}

	my $html_to_display = qq!<SELECT NAME="$name">\n!;
	foreach my $s (sort keys %{$sectionBank}) {
		my $S = $sectionBank->{$s};
		next if $S->{isolate} && getCurrentUser('aseclev') < 500;
		my $selected = $s eq $section ? ' SELECTED' : '';
		$html_to_display .= qq!\t<OPTION VALUE="$s"$selected>$S->{title}</OPTION>\n!;
	}
	$html_to_display .= "</SELECT>";
	print $html_to_display;
}

########################################################
sub selectSortcode {
	my $sortcode = $I{dbobject}->getCodes('sortcodes');

	my $html_to_display .= qq!<SELECT NAME="commentsort">\n!;
	foreach my $id (keys %$sortcode) {
		my $selected = $id eq getCurrentUser('commentsort') ? ' SELECTED' : '';
		$html_to_display .= qq!<OPTION VALUE="$id"$selected>$sortcode->{$id}</OPTION>\n!;
	}
	$html_to_display .= "</SELECT>";
	return $html_to_display;
}

########################################################
sub selectMode {
	my $commentcode = $I{dbobject}->getCodes('commentmodes');

	my $html_to_display .= qq!<SELECT NAME="mode">\n!;
	foreach my $id (keys %$commentcode) {
		my $selected = $id eq getCurrentUser('mode') ? ' SELECTED' : '';
		$html_to_display .= qq!<OPTION VALUE="$id"$selected>$commentcode->{$id}</OPTION>\n!;
	}
	$html_to_display .= "</SELECT>";
	return $html_to_display;
}

########################################################
# Prep for evaling (no \r allowed)
sub prepEvalBlock {
	my($b) = @_;
	$b =~ s/\r//g;
	return $b;
}

########################################################
# Preps a block for evaling (escaping out " mostly)
sub prepBlock {
	my($b) = @_;
	$b =~ s/\r//g;
	$b =~ s/"/\\"/g;
	$b = qq!"$b";!;
	return $b;
}

########################################################
# Gets a block, and ready's it for evaling
sub getEvalBlock {
	my($name) = @_;
	my $block = getSectionBlock($name);
	my $execme = prepEvalBlock($block);
	return $execme;
}

########################################################
# Gets the appropriate block depending on your section
# or else fall back to one that exists
sub getSectionBlock {
	my($name) = @_;
	my $thissect = getCurrentUser('light')? 'light' : $I{currentSection};
	my $block;
	if ($thissect) {
		$block = $I{dbobject}->getBlock($thissect . "_$name");
	}
	$block ||= $I{dbobject}->getBlock($name);
	return $block;
}

########################################################
# Get a Block based on mode, section & name, and prep it for evaling
sub getWidgetBlock {
	my($name) = @_;
	my $block = getSectionBlock($name);
	my $execme = prepBlock($block);
	return $execme;
}


########################################################
# Replace $_[0] with $_[1] || "0" in the User Hash
# users by getUser to allow form parameters to override user parameters
sub overRide {
	my($user, $p, $d) = @_;
	if (defined $I{query}->param($p)) {
		$user->{$p} = $I{query}->param($p);
	} else {
		$user->{$p} ||= $d || '0';
	}
}



########################################################
# When passed an ID it creates the user hash. If it is
# determined that this is an anonymous coward, it
# creates that form of the user account.
sub getUser {
	my($uid) = @_;
	#Ok, lets build user
	my $user;
	my $form = getCurrentForm();

	if (($uid != $I{anonymous_coward_uid})
		&& ($user = $I{dbobject}->getUser($uid, $ENV{SCRIPT_NAME}))) { 
	# should the below just be done in the library call for getUser?

		# Get the Timezone Stuff
		my $timezones = $I{dbobject}->getCodes('tzcodes');

		$user->{offset} = $timezones->{ $user->{tzcode} };

		my $dateformats = $I{dbobject}->getCodes('dateformats');

		$user->{'format'} = $dateformats->{ $user->{dfid} };
		$user->{'is_anon'} = 0;


	} else {
		getAnonCookie($user);
		my $coward = getCurrentAnonymousCoward();
		$I{SETCOOKIE} = setCookie('anon', $user->{anon_id}, 1);
		#Now, we copy $coward into user
		#Probably should improve on this
		for (keys %$coward) {
			$user->{$_} = $coward->{$_};
		}
		$user->{'is_anon'} = 1;

	}

	# Add On Admin Junk
	if ($form->{op} eq 'adminlogin') {
		my $sid;
		($user->{aseclev}, $sid) =
			$I{dbobject}->setAdminInfo($form->{aaid}, $form->{apasswd});			
		if ($user->{aseclev}) {
			$user->{aid} = $I{F}{aaid};
			$I{SETCOOKIE} = setCookie('session', $sid);
		} else {
			$user->{aid} = undef;
		}

	} elsif (length($I{query}->cookie('session')) > 3) {
		(@{$user}{qw[aid aseclev asection url]}) =
			$I{dbobject}->getAdminInfo(
				$I{query}->cookie('session'), $I{admin_timeout}
			);

	} else { 
		$user->{aid} = '';
		$user->{aseclev} = 0;
	}

	# Set a few defaults
	#passing in $user for the moment
	overRide($user, 'mode', 'thread');
	overRide($user, 'savechanges');
	overRide($user, 'commentsort');
	overRide($user, 'threshold');
	overRide($user, 'posttype');
	overRide($user, 'noboxes');
	overRide($user, 'light');


	$user->{seclev} = $user->{aseclev} if $user->{aseclev} > $user->{seclev};

	$user->{breaking}=0;

	if ($user->{commentlimit} > $I{breaking} && $user->{mode} ne 'archive') {
		$user->{commentlimit} = int($I{breaking} / 2);
		$user->{breaking} = 1;
	}

	# All sorts of checks on user data
	$user->{tzcode}		= uc($user->{tzcode});
	$user->{clbig}		||= 0;
	$user->{clsmall}	||= 0;
	$user->{exaid}		= testExStr($user->{exaid}) if $user->{exaid};
	$user->{exboxes}	= testExStr($user->{exboxes}) if $user->{exboxes};
	$user->{extid}		= testExStr($user->{extid}) if $user->{extid};
	$user->{points}		= 0 unless $user->{willing}; # No points if you dont want 'em

	return $user;
}

###############################################################	
#  What is it?  Where does it go?  The Random Leftover Shit

########################################################
# is this in User.pm now, or here, or both?
sub setCookie {
	my($name, $val, $session) = @_;

	return unless $name;
	# Can't we set a cookie with no value?  or is that not allowed?
	return unless $val;
	# domain must start with a . and have one more .
	# embedded in it, else we ignore it
	my $domain = $I{cookiedomain} &&
		$I{cookiedomain} =~ /^\..+\./ ? $I{cookiedomain} : '';

	my %cookie = (
		-name		=> $name,
		-path		=> $I{cookiepath},
		-value		=> $val || '',
	);

	$cookie{-expires} = '+1y' unless $session;
	$cookie{-domain}  = $domain if $domain;

	return {
		-date		=> CGI::expires(0, 'http'),
		-set_cookie	=> $I{query}->cookie(%cookie)
	};
}


########################################################
# Returns YY/MM/DD/HHMMSS all ready to be inserted
sub getsid {
	my($sec, $min, $hour, $mday, $mon, $year) = localtime;
	$year = $year % 100;
	my $sid = sprintf('%02d/%02d/%02d/%02d%0d2%02d',
		$year, $mon+1, $mday, $hour, $min, $sec);
	return $sid;
}


########################################################
# Returns the directory (eg YY/MM/DD/) that stories are being written in today
sub getsiddir {
	my($mday, $mon, $year) = (localtime)[3, 4, 5];
	$year = $year % 100;
	my $sid = sprintf('%02d/%02d/%02d/', $year, $mon+1, $mday);
	return $sid;
}


########################################################
# Saves an entry to the access log for static pages
# typically called now as part of getAd()
# We need to have logging occur in its own module
# for the next version
sub anonLog {
	my($op, $data) = ('/', '');

	$_ = $ENV{REQUEST_URI};
	s/(.*)\?/$1/;
	if (/404/) {
		$op = '404';
	} elsif (m[/(.*?)/(.*).shtml]) {
		($op, $data) = ($1,$2);
	} elsif (m[/(.*).shtml]) {
		$op = $1;
	} elsif (m[/(.+)]) {
		$data = $op = $1;
	} else {
		$data = $op = 'index';
	}

	$data =~ s/_F//;
	$op =~ s/_F//;

	$I{dbobject}->writelog($op, $data);
}


########################################################
# Takes the address, subject and an email, and does what it says
# used by dailyStuff, users.pl, and someday submit.pl
sub sendEmail {
	my($addr, $subject, $content) = @_;
	sendmail(
		smtp	=> $I{smtp_server},
		subject	=> $subject,
		to	=> $addr,
		body	=> $content,
		from	=> $I{mailfrom}
	) or apacheLog("Can't send mail '$subject' to $addr: $Mail::Sendmail::error");
}


########################################################
# The generic "Link a Story" function, used wherever stories need linking
sub linkStory {
	my($c) = @_;
	my($l, $dynamic);

	if ($I{currentMode} ne 'archive' && ($ENV{SCRIPT_NAME} || !$c->{section})) {
		$dynamic = 1 if $c->{mode} || exists $c->{threshold} || $ENV{SCRIPT_NAME};
		$l .= '&mode=' . ($c->{mode} || $I{U}{mode});
		$l .= "&threshold=$c->{threshold}" if exists $c->{threshold};
	}

	return qq!<A HREF="$I{rootdir}/! .
		($dynamic ? "article.pl?sid=$c->{sid}$l" : "$c->{section}/$c->{sid}.shtml") .
		qq!">$c->{'link'}</A>!;
			# "$c->{section}/$c->{sid}$userMode".".shtml").
}

########################################################
# Sets the appropriate @fg and @bg color pallete's based
# on what section you're in.  Used during initialization
sub getSectionColors {
	my $color_block = shift;
	my @colors;

	# they damn well better be legit
	if ($I{F}{colorblock}) {
		@colors = map { s/[^\w#]+//g ; $_ } split m/,/, $I{F}{colorblock};
	} else {
		@colors = split m/,/, getSectionBlock('colors');
	}

	$I{fg} = [@colors[0..3]];
	$I{bg} = [@colors[4..7]];
}


########################################################
# Gets sections wherver needed.  if blank, gets settings for homepage, and
# if defined tries to use cache.
sub getSection {
	my ($section) = @_;
	return { title => $I{slogan}, artcount => $I{U}{maxstories} || 30, issue => 3 }
		unless $section;
	return $I{dbobject}->getSectionBank($section);
}


###############################################################################
# Dealing with Polls

########################################################

########################################################
sub pollbooth {
	my($qid, $notable) = @_;

	$qid = $I{dbobject}->getVar('currentqid', 'value') unless $qid;
	my $qid_htm = stripByMode($qid, 'attribute');

	my $polls = $I{dbobject}->getPoll($qid);
	my($x, $tablestuff) = (0);
	for (@$polls) {
		my($question, $answer, $aid) = @$_;
		if ($x == 0) {
			$tablestuff = <<EOT;
<FORM ACTION="$I{rootdir}/pollBooth.pl">
\t<INPUT TYPE="hidden" NAME="qid" VALUE="$qid_htm">
<B>$question</B>
EOT
			$tablestuff .= <<EOT if $I{currentSection};
\t<INPUT TYPE="hidden" NAME="section" VALUE="$I{currentSection}">
EOT
			$x++;
		}
		$tablestuff .= qq!<BR><INPUT TYPE="radio" NAME="aid" VALUE="$aid">$answer\n!;
	}

	my $voters = $I{dbobject}->getPollQuestion($qid, 'voters');
	my $comments = $I{dbobject}->countComments($qid);
#	my $comments = $I{dbobject}->getPollComments($qid);
	my $sect = "section=$I{currentSection}&" if $I{currentSection};

	$tablestuff .= qq!<BR><INPUT TYPE="submit" VALUE="Vote"> ! .
		qq![ <A HREF="$I{rootdir}/pollBooth.pl?${sect}qid=$qid_htm&aid=$I{anonymous_coward_uid}"><B>Results</B></A> | !;
	$tablestuff .= qq!<A HREF="$I{rootdir}/pollBooth.pl?$sect"><B>Polls</B></A> !
		unless $notable eq 'rh';
	$tablestuff .= "Votes:<B>$voters</B>" if $notable eq 'rh';
	$tablestuff .= " ] <BR>\n";
	$tablestuff .= "Comments:<B>$comments</B> | Votes:<B>$voters</B>\n" if $notable ne 'rh';
	$tablestuff .="</FORM>\n";

	return $tablestuff if $notable;
	fancybox($I{fancyboxwidth}, 'Poll', $tablestuff, 'c');
}


###############################################################################
#
# Some Random Dave Code for HTML validation
# (pretty much the last legacy of daveCode[tm] by demaagd@imagegroup.com
#

########################################################
sub stripByMode {
	my($str, $fmode, $no_white_fix) = @_;
	$fmode ||= 'nohtml';

	$str =~ s/(\S{90})/$1 /g unless $no_white_fix;
	if ($fmode eq 'literal' || $fmode eq 'exttrans' || $fmode eq 'attribute') {
		# Encode all HTML tags
		$str =~ s/&/&amp;/g;
		$str =~ s/</&lt;/g;
		$str =~ s/>/&gt;/g;
	}

	# this "if" block part of patch from Ben Tilly
	if ($fmode eq 'plaintext' || $fmode eq 'exttrans') {
		$str = stripBadHtml($str);
		$str =~ s/\n/<BR>/gi;  # pp breaks
		$str =~ s/(?:<BR>\s*){2,}<BR>/<BR><BR>/gi;
		# Preserve leading indents
		$str =~ s/\t/    /g;
		$str =~ s/<BR>\n?( +)/"<BR>\n" . ("&nbsp; " x length($1))/ieg;

	} elsif ($fmode eq 'nohtml') {
		$str =~ s/<.*?>//g;
		$str =~ s/<//g;
		$str =~ s/>//g;

	} elsif ($fmode eq 'attribute') {
		$str =~ s/"/&#34;/g;

	} else {
		$str = stripBadHtml($str);
	}

	return $str;
}

########################################################
sub stripBadHtml  {
	my $str = shift;

	$str =~ s/<(?!.*?>)//gs;
	$str =~ s/<(.*?)>/approveTag($1)/sge;

	$str =~ s/></> </g;

	return $str;
}

########################################################
sub fixHref {
	my($rel_url, $print_errs) = @_;
	my $abs_url; # the "fixed" URL
	my $errnum; # the errnum for 404.pl

	for my $qr (@{$I{fixhrefs}}) {
		if ($rel_url =~ $qr->[0]) {
			my @ret = $qr->[1]->($rel_url);
			return $print_errs ? @ret : $ret[0];
		}
	}

	if ($rel_url =~ /^www\.\w+/) {
		# errnum 1
		$abs_url = "http://$rel_url";
		return($abs_url, 1) if $print_errs;
		return $abs_url;

	} elsif ($rel_url =~ /^ftp\.\w+/) {
		# errnum 2
		$abs_url = "ftp://$rel_url";
		return ($abs_url, 2) if $print_errs;
		return $abs_url;

	} elsif ($rel_url =~ /^[\w\-\$\.]+\@\S+/) {
		# errnum 3
		$abs_url = "mailto:$rel_url";
		return ($abs_url, 3) if $print_errs;
		return $abs_url;

	} elsif ($rel_url =~ /^articles/ && $rel_url =~ /\.shtml$/) {
		# errnum 6
		my @chunks = split m|/|, $rel_url;
		my $file = pop @chunks;

		if ($file =~ /^98/ || $file =~ /^0000/) {
			$rel_url = "$I{rootdir}/articles/older/$file";
			return ($rel_url, 6) if $print_errs;
			return $rel_url;
		} else {
			return;
		}

	} elsif ($rel_url =~ /^features/ && $rel_url =~ /\.shtml$/) {
		# errnum 7
		my @chunks = split m|/|, $rel_url;
		my $file = pop @chunks;

		if ($file =~ /^98/ || $file =~ /~00000/) {
			$rel_url = "$I{rootdir}/features/older/$file";
			return ($rel_url, 7) if $print_errs;
			return $rel_url;
		} else {
			return;
		}

	} elsif ($rel_url =~ /^books/ && $rel_url =~ /\.shtml$/) {
		# errnum 8
		my @chunks = split m|/|, $rel_url;
		my $file = pop @chunks;

		if ($file =~ /^98/ || $file =~ /^00000/) {
			$rel_url = "$I{rootdir}/books/older/$file";
			return ($rel_url, 8) if $print_errs;
			return $rel_url;
		} else {
			return;
		}

	} elsif ($rel_url =~ /^askslashdot/ && $rel_url =~ /\.shtml$/) {
		# errnum 9
		my @chunks = split m|/|, $rel_url;
		my $file = pop @chunks;

		if ($file =~ /^98/ || $file =~ /^00000/) {
			$rel_url = "$I{rootdir}/askslashdot/older/$file";
			return ($rel_url, 9) if $print_errs;
			return $rel_url;
		} else {
			return;
		}

	} else {
		# if we get here, we don't know what to
		# $abs_url = $rel_url;
		return;
	}

	# just in case
	return $abs_url;
}

########################################################
sub approveTag {
	my $tag = shift;

	$tag =~ s/^\s*?(.*)\s*?$/$1/; # trim leading and trailing spaces

	$tag =~ s/\bstyle\s*=(.*)$//i; # go away please

	# Take care of URL:foo and other HREFs
	if ($tag =~ /^URL:(.+)$/i) {
		my $url = fixurl($1);
		return qq!<A HREF="$url">$url</A>!;
	} elsif ($tag =~ /href\s*=(.+)$/i) {
		my $url = fixurl($1);
		return qq!<A HREF="$url">!;
	}

	# Validate all other tags
	$tag =~ s|^(/?\w+)|\U$1|;
	foreach my $goodtag (@{$I{approvedtags}}) {
		return "<$tag>" if $tag =~ /^$goodtag$/ || $tag =~ m|^/$goodtag$|;
	}
}

########################################################
sub fixparam {
	fixurl($_[0], 1);
}

########################################################
sub fixurl {
	my($url, $parameter) = @_;

	# RFC 2396
	my $mark = quotemeta(q"-_.!~*'()");
	my $alphanum = 'a-zA-Z0-9';
	my $unreserved = $alphanum . $mark;
	my $reserved = quotemeta(';|/?:@&=+$,');
	my $extra = quotemeta('%#');

	if ($parameter) {
		$url =~ s/([^$unreserved])/sprintf "%%%02X", ord $1/ge;
		return $url;
	} else {
		$url =~ s/[" ]//g;
		$url =~ s/^'(.+?)'$/$1/g;
		$url =~ s/([^$unreserved$reserved$extra])/sprintf "%%%02X", ord $1/ge;
		$url = fixHref($url) || $url;
		my $decoded_url = decode_entities($url);
		return $decoded_url =~ s|^\s*\w+script\b.*$||i ? undef : $url;
	}
}

########################################################
sub fixint {
	my ($int) = @_;
	$int =~ s/^\+//;
	$int =~ s/^(-?[\d.]+).*$/$1/ or return;
	return $int;
}

########################################################
sub chopEntity {
	my($text, $length) = @_;
	$text = substr($text, 0, $length) if $length;
	$text =~ s/&#?[a-zA-Z0-9]*$//;
	return $text;
}

###############################################################################
# Look and Feel Functions Follow this Point

########################################################
sub ssiHead {
	(my $dir = $I{rootdir}) =~ s|^http://[^/]+||;
	print "<!--#include virtual=\"$dir/";
	print "$I{currentSection}/" if $I{currentSection};
	print "slashhead$I{userMode}",".inc\"-->\n";
}

########################################################
sub ssiFoot {
	(my $dir = $I{rootdir}) =~ s|^http://[^/]+||;
	print "<!--#include virtual=\"$dir/";
	print "$I{currentSection}/" if $I{currentSection};
	print "slashfoot$I{userMode}",".inc\"-->\n";
}

########################################################
sub adminMenu {
	my $seclev = $I{U}{aseclev};
	return unless $seclev;
	print <<EOT;

<TABLE BGCOLOR="$I{bg}[2]" BORDER="0" WIDTH="100%" CELLPADDING="2" CELLSPACING="0">
	<TR><TD><FONT SIZE="${\( $I{fontbase} + 2 )}">
EOT

	print <<EOT if $seclev > 0;
	[ <A HREF="$I{rootdir}/admin.pl?op=adminclose">Logout $I{U}{aid}</A>
	| <A HREF="$I{rootdir}/">Home</A>
	| <A HREF="$I{rootdir}/getting_started.shtml">Help</A>
	| <A HREF="$I{rootdir}/admin.pl">Stories</A>
	| <A HREF="$I{rootdir}/topics.pl?op=listtopics">Topics</A>
EOT

	print <<EOT if $seclev > 10;
	| <A HREF="$I{rootdir}/admin.pl?op=edit">New</A>
EOT

	my $cnt = $I{dbobject}->getSubmissionCount($I{articles_only});

	print <<EOT if $seclev > 499;
	| <A HREF="$I{rootdir}/submit.pl?op=list">$cnt Submissions</A>
	| <A HREF="$I{rootdir}/admin.pl?op=blocked">Blocks</A>
	| <A HREF="$I{rootdir}/admin.pl?op=colored">Site Colors</A>
EOT

	print <<EOT if $seclev > 999 || ($I{U}{asection} && $seclev > 499);
	| <A HREF="$I{rootdir}/sections.pl?op=list">Sections</A>
	| <A HREF="$I{rootdir}/admin.pl?op=listfilters">Comment Filters</A>
EOT

	print <<EOT if $seclev >= 10000;
	| <A HREF="$I{rootdir}/admin.pl?op=authors">Authors</A>
	| <A HREF="$I{rootdir}/admin.pl?op=vars">Variables</A>
EOT

	print "] </FONT></TD></TR></TABLE>\n";
}

########################################################
sub formLabel {
	return qq!<P><FONT COLOR="$I{bg}[3]"><B>!, shift, "</B></FONT>\n",
		(@_ ? ('(', @_, ')') : ''), "<BR>\n";
}

########################################################
sub currentAdminUsers {
	my $html_to_display;

	my $aids = $I{dbobject}->currentAdmin();
	for (@$aids) {
		my($aid, $lastsecs, $lasttitle) = @$_;
		$html_to_display .= qq!\t<TR><TD BGCOLOR="$I{bg}[3]">\n!;
		$html_to_display .= qq!\t<A HREF="$I{rootdir}/admin.pl?op=authors&thisaid=$aid">!
			if $I{U}{aseclev} > 10000;
		$html_to_display .= qq!<FONT COLOR="$I{fg}[3]" SIZE="${\( $I{fontbase} + 2 )}"><B>$aid</B></FONT>!;
		$html_to_display .= '</A> ' if $I{U}{aseclev} > 10000;

		if ($aid eq $I{U}{aid}) {
		    $lastsecs = "-";
		} elsif ($lastsecs <= 99) {
		    $lastsecs .= "s";
		} elsif ($lastsecs <= 99*60) {
		    $lastsecs = int($lastsecs/60+0.5) . "m";
		} else {
		    $lastsecs = int($lastsecs/3600+0.5) . "h";
		}

		$lasttitle = "&nbsp;/&nbsp;$lasttitle" if $lasttitle && $lastsecs;

		$html_to_display .= qq!</TD><TD BGCOLOR="$I{bg}[2]"><FONT COLOR="$I{fg}[1]" SIZE="${\( $I{fontbase} + 2 )}">! .
		    "$lastsecs$lasttitle</FONT>&nbsp;</TD></TR>";
	}

	$html_to_display = <<EOT;
<TABLE HEIGHT="100%" BORDER="0" CELLPADDING="2" CELLSPACING="0">$html_to_display</TABLE>
EOT
	return $html_to_display;
}

########################################################
sub getAd {
	my $num = $_[0] || 1;
	return qq|<!--#perl sub="sub { use Slash; print Slash::getAd($num); }" -->|
		unless $ENV{SCRIPT_NAME};

	anonLog() unless $ENV{SCRIPT_NAME} =~ /\.pl/; # Log non .pl pages

	return $ENV{"AD_BANNER_$num"};
}

########################################################
sub redirect {
	my($url) = @_;

	if ($I{rootdir}) {	# rootdir strongly recommended
		$url = URI->new_abs($url, $I{rootdir})->canonical->as_string;
	} elsif ($url !~ m|^https?://|i) {	# but not required
		$url =~ s|^/*|$I{rootdir}/|;
	}

	my %params = (
		-type		=> 'text/html',
		-status		=> '302 Moved',
		-location	=> $url,
		($I{SETCOOKIE} ? %{$I{SETCOOKIE}} : ())
	);

	print CGI::header(%params), <<EOT;
<!DOCTYPE HTML PUBLIC "-//W3C//DTD HTML 3.2 Final//EN">
<HTML><HEAD><TITLE>302 Moved</TITLE></HEAD><BODY>
<P>You really want to be on <A HREF="$url">$url</A> now.</P>
</BODY>
EOT
}

########################################################
sub header {
	my($title, $section, $status) = @_;
	my $adhtml = '';
	$title ||= '';

	unless ($I{F}{ssi}) {
		my %params = (
			-cache_control => 'private',
			-type => 'text/html',
			($I{SETCOOKIE} ? %{$I{SETCOOKIE}} : ())
		);
		$params{-status} = $status if $status;
		$params{-pragma} = "no-cache"
			unless $I{U}{aseclev} || $ENV{SCRIPT_NAME} =~ /comments/;

		print CGI::header(%params);
	}

	$I{userMode} = $I{currentMode} eq 'flat' ? '_F' : '';
	$I{currentSection} = $section || '';
	getSectionColors();

	$title =~ s/<(.*?)>//g;

	print <<EOT if $title;
<!DOCTYPE HTML PUBLIC "-//W3C//DTD HTML 3.2 Final//EN">
<HTML><HEAD><TITLE>$title</TITLE>
EOT

	# ssi = 1 IS NOT THE SAME as ssi = 'yes'
	if ($I{F}{ssi} eq 'yes') {
		ssiHead($section);
		return;
	}

	if ($I{run_ads}) {
		$adhtml = getAd(1);
	}

	my $topics;
	unless ($I{U}{noicons} || $I{U}{light}) {
		$topics = $I{dbobject}->getBlock('topics');
	}

	my $vertmenu = $I{dbobject}->getBlock('mainmenu');
	my $menu = eval prepBlock($vertmenu);

	my $horizmenu = $menu;
	$horizmenu =~ s/^\s*//mg;
	$horizmenu =~ s/^-\s*//mg;
	$horizmenu =~ s/\s*$//mg;
	$horizmenu =~ s/<HR(?:>|\s[^>]*>)//g;
	$horizmenu = sprintf "[ %s ]", join ' | ', split /<BR>/, $horizmenu;

	my $sectionmenu = getSectionMenu();
	my $execme = getWidgetBlock('header');

	print eval $execme;
	print "\nError:$@\n" if $@;
	adminMenu();
}

########################################################
sub getSectionMenu {
	my $menu = $I{dbobject}->getBlock('sectionindex_html1');

	# the reason this is three calls is that sectionindex regularly is
	# updated by portald, so it's a more dynamic block
	$menu .= $I{dbobject}->getBlock('sectionindex');
	$menu .= $I{dbobject}->getBlock('sectionindex_html2');

	my $org_code = getEvalBlock('organisation');
	my $execme = prepEvalBlock($org_code);

	eval $execme;

	if ($@) {
		$menu .= "\n\n<!-- problem with eval of organisation:\n$@\nis the error. -->\n\n";
	}

	return $menu;
}

########################################################
sub footer {
	if ($I{F}{ssi}) {
		ssiFoot();
		return;
	}

	my $motd = '';
	if ($I{U}{aseclev}) {
		$motd .= currentAdminUsers();
	} else {
		$motd .= $I{dbobject}->getBlock('motd');
	}

	my $vertmenu = $I{dbobject}->getBlock('mainmenu');
	my $menu = prepBlock($vertmenu);

	my $horizmenu = eval $menu;
	$horizmenu =~ s/^\s*//mg;
	$horizmenu =~ s/^-\s*//mg;
	$horizmenu =~ s/\s*$//mg;
	$horizmenu =~ s/<HR(?:>|\s[^>]*>)//g;
	$horizmenu = sprintf "[ %s ]", join ' | ', split /<BR>/, $horizmenu;

	my $execme = getWidgetBlock('footer');
	print eval $execme;
	print "\nError:$@\n" if $@;
}

########################################################
sub titlebar {
	my($width, $title) = @_;
	my $execme = getWidgetBlock('titlebar');
	print eval $execme;
	print "\nError:$@\n" if $@;
}

########################################################
sub fancybox {
	my($width, $title, $contents) = @_;
	return unless $title && $contents;

	my $tmpwidth = $width;
	my $pct = 1 if $tmpwidth =~ s/%$//;
	# used in some blocks
	my $mainwidth = $tmpwidth-4;
	my $insidewidth = $mainwidth-8;
	if ($pct) {
		for ($mainwidth, $insidewidth) {
			$_ .= '%';
		}
	}

	my $execme = getWidgetBlock('fancybox');
	print eval $execme;
	print "\nError:$@\n" if $@;
}

########################################################
sub portalbox {
	my($width, $title, $contents, $bid, $url) = @_;
	return unless $title && $contents;

	$title = qq!<FONT COLOR="$I{fg}[3]">$title</FONT>!
		if $url && !$I{U}{light};
	$title = qq!<A HREF="$url">$title</A>! if $url;

	unless ($I{U}{exboxes}) {
		fancybox($width, $title, $contents);
		return;
	}

	my $execme = getWidgetBlock('portalmap');
	$title = eval $execme if $bid;

	my $tmpwidth = $width;
	my $pct = 1 if $tmpwidth =~ s/%$//;
	# used in some blocks
	my $mainwidth = $tmpwidth-4;
	my $insidewidth = $mainwidth-8;
	if ($pct) {
		for ($mainwidth, $insidewidth) {
			$_ .= '%';
		}
	}

	$execme = getWidgetBlock('fancybox');
	my $e = eval $execme;
	print "\nError:$@\n" if $@;
	return $e;
}

########################################################
# Behold, the beast that is threaded comments
sub selectComments {
	my($sid, $cid) = @_;
	$I{shit} = 0 if $I{F}{ssi};
	my $sql = "SELECT cid," . getDateFormat('date', 'time', $I{U}) . ",
				subject,comment,
				nickname,homepage,fakeemail,
				users.uid as uid,sig,
				comments.points as points,pid,sid,
				lastmod, reason
			   FROM comments,users
			  WHERE sid=" . $I{dbh}->quote($sid) . "
			    AND comments.uid=users.uid";
	$sql .= "	    AND comments.cid >= $I{F}{pid} " if $I{F}{pid} && $I{shit}; # BAD
	$sql .= "	    AND comments.cid >= $cid " if $cid && $I{shit}; # BAD
	$sql .= "	    AND (";
	$sql .= "		comments.uid=$I{U}{uid} OR " if $I{U}{uid} != $I{anonymous_coward_uid};
	$sql .= "		cid=$cid OR " if $cid;
	$sql .= "		comments.points >= " . $I{dbh}->quote($I{U}{threshold}) . " OR " if $I{U}{hardthresh};
	$sql .= "		  1=1 )   ";
	$sql .= "	  ORDER BY ";
	$sql .= "comments.points DESC, " if $I{U}{commentsort} eq '3';
	$sql .= " cid ";
	$sql .= ($I{U}{commentsort} == 1 || $I{U}{commentsort} == 5) ? 'DESC' : 'ASC';

	$sql .= "		LIMIT $I{shit}" if ! ($I{F}{pid} || $cid) && $I{shit} > 0;

	my $thisComment = $I{dbh}->prepare_cached($sql) or apacheLog($sql);
	$thisComment->execute or apacheLog($sql);

	my $comments; # One bigass struct full of comments
	foreach my $x (0..6) { $comments->[0]{totals}[$x] = 0 }

	while (my $C = $thisComment->fetchrow_hashref) {
		$C->{pid} = 0 if $I{U}{commentsort} > 3; # Ignore Threads

		$C->{points}++ if length($C->{comment}) > $I{U}{clbig}
			&& $C->{points} < $I{comment_maxscore} && $I{U}{clbig} != 0;

		$C->{points}-- if length($C->{comment}) < $I{U}{clsmall}
			&& $C->{points} > $I{comment_minscore} && $I{U}{clsmall};

		# fix points in case they are out of bounds
		$C->{points} = $I{comment_minscore}
			if $C->{points} < $I{comment_minscore};
		$C->{points} = $I{comment_maxscore}
			if $C->{points} > $I{comment_maxscore};

		my $tmpkids = $comments->[$C->{cid}]{kids};
		my $tmpvkids = $comments->[$C->{cid}]{visiblekids};
		$comments->[$C->{cid}] = $C;
		$comments->[$C->{cid}]{kids} = $tmpkids;
		$comments->[$C->{cid}]{visiblekids} = $tmpvkids;

		push @{$comments->[$C->{pid}]{kids}}, $C->{cid};
		$comments->[0]{totals}[$C->{points} - $I{comment_minscore}]++;  # invert minscore
		$comments->[$C->{pid}]{visiblekids}++
			if $C->{points} >= $I{U}{threshold};

		$I{U}{points} = 0 if $C->{uid} == $I{U}{uid}; # Mod/Post Rule
	}

	my $count = $thisComment->rows;
	$thisComment->finish;

	getCommentTotals($comments);
	$I{dbobject}->updateCommentTotals($sid, $comments) if $I{F}{ssi};
	reparentComments($comments);
	return($comments,$count);
}

########################################################
sub getCommentTotals {
	my ($comments) = @_;
	for my $x (0..5) {
		$comments->[0]{totals}[5-$x] += $comments->[0]{totals}[5-$x+1];
	}
}


########################################################
sub reparentComments {
	my ($comments) = @_;
	my $depth = $I{max_depth} || 7;

	return unless $depth || $I{U}{reparent};

	# adjust depth for root pid or cid
	if (my $cid = $I{F}{cid} || $I{F}{pid}) {
		while ($cid && (my($pid) = getCommentPid($I{F}{sid}, $cid))) {
			$depth++;
			$cid = $pid;
		}
	}

	for (my $x = 1; $x < @$comments; $x++) {
		next unless $comments->[$x];

		my $pid = $comments->[$x]{pid};
		my $reparent;

		# do threshold reparenting thing
		if ($I{U}{reparent} && $comments->[$x]{points} >= $I{U}{threshold}) {
			my $tmppid = $pid;
			while ($tmppid && $comments->[$tmppid]{points} < $I{U}{threshold}) {
				$tmppid = $comments->[$tmppid]{pid};
				$reparent = 1;
			}

			if ($reparent && $tmppid >= ($I{F}{cid} || $I{F}{pid})) {
				$pid = $tmppid;
			} else {
				$reparent = 0;
			}
		}

		if ($depth && !$reparent) { # don't reparent again!
			# set depth of this comment based on parent's depth
			$comments->[$x]{depth} = ($pid ? $comments->[$pid]{depth} : 0) + 1;

			# go back each pid until we find one with depth less than $depth
			while ($pid && $comments->[$pid]{depth} >= $depth) {
				$pid = $comments->[$pid]{pid};
				$reparent = 1;
			}
		}

		if ($reparent) {
			# remove child from old parent
			if ($pid >= ($I{F}{cid} || $I{F}{pid})) {
				@{$comments->[$comments->[$x]{pid}]{kids}} =
					grep { $_ != $x }
					@{$comments->[$comments->[$x]{pid}]{kids}}
			}

			# add child to new parent
			$comments->[$x]{realpid} = $comments->[$x]{pid};
			$comments->[$x]{pid} = $pid;
			push @{$comments->[$pid]{kids}}, $x;
		}
	}
}

########################################################
sub selectThreshold  {
	my($counts) = @_;

	my $s = qq!<SELECT NAME="threshold">\n!;
	foreach my $x ($I{comment_minscore}..$I{comment_maxscore}) {
		my $select = ' SELECTED' if $x == $I{U}{threshold};
		$s .= <<EOT;
	<OPTION VALUE="$x"$select>$x: $counts->[$x - $I{comment_minscore}] comments
EOT
	}
	$s .= "</SELECT>\n";
}

########################################################
sub printComments {
	# return;
	my($sid, $pid, $cid, $commentstatus) = @_;

	$pid ||= '0';
	my $lvl = 0;

	# Get the Comments
	my($comments, $count) = selectComments($sid, $cid || $pid);

	# Should I index or just display normally?
	my $cc = 0;
	if ($comments->[$cid || $pid]{visiblekids}) {
		$cc = $comments->[$cid || $pid]{visiblekids};
	}

	$lvl++ if $I{U}{mode} ne 'flat' && $I{U}{mode} ne 'archive'
		&& $cc > $I{U}{commentspill}
		&& ($I{U}{commentlimit} > $cc || $I{U}{commentlimit} > $I{U}{commentspill});

	print qq!<TABLE WIDTH="100%" BORDER="0" CELLSPACING="1" CELLPADDING="2">\n!;

	if ($I{U}{mode} ne 'archive') {
		print qq!\t<TR><TD BGCOLOR="$I{bg}[3]" ALIGN="CENTER">!,
			qq!<FONT SIZE="${\( $I{fontbase} + 2 )}" COLOR="$I{fg}[3]">!;

		my($title, $section);
		# Print Story Name if Applicable
		if ($I{dbobject}->getStoryBySid($sid)) {
			$title = $I{dbobject}->getStoryBySid($sid, 'title');
			$section = $I{dbobject}->getStoryBySid($sid, 'section');
		} else {
			my $story = $I{dbobject}->getNewStory($sid, 'title', 'section');
			$title = $story->{'title'};
			$section = $story->{'section'};
		}

		if ($title) {
			printf "'%s'", linkStory({
				'link'	=> qq!<FONT COLOR="$I{fg}[3]">$title</FONT>!,
				sid	=> $sid,
				section	=> $section
			});
		} else {
			print linkComment({
				sid => $sid, pid => 0, op => '',
				color => $I{fg}[3], subject => 'Top'
			});
		}

		print ' | ';

		if ($I{U}{uid} == $I{anonymous_coward_uid}) {
			print qq!<A HREF="$I{rootdir}/users.pl"><FONT COLOR="$I{fg}[3]">!,
				qq!Login/Create an Account</FONT></A> !;
		} elsif ($I{U}{uid} != $I{anonymous_coward_uid}) {
			print qq!<A HREF="$I{rootdir}/users.pl?op=edituser">!,
				qq!<FONT COLOR="$I{fg}[3]">Preferences</FONT></A> !
		}

		print ' | ' . linkComment({
			sid => $sid, pid => 0, op => '',
			color=> $I{fg}[3], subject => 'Top'
		}) if $pid;

		print " | <B>$I{U}{points}</B> ",
			qq!<A HREF="$I{rootdir}/moderation.shtml"><FONT COLOR="$I{fg}[3]">!,
			"moderator</FONT></A> points " if $I{U}{points};

		print " | <B>$count</B> comments " if $count;
		# print " | <B>$cc</B> siblings " if $cc;
		print " (Spill at <B>$I{U}{commentspill}</B>!)",
			" | Index Only " if $lvl && $I{U}{mode} eq 'thread';

		print " | Starting at #$I{F}{startat}" if $I{F}{startat};

		print <<EOT;
 | <A HREF="$I{rootdir}/search.pl?op=comments&sid=$sid">
<FONT COLOR="$I{fg}[3]">Search Discussion</FONT></A></FONT>
	</TD></TR>

	<TR><TD BGCOLOR="$I{bg}[2]" ALIGN="CENTER"><FONT SIZE="${\( $I{fontbase} + 2 )}">
		<FORM ACTION="$I{rootdir}/comments.pl">
		<INPUT TYPE="HIDDEN" NAME="sid" VALUE="$sid">
		<INPUT TYPE="HIDDEN" NAME="cid" VALUE="$cid">
		<INPUT TYPE="HIDDEN" NAME="pid" VALUE="$pid">
		<INPUT TYPE="HIDDEN" NAME="startat" VALUE="$I{F}{startat}">
EOT

		print "Threshold: ", selectThreshold($comments->[0]{totals}),
			selectMode(), selectSortcode();


		print qq!\t\tSave:<INPUT TYPE="CHECKBOX" NAME="savechanges">!
			if $I{U}{uid} != $I{anonymous_coward_uid};

		print <<EOT;
		<INPUT TYPE="submit" NAME="op" VALUE="Change">
		<INPUT TYPE="submit" NAME="op" VALUE="Reply">
	</TD></TR>
	<TR><TD BGCOLOR="$I{bg}[3]" ALIGN="CENTER">
		<FONT COLOR="$I{fg}[3]" SIZE="${\( $I{fontbase} + 2 )}">
EOT

		print $I{dbobject}->getBlock('commentswarning'), "</FONT></FORM></TD></TR>";

		if ($I{U}{mode} eq 'nocomment') {
			print "</TABLE>";
			return;
		}
	} else {
		print <<EOT;
	<TR><TD BGCOLOR="$I{bg}[3]"><FONT COLOR="$I{fg}[3]" SIZE="${\( $I{fontbase} + 2 )}">
			This discussion has been archived.
			No new comments can be posted.
	</TD></TR>
EOT
	}

	print <<EOT if $I{U}{aseclev} || $I{U}{points};
	<FORM ACTION="$I{rootdir}/comments.pl" METHOD="POST">
	<INPUT TYPE="HIDDEN" NAME="sid" VALUE="$sid">
	<INPUT TYPE="HIDDEN" NAME="cid" VALUE="$cid">
	<INPUT TYPE="HIDDEN" NAME="pid" VALUE="$pid">
EOT

	if ($cid) {
		my $C = $comments->[$cid];
		dispComment($C);

		# Next and previous.
		my($n, $p);
		if (my $sibs = $comments->[$C->{pid}]{kids}) {
			for (my $x=0; $x< @$sibs; $x++) {
				($n,$p) = ($sibs->[$x+1], $sibs->[$x-1])
					if $sibs->[$x] == $cid;
			}
		}
		print qq!\t</TD></TR>\n\t<TR><TD BGCOLOR="$I{bg}[2]" ALIGN="CENTER">\n!;
		print "\t\t&lt;&lt;", linkComment($comments->[$p], 1) if $p;
		print ' | ', linkComment($comments->[$pid], 1) if $C->{pid};
		print ' | ', linkComment($comments->[$n], 1), "&gt;&gt;\n" if $n;
		print qq!\t</TD></TR>\n\t<TR><TD ALIGN="CENTER">!;
		moderatorCommentLog($sid, $cid);
		print "\t</TD></TR>\n";
	}

	my $lcp = linkCommentPages($sid, $pid, $cid, $cc);
	print $lcp;
	print "\t<TR><TD>\n" if $lvl; #|| $I{U}{mode} eq "nested" and $lvl);
	displayThread($sid, $pid, $lvl, $comments, $cid);
	print "\n\t</TD></TR>\n" if $lvl; # || ($I{U}{mode} eq "nested" and $lvl);
	print $lcp;

	my $delete_text = ($I{U}{aseclev} > 99 && $I{authors_unlimited})
		? "<BR><B>NOTE: Checked comments will be deleted.</B>"
		: "";

	print <<EOT if ($I{U}{aseclev} || $I{U}{points}) && $I{U}{uid} > 0;
	<TR><TD>
		<P>Have you read the
		<A HREF="$I{rootdir}/moderation.shtml">Moderator Guidelines</A>
		yet? (<B>Updated 9.9</B>)
		<INPUT TYPE="SUBMIT" NAME="op" VALUE="moderate">
		$delete_text
	</TD></TR></FORM>
EOT

	print "</TABLE>\n";
}

########################################################
sub moderatorCommentLog {
	my($sid, $cid) = @_;
	my $c = sqlSelectMany(  "comments.sid as sid,
				 comments.cid as cid,
				 comments.points as score,
				 subject, moderatorlog.uid as uid,
				 users.nickname as nickname,
				 moderatorlog.val as val,
				 moderatorlog.reason as reason",
				"moderatorlog, users, comments",
				"moderatorlog.active=1
				 AND moderatorlog.sid='$sid'
			     AND moderatorlog.cid=$cid
			     AND moderatorlog.uid=users.uid
			     AND comments.sid=moderatorlog.sid
			     AND comments.cid=moderatorlog.cid"
	);

	my(@reasonHist, $reasonTotal);
	if ($c->rows > 0) {
		print <<EOT if $I{U}{aseclev} > 1000;
<TABLE BGCOLOR="$I{bg}[2]" ALIGN="CENTER" BORDER="0" CELLPADDING="2" CELLSPACING="0">
	<TR BGCOLOR="$I{bg}[3]">
		<TH><FONT COLOR="$I{fg}[3]"> val </FONT></TH>
		<TH><FONT COLOR="$I{fg}[3]"> reason </FONT></TH>
		<TH><FONT COLOR="$I{fg}[3]"> moderator </FONT></TH>
	</TR>
EOT

		while (my $C = $c->fetchrow_hashref) {
			print <<EOT if $I{U}{aseclev} > 1000;
	<TR>
		<TD> <B>$C->{val}</B> </TD>
		<TD> $I{reasons}[$C->{reason}] </TD>
		<TD> $C->{nickname} ($C->{uid}) </TD>
	</TR>
EOT

			$reasonHist[$C->{reason}]++;
			$reasonTotal++;
		}

		print "</TABLE>\n" if $I{U}{aseclev} > 1000;
	}

	$c->finish;
	return unless $reasonTotal;

	print qq!<FONT COLOR="$I{bg}[3]"><B>Moderation Totals</B></FONT>:!;
	foreach (0 .. @reasonHist) {
		print "$I{reasons}->[$_]=$reasonHist[$_], " if $reasonHist[$_];
	}
	print "<B>Total=$reasonTotal</B>.";
}

########################################################
sub linkCommentPages {
	my($sid, $pid, $cid, $total) = @_;
	my($links, $page);
	return if $total < $I{U}{commentlimit} || $I{U}{commentlimit} < 1;

	for (my $x = 0; $x < $total; $x += $I{U}{commentlimit}) {
		$links .= ' | ' if $page++ > 0;
		$links .= "<B>(" if $I{F}{startat} && $x == $I{F}{startat};
		$links .= linkComment({
			sid => $sid, pid => $pid, cid => $cid,
			subject => $page, startat => $x
		});
		$links .= ")</B>" if $I{F}{startat} && $x == $I{F}{startat};
	}
	if ($I{U}{breaking}) {
		$links .= " ($I{sitename} Overload: CommentLimit $I{U}{commentlimit})";
	}

	return <<EOT;
	<TR><TD BGCOLOR="$I{bg}[2]" ALIGN="CENTER"><FONT SIZE="${\( $I{fontbase} + 2 )}">
		$links
	</FONT></TD></TR>
EOT
}

########################################################
sub linkComment {
	my($C, $comment, $date) = @_;
	my $x = qq!<A HREF="$I{rootdir}/comments.pl?sid=$C->{sid}!;
	$x .= "&op=$C->{op}" if $C->{op};
	$x .= "&threshold=" . ($C->{threshold} || $I{U}{threshold});
	$x .= "&commentsort=$I{U}{commentsort}";
	$x .= "&mode=$I{U}{mode}";
	$x .= "&startat=$C->{startat}" if $C->{startat};

	if ($comment) {
		$x .= "&cid=$C->{cid}";
	} else {
		$x .= "&pid=" . ($C->{realpid} || $C->{pid});
		$x .= "#$C->{cid}" if $C->{cid};
	}

	my $s = $C->{color}
		? qq!<FONT COLOR="$C->{color}">$C->{subject}</FONT>!
		: $C->{subject};

	$x .= qq!">$s</A>!;
	$x .= " by $C->{nickname}" if $C->{nickname};
	$x .= qq! <FONT SIZE="-1">(Score:$C->{points})</FONT> !
		if !$I{U}{noscores} && $C->{points};
	$x .= qq! <FONT SIZE="-1"> $C->{'time'} </FONT>! if $date;
	$x .= "\n";
	return $x;
}

########################################################
sub displayThread {
	my($sid, $pid, $lvl, $comments, $cid) = @_;

	my $displayed = 0;
	my $skipped = 0;
	my $hidden = 0;
	my $indent = 1;
	my $full = !$lvl;
	my $cagedkids = $full;

	if ($I{U}{mode} eq 'flat' || $I{U}{mode} eq 'archive') {
		$indent = 0;
		$full = 1;
	} elsif ($I{U}{mode} eq 'nested') {
		$indent = 1;
		$full = 1;
	}


	foreach my $cid (@{$comments->[$pid]{kids}}) {
		my $C = $comments->[$cid];

		$skipped++;
		$I{F}{startat} ||= 0;
		next if $skipped < $I{F}{startat};

		$I{F}{startat} = 0; # Once We Finish Skipping... STOP

		if ($C->{points} < $I{U}{threshold}) {
			if ($I{U}{uid} == $I{anonymous_coward_uid} || $I{U}{uid} != $C->{uid})  {
				$hidden++;
				next;
			}
		}

		my $highlight = 1 if $C->{points} >= $I{U}{highlightthresh};
		my $finish_list = 0;

		if ($full || $highlight) {
			print "<TABLE>" if $lvl && $indent;
			dispComment($C);
			print "</TABLE>" if $lvl && $indent;
			$cagedkids = 0 if $lvl && $indent;
			$displayed++;
		} else {
			my $pcnt = @{$comments->[$C->{pid}]{kids} } + 0;
			printf "\t\t<LI>%s\n",
				linkComment($C, $pcnt > $I{U}{commentspill}, "1");
			$finish_list++;
		}

		if ($C->{kids}) {
			print "\n\t<TR><TD>\n" if $cagedkids;
			print "\n\t<UL>\n" if $indent;
			displayThread($sid, $C->{cid}, $lvl+1, $comments);
			print "\n\t</UL>\n" if $indent;
			print "\n\t</TD></TR>\n" if $cagedkids;
		}

		print "</LI>\n" if $finish_list;

		last if $displayed >= $I{U}{commentlimit};
	}

	if ($hidden && !$I{U}{hardthresh} && $I{U}{mode} ne 'archive') {
		print qq!\n<TR><TD BGCOLOR="$I{bg}[2]">\n! if $cagedkids;
		print qq!<LI><FONT SIZE="${\( $I{fontbase} + 2 )}"><B> !,
			linkComment({
				sid => $sid, threshold => $I{comment_minscore}, pid => $pid,
				subject => "$hidden repl" . ($hidden > 1 ? 'ies' : 'y')
			}) . ' beneath your current threshold.</B></FONT>';
		print "\n\t</TD></TR>\n" if $cagedkids;
	}
	return $displayed;
}

########################################################
sub dispComment  {
	my($C) = @_;
	my $subj = $C->{subject};
	my $time = $C->{'time'};
	my $username;

	$username = $C->{fakeemail} ? <<EOT : $C->{nickname};
<A HREF="mailto:$C->{fakeemail}">$C->{nickname}</A>
<B><FONT SIZE="${\( $I{fontbase} + 2 )}">($C->{fakeemail})</FONT></B>
EOT

	(my $nickname  = $C->{nickname}) =~ s/ /+/g;
	my $userinfo = <<EOT unless $C->{nickname} eq $I{anon_name};
(<A HREF="$I{rootdir}/users.pl?op=userinfo&nick=$nickname">User #$C->{uid} Info</A>)
EOT

	my $userurl = qq!<A HREF="$C->{homepage}">$C->{homepage}</A><BR>!
		if length($C->{homepage}) > 8;

	my $score = '';
	unless ($I{U}{noscores}) {
		$score  = " (Score:$C->{points}";
		$score .= ", $I{reasons}[$C->{reason}]" if $C->{reason};
		$score .= ")";
	}

	$C->{comment} .= "<BR>$C->{sig}" unless $I{U}{nosigs};

	if ($I{F}{mode} ne 'archive' && length($C->{comment}) > $I{U}{maxcommentsize}
		&& $I{F}{cid} ne $C->{cid}) {

		$C->{comment} = substr $C->{comment}, 0, $I{U}{maxcommentsize};
		$C->{comment} .= sprintf '<P><B>%s</B>', linkComment({
			sid => $C->{sid}, cid => $C->{cid}, pid => $C->{cid},
			subject => "Read the rest of this comment..."
		}, 1);
	}

	my $comment = $C->{comment}; # Old Compatibility Thing

	my $execme = getWidgetBlock('comment');
	print eval $execme;
	print "\nError:$@\n" if $@;

	if ($I{U}{mode} ne 'archive') {
		my $pid = $C->{realpid} || $C->{pid};
		my $m = sprintf '%s | %s', linkComment({
			sid => $C->{sid}, pid => $C->{cid}, op => 'Reply',
			subject => 'Reply to This'
		}), linkComment({
			sid => $C->{sid},
			cid => $pid,
			pid => $pid,
			subject => 'Parent'
		}, $pid);

		if (((	   $I{U}{willing}
			&& $I{U}{points} > 0
			&& $C->{uid} ne $I{U}{uid}
			&& $C->{lastmod} ne $I{U}{uid})
		    || ($I{U}{aseclev} > 99 && $I{authors_unlimited}))
		    	&& $I{U}{uid} != $I{anonymous_coward_uid}) {

			my $o;
			foreach (0 .. @{$I{reasons}} - 1) {
				$o .= qq!\t<OPTION VALUE="$_">$I{reasons}[$_]</OPTION>\n!;
			}

			$m.= qq! | <SELECT NAME="reason_$C->{cid}">\n$o</SELECT> !;
		    }

		$m .= qq! | <INPUT TYPE="CHECKBOX" NAME="del_$C->{cid}"> !
			if $I{U}{aseclev} > 99;
		print qq!\n\t<TR><TD><FONT SIZE="${\( $I{fontbase} + 2 )}">\n! .
			qq![ $m ]\n\t</FONT></TD></TR>\n<TR><TD>!;
	}
}

##############################################################################
#  Functions for dealing with Story selection and Display

########################################################
sub dispStory {
	my($S, $A, $T, $full) = @_;
	my $title = $S->{title};
	if (!$full && index($S->{title}, ':') == -1
		&& $S->{section} ne $I{defaultsection}
		&& $S->{section} ne $I{F}{section}) {

		# Need Header
		my $SECT = getSection($S->{section});

		# Until something better can be done we manually
		# fix title for the appropriate mode. This is an
		# UGLY hack, but until something more configurable
		# comes along (and using a block, here might be an
		# even uglier hack...but would solve the immediate
		# problem.
		$title = $I{U}{light} ? <<LIGHT : <<NORMAL;
\t\t\t<A HREF="$I{rootdir}/$S->{section}/">$SECT->{title}</A>: $S->{title}
LIGHT
\t\t\t<A HREF="$I{rootdir}/$S->{section}/"><FONT COLOR="$I{fg}[3]">$SECT->{title}</FONT></A>: $S->{title}
NORMAL
	}

	titlebar($I{titlebar_width}, $title);

	my $bt = $full ? "<P>$S->{bodytext}</P>" : '<BR>';
	my $author = qq!<A HREF="$A->{url}">$S->{aid}</A>!;

	my $topicicon = '';
	$topicicon .= ' [ ' if $I{U}{noicons};
	$topicicon .= qq!<A HREF="$I{rootdir}/search.pl?topic=$T->{tid}">!;

	if ($I{U}{noicons}) {
		$topicicon .= "<B>$T->{alttext}</B>";
	} else {
		$topicicon .= <<EOT;
<IMG SRC="$I{imagedir}/topics/$T->{image}" WIDTH="$T->{width}" HEIGHT="$T->{height}"
	BORDER="0" ALIGN="RIGHT" HSPACE="20" VSPACE="10" ALT="$T->{alttext}">
EOT
	}

	$topicicon .= '</A>';
	$topicicon .= ' ] ' if $I{U}{noicons};

	my $execme = getWidgetBlock('story');
	print eval $execme;
	print "\nError:$@\n" if $@;

	if ($full && ($S->{bodytext} || $S->{books_publisher})) {
		my $execme = getWidgetBlock('storymore');
		print eval $execme;
		print "\nError:$@\n" if $@;
#	} elsif ($full) {
#		print $S->{bodytext};
	}
}

########################################################
sub displayStory {
	# caller is the pagename of the calling script
	my($sid, $full, $caller) = @_;

	# we need this for time stamping
	my $code_time = time;

	# this is a timestamp, in memory of this apache child
	# process, in raw seconds since 1970
	$I{storyBank}{timestamp} ||= $code_time;

	# set this to 0 if the calling page is index.pl and it's not
	# already defined
	# index.pl is the only script that loops through all of the stories
	# so this is the only script that will allow us to increment an array
	# to hold the proper count and sequence of the stories and their sids .
	$I{StoryCount} ||= 0 if $caller eq 'index';

	# this array is to store sids of the stories that are displayed on the front
	# index page. This is used for anonymous coward in article.pl to get the next
	# and previous query without hitting the database
	$I{sid_array}[$I{StoryCount}] = $sid
		if !$I{sid_array}[$I{StoryCount}] && $caller eq 'index';

	# difference between the timestamp on storyBank and the time this
	# code is executing
	my $diff = $code_time - $I{storyBank}{timestamp};

	# this will force the storyBank to refresh if one of it's members is
	# older than the value we set for $story_expire
	if ($code_time - $I{storyBank}{timestamp} > $I{story_expire} && $I{story_refresh} != 1) {
		$I{story_refresh} = 1;

		# This clears the stories from the cache (doesn't harm the database)
		$I{dbobject}->clearStory();

		# smack a time stamp on it with the current time (this is the new timestamp)
		$I{storyBank}{timestamp} = $code_time;
	}

	# give this member of storyBank the current iteration of
	# StoryCount if it's not already defined and the calling page is
	# index.pl

	$I{dbobject}->setStoryBySid($sid, 'story_order',$I{StoryCount})
	    if !$I{dbobject}->getStoryBySid($sid, 'story_order') && $caller eq 'index';


	# increment if the calling page was index.pl 
	$I{StoryCount}++ if $caller eq 'index';

	my $S = $I{dbobject}->getStoryBySid($sid);
	

	# convert the time of the story (this is mysql format) 
	# and convert it to the user's prefered format 
	# based on their preferences 
	$I{U}{storytime} = timeCalc($S->{'time'});

	if ($full && sqlTableExists($S->{section}) && $S->{section}) {
		my $E = sqlSelectHashref('*', $S->{section}, "sid='$S->{sid}'");
		foreach (keys %$E) {
			$S->{$_} = $E->{$_};
		}
	}

	# No, we do not need this variable, but for readability 
	# I think it is justified (and it is just a reference....)
	my $topic = $I{dbobject}->getTopics($S->{tid});
	dispStory($S, $I{dbobject}->getAuthor($S->{aid}), $topic, $full);
	return($S, $I{dbobject}->getAuthor($S->{aid}), $topic);
}

#######################################################################
# timeCalc 051199 PMG
# inputs: raw date from mysql
# returns: formatted date string from dateformats in mysql, converted to
# time strings that Date::Manip can format
#######################################################################
# interpolative hash for converting
# from mysql date format to perl
# the key is mysql's format,
# the value is perl's format
# Date::Manip format
my $timeformats = {
	'%M' => '%B',
	'%W' => '%A',
	'%D' => '%E',
	'%Y' => '%Y',
	'%y' => '%y',
	'%a' => '%a',
	'%d' => '%d',
	'%e' => '%e',
	'%c' => '%f',
	'%m' => '%m',
	'%b' => '%b',
	'%j' => '%j',
	'%H' => '%H',
	'%k' => '%k',
	'%h' => '%I',
	'%I' => '%I',
	'%l' => '%i',
	'%i' => '%M',
	'%r' => '%r',
	'%T' => '%T',
	'%S' => '%S',
	'%s' => '%S',
	'%p' => '%p',
	'%w' => '%w',
	'%U' => '%U',
	'%u' => '%W',
	'%%' => '%%'
};

sub timeCalc {
	# raw mysql date of story
	my $date = shift;

	# lexical
	my(@dateformats, $err);

	# I put this here because
	# when they select "6 ish" it
	# looks really stupid for it to
	# display "posted by xxx on 6 ish"
	# It looks better for it to read:
	# "posted by xxx around 6 ish"
	# call me anal!
	if ($I{U}{'format'} eq '%l ish' || $I{U}{'format'} eq '%h ish') {
		$I{U}{aton} = " around ";
	} else {
		$I{U}{aton} = " on ";
	}

	# find out the user's time based on personal offset
	# in seconds
	$date = DateCalc($date, "$I{U}{offset} SECONDS", \$err);

	# create a new U{} hash key member for storing the new format
	$I{U}{perlformat} = $I{U}{'format'};

	# interpolate from mysql format to perl format
	$I{U}{perlformat} =~ s/(\%\w)/$timeformats->{$1}/g;

	# convert the raw date to pretty formatted date
	$date = UnixDate($date, $I{U}{perlformat});

	# return the new pretty date
	return $date;
}

########################################################
sub pollItem {
	my($answer, $imagewidth, $votes, $percent) = @_;

	my $execme = getWidgetBlock('pollitem');
	print eval $execme;
	print "\nError:$@\n" if $@;
}

########################################################
sub testExStr {
	local($_) = @_;
	$_ .= "'" unless m/'$/;
	return $_;
}

########################################################
sub selectStories {
	my($SECT, $limit, $tid) = @_;

	my $s = "SELECT sid, section, title, date_format(" .
		getDateOffset('time', $I{U}) . ',"%W %M %d %h %i %p"),
			commentcount, to_days(' . getDateOffset('time', $I{U}) . "),
			hitparade
		   FROM newstories
		  WHERE 1=1 "; # Mysql's Optimize gets this.

	$s .= " AND displaystatus=0 " unless $I{F}{section};
	$s .= " AND time < now() "; # unless $I{U}{aseclev};
	$s .= "	AND (displaystatus>=0 AND '$SECT->{section}'=section)" if $I{F}{section};
	$I{F}{issue} =~ s/[^0-9]//g; # Kludging around a screwed up URL somewhere
	$s .= "   AND $I{F}{issue} >= to_days(" . getDateOffset("time", $I{U}) . ") "
		if $I{F}{issue};
	$s .= "	AND tid='$tid'" if $tid;

	# User Config Vars
	$s .= "	AND tid not in ($I{U}{extid})"		if $I{U}{extid};
	$s .= "	AND aid not in ($I{U}{exaid})"		if $I{U}{exaid};
	$s .= "	AND section not in ($I{U}{exsect})"	if $I{U}{exsect};

	# Order
	$s .= "	ORDER BY time DESC ";

	if ($limit) {
		$s .= "	LIMIT $limit";
	} elsif ($I{currentSection} eq 'index') {
		$s .= "	LIMIT $I{U}{maxstories}";
	} else {
		$s .= "	LIMIT $SECT->{artcount}";
	}
#	print "\n\n\n\n\n<-- stories select $s -->\n\n\n\n\n";

	my $cursor = $I{dbh}->prepare($s) or apacheLog($s);
	$cursor->execute or apacheLog($s);
	return $cursor;
}

########################################################
sub getOlderStories {
	my($cursor, $SECT)=@_;
	my($today, $stuff);

	$cursor ||= selectStories($SECT);

	unless($cursor->{Active}) {
		$cursor->finish;
		return "Your maximum stories is $I{U}{maxstories} ";
	}

	while (my($sid, $section, $title, $time, $commentcount, $day) = $cursor->fetchrow) {
		my($w, $m, $d, $h, $min, $ampm) = split m/ /, $time;
		if ($today ne $w) {
			$today  = $w;
			$stuff .= '<P><B>';
			$stuff .= <<EOT if $SECT->{issue} > 1;
<A HREF="$I{rootdir}/index.pl?section=$SECT->{section}&issue=$day&mode=$I{currentMode}">
EOT
			$stuff .= qq!<FONT SIZE="${\( $I{fontbase} + 4 )}">$w</FONT>!;
			$stuff .= '</A>' if $SECT->{issue} > 1;
			$stuff .= " $m $d</B></P>\n";
		}

		$stuff .= sprintf "<LI>%s ($commentcount)</LI>\n", linkStory({
			'link' => $title, sid => $sid, section => $section
		});
	}

	if ($SECT->{issue}) {
		my $yesterday;
		unless ($I{F}{issue} > 1 || $I{F}{issue}) {
			my @date = localtime();
			$date[4] += 1;
			$date[5] += 1;
			$date[6] += 1900;
			$yesterday = Date_DaysSince1BC($date[5], $date[4], $date[6])
		} else {
			$yesterday = int($I{F}{issue}) - 1;
		}

		my $min = $SECT->{artcount} + $I{F}{min};

		$stuff .= qq!<P ALIGN="RIGHT">! if $SECT->{issue};
		$stuff .= <<EOT if $SECT->{issue} == 1 || $SECT->{issue} == 3;
<BR><A HREF="$I{rootdir}/search.pl?section=$SECT->{section}&min=$min">
<B>Older Articles</B></A>
EOT
		$stuff .= <<EOT if $SECT->{issue} == 2 || $SECT->{issue} == 3;
<BR><A HREF="$I{rootdir}/index.pl?section=$SECT->{section}&mode=$I{currentMode}&issue=$yesterday">
<B>Yesterday's Edition</B></A>
EOT
	}
	$cursor->finish;
	return $stuff;
}

########################################################
# use lockTest to test if a story is being edited by someone else
########################################################
sub getImportantWords {
	my $s = shift;
	$s =~ s/[^A-Z0-9 ]//gi;
	my @w = split m/ /, $s;
	my @words;
	foreach (@w) {
		if (length($_) > 3 || (length($_) < 4 && uc($_) eq $_)) {
			push @words, $_;
		}
	}
	return @words;
}

########################################################
sub matchingStrings {
	my($s1, $s2)=@_;
	return '100' if $s1 eq $s2;
	my @w1 = getImportantWords($s1);
	my @w2 = getImportantWords($s2);
	my $m = 0;
	return 0 if @w1 < 2 || @w2 < 2;
	foreach my $w (@w1) {
		foreach (@w2) {
			$m++ if $w eq $_;
		}
	}
	return int($m / @w1 * 100) if $m;
	return 0;
}

########################################################
sub lockTest {
	my ($subj) = @_;
	return unless $subj;
	my $msg;
	my $locks = $I{dbobject}->getLock();
	for (@$locks) {
		my ($thissubj, $aid) = @$_;
		if ($aid ne $I{U}{aid} && (my $x = matchingStrings($thissubj, $subj))) {
			$msg .= <<EOT
<B>$x%</B> matching with <FONT COLOR="$I{fg}[1]">$thissubj</FONT> by <B>$aid</B><BR>
EOT

		}
	}
	return $msg;
}

########################################################
sub getAnonCookie {	
	my($user) = @_;
	if (my $cookie = $I{query}->cookie('anon')) {
		$user->{anon_id} = $cookie;
		$user->{anon_cookie} = 1;
	} else {
		$user->{anon_id} = getAnonId();
	}
}

########################################################
sub getAnonId {
	return '-1-' . getFormkey();
}

########################################################
sub getFormkey {
	my @rand_array = ( 'a' .. 'z', 'A' .. 'Z', 0 .. 9 );
	return join("", map { $rand_array[rand @rand_array] }  0 .. 9);
}

########################################################
sub getFormkeyId {
	my ($uid) = @_;
	my $user = getCurrentUser();

	# this id is the key for the commentkey table, either UID or
	# unique hash key generated by IP address
	my $id;

	# if user logs in during submission of form, after getting
	# formkey as AC, check formkey with user as AC
	if ($user->{uid} > 0 && $I{query}->param('rlogin') && length($I{F}{upasswd}) > 1) {
		getAnonCookie($user);
		$id = $user->{anon_id};
	} elsif ($uid > 0) {
		$id = $uid;
	} else {
		$id = $user->{anon_id};
	}
	return($id);
}


########################################################
sub intervalString {
	# Ok, this isn't necessary, but it makes it look better than saying:
	#  "blah blah submitted 23333332288 seconds ago"
	# call me anal.
	my $interval = shift;
	my $interval_string = "";

	if ($interval > 60) {
		my($hours, $minutes) = 0;
		if ($interval > 3600) {
			$hours = int($interval/3600);
			if ($hours > 1) {
				$interval_string = "$hours hours ";
			} elsif ($hours > 0) {
				$interval_string = "$hours hour ";
			}
			$minutes = int(($interval % 3600) / 60);

			} else {
				$minutes = int($interval / 60);
			}
			if ($minutes > 0) {
				$interval_string .= ", " if $hours;
				if ($minutes > 1) {
					$interval_string .= " $minutes minutes ";
				} else {
					$interval_string .= " $minutes minute ";
				}
			}
		} else {
			$interval_string = "$interval seconds ";
		}
		return($interval_string);
}

##################################################################
sub submittedAlready {
	my($formkey, $formname) = @_;

	my $cant_find_formkey_err = <<EOT;
<P><B>We can't find your formkey.</B></P>
<P>You must fill out a form and submit from that
form as required.</P>
EOT

	# find out if this form has been submitted already
	my($submitted_already, $submit_ts) = $I{dbobject}->checkForm($formkey, $formname)
		or errorMessage($cant_find_formkey_err) and return(0);

		if ($submitted_already) {
			# interval of when it was submitted (this won't be used unless it's already been submitted)
			my $interval_string = intervalString(time() - $submit_ts);
			my $submitted_already_err = <<EOT;
<B>Easy does it!</B>
<P>This comment has been submitted already, $interval_string ago.
No need to try again.</P>
EOT

			# else print an error
			errorMessage($submitted_already_err);
		}
		return($submitted_already);
}

##################################################################
# nice little function to print out errors
sub errorMessage {
	my ($error_message) = @_;
	print qq|$error_message\n|;
	return;
}




##################################################################
# make sure they're not posting faster than the limit
sub checkSubmission {
	my($formname, $limit, $max, $id) = @_;
	my $formkey_earliest = time() - $I{formkey_timeframe};

	my $last_submitted = $I{dbobject}->getSubmissionLast($id, $formname, $I{U});

	my $interval = time() - $last_submitted;

	if ($interval < $limit) {
		my $limit_string = intervalString($limit);
		my $interval_string = intervalString($interval);
		my $speed_limit_err = <<EOT;
<B>Slow down cowboy!</B><BR>
<P>$I{sitename} requires you to wait $limit_string between
each submission of $ENV{SCRIPT_NAME} in order to allow everyone to have a fair chance to post.</P>
<P>It's been $interval_string since your last submission!</P>
EOT
		errorMessage($speed_limit_err);
		return(0);

	} else {
		if ($I{dbobject}->checkTimesPosted($formname, $max, $id, $formkey_earliest, $I{U})) {
			undef $I{F}{formkey} unless $I{F}{formkey} =~ /^\w{10}$/;

			unless ($I{F}{formkey} && $I{dbobject}->checkFormkey($formkey_earliest, $formname, $id, $I{F}{formkey}, $I{U})) {
				$I{dbobject}->formAbuse("invalid form key", $ENV{REMOTE_ADDR}, $ENV{SCRIPT_NAME}, $ENV{QUERY_STRING});
				my $invalid_formkey_err = "<P><B>Invalid form key!</B></P>\n";
				errorMessage($invalid_formkey_err);
				return(0);
			}

			if (submittedAlready($I{F}{formkey}, $formname)) {
				$I{dbobject}->formAbuse("form already submitted", $ENV{REMOTE_ADDR}, $ENV{SCRIPT_NAME}, $ENV{QUERY_STRING});
				return(0);
			}

		} else {
			$I{dbobject}->formAbuse("max form submissions $max reached", $ENV{REMOTE_ADDR}, $ENV{SCRIPT_NAME}, $ENV{QUERY_STRING});
			my $timeframe_string = intervalString($I{formkey_timeframe});
			my $max_posts_err =<<EOT;
<P><B>You've reached you limit of maximum submissions to $ENV{SCRIPT_NAME} :
$max submissions over $timeframe_string!</B></P>
EOT
			errorMessage($max_posts_err);
			return(0);
		}
	}
	return(1);
}


########################################################
#sub CLOSE { $I{dbh}->disconnect if $I{dbh} }
########################################################
sub handler { 1 }
########################################################

########################################################
# All of these methods are just for backwards
# compatibility. They will all go away.

sub sqlConnect {
	$I{dbobject}->sqlConnect();
}
sub sqlSelectMany {
	$I{dbobject}->sqlSelectMany(@_);
}
sub sqlSelect {
	$I{dbobject}->sqlSelect(@_);
}
sub sqlSelectHash {
	$I{dbobject}->sqlSelect(@_);
}
sub selectCount  {
#Nothing seems to even call this method
	$I{dbobject}->selectCount(@_);
}
sub sqlSelectHashref {
	$I{dbobject}->sqlSelectHashref(@_);
}
sub sqlSelectAll {
	$I{dbobject}->sqlSelectAll(@_);
}
sub sqlUpdate {
	$I{dbobject}->sqlUpdate(@_);
}
sub sqlReplace {
	$I{dbobject}->sqlReplace(@_);
}
sub sqlInsert {
	$I{dbobject}->sqlInsert(@_);
}
sub sqlTableExists {
	$I{dbobject}->sqlTableExists(@_);
}
sub sqlSelectColumns {
	$I{dbobject}->sqlSelectColumns(@_);
}
