#!/usr/bin/perl -w

#  $Id$
use strict;
use Slash;
use Slash::Display;
use Slash::Utility;

##################################################################
sub main {
	my $form = getCurrentForm();
	my $user = getCurrentUser();
	my $dbslash = getCurrentDB();
	my $constants = getCurrentStatic();

	# Let's make ONE call to getStory() and fetch all we need.
	# - Cliff
	my $story = $dbslash->getStory($form->{sid});

	if ($story->{writestatus} == 10) {
		$ENV{SCRIPT_NAME} = '';
		redirect(<<EOT);
$constants->{rootdir}/$story->{section}/$story->{sid}_$constants->{userMode}.shtml
EOT
		return;
	};

	my $SECT = $dbslash->getSection($story->{section});
	my $title = $SECT->{isolate} ?
		"$SECT->{title} | $story->{title}" :
		"$constants->{sitename} | $story->{title}";

	header($title, $story->{section});
	slashDisplay('display', {
		poll			=> pollbooth($story->{sid}, 1),
		section			=> $SECT,
		section_block		=> $dbslash->getBlock($SECT->{section}),
		show_poll		=> $dbslash->getPollQuestion($story->{sid}),
		story			=> $story,
		'next'			=> $dbslash->getStoryByTime('>', $story, $SECT),
		prev			=> $dbslash->getStoryByTime('<', $story, $SECT),
	});

	printComments($form->{sid});

	writeLog($SECT->{section}, $story->{sid} || $form->{sid})
		unless $form->{ssi};
	footer();
}

createEnvironment();
main();
1;
