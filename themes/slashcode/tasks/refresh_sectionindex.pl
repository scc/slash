#!/usr/bin/perl -w
#
# $Id$
#
# SlashD Task (c) OSDN 2001
#
# Description: refreshes the static "sectionindex_display" template for use
# in HTML output.

use strict;

use Slash::Display;

use vars qw( %task $me );

$task{$me}{timespec} = '0-59/10 * * * *';
$task{$me}{timespec_panic_1} = ''; # not that important
$task{$me}{on_startup} = 1;
$task{$me}{code} = sub {
	my($virtual_user, $constants, $slashdb, $user) = @_;
	my $sections = $slashdb->getSectionInfo();

	my $new_template = slashDisplay('sectionindex', {
		sections => $sections,
	}, 1);

	# If it exists, we update it, if not, we create it.  The final "1" arg
	# means to ignore errors.
	my $tpid = $slashdb->getTemplateByName(
		'sectionindexd', 'tpid', 0, '', '', 1
	);

	my(%template) = ( 
		name => 'sectionindexd',
		tpid => $tpid, 
		template => $new_template,
	);
	if ($tpid) {
		$slashdb->setTemplate($tpid, \%template);
	} else {
		$slashdb->createTemplate(\%template);
	}

	return scalar(@$sections) . " sections refreshed";
};

1;

