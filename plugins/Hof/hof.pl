#!/usr/bin/perl -w

#  $Id$
use strict;
use Slash;
use Slash::Display;
use Slash::Utility;

##################################################################
sub main {
	my $slashdb = getCurrentDB();
	my $form = getCurrentForm();
	my $section = getSection($form->{section});

	header(getData('head'), $section->{section});

	my(@topcomments, $topcomments);
	$topcomments = $slashdb->getCommentsTop($form->{sid});
	for (@$topcomments) {
		my $top = $topcomments[@topcomments] = {};
		# leave as "aid" for now
		@{$top}{qw(section sid aid title pid subj cdate sdate uid cid score)} = @$_;
		my $user_email = $slashdb->getUser($top->{uid}, ['fakeemail', 'nickname']);
		@{$top}{'fakeemail', 'nickname'} = @{$user_email}{'fakeemail', 'nickname'};
	}

	slashDisplay('main', {
		width		=> '98%',
		actives		=> $slashdb->countStories(),
		visited		=> $slashdb->countStoriesStuff(),
		activea		=> $slashdb->countStoriesAuthors(),
		activep		=> $slashdb->countPollquestions(),
		currtime	=> scalar localtime,
		topcomments	=> \@topcomments,
	});

# this is commented out ... ?
# 	if (0) {  #  only do this in static mode
# 		print "<P>";
# 		titlebar("100%", "Most Popular Slashboxes");
# 		my $boxes = $I{dbobject}->getDescription('sectionblocks');
# 		my(%b, %titles);
# 
# 		while (my($bid, $title) = each %$boxes) {
# 			$b{$bid} = 1;
# 			$titles{$bid} = $title;
# 		}
# 
# 
# 		#Something tells me we could simplify this with some 
# 		# thought -Brian
# 		foreach my $bid (keys %b) {
# 			$b{$bid} = $I{dbobject}->countUsersIndexExboxesByBid($bid);
# 		}
# 
# 		my $x;
# 		foreach my $bid (sort { $b{$b} <=> $b{$a} } keys %b) {
# 			$x++;
# 			$titles{$bid} =~ s/<(.*?)>//g;
# 			print <<EOT;
# 
# <B>$b{$bid}</B> <A HREF="$I{rootdir}/users.pl?op=preview&bid=$bid">$titles{$bid}</A><BR>
# EOT
# 			last if $x > 10;
# 		}
# 	}

	writeLog('hof');
	footer($form->{ssi});
}

#################################################################
createEnvironment();
main();

1;
