# This code is a part of Slash, and is released under the GPL.
# Copyright 1997-2001 by Open Source Development Network. See README
# and COPYING for more information, or see http://slashcode.com/.
# $Id$

package Slash;

# BENDER: It's time to kick some shiny metal ass!

=head1 NAME

Slash - the BEAST

=head1 SYNOPSIS

	use Slash;  # figure the rest out ;-)

=head1 DESCRIPTION

Slash is the code that runs Slashdot.

=head1 FUNCTIONS

=cut

use strict;  # ha ha ha ha ha!
use Symbol 'gensym';

use Slash::DB;
use Slash::Display;
use Slash::Utility;

use base 'Exporter';
use vars qw($VERSION @EXPORT);

use constant COMMENTS_OPEN 	=> 0;
use constant COMMENTS_RECYCLE 	=> 1;
use constant COMMENTS_READ_ONLY => 2;

$VERSION   = '2.001000';  # v2.1.0
# note: those last two lines of functions will be moved elsewhere
@EXPORT	   = qw(
	getData
	gensym

	dispComment displayStory displayThread dispStory
	getOlderStories moderatorCommentLog printComments
);

# all of these will also get moved elsewhere
# @EXPORT_OK = qw(
# 	getCommentTotals reparentComments selectComments
# );

# this is the worst damned warning ever, so SHUT UP ALREADY!
$SIG{__WARN__} = sub { warn @_ unless $_[0] =~ /Use of uninitialized value/ };

# BENDER: Fry, of all the friends I've had ... you're the first.


########################################################
# Behold, the beast that is threaded comments
sub selectComments {
	my($header, $cid, $sid) = @_;
	my $slashdb = getCurrentDB();
	my $constants = getCurrentStatic();
	my $user = getCurrentUser();
	my $form = getCurrentForm();
	my($min, $max) = ($constants->{comment_minscore}, $constants->{comment_maxscore});
	my $num_scores = $max-$min+1;

	my $comments; # One bigass struct full of comments
	foreach my $x (0..$num_scores-1) {
		$comments->[0]{totals}[$x] = $comments->[0]{natural_totals}[$x] = 0
	}

	my $thisComment = $slashdb->getCommentsForUser($header, $cid);
	for my $C (@$thisComment) {
		# Let's think about whether we really want to set pid to 0 here.  It may
		# be a friendlier UI to allow bouncing up to parent comments even though
		# the comment sort is set to flat. - Jamie 2001/06/19
		$C->{pid} = 0 if $user->{commentsort} > 3; # Ignore Threads

		# Tally up this comment in its "natural" score category (before the user's
		# preferences get a chance to knock it up or down).
		$comments->[0]{natural_totals}[$C->{points} - $min]++;

		$C->{points}++ if $user->{clbig} and length($C->{comment}) > $user->{clbig}
			and $C->{points} < $max;

		$C->{points}-- if $user->{clsmall} and length($C->{comment}) < $user->{clsmall}
			and $C->{points} > $min;

		# fix points in case they are out of bounds
		# (XXX looking at the logic above, this seems unnecessary)
		$C->{points} = $min if $C->{points} < $min;
		$C->{points} = $max if $C->{points} > $max;

		# Also tally up this comment for the user's personal score.
		$comments->[0]{totals}[$C->{points} - $min]++;

		my $tmpkids = $comments->[$C->{cid}]{kids};
		my $tmpvkids = $comments->[$C->{cid}]{visiblekids};
		$comments->[$C->{cid}] = $C;
		$comments->[$C->{cid}]{kids} = $tmpkids;
		$comments->[$C->{cid}]{visiblekids} = $tmpvkids;

		push @{$comments->[$C->{pid}]{kids}}, $C->{cid};
		$comments->[$C->{pid}]{visiblekids}++
#			if $C->{points} >= ($user->{threshold} || $min); # XXX wrong for two reasons - should be form->threshold, and a threshold of 0 should not be replaced by -1 - still fixing this logic elsewhere, stay tuned - Jamie
			if $C->{points} >= (defined($form->{threshold}) ? $form->{threshold} : $user->{threshold});

		$user->{points} = 0 if $C->{uid} == $user->{uid}; # Mod/Post Rule
	}

	my $count = @$thisComment;

	# Cascade comment point totals down to the lowest score, so
	# (2, 1, 3, 5, 4, 2, 1) becomes (18, 16, 15, 12, 7, 3, 1).
	for my $x (reverse(0..$num_scores-2)) {
		$comments->[0]{totals}[$x]		+= $comments->[0]{totals}[$x+1];
		$comments->[0]{natural_totals}[$x]	+= $comments->[0]{natural_totals}[$x+1];
	}

	reparentComments($comments);
	return($comments, $count);
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

=head2 printComments(SID [, PID, CID])

Prints all that comment stuff.

=over 4

=item Parameters

=over 4

=item SID

The story ID to print comments for.

=item PID

The parent ID of the comments to print.

=item CID

The comment ID to print.

=back

=item Return value

None.

=item Dependencies

The 'printCommentsMain', 'printCommNoArchive',
and 'printCommComments' template blocks.

=back

=cut

sub printComments {
	my($sid, $pid, $cid) = @_;
	my $user = getCurrentUser();
	my $form = getCurrentForm();
	my $slashdb = getCurrentDB();

	my($discussion, $header);
	# SID compatibility
	if ($sid !~ /^\d+$/) {
		$discussion = $slashdb->getDiscussionBySid($sid);
		$header = $discussion->{id};
	} else {
		$discussion = $slashdb->getDiscussion($sid);
		$sid = $discussion->{sid};
		$header = $discussion->{id};
	}

print STDERR "==========\nDEBUG printComments: Sid:($sid) Header:($header) PID:($pid) CID:($cid) Discussion:($discussion)\n";

	$pid ||= 0;
	$cid ||= 0;
	my $lvl = 0;

	# Get the Comments
	my($comments, $count) = selectComments($header, $cid || $pid, $sid);

# { use Data::Dumper; print STDERR "form: " . Dumper($form) . "comments: " . Dumper($comments) . "\n" }

	# Should I index or just display normally?
	my $cc = 0;
	if ($comments->[$cid || $pid]{visiblekids}) {
		$cc = $comments->[$cid || $pid]{visiblekids};
	}

	$lvl++ if $user->{mode} ne 'flat' && $user->{mode} ne 'archive'
		&& $cc > $user->{commentspill}
		&& ( $user->{commentlimit} > $cc ||
		     $user->{commentlimit} > $user->{commentspill} );

	if ($discussion->{type} == COMMENTS_READ_ONLY) {
		$user->{state}{comment_read_only} = 1;
		slashDisplay('printCommNoArchive');
	}

	slashDisplay('printCommentsMain', {
		comments	=> $comments,
		title		=> $discussion->{title},
		link		=> $discussion->{url},
		count		=> $count,
		sid		=> $header,
		cid		=> $cid,
		pid		=> $pid,
		lvl		=> $lvl,
	});

	return if $user->{mode} eq 'nocomment';

	my($comment, $next, $previous);
	if ($cid) {
		my($next, $previous);
		$comment = $comments->[$cid];
		if (my $sibs = $comments->[$comment->{pid}]{kids}) {
			FINDSIBS: for (my $x = 0; $x <= $#$sibs; $x++) {
				if ($sibs->[$x] == $cid) {
					($next, $previous) = ($sibs->[$x+1], $sibs->[$x-1]);
					last FINDSIBS;
				}
			}
		}
		$next = $comments->[$next] if $next;
		$previous = $comments->[$previous] if $previous;
	}

	slashDisplay('printCommComments', {
		can_moderate	=> 
			( ($user->{seclev} > 100 || $user->{points}) &&
			  !$user->{is_anon} ) &&
			getCurrentStatic('allow_moderation'),
		comment		=> $comment,
		comments	=> $comments,
		'next'		=> $next,
		previous	=> $previous,
		sid		=> $header,
		cid		=> $cid,
		pid		=> $pid,
		cc		=> $cc,
		lcp		=> linkCommentPages($header, $pid, $cid, $cc),
		lvl		=> $lvl,
	});
}

#========================================================================

=head2 moderatorCommentLog(SID, CID)

Prints a table detailing the history of moderation of
a particular comment.

=over 4

=item Parameters

=over 4

=item SID

Comment's story ID.

=item CID

Comment's ID.

=back

=item Return value

The HTML.

=item Dependencies

The 'modCommentLog' template block.

=back

=cut

sub moderatorCommentLog {
	my($cid) = @_;
	my $slashdb = getCurrentDB();
	my $constants = getCurrentStatic();

	my $seclev = getCurrentUser('seclev');
	my $mod_admin = $seclev >= $constants->{modviewseclev} ? 1 : 0;
	my $comments = $slashdb->getModeratorCommentLog($cid);
#	my $comments = $slashdb->getModeratorCommentLog($sid, $cid);
	my(@reasonHist, $reasonTotal);

	for my $comment (@$comments) {
		$reasonHist[$comment->{reason}]++;
		$reasonTotal++;
	}

	slashDisplay('modCommentLog', {
		# modviewseclev
		mod_admin	=> $mod_admin, 
		comments	=> $comments,
		reasonTotal	=> $reasonTotal,
		reasonHist	=> \@reasonHist,
	}, { Return => 1, Nocomm => 1 });
}

#========================================================================

=head2 displayThread(SID, PID, LVL, COMMENTS)

Displays an entire thread.  w00p!

=over 4

=item Parameters

=over 4

=item SID

The story ID.

=item PID

The parent ID.

=item LVL

What level of the thread we're at.

=item COMMENTS

Arrayref of all our comments.

=back

=item Return value

The thread.

=item Dependencies

The 'displayThread' template block.

=back

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
			$const->{$_} = getData($_, '', '');
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
			subject		=> getData('displayThreadLink', { hidden => $hidden }, '')
		});
		$return .= slashDisplay('displayThread', { 'link' => $link },
			{ Return => 1, Nocomm => 1 });
		$return .= $const->{cagebigend} if $cagedkids;
	}

	return $return;
}

#========================================================================

=head2 dispComment(COMMENT)

Displays a particular comment.

=over 4

=item Parameters

=over 4

=item COMMENT

Hashref of comment data.
If the 'no_moderation' key of the COMMENT hashref exists, the
moderation elements of the comment will not be displayed.

=back

=item Return value

The comment to display.

=item Dependencies

The 'dispComment' template block.

=back

=cut

sub dispComment {
	my($comment) = @_;
	my $slashdb = getCurrentDB();
	my $constants = getCurrentStatic();
	my $user = getCurrentUser();
	my $form = getCurrentForm();

	my($comment_shrunk, %reasons);

	if ($form->{mode} ne 'archive' && length($comment->{comment}) > $user->{maxcommentsize}
		&& $form->{cid} ne $comment->{cid}) {
		$comment_shrunk = balanceTags(
			chopEntity($comment->{comment}, $user->{maxcommentsize})
		);
		$comment_shrunk = addDomainTags($comment_shrunk);
	}

	my $udt = exists($user->{domaintags}) ? $user->{domaintags} : 1;	# default is 1
	$udt =~ /^(\d+)$/; $udt = 1 if !length($1);	# make sure it's numeric, sigh
	my $want_tags = 1;				# assume we'll be displaying the [domain.tags]
	$want_tags = 0 if				# but, don't display them if...
		$udt == 0				# the user has said they never want the tags
		or (					# or
			$udt == 1			# the user leaves it up to us
			and $comment->{fakeemail}	# and we think the poster has earned tagless posting
		);
	if ($want_tags) {
		$comment->{comment} =~ s{</A ([^>]+)>}{</A> [$1]}gi;
		$comment_shrunk =~ s{</A ([^>]+)>}{</A> [$1]}gi if $comment_shrunk;
	} else {
		$comment->{comment} =~ s{</A[^>]+>}{</A>}gi;
		$comment_shrunk =~ s{</A[^>]+>}{</A>}gi if $comment_shrunk;
	}

	for (0 .. @{$constants->{reasons}} - 1) {
		$reasons{$_} = $constants->{reasons}[$_];
	}

	# I wonder if much of this logic should be moved out to the theme.
	# This logic can then be placed at the theme level and would eventually
	# become what is put into $comment->{no_moderation}. As it is, a lot
	# of the functionality of the moderation engine is intrinsically linked
	# with how things behave on Slashdot.	- Cliff 6/6/01
	my $can_mod = 	$constants->{allow_moderation} &&
			!$comment->{no_moderation} && 
			!$user->{is_anon} &&
			( ( $user->{willing} && $user->{points} > 0 &&
			    $comment->{uid} != $user->{uid} &&
			    $comment->{lastmod} != $user->{uid} ) ||
			  ($user->{seclev} > 99 &&
			   $constants->{authors_unlimited}) );

	# don't inherit these ...
	for (qw(sid cid pid date subject comment uid points lastmod
		reason nickname fakeemail homepage sig)) {
		$comment->{$_} = '' unless exists $comment->{$_};
	}

	slashDisplay('dispComment', {
		%$comment,
		comment_shrunk	=> $comment_shrunk,
		reasons		=> \%reasons,
		can_mod		=> $can_mod,
		is_anon		=> isAnon($comment->{uid}),
	}, { Return => 1, Nocomm => 1 });
}


#========================================================================

=head2 dispStory(STORY, AUTHOR, TOPIC, FULL)

Display a story.

=over 4

=item Parameters

=over 4

=item STORY

Hashref of data about the story.

=item AUTHOR

Hashref of data about the story's author.

=item TOPIC

Hashref of data about the story's topic.

=item FULL

Boolean for show full story, or just the
introtext portion.

=back

=item Return value

Story to display.

=item Dependencies

The 'dispStory' template block.

=back

=cut


sub dispStory {
	my($story, $author, $topic, $full) = @_;
	my $slashdb      = getCurrentDB();
	my $constants    = getCurrentStatic();
	my $form_section = getCurrentForm('section');


	my $section = $slashdb->getSection($story->{section});

	my %data = (
		story	=> $story,
		section => $section,
		topic	=> $topic,
		author	=> $author,
		full	=> $full,
		magic	=> (!$full && (index($story->{title}, ':') == -1)
			&& ($story->{section} ne $constants->{defaultsection})
			&& ($story->{section} ne $form_section)),
		width	=> $constants->{titlebar_width}
	);

	slashDisplay('dispStory', \%data, 1);
}

#========================================================================

=head2 displayStory(SID, FULL)

Display a story by SID (frontend to C<dispStory>).

=over 4

=item Parameters

=over 4

=item SID

Story ID to display.

=item FULL

Boolean for show full story, or just the
introtext portion.

=back

=item Return value

A list of story to display, hashref of story data,
hashref of author data, and hashref of topic data.

=back

=cut

sub displayStory {
	# caller is the pagename of the calling script
	my($sid, $full) = @_;	# , $caller  no longer needed?  -- pudge

	my $slashdb = getCurrentDB();
	my $story = $slashdb->getStory($sid);
	my $author = $slashdb->getAuthor($story->{uid},
		['nickname', 'fakeemail', 'homepage']);
	my $topic = $slashdb->getTopic($story->{tid});

	# convert the time of the story (this is database format)
	# and convert it to the user's prefered format
	# based on their preferences

	# An interesting note... this is pretty much the
	# only reason this function is even needed.
	# Everything else can easily be done with
	# dispStory(). Even this could be worked
	# into the logic for the template Display
	#  -Brian

	# well, also, dispStory needs a story reference, not an SID,
	# though that could be changed -- pudge

	$story->{storytime} = timeCalc($story->{'time'});

	# get extra data from section table for this story
	# (if exists)
	# this only needs to run for slashdot
	# why is this commented out?  -- pudge
	# Its basically an undocumented feature
	# that Slash uses.
	#$slashdb->setSectionExtra($full, $story);

	my $return = dispStory($story, $author, $topic, $full);
	return($return, $story, $author, $topic);
}


#========================================================================

=head2 getOlderStories(STORIES, SECTION)

Get older stories for older stories box.

=over 4

=item Parameters

=over 4

=item STORIES

Array ref of the "essentials" of the stories to display, gotten from
getStoriesEssentials. If empty, pulls the appropriate data from the
specified section.

=item SECTION

Hashref of section data.

=back

=item Return value

The older stories.

=item Dependencies

The 'getOlderStories' template block.

=back

=cut

sub getOlderStories {
	my($stories_essentials, $section) = @_;
	my($count, $stories_bigarray, $today, $stuff);
	my $slashdb = getCurrentDB();
	my $constants = getCurrentStatic();
	my $user = getCurrentUser();
	my $form = getCurrentForm();

	$stories_essentials ||= $slashdb->getStoriesEssentials($section);
	for my $sr (@$stories_essentials) {

		my @wordy_split = split / /, $sr->{wordytime};
		for my $i (0..5) {
			$sr->{ (qw( w m d h min ampm ))[$i] } = $wordy_split[$i]
		}
		$sr->{link} = linkStory({
			link	=> $sr->{title},
			sid	=> $sr->{sid},
			section	=> $sr->{section},
		});
		push @$stories_bigarray, $sr;

	}

	my $yesterday = $slashdb->getDay()
		unless $form->{issue} > 1 || $form->{issue};
	$yesterday ||= int($form->{issue}) - 1;

	slashDisplay('getOlderStories', {
		stories		=> $stories_bigarray,
		section		=> $section,
		yesterday	=> $yesterday,
		start		=> $section->{artcount} + $form->{start},
	}, 1);
}


#========================================================================

=head2 getData(VALUE [, PARAMETERS, PAGE])

Returns snippets of data associated with a given page.

=over 4

=item Parameters

=over 4

=item VALUE

The name of the data-snippet to process and retrieve.

=item PARAMETERS

Data stored in a hashref which is to be passed to the retrieved snippet.

=item PAGE

The name of the page to which VALUE is associated.

=back

=item Return value

Returns data snippet with all necessary data interpolated.

=item Dependencies

Gets little snippets of data, determined by the value parameter, from
a data template. A data template is a colletion of data snippets
in one template, which are grouped together for efficiency. Each
script can have it's own data template (specified by the PAGE
parameter). If PAGE is unspecified, snippets will be retrieved from
the last page visited by the user as determined by Slash::Apache::User.

=back

=cut

sub getData {
	my($value, $hashref, $page) = @_;
	$hashref ||= {};
	$hashref->{value} = $value;
	my %opts = ( Return => 1, Nocomm => 1 );
	$opts{Page} = $page || 'NONE' if defined $page;
	return slashDisplay('data', $hashref, \%opts);
}

1;

__END__

=head1 BENDER'S TOP TEN MOST FREQUENTLY UTTERED WORDS

=over 4

=item 1.

ass

=item 2.

daffodil

=item 3.

shiny

=item 4.

my

=item 5.

bite

=item 6.

pimpmobile

=item 7.

up

=item 8.

yours

=item 9.

chumpette

=item 10.

chump

=back
