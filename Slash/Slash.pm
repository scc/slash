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
use CGI::Cookie;
use DBI;
use Data::Dumper;  # the debuggerer's best friend
use Date::Manip;
use Exporter ();
use File::Spec::Functions;
use HTML::Entities;
use Mail::Sendmail;
use URI;

use Slash::DB;
use Slash::Display;
use Slash::Utility;

use vars qw($VERSION @ISA @EXPORT %I $CRLF);

# this is the worst damned warning ever, so SHUT UP ALREADY!
$SIG{__WARN__} = sub { warn @_ unless $_[0] =~ /Use of uninitialized value/ };

$VERSION = '1.0.8';
@ISA	 = 'Exporter';
@EXPORT  = qw(
	approveTag getSlash linkStory getSection
	selectTopic selectSection fixHref
	getsid getsiddir getWidgetBlock
	anonLog pollbooth stripByMode header footer pollItem
	prepEvalBlock prepBlock formLabel
	titlebar fancybox portalbox printComments displayStory
	sendEmail getOlderStories timeCalc
	getEvalBlock dispStory lockTest getSlashConf
	dispComment linkComment redirect fixurl fixparam chopEntity
	getFormkeyId checkSubmission errorMessage createSelect
	createEnvironment createMenu
);
$CRLF = "\015\012";

###############################################################################
# Let's get this party Started
# Entirely legacy at this point
sub getSlashConf {
	my $constants = getCurrentStatic();
	# Yes this is ugly and should go away
	# Just as soon as the last of %I is gone, this is gone
	@I{ keys %$constants } = values %$constants;

	return \%I;
}


###############################################################################
# Entirely legacy at this point
sub getSlash {
	return unless $ENV{GATEWAY_INTERFACE};

	$I{dbobject} = getCurrentDB();

	# %I legacy
	$I{F} = getCurrentForm();
	$I{U} = getCurrentUser();

	getSlashConf();  # remove when %I is gone

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
	my($label, $hashref, $default, $return) = @_;
	my $html = qq!\n<SELECT NAME="$label">\n!;

	for my $code (sort keys %$hashref) {
		my $selected = ($default eq $code) ? ' SELECTED' : '';
		$html .= qq!\t<OPTION VALUE="$code"$selected>$hashref->{$code}</OPTION>\n!;
	}
	$html .= "</SELECT>\n";

	if ($return) {
		return $html;
	} else {
		print $html;
	}
}

########################################################
sub selectTopic {
	my($name, $tid, $return) = @_;
	my $dbslash = getCurrentDB();

	my $html_to_display = qq!<SELECT NAME="$name">\n!;
	my $topicbank = $dbslash->getTopics();
	foreach my $thistid (sort keys %$topicbank) {
		my $topic = $dbslash->getTopic($thistid);
		my $selected = $topic->{tid} eq $tid ? ' SELECTED' : '';
		$html_to_display .= qq!\t<OPTION VALUE="$topic->{tid}"$selected>$topic->{alttext}</OPTION>\n!;
	}
	$html_to_display .= "</SELECT>\n";

	if ($return) {
		return $html_to_display;
	} else {
		print $html_to_display;
	}
}

########################################################
# Drop down list of available sections (based on admin seclev)
sub selectSection {
	my($name, $section, $SECT, $return) = @_;
	my $dbslash = getCurrentDB();
	my $sectionBank = $dbslash->getSections();
	$SECT ||= {};

	if ($SECT->{isolate}) {
		print qq!<INPUT TYPE="hidden" NAME="$name" VALUE="$section">\n!;
		return;
	}

	my $html_to_display = qq!<SELECT NAME="$name">\n!;
	for my $s (sort keys %{$sectionBank}) {
		my $S = $sectionBank->{$s};
		next if $S->{isolate} && getCurrentUser('aseclev') < 500;
		my $selected = $s eq $section ? ' SELECTED' : '';
		$html_to_display .= qq!\t<OPTION VALUE="$s"$selected>$S->{title}</OPTION>\n!;
	}
	$html_to_display .= "</SELECT>";

	if ($return) {
		return $html_to_display;
	} else {
		print $html_to_display;
	}
}

########################################################
sub selectSortcode {
	my $dbslash = getCurrentDB();
	my $sortcode = $dbslash->getCodes('sortcodes');

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
	my $dbslash = getCurrentDB();
	my $commentcode = $dbslash->getCodes('commentmodes');

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

	my $dbslash = getCurrentDB();
	my $thissect = getCurrentUser('light') ? 'light' : getCurrentStatic('currentSection');
	my $block;
	if ($thissect) {
		$block = $dbslash->getBlock($thissect . "_$name", 'block');
	}
	$block ||= $dbslash->getBlock($name, 'block');
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


###############################################################	
#  What is it?  Where does it go?  The Random Leftover Shit

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

	local $_ = $ENV{REQUEST_URI};
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

	writeLog($op, $data);
}


########################################################
# Takes the address, subject and an email, and does what it says
# used by dailyStuff, users.pl, and someday submit.pl
sub sendEmail {
	my($addr, $subject, $content) = @_;
	my $constants = getCurrentStatic();
	sendmail(
		smtp	=> $constants->{smtp_server},
		subject	=> $subject,
		to	=> $addr,
		body	=> $content,
		from	=> $constants->{mailfrom}
	) or apacheLog("Can't send mail '$subject' to $addr: $Mail::Sendmail::error");
}


########################################################
# The generic "Link a Story" function, used wherever stories need linking
sub linkStory {
	my($c) = @_;
	my($l, $dynamic);

	if (getCurrentUser('currentMode') ne 'archive' && ($ENV{SCRIPT_NAME} || !$c->{section})) {
		$dynamic = 1 if $c->{mode} || exists $c->{threshold} || $ENV{SCRIPT_NAME};
		$l .= '&mode=' . ($c->{mode} || getCurrentUser('mode'));
		$l .= "&threshold=$c->{threshold}" if exists $c->{threshold};
	}

	my $rootdir = getCurrentStatic('rootdir');
	return qq!<A HREF="$rootdir/! .
		($dynamic ? "article.pl?sid=$c->{sid}$l" : "$c->{section}/$c->{sid}.shtml") .
		qq!">$c->{'link'}</A>!;
			# "$c->{section}/$c->{sid}$userMode".".shtml").
}

########################################################
# Sets the appropriate @fg and @bg color pallete's based
# on what section you're in.  Used during initialization
sub getSectionColors {
	my($color_block) = @_;
	my $constants = getCurrentStatic();
	my @colors;
	my $colorblock = getCurrentForm('colorblock');

	# they damn well better be legit
	if ($colorblock) {
		@colors = map { s/[^\w#]+//g ; $_ } split m/,/, $colorblock;
	} else {
		@colors = split m/,/, getSectionBlock('colors');
	}

	# %I included for backward compatability
	$I{fg} = $constants->{fg} = [@colors[0..3]];
	$I{bg} = $constants->{bg} = [@colors[4..7]];
}


########################################################
# Gets sections wherver needed.  if blank, gets settings for homepage, and
# if defined tries to use cache.
# Look at this for a rewrite
sub getSection {
	my($section) = @_;
	return { title => getCurrentStatic('slogan'), artcount => getCurrentUser('maxstories') || 30, issue => 3 }
		unless $section;
	my $dbslash = getCurrentDB();
	return $dbslash->getSection($section);
}


###############################################################################
# Dealing with Polls

########################################################

########################################################
sub pollbooth {
	my($qid, $no_table, $center) = @_;
	my $dbslash = getCurrentDB();
	my $constants = getCurrentStatic();

	$qid = $dbslash->getVar('currentqid', 'value') unless $qid;
	my $sect = "section=$constants->{currentSection}&"
		if $constants->{currentSection};
	my $polls = $dbslash->getPoll($qid);

	my $pollbooth = slashDisplay('pollbooth', {
		polls		=> $polls,
		question	=> $polls->[0][0],
		qid		=> stripByMode($qid, 'attribute'),
		voters		=> $dbslash->getPollQuestion($qid, 'voters'),
		comments	=> $dbslash->countComments($qid),
		sect		=> $sect,
	}, 1);

	return $pollbooth if $no_table;
	fancybox($constants->{fancyboxwidth}, 'Poll', $pollbooth, $center);
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
	if ($fmode eq 'literal' || $fmode eq 'exttrans' || $fmode eq 'attribute' || $fmode eq 'code') {
		# Encode all HTML tags
		$str =~ s/&/&amp;/g;
		$str =~ s/</&lt;/g;
		$str =~ s/>/&gt;/g;
	}

	# this "if" block part of patch from Ben Tilly
	if ($fmode eq 'plaintext' || $fmode eq 'exttrans' || $fmode eq 'code') {
		$str = stripBadHtml($str);
		$str =~ s/\n/<BR>/gi;  # pp breaks
		$str =~ s/(?:<BR>\s*){2,}<BR>/<BR><BR>/gi;
		# Preserve leading indents
		$str =~ s/\t/    /g;
		$str =~ s/<BR>\n?( +)/"<BR>\n" . ("&nbsp; " x length($1))/ieg;
		$str = '<CODE>' . $str . '</CODE>' if $fmode eq 'code';

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

	my $fixhrefs = getCurrentStatic('fixhrefs');
	for my $qr (@{$fixhrefs}) {
		if ($rel_url =~ $qr->[0]) {
			my @ret = $qr->[1]->($rel_url);
			return $print_errs ? @ret : $ret[0];
		}
	}

	my $rootdir = getCurrentStatic('rootdir');
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
			$rel_url = "$rootdir/articles/older/$file";
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
			$rel_url = "$rootdir/features/older/$file";
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
			$rel_url = "$rootdir/books/older/$file";
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
			$rel_url = "$rootdir/askslashdot/older/$file";
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
	my($tag) = @_;

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
	my $approvedtags = getCurrentStatic('approvedtags');
	$tag =~ s|^(/?\w+)|\U$1|;
	foreach my $goodtag (@$approvedtags) {
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
	my $constants = getCurrentStatic();
	(my $dir = $constants->{rootdir}) =~ s|^http://[^/]+||;
	print "<!--#include virtual=\"$dir/";
	print "$constants->{currentSection}/" if $constants->{currentSection};
	print "slashhead$constants->{userMode}",".inc\"-->\n";
}

########################################################
sub ssiFoot {
	my $constants = getCurrentStatic();
	(my $dir = $constants->{rootdir}) =~ s|^http://[^/]+||;
	print "<!--#include virtual=\"$dir/";
	print "$constants->{currentSection}/" if $constants->{currentSection};
	print "slashfoot$constants->{userMode}",".inc\"-->\n";
}

########################################################
sub formLabel {
	my($value, $comment) = @_;
	return unless $value;

	my %data;
	$data{value} = $value;
	$data{comment} = $comment if defined $_[1];

	slashDisplay('formLabel', \%data, 1, 1);
}

########################################################
sub currentAdminUsers {
	my $html_to_display;
	my $dbslash = getCurrentDB();
	my $constants = getCurrentStatic();
	my $user = getCurrentUser();

	my $aids = $dbslash->currentAdmin();
	for (@$aids) {
		my($aid, $lastsecs, $lasttitle) = @$_;
		$html_to_display .= qq!\t<TR><TD BGCOLOR="$constants->{bg}[3]">\n!;
		$html_to_display .= qq!\t<A HREF="$constants->{rootdir}/admin.pl?op=authors&thisaid=$aid">!
			if $user->{aseclev} > 10000;
		$html_to_display .= qq!<FONT COLOR="$constants->{fg}[3]" SIZE="${\( $constants->{fontbase} + 2 )}"><B>$aid</B></FONT>!;
		$html_to_display .= '</A> ' if $user->{aseclev} > 10000;

		if ($aid eq $user->{aid}) {
		    $lastsecs = "-";
		} elsif ($lastsecs <= 99) {
		    $lastsecs .= "s";
		} elsif ($lastsecs <= 99*60) {
		    $lastsecs = int($lastsecs/60+0.5) . "m";
		} else {
		    $lastsecs = int($lastsecs/3600+0.5) . "h";
		}

		$lasttitle = "&nbsp;/&nbsp;$lasttitle" if $lasttitle && $lastsecs;

		$html_to_display .= qq!</TD><TD BGCOLOR="$constants->{bg}[2]"><FONT COLOR="$constants->{fg}[1]" SIZE="${\( $constants->{fontbase} + 2 )}">! .
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
	my $constants = getCurrentStatic();

	if ($constants->{rootdir}) {	# rootdir strongly recommended
		$url = URI->new_abs($url, $constants->{rootdir})->canonical->as_string;
	} elsif ($url !~ m|^https?://|i) {	# but not required
		$url =~ s|^/*|$constants->{rootdir}/|;
	}

	my %params = (
		-type		=> 'text/html',
		-status		=> '302 Moved',
		-location	=> $url
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
	my $dbslash = getCurrentDB();
	my $constants = getCurrentStatic();
	my $user = getCurrentUser();
	my $form = getCurrentForm();

	my $adhtml = '';
	$title ||= '';

	unless ($form->{ssi}) {
		my %params = (
			-cache_control => 'private',
			-type => 'text/html'
		);
		$params{-status} = $status if $status;
		$params{-pragma} = "no-cache"
			unless $user->{aseclev} || $ENV{SCRIPT_NAME} =~ /comments/;

		print CGI::header(%params);
	}

	$constants->{userMode} = $user->{currentMode} eq 'flat' ? '_F' : '';
	$constants->{currentSection} = $section || '';
	getSectionColors();

	$title =~ s/<(.*?)>//g;

	print <<EOT if $title;
<!DOCTYPE HTML PUBLIC "-//W3C//DTD HTML 3.2 Final//EN">
<HTML><HEAD><TITLE>$title</TITLE>
EOT

	# ssi = 1 IS NOT THE SAME as ssi = 'yes'
	if ($form->{ssi} eq 'yes') {
		ssiHead($section);
		return;
	}

	if ($constants->{run_ads}) {
		$adhtml = getAd(1);
	}

	my $topics;
	unless ($user->{noicons} || $user->{light}) {
		$topics = $dbslash->getBlock('topics', 'block');
	}

	my $vertmenu = $dbslash->getBlock('mainmenu', 'block');
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
	if ($user->{is_admin}) {
		print createMenu('admin');
	}
}

########################################################
sub getSectionMenu {
	my $dbslash = getCurrentDB();
	my $menu = $dbslash->getBlock('sectionindex_html1', 'block');

	# the reason this is three calls is that sectionindex regularly is
	# updated by portald, so it's a more dynamic block
	$menu .= $dbslash->getBlock('sectionindex', 'block');
	$menu .= $dbslash->getBlock('sectionindex_html2', 'block');

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
	my $dbslash = getCurrentDB();
	my $form = getCurrentForm();

	if ($form->{ssi}) {
		ssiFoot();
		return;
	}

	my $motd = '';
	if (getCurrentUser('aseclev')) {
		$motd .= currentAdminUsers();
	} else {
		$motd .= $dbslash->getBlock('motd', 'block');
	}

	my $vertmenu = $dbslash->getBlock('mainmenu', 'block');
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
	slashDisplay('titlebar', {
		width	=> $width,
		title	=> $title
	});
}

########################################################
sub fancybox {
	my($width, $title, $contents, $center) = @_;
	return unless $title && $contents;

	my $tmpwidth = $width;
	# allow width in percent or raw pixels
	my $pct = 1 if $tmpwidth =~ s/%$//;
	# used in some blocks
	my $mainwidth = $tmpwidth-4;
	my $insidewidth = $mainwidth-8;
	if ($pct) {
		for ($mainwidth, $insidewidth) {
			$_ .= '%';
		}
	}

	slashDisplay('fancybox', {
		width		=> $width,
		contents	=> $contents,
		title		=> $title,
		center		=> 1
	});
}

########################################################
sub portalbox {
	my($width, $title, $contents, $bid, $url) = @_;
	return unless $title && $contents;
	my $constants = getCurrentStatic();
	my $user = getCurrentUser();

	$title = qq!<FONT COLOR="$constants->{fg}[3]">$title</FONT>!
		if $url && !$user->{light};
	$title = qq!<A HREF="$url">$title</A>! if $url;

	unless ($user->{exboxes}) {
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

	slashDisplay('fancybox', {
		width		=> $width,
		contents	=> $contents,
		title		=> $title,
		center		=> 0
	}, 1);
}

########################################################
# Behold, the beast that is threaded comments
sub selectComments {
	my($sid, $cid) = @_;
	my $dbslash = getCurrentDB();
	my $constants = getCurrentStatic();
	my $user = getCurrentUser();
	my $form = getCurrentForm();

	my $comments; # One bigass struct full of comments
	foreach my $x (0..6) { $comments->[0]{totals}[$x] = 0 }

	my $thisComment = $dbslash->getCommentsForUser($sid, $cid);
	for my $C (@$thisComment) {
		$C->{pid} = 0 if $user->{commentsort} > 3; # Ignore Threads

		$C->{points}++ if length($C->{comment}) > $user->{clbig}
			&& $C->{points} < $constants->{comment_maxscore} && $user->{clbig} != 0;

		$C->{points}-- if length($C->{comment}) < $user->{clsmall}
			&& $C->{points} > $constants->{comment_minscore} && $user->{clsmall};

		# fix points in case they are out of bounds
		$C->{points} = $constants->{comment_minscore}
			if $C->{points} < $constants->{comment_minscore};
		$C->{points} = $constants->{comment_maxscore}
			if $C->{points} > $constants->{comment_maxscore};

		my $tmpkids = $comments->[$C->{cid}]{kids};
		my $tmpvkids = $comments->[$C->{cid}]{visiblekids};
		$comments->[$C->{cid}] = $C;
		$comments->[$C->{cid}]{kids} = $tmpkids;
		$comments->[$C->{cid}]{visiblekids} = $tmpvkids;

		push @{$comments->[$C->{pid}]{kids}}, $C->{cid};
		$comments->[0]{totals}[$C->{points} - $constants->{comment_minscore}]++;  # invert minscore
		$comments->[$C->{pid}]{visiblekids}++
			if $C->{points} >= $user->{threshold};

		$user->{points} = 0 if $C->{uid} == $user->{uid}; # Mod/Post Rule
	}

	my $count = @$thisComment;

	getCommentTotals($comments);
	$dbslash->updateCommentTotals($sid, $comments) if $form->{ssi};
	reparentComments($comments);
	return($comments,$count);
}

########################################################
sub getCommentTotals {
	my($comments) = @_;
	for my $x (0..5) {
		$comments->[0]{totals}[5-$x] += $comments->[0]{totals}[5-$x+1];
	}
}


########################################################
sub reparentComments {
	my($comments) = @_;
	my $dbslash = getCurrentDB();
	my $constants = getCurrentStatic();
	my $user = getCurrentUser();
	my $form = getCurrentForm();

	my $depth = $constants->{max_depth} || 7;

	return unless $depth || $user->{reparent};

	# adjust depth for root pid or cid
	if (my $cid = $form->{cid} || $form->{pid}) {
		while ($cid && (my($pid) = $dbslash->getCommentPid($form->{sid}, $cid))) {
			$depth++;
			$cid = $pid;
		}
	}

	for (my $x = 1; $x < @$comments; $x++) {
		next unless $comments->[$x];

		my $pid = $comments->[$x]{pid};
		my $reparent;

		# do threshold reparenting thing
		if ($user->{reparent} && $comments->[$x]{points} >= $user->{threshold}) {
			my $tmppid = $pid;
			while ($tmppid && $comments->[$tmppid]{points} < $user->{threshold}) {
				$tmppid = $comments->[$tmppid]{pid};
				$reparent = 1;
			}

			if ($reparent && $tmppid >= ($form->{cid} || $form->{pid})) {
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
			if ($pid >= ($form->{cid} || $form->{pid})) {
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
	my $constants = getCurrentStatic();

	my $s = qq!<SELECT NAME="threshold">\n!;
	foreach my $x ($constants->{comment_minscore}..$constants->{comment_maxscore}) {
		my $select = ' SELECTED' if $x == getCurrentUser('threshold');
		$s .= <<EOT;
	<OPTION VALUE="$x"$select>$x: $counts->[$x - $constants->{comment_minscore}] comments
EOT
	}
	$s .= "</SELECT>\n";
}

########################################################
sub printComments {
	my($sid, $pid, $cid, $commentstatus) = @_;
	my $constants = getCurrentStatic();
	my $user = getCurrentUser();
	my $form = getCurrentForm();

	$pid ||= '0';
	my $lvl = 0;

	# Get the Comments
	my($comments, $count) = selectComments($sid, $cid || $pid);

	# Should I index or just display normally?
	my $cc = 0;
	if ($comments->[$cid || $pid]{visiblekids}) {
		$cc = $comments->[$cid || $pid]{visiblekids};
	}

	$lvl++ if $user->{mode} ne 'flat' && $user->{mode} ne 'archive'
		&& $cc > $user->{commentspill}
		&& ($user->{commentlimit} > $cc || $user->{commentlimit} > $user->{commentspill});

	print qq!<TABLE WIDTH="100%" BORDER="0" CELLSPACING="1" CELLPADDING="2">\n!;

	if ($user->{mode} ne 'archive') {
		print qq!\t<TR><TD BGCOLOR="$constants->{bg}[3]" ALIGN="CENTER">!,
			qq!<FONT SIZE="${\( $constants->{fontbase} + 2 )}" COLOR="$constants->{fg}[3]">!;

		my($title, $section);
		# Print Story Name if Applicable
		my $dbslash = getCurrentDB();
		if ($dbslash->getStory($sid)) {
			$title = $dbslash->getStory($sid, 'title');
			$section = $dbslash->getStory($sid, 'section');
		} else {
			my $story = $dbslash->getNewStory($sid, ['title', 'section']);
			$title = $story->{'title'};
			$section = $story->{'section'};
		}

		if ($title) {
			printf "'%s'", linkStory({
				'link'	=> qq!<FONT COLOR="$constants->{fg}[3]">$title</FONT>!,
				sid	=> $sid,
				section	=> $section
			});
		} else {
			print linkComment({
				sid => $sid, pid => 0, op => '',
				color => $constants->{fg}[3], subject => 'Top'
			});
		}

		print ' | ';

		if ($user->{is_anon}) {
			print qq!<A HREF="$constants->{rootdir}/users.pl"><FONT COLOR="$constants->{fg}[3]">!,
				qq!Login/Create an Account</FONT></A> !;
		} else {
			print qq!<A HREF="$constants->{rootdir}/users.pl?op=edituser">!,
				qq!<FONT COLOR="$constants->{fg}[3]">Preferences</FONT></A> !
		}

		print ' | ' . linkComment({
			sid => $sid, pid => 0, op => '',
			color=> $constants->{fg}[3], subject => 'Top'
		}) if $pid;

		print " | <B>$user->{points}</B> ",
			qq!<A HREF="$constants->{rootdir}/moderation.shtml"><FONT COLOR="$constants->{fg}[3]">!,
			"moderator</FONT></A> points " if $user->{points};

		print " | <B>$count</B> comments " if $count;
		# print " | <B>$cc</B> siblings " if $cc;
		print " (Spill at <B>$user->{commentspill}</B>!)",
			" | Index Only " if $lvl && $user->{mode} eq 'thread';

		print " | Starting at #$form->{startat}" if $form->{startat};

		print <<EOT;
 | <A HREF="$constants->{rootdir}/search.pl?op=comments&sid=$sid">
<FONT COLOR="$constants->{fg}[3]">Search Discussion</FONT></A></FONT>
	</TD></TR>

	<TR><TD BGCOLOR="$constants->{bg}[2]" ALIGN="CENTER"><FONT SIZE="${\( $constants->{fontbase} + 2 )}">
		<FORM ACTION="$constants->{rootdir}/comments.pl">
		<INPUT TYPE="HIDDEN" NAME="sid" VALUE="$sid">
		<INPUT TYPE="HIDDEN" NAME="cid" VALUE="$cid">
		<INPUT TYPE="HIDDEN" NAME="pid" VALUE="$pid">
		<INPUT TYPE="HIDDEN" NAME="startat" VALUE="$form->{startat}">
EOT

		print "Threshold: ", selectThreshold($comments->[0]{totals}),
			selectMode(), selectSortcode();


		print qq!\t\tSave:<INPUT TYPE="CHECKBOX" NAME="savechanges">!
			unless $user->{is_anon};

		print <<EOT;
		<INPUT TYPE="submit" NAME="op" VALUE="Change">
		<INPUT TYPE="submit" NAME="op" VALUE="Reply">
	</TD></TR>
	<TR><TD BGCOLOR="$constants->{bg}[3]" ALIGN="CENTER">
		<FONT COLOR="$constants->{fg}[3]" SIZE="${\( $constants->{fontbase} + 2 )}">
EOT

		print $dbslash->getBlock('commentswarning', 'block'), "</FONT></FORM></TD></TR>";

		if ($user->{mode} eq 'nocomment') {
			print "</TABLE>";
			return;
		}
	} else {
		print <<EOT;
	<TR><TD BGCOLOR="$constants->{bg}[3]"><FONT COLOR="$constants->{fg}[3]" SIZE="${\( $constants->{fontbase} + 2 )}">
			This discussion has been archived.
			No new comments can be posted.
	</TD></TR>
EOT
	}

	print <<EOT if $user->{aseclev} || $user->{points};
	<FORM ACTION="$constants->{rootdir}/comments.pl" METHOD="POST">
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
		print qq!\t</TD></TR>\n\t<TR><TD BGCOLOR="$constants->{bg}[2]" ALIGN="CENTER">\n!;
		print "\t\t&lt;&lt;", linkComment($comments->[$p], 1) if $p;
		print ' | ', linkComment($comments->[$pid], 1) if $C->{pid};
		print ' | ', linkComment($comments->[$n], 1), "&gt;&gt;\n" if $n;
		print qq!\t</TD></TR>\n\t<TR><TD ALIGN="CENTER">!;
		moderatorCommentLog($sid, $cid);
		print "\t</TD></TR>\n";
	}

	my $lcp = linkCommentPages($sid, $pid, $cid, $cc);
	print $lcp;
	print "\t<TR><TD>\n" if $lvl; #|| $user->{mode} eq "nested" and $lvl);
	displayThread($sid, $pid, $lvl, $comments, $cid);
	print "\n\t</TD></TR>\n" if $lvl; # || ($user->{mode} eq "nested" and $lvl);
	print $lcp;

	my $delete_text = ($user->{aseclev} > 99 && $constants->{authors_unlimited})
		? "<BR><B>NOTE: Checked comments will be deleted.</B>"
		: "";

	print <<EOT if ($user->{aseclev} || $user->{points}) && $user->{uid} > 0;
	<TR><TD>
		<P>Have you read the
		<A HREF="$constants->{rootdir}/moderation.shtml">Moderator Guidelines</A>
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
	my $slashdb = getCurrentDB();
	my $constants = getCurrentStatic();

	my $aseclev = getCurrentUser('aseclev');
	my $comments = $slashdb->getModeratorCommentLog($sid, $cid);
	my(@reasonHist, $reasonTotal);

	if (@$comments) {
		print <<EOT if $aseclev > 1000;
<TABLE BGCOLOR="$constants->{bg}[2]" ALIGN="CENTER" BORDER="0" CELLPADDING="2" CELLSPACING="0">
	<TR BGCOLOR="$constants->{bg}[3]">
		<TH><FONT COLOR="$constants->{fg}[3]"> val </FONT></TH>
		<TH><FONT COLOR="$constants->{fg}[3]"> reason </FONT></TH>
		<TH><FONT COLOR="$constants->{fg}[3]"> moderator </FONT></TH>
	</TR>
EOT

		for my $C (@$comments) {
			print <<EOT if $aseclev > 1000;
	<TR>
		<TD> <B>$C->{val}</B> </TD>
		<TD> $constants->{reasons}[$C->{reason}] </TD>
		<TD> $C->{nickname} ($C->{uid}) </TD>
	</TR>
EOT

			$reasonHist[$C->{reason}]++;
			$reasonTotal++;
		}

		print "</TABLE>\n" if $aseclev > 1000;
	}

	return unless $reasonTotal;

	print qq!<FONT COLOR="$constants->{bg}[3]"><B>Moderation Totals</B></FONT>:!;
	foreach (0 .. @reasonHist) {
		print "$constants->{reasons}[$_]=$reasonHist[$_], " if $reasonHist[$_];
	}
	print "<B>Total=$reasonTotal</B>.";
}

########################################################
sub linkCommentPages {
	my($sid, $pid, $cid, $total) = @_;
	my($links, $page);
	my $constants = getCurrentStatic();
	my $user = getCurrentUser();
	my $form = getCurrentForm();

	return if $total < $user->{commentlimit} || $user->{commentlimit} < 1;

	for (my $x = 0; $x < $total; $x += $user->{commentlimit}) {
		$links .= ' | ' if $page++ > 0;
		$links .= "<B>(" if $form->{startat} && $x == $form->{startat};
		$links .= linkComment({
			sid => $sid, pid => $pid, cid => $cid,
			subject => $page, startat => $x
		});
		$links .= ")</B>" if $form->{startat} && $x == $form->{startat};
	}
	if ($user->{breaking}) {
		$links .= " ($constants->{sitename} Overload: CommentLimit $user->{commentlimit})";
	}

	return <<EOT;
	<TR><TD BGCOLOR="$constants->{bg}[2]" ALIGN="CENTER"><FONT SIZE="${\( $constants->{fontbase} + 2 )}">
		$links
	</FONT></TD></TR>
EOT
}

########################################################
sub linkComment {
	my($C, $comment, $date) = @_;
	my $constants = getCurrentStatic();
	my $user = getCurrentUser();

	my $x = qq!<A HREF="$constants->{rootdir}/comments.pl?sid=$C->{sid}!;
	$x .= "&op=$C->{op}" if $C->{op};
	$x .= "&threshold=" . ($C->{threshold} || $user->{threshold});
	$x .= "&commentsort=$user->{commentsort}";
	$x .= "&mode=$user->{mode}";
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
		if !$user->{noscores} && $C->{points};
	$x .= qq! <FONT SIZE="-1"> $C->{'time'} </FONT>! if $date;
	$x .= "\n";
	return $x;
}

########################################################
sub displayThread {
	my($sid, $pid, $lvl, $comments, $cid) = @_;
	my $constants = getCurrentStatic();
	my $user = getCurrentUser();
	my $form = getCurrentForm();

	my $displayed = 0;
	my $skipped = 0;
	my $hidden = 0;
	my $indent = 1;
	my $full = !$lvl;
	my $cagedkids = $full;

	if ($user->{mode} eq 'flat' || $user->{mode} eq 'archive') {
		$indent = 0;
		$full = 1;
	} elsif ($user->{mode} eq 'nested') {
		$indent = 1;
		$full = 1;
	}


	foreach my $cid (@{$comments->[$pid]{kids}}) {
		my $C = $comments->[$cid];

		$skipped++;
		$form->{startat} ||= 0;
		next if $skipped < $form->{startat};

		$form->{startat} = 0; # Once We Finish Skipping... STOP

		if ($C->{points} < $user->{threshold}) {
			if ($user->{is_anon} || $user->{uid} != $C->{uid})  {
				$hidden++;
				next;
			}
		}

		my $highlight = 1 if $C->{points} >= $user->{highlightthresh};
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
				linkComment($C, $pcnt > $user->{commentspill}, "1");
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

		last if $displayed >= $user->{commentlimit};
	}

	if ($hidden && !$user->{hardthresh} && $user->{mode} ne 'archive') {
		print qq!\n<TR><TD BGCOLOR="$constants->{bg}[2]">\n! if $cagedkids;
		print qq!<LI><FONT SIZE="${\( $constants->{fontbase} + 2 )}"><B> !,
			linkComment({
				sid		=> $sid,
				threshold	=> $constants->{comment_minscore},
				pid		=> $pid,
				subject		=> "$hidden repl" . ($hidden > 1 ? 'ies' : 'y')
			}) . ' beneath your current threshold.</B></FONT>';
		print "\n\t</TD></TR>\n" if $cagedkids;
	}
	return $displayed;
}

########################################################
sub dispComment  {
	my($C) = @_;
	my $constants = getCurrentStatic();
	my $user = getCurrentUser();
	my $form = getCurrentForm();

	my $subj = $C->{subject};
	my $time = $C->{'time'};
	my $username;

	$username = $C->{fakeemail} ? <<EOT : $C->{nickname};
<A HREF="mailto:$C->{fakeemail}">$C->{nickname}</A>
<B><FONT SIZE="${\( $constants->{fontbase} + 2 )}">($C->{fakeemail})</FONT></B>
EOT

	my $nickname = fixparam($C->{nickname});
	my $userinfo = <<EOT unless $C->{nickname} eq getCurrentAnonymousCoward('nickname');
(<A HREF="$constants->{rootdir}/users.pl?op=userinfo&nick=$nickname">User #$C->{uid} Info</A>)
EOT

	my $userurl = qq!<A HREF="$C->{homepage}">$C->{homepage}</A><BR>!
		if length($C->{homepage}) > 8;

	my $score = '';
	unless ($user->{noscores}) {
		$score  = " (Score:$C->{points}";
		$score .= ", $constants->{reasons}[$C->{reason}]" if $C->{reason};
		$score .= ")";
	}

	$C->{comment} .= "<BR>$C->{sig}" unless $user->{nosigs};

	if ($form->{mode} ne 'archive' && length($C->{comment}) > $user->{maxcommentsize}
		&& $form->{cid} ne $C->{cid}) {

		$C->{comment} = substr $C->{comment}, 0, $user->{maxcommentsize};
		$C->{comment} .= sprintf '<P><B>%s</B>', linkComment({
			sid => $C->{sid}, cid => $C->{cid}, pid => $C->{cid},
			subject => "Read the rest of this comment..."
		}, 1);
	}

	my $comment = $C->{comment}; # Old Compatibility Thing

	my $execme = getWidgetBlock('comment');
	print eval $execme;
	print "\nError:$@\n" if $@;

	if ($user->{mode} ne 'archive') {
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

		if (((	   $user->{willing}
			&& $user->{points} > 0
			&& $C->{uid} ne $user->{uid}
			&& $C->{lastmod} ne $user->{uid})
		    || ($user->{aseclev} > 99 && $constants->{authors_unlimited}))
		    	&& !$user->{is_anon}) {

			my $o;
			foreach (0 .. @{$constants->{reasons}} - 1) {
				$o .= qq!\t<OPTION VALUE="$_">$constants->{reasons}[$_]</OPTION>\n!;
			}

			$m.= qq! | <SELECT NAME="reason_$C->{cid}">\n$o</SELECT> !;
		    }

		$m .= qq! | <INPUT TYPE="CHECKBOX" NAME="del_$C->{cid}"> !
			if $user->{aseclev} > 99;
		print qq!\n\t<TR><TD><FONT SIZE="${\( $constants->{fontbase} + 2 )}">\n! .
			qq![ $m ]\n\t</FONT></TD></TR>\n<TR><TD>!;
	}
}

##############################################################################
#  Functions for dealing with Story selection and Display

########################################################
sub dispStory {
	my($section, $authors, $topic, $full) = @_;
	my $constants = getCurrentStatic();
	my $user = getCurrentUser();
	my $form = getCurrentForm();

	my $title = $section->{title};

	if (!$full && index($section->{title}, ':') == -1
		&& $section->{section} ne $constants->{defaultsection}
		&& $section->{section} ne $form->{section}) {

		# Need Header
		my $SECT = getSection($section->{section});

		# Until something better can be done we manually
		# fix title for the appropriate mode. This is an
		# UGLY hack, but until something more configurable
		# comes along (and using a block, here might be an
		# even uglier hack...but would solve the immediate
		# problem.
		$title = $user->{light} ? <<LIGHT : <<NORMAL;
\t\t\t<A HREF="$constants->{rootdir}/$section->{section}/">$SECT->{title}</A>: $section->{title}
LIGHT
\t\t\t<A HREF="$constants->{rootdir}/$section->{section}/"><FONT COLOR="$constants->{fg}[3]">$SECT->{title}</FONT></A>: $section->{title}
NORMAL
	}

	titlebar($constants->{titlebar_width}, $title);

	my $bt = $full ? "<P>$section->{bodytext}</P>" : '<BR>';
	my $author = qq!<A HREF="$authors->{url}">$section->{aid}</A>!;

	my $topicicon = '';
	$topicicon .= ' [ ' if $user->{noicons};
	$topicicon .= qq!<A HREF="$constants->{rootdir}/search.pl?topic=$topic->{tid}">!;

	if ($user->{noicons}) {
		$topicicon .= "<B>$topic->{alttext}</B>";
	} else {
		$topicicon .= <<EOT;
<IMG SRC="$constants->{imagedir}/topics/$topic->{image}" WIDTH="$topic->{width}" HEIGHT="$topic->{height}"
	BORDER="0" ALIGN="RIGHT" HSPACE="20" VSPACE="10" ALT="$topic->{alttext}">
EOT
	}

	$topicicon .= '</A>';
	$topicicon .= ' ] ' if $user->{noicons};

	my $execme = getWidgetBlock('story');
	print eval $execme;
	print "\nError:$@\n" if $@;

	if ($full && ($section->{bodytext} || $section->{books_publisher})) {
		my $execme = getWidgetBlock('storymore');
		print eval $execme;
		print "\nError:$@\n" if $@;
#	} elsif ($full) {
#		print $section->{bodytext};
	}
}

########################################################
sub displayStory {
	# caller is the pagename of the calling script
	my($sid, $full, $caller) = @_;

	my $dbslash = getCurrentDB();

	my $story = $dbslash->getStory($sid);
	
	# convert the time of the story (this is database format) 
	# and convert it to the user's prefered format 
	# based on their preferences 
	setCurrentUser('storytime', timeCalc($story->{'time'}));

	$dbslash->setSectionExtra($full, $story);

	# No, we do not need this variable, but for readability 
	# I think it is justified (and it is just a reference....)
	my $topic = $dbslash->getTopic($story->{tid});
	dispStory($story, $dbslash->getAuthor($story->{aid}), $topic, $full);
	return($story, $dbslash->getAuthor($story->{aid}), $topic);
}

#######################################################################
# timeCalc 051100 PMG 
# Removed timeformats hash and updated table to have perl formats 092000 PMG 
# inputs: raw date from database
# returns: formatted date string from dateformats converted to
# time strings that Date::Manip can format
#######################################################################
sub timeCalc {
	# raw mysql date of story
	my($date) = @_;
	my $user = getCurrentUser();
	my(@dateformats, $err);

	# I put this here because
	# when they select "6 ish" it
	# looks really stupid for it to
	# display "posted by xxx on 6 ish"
	# It looks better for it to read:
	# "posted by xxx around 6 ish"
	# call me anal!
	if ($user->{'format'} eq '%i ish') {
		$user->{aton} = " around ";
	} else {
		$user->{aton} = " on ";
	}

	# find out the user's time based on personal offset
	# in seconds
	$date = DateCalc($date, "$user->{offset} SECONDS", \$err);

	# convert the raw date to pretty formatted date
	$date = UnixDate($date, $user->{'format'});

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
sub getOlderStories {
	my($array_ref, $SECT) = @_;
	my($today, $stuff);
	my $dbslash = getCurrentDB();
	my $constants = getCurrentStatic();
	my $user = getCurrentUser();
	my $form = getCurrentForm();

	$array_ref ||= $dbslash->getStories($SECT, $constants->{currentSection});

	for (@{$array_ref}) {
		my($sid, $section, $title, $time, $commentcount, $day) = @{$_}; 
		my($w, $m, $d, $h, $min, $ampm) = split m/ /, $time;
		if ($today ne $w) {
			$today  = $w;
			$stuff .= '<P><B>';
			$stuff .= <<EOT if $SECT->{issue} > 1;
<A HREF="$constants->{rootdir}/index.pl?section=$SECT->{section}&issue=$day&mode=$user->{'currentMode'}">
EOT
			$stuff .= qq!<FONT SIZE="${\( $constants->{fontbase} + 4 )}">$w</FONT>!;
			$stuff .= '</A>' if $SECT->{issue} > 1;
			$stuff .= " $m $d</B></P>\n";
		}

		$stuff .= sprintf "<LI>%s ($commentcount)</LI>\n", linkStory({
			'link' => $title, sid => $sid, section => $section
		});
	}

	if ($SECT->{issue}) {
		my $yesterday;
		unless ($form->{issue} > 1 || $form->{issue}) {
			$yesterday = $dbslash->getDay() - 1;
		} else {
			$yesterday = int($form->{issue}) - 1;
		}

		my $min = $SECT->{artcount} + $form->{min};

		$stuff .= qq!<P ALIGN="RIGHT">! if $SECT->{issue};
		$stuff .= <<EOT if $SECT->{issue} == 1 || $SECT->{issue} == 3;
<BR><A HREF="$constants->{rootdir}/search.pl?section=$SECT->{section}&min=$min">
<B>Older Articles</B></A>
EOT
		$stuff .= <<EOT if $SECT->{issue} == 2 || $SECT->{issue} == 3;
<BR><A HREF="$constants->{rootdir}/index.pl?section=$SECT->{section}&mode=$user->{'currentMode'}&issue=$yesterday">
<B>Yesterday's Edition</B></A>
EOT
	}
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
	return if @w1 < 2 || @w2 < 2;
	foreach my $w (@w1) {
		foreach (@w2) {
			$m++ if $w eq $_;
		}
	}
	return int($m / @w1 * 100) if $m;
	return;
}

########################################################
sub lockTest {
	my($subj) = @_;
	return '' unless $subj;
	my $dbslash = getCurrentDB();
	my $constants = getCurrentStatic();
	my $msg;

	my $locks = $dbslash->getLock();
	for (@$locks) {
		my ($thissubj, $aid) = @$_;
		if ($aid ne getCurrentUser('aid') && (my $x = matchingStrings($thissubj, $subj))) {
			$msg .= <<EOT
<B>$x%</B> matching with <FONT COLOR="$constants->{fg}[1]">$thissubj</FONT> by <B>$aid</B><BR>
EOT

		}
	}
	return $msg;
}

########################################################
sub getAnonCookie {	
	my($user) = @_;
	my $r = Apache->request;
	my $cookies = CGI::Cookie->parse($r->header_in('Cookie'));
	if (my $cookie = $cookies->{anon}->value) {
		$user->{anon_id} = $cookie;
		$user->{anon_cookie} = 1;
	} else {
		$user->{anon_id} = getAnonId();
	}
}

########################################################
# we need to reorg this ... maybe get rid of the need for it -- pudge
sub getFormkeyId {
	my($uid) = @_;
	my $user = getCurrentUser();
	my $form = getCurrentForm();

	# this id is the key for the commentkey table, either UID or
	# unique hash key generated by IP address
	my $id;

	# if user logs in during submission of form, after getting
	# formkey as AC, check formkey with user as AC
	if ($user->{uid} > 0 && $form->{rlogin} && length($form->{upasswd}) > 1) {
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
	my $dbslash = getCurrentDB();

	my $cant_find_formkey_err = <<EOT;
<P><B>We can't find your formkey.</B></P>
<P>You must fill out a form and submit from that
form as required.</P>
EOT

	# find out if this form has been submitted already
	my($submitted_already, $submit_ts) = $dbslash->checkForm($formkey, $formname)
		or errorMessage($cant_find_formkey_err), return;

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
	my($error_message) = @_;
	print qq|$error_message\n|;
	return;
}




##################################################################
# make sure they're not posting faster than the limit
sub checkSubmission {
	my($formname, $limit, $max, $id) = @_;
	my $dbslash = getCurrentDB();
	my $constants = getCurrentStatic();

	my $formkey_earliest = time() - $constants->{formkey_timeframe};
	# If formkey starts to act up, me doing the below
	# may be the cause
	my $formkey = getCurrentForm('formkey');

	my $last_submitted = $dbslash->getSubmissionLast($id, $formname);

	my $interval = time() - $last_submitted;

	if ($interval < $limit) {
		my $limit_string = intervalString($limit);
		my $interval_string = intervalString($interval);
		my $speed_limit_err = <<EOT;
<B>Slow down cowboy!</B><BR>
<P>$constants->{sitename} requires you to wait $limit_string between
each submission of $ENV{SCRIPT_NAME} in order to allow everyone to have a fair chance to post.</P>
<P>It's been $interval_string since your last submission!</P>
EOT
		errorMessage($speed_limit_err);
		return;

	} else {
		if ($dbslash->checkTimesPosted($formname, $max, $id, $formkey_earliest)) {
			undef $formkey unless $formkey =~ /^\w{10}$/;

			unless ($formkey && $dbslash->checkFormkey($formkey_earliest, $formname, $id, $formkey)) {
				$dbslash->formAbuse("invalid form key", $ENV{REMOTE_ADDR}, $ENV{SCRIPT_NAME}, $ENV{QUERY_STRING});
				my $invalid_formkey_err = "<P><B>Invalid form key!</B></P>\n";
				errorMessage($invalid_formkey_err);
				return;
			}

			if (submittedAlready($formkey, $formname)) {
				$dbslash->formAbuse("form already submitted", $ENV{REMOTE_ADDR}, $ENV{SCRIPT_NAME}, $ENV{QUERY_STRING});
				return;
			}

		} else {
			$dbslash->formAbuse("max form submissions $max reached", $ENV{REMOTE_ADDR}, $ENV{SCRIPT_NAME}, $ENV{QUERY_STRING});
			my $timeframe_string = intervalString($constants->{formkey_timeframe});
			my $max_posts_err =<<EOT;
<P><B>You've reached you limit of maximum submissions to $ENV{SCRIPT_NAME} :
$max submissions over $timeframe_string!</B></P>
EOT
			errorMessage($max_posts_err);
			return;
		}
	}
	return 1;
}

########################################################
# Ok, in a CGI we need to set up enough of an
# environment so that methods that are accustom
# to Apache do not choke.
sub createEnvironment {
	my($virtual_user) = @_;
	my $slashdb = new Slash::DB($virtual_user);
	my $constants = $slashdb->getSlashConf();
	# We assume that the user for scripts is the anonymous user
	my $user = $slashdb->getUser($constants->{anonymous_coward_uid});
	createCurrentDB($slashdb);
	createCurrentStatic($constants);
	createCurrentUser($user);
	createCurrentAnonymousCoward($user);

	return($constants, $slashdb);
}

########################################################
sub createMenu {
	my($menu) = @_;
	my $dbslash = getCurrentDB();
	my $constants = getCurrentStatic();
	my $user = getCurrentUser();
	my $menu_items = getCurrentMenu($menu);
	my $items = [];

	for my $item (sort { $a->{menuorder} <=> $b->{menuorder} } @$menu_items) {
		next unless $user->{seclev} >= $item->{seclev};
		push @$items, {
			value => slashDisplay(\$item->{value}, 0, 1, 1),
			label => slashDisplay(\$item->{label}, 0, 1, 1)
		};
	}

	return slashDisplay("menu-$menu", { items => $items, count => @$items - 1 }, 1);
}

1;

__END__
