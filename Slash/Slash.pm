package Slash;

=head1 NAME

Slash - the BEAST

=head1 SYNOPSIS

	use Slash;  # figure the rest out ;-)

=head1 DESCRIPTION

Slash is the code that runs Slashdot.

=head1 FUNCTIONS

Unless otherwise noted, they are publically available functions.

=over 4

=cut

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

use vars qw($VERSION @ISA @EXPORT);

# this is the worst damned warning ever, so SHUT UP ALREADY!
$SIG{__WARN__} = sub { warn @_ unless $_[0] =~ /Use of uninitialized value/ };

#  $Id$
$VERSION = '1.0.9';
@ISA	 = 'Exporter';
@EXPORT  = qw(
	checkSubmission createMenu createSelect
	currentAdminUsers dispComment displayStory displayThread
	dispStory errorMessage fancybox footer getFormkeyId
	getOlderStories getSection getSectionBlock getsid getsiddir
	header horizmenu linkComment linkStory lockTest
	moderatorCommentLog pollbooth portalbox printComments
	redirect selectMode selectSection selectSortcode
	selectThreshold selectTopic sendEmail titlebar
	anonLog timeCalc
);  # anonLog, timeCalc?

# BENDER: Fry, of all the friends I've had ... you're the first.

#========================================================================

=item createSelect(LABEL, DATA [, DEFAULT, RETURN, NSORT])

Creates a drop-down list in HTML.

Parameters

	LABEL
	The name for the HTML entity.

	DATA
	A hashref containing key-value pairs for the list.
	Keys are list values, and values are list labels.

	DEFAULT
	Default value for the list.

	RETURN
	See "Return value" below.

	NSORT
	Sort numerically, not alphabetically.

Return value

	If RETURN is true, the text of the list is returned.
	Otherwise, list is just printed, and returns
	true/false if operation is successful.

Dependencies

	The 'select' template block.

=cut

sub createSelect {
	my($label, $hashref, $default, $return, $nsort) = @_;
	my $display = {
		label	=> $label,
		items	=> $hashref,
		default	=> $default,
		numeric	=> $nsort	
	};

	if ($return) {
		return slashDisplay('select', $display, 1);
	} else {
		slashDisplay('select', $display);
	}
}

#========================================================================

=item selectTopic(LABEL [, DEFAULT, RETURN])

Creates a drop-down list of topics in HTML.  Calls C<createSelect>.

Parameters

	LABEL
	The name for the HTML entity.

	DEFAULT
	Default topic for the list.

	RETURN
	See "Return value" below.

Return value

	If RETURN is true, the text of the list is returned.
	Otherwise, list is just printed, and returns
	true/false if operation is successful.

=cut

sub selectTopic {
	my($label, $default, $return) = @_;
	my $slashdb = getCurrentDB();

	my $topicbank = $slashdb->getTopics();
	my %topics = map {
		($_, $topicbank->{$_}{alttext})
	} keys %$topicbank;

	createSelect($label, \%topics, $default, $return);
}

#========================================================================

=item selectSection(LABEL [, DEFAULT, SECT, RETURN])

Creates a drop-down list of sections in HTML.  Calls C<createSelect>.

Parameters

	LABEL
	The name for the HTML entity.

	DEFAULT
	Default topic for the list.

	SECT
	Hashref for current section.  If SECT->{isolate} is true,
	list is not created, but hidden value is returned instead.

	RETURN
	See "Return value" below.

Return value

	If RETURN is true, the text of the list is returned.
	Otherwise, list is just printed, and returns
	true/false if operation is successful.

Dependencies

	The 'sectionisolate' template block.

=cut

sub selectSection {
	my($label, $default, $SECT, $return) = @_;
	my $slashdb = getCurrentDB();

	$SECT ||= {};
	if ($SECT->{isolate}) {
		slashDisplay('sectionisolate',
			{ name => $label, section => $default });
		return;
	}

	my $seclev = getCurrentUser('seclev');
	my $sectionbank = $slashdb->getSections();
	my %sections = map {
		($_, $sectionbank->{$_}{title})
	} grep {
		!($sectionbank->{$_}{isolate} && $seclev < 500)
	} keys %$sectionbank;

	createSelect($label, \%sections, $default, $return);
}

#========================================================================

=item selectSortcode()

Creates a drop-down list of sortcodes in HTML.  Default is the user's
preference.  Calls C<createSelect>.

Return value

	The created list.

=cut

sub selectSortcode {
	my $slashdb = getCurrentDB();
	createSelect('commentsort', $slashdb->getCodes('sortcodes'),
		getCurrentUser('commentsort'), 1);
}

#========================================================================

=item selectMode()

Creates a drop-down list of modes in HTML.  Default is the user's
preference.  Calls C<createSelect>.

Return value

	The created list.

=cut

sub selectMode {
	my $slashdb = getCurrentDB();

	createSelect('mode', $slashdb->getCodes('commentmodes'),
		getCurrentUser('mode'), 1);
}

#========================================================================

=item selectThreshold(COUNTS)

Creates a drop-down list of thresholds in HTML.  Default is the user's
preference.  Calls C<createSelect>.

Parameters

	COUNTS
	An arrayref of thresholds -> counts for that threshold.

Return value

	The created list.

Dependencies

	The 'selectThresholdLabel' template block.

=cut

sub selectThreshold  {
	my($counts) = @_;
	my $constants = getCurrentStatic();
	my $user = getCurrentUser();

	my %data;
	foreach my $c ($constants->{comment_minscore} .. $constants->{comment_maxscore}) {
		$data{$c} = slashDisplay('selectThresholdLabel', {
			points	=> $c,
			count	=> $counts->[$c - $constants->{comment_minscore}],
		}, { Return => 1, Nocomm => 1 });
	}

	createSelect('threshold', \%data, getCurrentUser('threshold'), 1, 1);
}

########################################################
# Gets the appropriate block depending on your section
# or else fall back to one that exists
sub getSectionBlock {
	my($name) = @_;
	my $slashdb = getCurrentDB();
	my $thissect = getCurrentUser('light') ? 'light' : getCurrentUser('currentSection');
	my $block;

	if ($thissect) {
		$block = $slashdb->getBlock("${thissect}_${name}", 'block');
	}

	$block ||= $slashdb->getBlock($name, 'block');
	return $block;
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
	) or errorLog("Can't send mail '$subject' to $addr: $Mail::Sendmail::error");
}


#========================================================================

=item linkStory(STORY)

The generic "Link a Story" function, used wherever stories need linking.

Parameters

	STORY
	A hashref containing data about a story to be linked to.

Return value

	The complete <A HREF ...></A> text for linking to the story.

Dependencies

	The 'linkStory' template block.

=cut

sub linkStory {
	my($c) = @_;
	my $user = getCurrentUser();
	my($dynamic, $mode, $threshold);

	if ($user->{currentMode} ne 'archive' && ($ENV{SCRIPT_NAME} || !$c->{section})) {
		$dynamic = 1 if $c->{mode} || exists $c->{threshold} || $ENV{SCRIPT_NAME};
		$mode = $c->{mode} || $user->{mode};
		$threshold = $c->{threshold} if exists $c->{threshold};
	}

	return slashDisplay('linkStory', {
		dynamic		=> $dynamic,
		mode		=> $mode,
		threshold	=> $threshold,
		sid		=> $c->{sid},
		section		=> $c->{section},
		text		=> $c->{'link'}
	}, { Return => 1, Nocomm => 1 });
}

########################################################
# Sets the appropriate @fg and @bg color pallete's based
# on what section you're in.  Used during initialization
sub getSectionColors {
	my($color_block) = @_;
	my $user = getCurrentUser();
	my @colors;
	my $colorblock = getCurrentForm('colorblock');

	# they damn well better be legit
	if ($colorblock) {
		@colors = map { s/[^\w#]+//g ; $_ } split m/,/, $colorblock;
	} else {
		@colors = split m/,/, getSectionBlock('colors');
	}

	$user->{fg} = [@colors[0..3]];
	$user->{bg} = [@colors[4..7]];
}


########################################################
# Gets sections wherver needed.  if blank, gets settings for homepage, and
# if defined tries to use cache.
# Look at this for a rewrite
sub getSection {
	my($section) = @_;
	return { title => getCurrentStatic('slogan'), artcount => getCurrentUser('maxstories') || 30, issue => 3 }
		unless $section;
	my $slashdb = getCurrentDB();
	return $slashdb->getSection($section);
}


#========================================================================

=item pollbooth(QID [, NO_TABLE, CENTER])

Creates a voting pollbooth.

Parameters

	QID
	The unique question ID for the poll.

	NO_TABLE
	Boolean for whether to leave the poll out of a table.
	If false, then will be formatted inside a C<fancybox>.

	CENTER
	Whether or not to center the tabled pollbooth (only
	works with NO_TABLE).

Return value

	Well, right now prints if NO_TABLE is true, and returns if
	NO_TABLE is false.  That's because if you don't want it in
	a table, it is presumed you are going to do something with it.

Dependencies

	The 'pollbooth' template block.

=cut

sub pollbooth {
	my($qid, $no_table, $center) = @_;
	my $slashdb = getCurrentDB();
	my $constants = getCurrentStatic();

	$qid = $slashdb->getVar('currentqid', 'value') unless $qid;
	my $sect = getCurrentUser('currentSection');
	my $polls = $slashdb->getPoll($qid);

	my $pollbooth = slashDisplay('pollbooth', {
		polls		=> $polls,
		question	=> $polls->[0][0],
		qid		=> stripByMode($qid, 'attribute'),
		voters		=> $slashdb->getPollQuestion($qid, 'voters'),
		comments	=> $slashdb->countComments($qid),
		sect		=> $sect,
	}, 1);

	return $pollbooth if $no_table;
	fancybox($constants->{fancyboxwidth}, 'Poll', $pollbooth, $center);
}

########################################################
# Look and Feel Functions Follow this Point
########################################################

#========================================================================

=item ssiHead()

Prints the head for server-parsed HTML pages.

Return value

	The SSI head.

Dependencies

	The 'ssihead' template block.

=cut

sub ssiHead {
	my $constants = getCurrentStatic();
	my $user = getCurrentUser();
	(my $dir = $constants->{rootdir}) =~ s|^http://[^/]+||;
	slashDisplay('ssihead', {
		dir	=> $dir,
		section => "$user->{currentSection}/"
	});
}

#========================================================================

=item ssiFoot()

Prints the foot for server-parsed HTML pages.

Return value

	The SSI foot.

Dependencies

	The 'ssifoot' template block.

=cut

sub ssiFoot {
	my $constants = getCurrentStatic();
	my $user = getCurrentUser();
	(my $dir = $constants->{rootdir}) =~ s|^http://[^/]+||;
	slashDisplay('ssifoot', {
		dir	=> $dir,
		section => "$user->{currentSection}/"
	});
}

#========================================================================

=item formLabel(VALUE [, COMMENT])

Prints a label for a form element.

Parameters

	VALUE
	The label.

	COMMENT
	An additional comment to stick in parentheses.

Return value

	The form label.

Dependencies

	The 'formLabel' template block.

=cut

sub formLabel {
	my($value, $comment) = @_;
	return unless $value;

	my %data;
	$data{value} = $value;
	$data{comment} = $comment if defined $_[1];

	slashDisplay('formLabel', \%data, { Return => 1, Nocomm => 1 });
}

#========================================================================

=item currentAdminUsers()

Displays table of current admin users, with what they are adminning.

Return value

	The HTML to display.

Dependencies

	The 'currentAdminUsers' template block.

=cut

sub currentAdminUsers {
	my $html_to_display;
	my $slashdb = getCurrentDB();
	my $constants = getCurrentStatic();
	my $user = getCurrentUser();

	my $aids = $slashdb->currentAdmin();
	for (@$aids) {
		if ($_->[0] eq $user->{nickname}) {
		    $_->[1] = "-";
		} elsif ($_->[1] <= 99) {
		    $_->[1] .= "s";
		} elsif ($_->[1] <= 99*60) {
		    $_->[1] = int($_->[1]/60+0.5) . "m";
		} else {
		    $_->[1] = int($_->[1]/3600+0.5) . "h";
		}
	}

	return slashDisplay('currentAdminUsers', {
		ids		=> $aids,
		can_edit_admins	=> $user->{seclev} > 10000,
	}, 1);
}

########################################################
sub getAd {
	my $num = $_[0] || 1;
	return qq|<!--#perl sub="sub { use Slash; print Slash::getAd($num); }" -->|
		unless $ENV{SCRIPT_NAME};

	anonLog() unless $ENV{SCRIPT_NAME} =~ /\.pl/; # Log non .pl pages

	return $ENV{"AD_BANNER_$num"};
}

#========================================================================

=item redirect(URL)

Redirect browser to URL.

Parameters

	URL
	URL to redirect browser to.

Return value

	None.

Dependencies

	The 'html-redirect' template block.

=cut

sub redirect {
	my($url) = @_;
	my $constants = getCurrentStatic();

	if ($constants->{rootdir}) {	# rootdir strongly recommended
		$url = URI->new_abs($url, $constants->{rootdir})->canonical->as_string;
	} elsif ($url !~ m|^https?://|i) {	# but not required
		$url =~ s|^/*|/|;
	}

	my %params = (
		-type		=> 'text/html',
		-status		=> '302 Moved',
		-location	=> $url
	);

	print CGI::header(%params);
	slashDisplay('html-redirect', { url => $url });
}

#========================================================================

=item header([TITLE, SECTION, STATUS])

Prints the header for the document.

Parameters

	TITLE
	The title for the HTML document.  The HTML header won't
	print without this.

	SECTION
	The section to handle the header.  This sets the
	currentSection constant, too.

	STATUS
	A special status to print in the HTTP header.

Return value

	None.

Side effects

	Sets currentSection and userMode constants.

Dependencies

	The 'html-header' and 'header' template blocks.

=cut

sub header {
	my($title, $section, $status) = @_;
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
		$params{-pragma} = 'no-cache'
			unless $user->{seclev} || $ENV{SCRIPT_NAME} =~ /comments/;

		print CGI::header(%params);
	}

	$constants->{userMode} = $user->{currentMode} eq 'flat' ? '_F' : '';
	$user->{currentSection} = $section || '';
	getSectionColors();

	$title =~ s/<(.*?)>//g;

	slashDisplay('html-header', { title => $title }, { Nocomm => 1 }) if $title;

	# ssi = 1 IS NOT THE SAME as ssi = 'yes'
	if ($form->{ssi} eq 'yes') {
		ssiHead($section);
		return;
	}

	if ($constants->{run_ads}) {
		$adhtml = getAd(1);
	}

	slashDisplay('header');

	print createMenu('admin') if $user->{is_admin};
}

#========================================================================

=item footer()

Prints the footer for the document.

Return value

	None.

Dependencies

	The 'footer' template block.

=cut

sub footer {
	my $form = getCurrentForm();

	if ($form->{ssi}) {
		ssiFoot();
		return;
	}

	slashDisplay('footer', {}, { Nocomm => 1 });
}

#========================================================================

=item horizmenu()

Silly little function to create a horizontal menu from the
'mainmenu' block.

Return value

	The horizontal menu.

Dependencies

	The 'mainmenu' template block.

=cut

sub horizmenu {
	my $horizmenu = slashDisplay('mainmenu', {}, { Return => 1, Nocomm => 1 });
	$horizmenu =~ s/^\s*//mg;
	$horizmenu =~ s/^-\s*//mg;
	$horizmenu =~ s/\s*$//mg;
	$horizmenu =~ s/<HR(?:>|\s[^>]*>)//g;
	$horizmenu = join ' | ', split /<BR>/, $horizmenu;
	$horizmenu =~ s/[\|\s]+$//;
	$horizmenu =~ s/^[\|\s]+//;
	return "[ $horizmenu ]";
}

#========================================================================

=item titlebar(WIDTH, TITLE)

Prints a titlebar widget.  Deprecated; exactly equivalent to:

	slashDisplay('titlebar', {
		width	=> $width,
		title	=> $title
	});

Parameters

	WIDTH
	Width of the titlebar.

	TITLE
	Title of the titlebar.

Return value

	None.

Dependencies

	The 'titlebar' template block.

=cut

sub titlebar {
	my($width, $title) = @_;
	slashDisplay('titlebar', {
		width	=> $width,
		title	=> $title
	});
}

#========================================================================

=item fancybox(WIDTH, TITLE, CONTENTS [, CENTER, RETURN])

Creates a fancybox widget.

Parameters

	WIDTH
	Width of the fancybox.

	TITLE
	Title of the fancybox.

	CONTENTS
	Contents of the fancybox.  (I see a pattern here.)

	CENTER
	Boolean for whether or not the fancybox
	should be centered.

	RETURN
	Boolean for whether to return or print the
	fancybox.

Return value

	The fancybox if RETURN is true, or true/false
	on success/failure.

Dependencies

	The 'fancybox' template block.

=cut

sub fancybox {
	my($width, $title, $contents, $center, $return) = @_;
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
		center		=> $center,
		mainwidth	=> $mainwidth,
		insidewidth	=> $insidewidth,
	}, $return);
}

#========================================================================

=item portalbox(WIDTH, TITLE, CONTENTS, BID [, URL])

Creates a portalbox widget.  Calls C<fancybox> to process
the box itself.

Parameters

	WIDTH
	Width of the portalbox.

	TITLE
	Title of the portalbox.

	CONTENTS
	Contents of the portalbox.

	BID
	The block ID for the portal in question.

	URL
	URL to link the title of the portalbox to.

Return value

	The portalbox.

Dependencies

	The 'fancybox', 'portalboxtitle', and
	'portalmap' template blocks.

=cut

sub portalbox {
	my($width, $title, $contents, $bid, $url) = @_;
	return unless $title && $contents;
	my $constants = getCurrentStatic();
	my $user = getCurrentUser();

	$title = slashDisplay('portalboxtitle', {
		title	=> $title,
		url	=> $url,
	}, { Return => 1, Nocomm => 1 });

	if ($user->{exboxes}) {
		$title = slashDisplay('portalmap', {
			title	=> $title,
			bid	=> $bid,
		}, { Return => 1, Nocomm => 1 });
	}

	fancybox($width, $title, $contents, 0, 1);
}

########################################################
# Behold, the beast that is threaded comments
sub selectComments {
	my($sid, $cid) = @_;
	my $slashdb = getCurrentDB();
	my $constants = getCurrentStatic();
	my $user = getCurrentUser();
	my $form = getCurrentForm();

	my $comments; # One bigass struct full of comments
	foreach my $x (0..6) { $comments->[0]{totals}[$x] = 0 }

	my $thisComment = $slashdb->getCommentsForUser($sid, $cid);
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
			if $C->{points} >= ($user->{threshold} || $constants->{comment_minscore});

		$user->{points} = 0 if $C->{uid} == $user->{uid}; # Mod/Post Rule
	}

	my $count = @$thisComment;

	getCommentTotals($comments);
	$slashdb->updateCommentTotals($sid, $comments) if $form->{ssi};
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
	my $slashdb = getCurrentDB();
	my $constants = getCurrentStatic();
	my $user = getCurrentUser();
	my $form = getCurrentForm();

	my $depth = $constants->{max_depth} || 7;

	return unless $depth || $user->{reparent};

	# adjust depth for root pid or cid
	if (my $cid = $form->{cid} || $form->{pid}) {
		while ($cid && (my($pid) = $slashdb->getCommentPid($form->{sid}, $cid))) {
			$depth++;
			$cid = $pid;
		}
	}

	for (my $x = 1; $x < @$comments; $x++) {
		next unless $comments->[$x];

		my $pid = $comments->[$x]{pid};
		my $reparent;

		# do threshold reparenting thing
		print STDERR "$user:$user->{reparent}:$user->{threshold}: \n";
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

#========================================================================

=item printComments(SID [, PID, CID])

Prints all that comment stuff.

Parameters

	SID
	The story ID to print comments for.

	PID
	The parent ID of the comments to print.

	CID
	The comment ID to print.

Return value

	None.

Dependencies

	The 'printCommentsMain', 'printCommentsNoArchive',
	and 'printCommentsComments' template blocks.

=cut

sub printComments {
	my($sid, $pid, $cid) = @_;
	my $constants = getCurrentStatic();
	my $user = getCurrentUser();
	my $form = getCurrentForm();

	$pid ||= 0;
	$cid ||= 0;
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

	if ($user->{mode} ne 'archive') {
		my($title, $section);
		my $slashdb = getCurrentDB();

		if ($slashdb->getStory($sid)) {
			$title = $slashdb->getStory($sid, 'title');
			$section = $slashdb->getStory($sid, 'section');
		} else {
			my $story = $slashdb->getNewStory($sid, ['title', 'section']);
			$title = $story->{title};
			$section = $story->{section};
		}

		slashDisplay('printCommentsMain', {
			comments	=> $comments,
			title		=> $title,
			count		=> $count,
			sid		=> $sid,
			cid		=> $cid,
			pid		=> $pid,
			section		=> $section,
			lvl		=> $lvl,
		});

		return if $user->{mode} eq 'nocomment';

	} else {
		slashDisplay('printCommentsNoArchive');
	}


	my($comment, $next, $previous);
	if ($cid) {
		my($next, $previous);
		$comment = $comments->[$cid];
		if (my $sibs = $comments->[$comment->{pid}]{kids}) {
			for (my $x = 0; $x < @$sibs; $x++) {
				($next, $previous) = ($sibs->[$x+1], $sibs->[$x-1])
					if $sibs->[$x] == $cid;
			}
		}
		$next = $comments->[$next] if $next;
		$previous = $comments->[$previous] if $previous;
	}

	slashDisplay('printCommentsComments', {
		can_moderate	=> (($user->{seclev} || $user->{points}) && !$user->{is_anon}),
		comment		=> $comment,
		comments	=> $comments,
		'next'		=> $next,
		previous	=> $previous,
		sid		=> $sid,
		cid		=> $cid,
		pid		=> $pid,
		cc		=> $cc,
		lcp		=> linkCommentPages($sid, $pid, $cid, $cc),
	});
}

#========================================================================

=item moderatorCommentLog(SID, CID)

Prints a table detailing the history of moderation of
a particular comment.

Parameters

	SID
	Comment's story ID.

	CID
	Comment's ID.

Return value

	The HTML.

Dependencies

	The 'moderatorCommentLog' template block.

=cut

sub moderatorCommentLog {
	my($sid, $cid) = @_;
	my $slashdb = getCurrentDB();
	my $constants = getCurrentStatic();

	my $seclev = getCurrentUser('seclev');
	my $comments = $slashdb->getModeratorCommentLog($sid, $cid);
	my(@reasonHist, $reasonTotal);

	for my $comment (@$comments) {
		$reasonHist[$comment->{reason}]++;
		$reasonTotal++;
	}

	slashDisplay('moderatorCommentLog', {
		mod_admin	=> getCurrentUser('seclev') > 1000,
		comments	=> $comments,
		reasonTotal	=> $reasonTotal,
		reasonHist	=> \@reasonHist,
	}, { Return => 1, Nocomm => 1 });
}

#========================================================================

=item linkCommentPages(SID, PID, CID, TOTAL)

Print links to pages for additional comments.

Parameters

	SID
	Story ID.

	PID
	Parent ID.

	CID
	Comment ID.

	TOTAL
	Total number of comments.

Return value

	Links.

Dependencies

	The 'linkCommentPages' template block.

=cut

sub linkCommentPages {
	my($sid, $pid, $cid, $total) = @_;

	return slashDisplay('linkCommentPages', {
		sid	=> $sid,
		pid	=> $pid,
		cid	=> $cid,
		total	=> $total,
	}, 1);
}

#========================================================================

=item linkComment(COMMENT [, PRINTCOMMENT, DATE])

Print a link to a comment.

Parameters

	COMMENT
	A hashref containing data about the comment.

	PRINTCOMMENT
	Boolean for whether to create link directly
	to comment, instead of to the story for that comment.

	DATE
	Boolean for whather to print date with link.

Return value

	Link for comment.

Dependencies

	The 'linkComment' template block.

=cut

sub linkComment {
	my($comment, $printcomment, $date) = @_;
	my $user = getCurrentUser();

	slashDisplay('linkComment', {
		%$comment, # defaults
		date		=> $date,
		pid		=> $comment->{realpid} || $comment->{pid},
		threshold	=> $comment->{threshold} || $user->{threshold},
		commentsort	=> $user->{commentsort},
		mode		=> $user->{mode},
		comment		=> $printcomment,
	}, { Return => 1, Nocomm => 1 });
}

#========================================================================

=item displayThread(SID, PID, LVL, COMMENTS)

Displays an entire thread.  w00p!

Parameters

	SID
	The story ID.

	PID
	The parent ID.

	LVL
	What level of the thread we're at.

	COMMENTS
	Arrayref of all our comments.

Return value

	The thread.

Dependencies

	The 'displayThread' template block.

=cut

sub displayThread {
	my($sid, $pid, $lvl, $comments, $const) = @_;
	my $constants = getCurrentStatic();
	my $user = getCurrentUser();
	my $form = getCurrentForm();

	$lvl ||= 0;
	my $mode = getCurrentUser('mode');
	my $indent = 1;
	my $full = my $cagedkids = !$lvl;
	my $hidden = my $displayed = my $skipped = 0;
	my $return = '';

	if ($user->{mode} eq 'flat' || $user->{mode} eq 'archive') {
		$indent = 0;
		$full = 1;
	} elsif ($user->{mode} eq 'nested') {
		$indent = 1;
		$full = 1;
	}

	unless ($const) {
		for (map { ($_ . "begin", $_ . "end") }
			qw(table cage cagebig indent comment)) {
			$const->{$_} = getData($_);
		}
	}

	foreach my $cid (@{$comments->[$pid]{kids}}) {
		my $comment = $comments->[$cid];

		$skipped++;
		$form->{startat} ||= 0;
		next if $skipped < $form->{startat};
		$form->{startat} = 0; # Once We Finish Skipping... STOP

		if ($comment->{points} < $user->{threshold}) {
			if ($user->{is_anon} || ($user->{uid} != $comment->{uid})) {
				$hidden++;
				next;
			}
		}

		my $highlight = 1 if $comment->{points} >= $user->{highlightthresh};
		my $finish_list = 0;

		if ($full || $highlight) {
			if ($lvl && $indent) {
				$return .= $const->{tablebegin} .
					dispComment($comment) . $const->{tableend};
				$cagedkids = 0;
			} else {
				$return .= dispComment($comment);
			}
			$displayed++;
		} else {
			my $pntcmt = @{$comments->[$comment->{pid}]{kids}} > $user->{commentspill};
			$return .= $const->{commentbegin} .
				linkComment($comment, $pntcmt, 1);
			$finish_list++;
		}

		if ($comment->{kids}) {
			$return .= $const->{cagebegin} if $cagedkids;
			$return .= $const->{indentbegin} if $indent;
			$return .= displayThread($sid, $cid, $lvl+1, $comments, $const);
			$return .= $const->{indentend} if $indent;
			$return .= $const->{cageend} if $cagedkids;			
		}

		$return .= $const->{commentend} if $finish_list;

		last if $displayed >= $user->{commentlimit};
	}

	if ($hidden && ! $user->{hardthresh} && $user->{mode} ne 'archive') {
		$return .= $const->{cagebigbegin} if $cagedkids;
		my $link = linkComment({
			sid		=> $sid,
			threshold	=> $constants->{comment_minscore},
			pid		=> $pid,
			subject		=> getData('displayThreadLink', { hidden => $hidden })
		});
		$return .= slashDisplay('displayThread', { 'link' => $link },
			{ Return => 1, Nocomm => 1 });
		$return .= $const->{cagebigend} if $cagedkids;
	}

	return $return;
}

#========================================================================

=item dispComment(COMMENT)

Displays a particular comment.

Parameters

	COMMENT
	Hashref of comment data.
		If the 'no_moderation' key of the COMMENT hashref exists, the
		moderation elements of the comment will not be displayed.

Return value

	The comment to display.

Side effects


Dependencies

	The 'dispComment' template block.

=cut

sub dispComment {
	my($comment) = @_;
	my $constants = getCurrentStatic();
	my $user = getCurrentUser();
	my $form = getCurrentForm();

	my($comment_shrunk, %reasons);

	if ($form->{mode} ne 'archive' && length($comment->{comment}) > $user->{maxcommentsize}
		&& $form->{cid} ne $comment->{cid}) {
		$comment_shrunk = substr $comment->{comment}, 0, $user->{maxcommentsize};
	}

	for (0 .. @{$constants->{reasons}} - 1) {
		$reasons{$_} = $constants->{reasons}[$_];
	}

	my $can_mod = ! $user->{is_anon} &&
		((	$user->{willing} && $user->{points} > 0 &&
			$comment->{uid} != $user->{uid} && $comment->{lastmod} != $user->{uid}
		) || ($user->{seclev} > 99 && $constants->{authors_unlimited}));

	slashDisplay('dispComment', {
		%$comment,
		comment_shrunk	=> $comment_shrunk,
		reasons		=> \%reasons,
		can_mod		=> $comment->{no_moderation} ? 0 : $can_mod,
		is_anon		=> isAnon($comment->{uid}),
		fixednickname	=> fixparam($comment->{nickname}),
	}, { Return => 1, Nocomm => 1 });
}

###########################################################
#  Functions for dealing with Story selection and Display #
###########################################################

#========================================================================

=item dispStory(STORY, AUTHOR, TOPIC, FULL)

Display a story.

Parameters

	STORY
	Hashref of data about the story.

	AUTHOR
	Hashref of data about the story's author.

	TOPIC
	Hashref of data about the story's topic.

	FULL
	Boolean for show full story, or just the
	introtext portion.

Return value

	Story to display.

Dependencies

	The 'dispStory' and 'dispStoryTitle' template blocks.

=cut


sub dispStory {
	my($story, $author, $topic, $full) = @_;
	my $constants = getCurrentStatic();
	my $user = getCurrentUser();
	my $form = getCurrentForm();

	my $section = getSection($story->{section});

	my %data = (
		story	=> $story,
		section => $section,
		topic	=> $topic,
		author	=> $author,
		full	=> $full,
		magic	=> (!$full && index($story->{title}, ':') == -1
			&& $story->{section} ne $constants->{defaultsection}
			&& $story->{section} ne $form->{section})
	);

	my $title = slashDisplay('dispStoryTitle', \%data,
		{ Return => 1, Nocomm => 1 });
	slashDisplay('dispStory', {
		%data,
		width	=> $constants->{titlebar_width},
		title	=> $title,
	}, 1);

}

#========================================================================

=item displayStory(SID, FULL, CALLER)

Display a story (frontend to C<dispStory>).

Parameters

	SID
	Story ID to display.

	FULL
	Boolean for show full story, or just the
	introtext portion.

	CALLER
	The calling script.

Return value

	A list of story to display, hashref of story data,
	hashref of author data, and hashref of topic data.

=cut

sub displayStory {
	# caller is the pagename of the calling script
	my($sid, $full, $caller) = @_;

	my $slashdb = getCurrentDB();
	my $story = $slashdb->getStory($sid);
	my $author = $slashdb->getUser($story->{uid}, ['nickname', 'fakemail']);
	my $topic = $slashdb->getTopic($story->{tid});
	
	# convert the time of the story (this is database format) 
	# and convert it to the user's prefered format 
	# based on their preferences 
	setCurrentUser('storytime', timeCalc($story->{'time'}));

	# get extra data from section table for this story
	# (if exists)
	$slashdb->setSectionExtra($full, $story);

	my $return = dispStory($story, $author, $topic, $full);
	return($return, $story, $author, $topic);
}


#========================================================================

=item timeCalc(DATE)

Format time strings.

Parameters

	DATE
	Raw date from database.

Return value

	Formatted date string.

Dependencies

	The 'atonish' and 'aton' template blocks.

=cut

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
	if ($user->{'format'} eq '%i ish') {
		$user->{aton} = getData('atonish');
	} else {
		$user->{aton} = getData('aton');
	}

	# find out the user's time based on personal offset
	# in seconds
	$date = DateCalc($date, "$user->{offset} SECONDS", \$err);

	# convert the raw date to pretty formatted date
	$date = UnixDate($date, $user->{'format'});

	# return the new pretty date
	return $date;
}

#========================================================================

=item getOlderStories(STORIES, SECTION)

Get older stories for older stories box.

Parameters

	STORIES
	Array ref of the older stories.

	SECTION
	Hashref of section data.

Return value

	The older stories.

Dependencies

	The 'getOlderStories' template block.

=cut

sub getOlderStories {
	my($stories, $section) = @_;
	my($count, $newstories, $today, $stuff);
	my $slashdb = getCurrentDB();
	my $constants = getCurrentStatic();
	my $user = getCurrentUser();
	my $form = getCurrentForm();

	$stories ||= $slashdb->getStories($section, $user->{currentSection});
	for (@$stories) {
		my($sid, $sect, $title, $time, $commentcount, $day) = @{$_}; 
		my($w, $m, $d, $h, $min, $ampm) = split m/ /, $time;
		push @$newstories, {
			sid		=> $sid,
			section		=> $sect,
			title		=> $title,
			'time'		=> $time,
			commentcount	=> $commentcount,
			day		=> $day,
			w		=> $w,
			'm'		=> $m,
			d		=> $d,
			h		=> $h,
			min		=> $min,
			ampm		=> $ampm,
			'link'		=> linkStory({
				'link'	=> $title,
				sid	=> $sid,
				section	=> $sect
			})
		};
	}

	slashDisplay('getOlderStories', {
		stories		=> $newstories,
		section		=> $section,
		yesterday	=> (($form->{issue} > 1 || $form->{issue}) ? $slashdb->getDay() : int($form->{issue})) - 1,
		min		=> $section->{artcount} + $form->{min},
	}, 1);
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
	return unless $subj;
	my $slashdb = getCurrentDB();
	my $constants = getCurrentStatic();

	my $msg;
	my $locks = $slashdb->getLock();
	for (@$locks) {
		my($subject, $aid) = @$_;
		if ($aid ne getCurrentUser('aid') && (my $pct = matchingStrings($subject, $subj))) {
			$msg .= slashDisplay('lockTest', {
				percent	=> $pct,
				subject	=> $subject,
				aid	=> $aid
			}, 1);
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
	my($interval) = @_;
	my $interval_string;

	if ($interval > 60) {
		my($hours, $minutes) = 0;
		if ($interval > 3600) {
			$hours = int($interval/3600);
			if ($hours > 1) {
				$interval_string = $hours . ' ' . getData('hours');
			} elsif ($hours > 0) {
				$interval_string = $hours . ' ' . getData('hour');
			}
			$minutes = int(($interval % 3600) / 60);

		} else {
			$minutes = int($interval / 60);
		}

		if ($minutes > 0) {
			$interval_string .= ", " if $hours;
			if ($minutes > 1) {
				$interval_string .= $minutes . ' ' . getData('minutes');
			} else {
				$interval_string .= $minutes . ' ' . getData('minute');
			}
		}
	} else {
		$interval_string = $interval . ' ' . getData('seconds');
	}

	return($interval_string);
}

##################################################################
sub submittedAlready {
	my($formkey, $formname) = @_;
	my $slashdb = getCurrentDB();

	# find out if this form has been submitted already
	my($submitted_already, $submit_ts) = $slashdb->checkForm($formkey, $formname)
		or errorMessage(getData('noformkey')), return;

		if ($submitted_already) {
			errorMessage(getData('submitalready', {
				interval_string => intervalString(time() - $submit_ts)
			}));
		}
		return($submitted_already);
}

##################################################################
# nice little function to print out errors
sub errorMessage {
	my($error_message) = @_;
	print $error_message, "\n";
	return;
}


##################################################################
# make sure they're not posting faster than the limit
sub checkSubmission {
	my($formname, $limit, $max, $id) = @_;
	my $slashdb = getCurrentDB();
	my $constants = getCurrentStatic();

	my $formkey_earliest = time() - $constants->{formkey_timeframe};
	# If formkey starts to act up, me doing the below
	# may be the cause
	my $formkey = getCurrentForm('formkey');

	my $last_submitted = $slashdb->getSubmissionLast($id, $formname);

	my $interval = time() - $last_submitted;

	if ($interval < $limit) {
		errorMessage(getData('speedlimit', {
			limit_string	=> intervalString($limit),
			interval_string	=> intervalString($interval)
		}));
		return;

	} else {
		if ($slashdb->checkTimesPosted($formname, $max, $id, $formkey_earliest)) {
			undef $formkey unless $formkey =~ /^\w{10}$/;

			unless ($formkey && $slashdb->checkFormkey($formkey_earliest, $formname, $id, $formkey)) {
				$slashdb->formAbuse("invalid form key", $ENV{REMOTE_ADDR}, $ENV{SCRIPT_NAME}, $ENV{QUERY_STRING});
				errorMessage(getData('invalidformkey'));
				return;
			}

			if (submittedAlready($formkey, $formname)) {
				$slashdb->formAbuse("form already submitted", $ENV{REMOTE_ADDR}, $ENV{SCRIPT_NAME}, $ENV{QUERY_STRING});
				return;
			}

		} else {
			$slashdb->formAbuse("max form submissions $max reached", $ENV{REMOTE_ADDR}, $ENV{SCRIPT_NAME}, $ENV{QUERY_STRING});
			errorMessage(getData('maxposts', {
				max		=> $max,
				timeframe	=> intervalString($constants->{formkey_timeframe})
			}));
			return;
		}
	}
	return 1;
}

#========================================================================

=item createMenu(MENU)

Creates a menu.

Parameters

	MENU
	The name of the menu to get.

Return value

	The menu.

Dependencies

	The template blocks 'menu-admin', 'menu-user', and any other
	template blocks for menus, along with all the data in the
	'menus' table.

=cut

sub createMenu {
	my($menu) = @_;
	my $slashdb = getCurrentDB();
	my $constants = getCurrentStatic();
	my $user = getCurrentUser();
	my $menu_items = getCurrentMenu($menu);
	my $items = [];

	for my $item (sort { $a->{menuorder} <=> $b->{menuorder} } @$menu_items) {
		next unless $user->{seclev} >= $item->{seclev};
		push @$items, {
			value => slashDisplay(\$item->{value}, {}, { Return => 1, Nocomm => 1 }),
			label => slashDisplay(\$item->{label}, {}, { Return => 1, Nocomm => 1 })
		};
	}

	return slashDisplay("menu-$menu", { items => $items }, 1);
}


#################################################################
# this gets little snippets of data all in grouped together in
# one template, called "Slash-data"
sub getData {
	my($value, $hashref) = @_;
	$hashref ||= {};
	$hashref->{value} = $value;
	return slashDisplay('Slash-data', $hashref,
		{ Return => 1, Nocomm => 1 });
}

1;

__END__

=head1 AUTHOR

Copyright (C) 1997 Rob "CmdrTaco" Malda, malda@slashdot.org

This program is free software; you can redistribute it and/or
modify it under the terms of the GNU General Public License
as published by the Free Software Foundation; either version 2
of the License, or (at your option) any later version.

This program is distributed in the hope that it will be useful,
but WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
GNU General Public License for more details.

You should have received a copy of the GNU General Public License
along with this program; if not, write to the Free Software
Foundation, Inc., 59 Temple Place - Suite 330, Boston, MA  02111-1307, USA.
