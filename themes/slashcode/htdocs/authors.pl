#!/usr/bin/perl -w

#  $Id$
use strict;
use Slash;
use Slash::Display;
use Slash::Utility;

sub main {
	my $slashdb = getCurrentDB();
	my $constants = getCurrentStatic();
	my $form = getCurrentForm();

	my $section = getSection($form->{section});
	my $list = $slashdb->getAuthorDescription();
	my $authors = $slashdb->getAuthors();

	header("$constants->{sitename}: Authors", $section->{section});
	slashDisplay('main', {
		uids	=> $list,
		authors	=> $authors,
		title	=> "The Authors",
		admin	=> getCurrentUser('seclev') >= 1000,
		'time'	=> scalar localtime,
	});

	writeLog('authors');
	footer($form->{ssi});
}

createEnvironment();
main();
