#!/usr/bin/perl -w
#
# $Id$
#
# SlashD Task (c) OSDN 2001
#
# Description: refreshes the static "sectionindex_display" template for use
# in HTML output.


use strict;
my $me = 'refresh_sectionindex.pl';

use vars qw( %task );

$task{$me}{timespec} = '0-59/10 * * * *';
$task{$me}{code} = sub {
	my($virtual_user, $constants, $slashdb, $user) = @_;
	my $sections = $slashdb->getSectionInfo();

	if ($virtual_user eq 'banjo'
		and `/bin/hostname` =~ /cpu25/) {
		my $min = (localtime)[1];
		if ($min >= 35 and $min <= 55) {
			slashdLog("skipping $me while DB import in progress");
			return;
		}
	}

	my $new_template = slashDisplay('sectionindex', {
		sections => $sections,
	}, 1);

	# If it exists, we update it, if not, we create it.  The final "1" arg
	# means to ignore errors.
	my $tpid = $slashdb->getTemplateByName('sectionindex_display', 'tpid', 0, '', '', 1);

	my(%template) = ( 
		name => 'sectionindex_display',
		tpid => $tpid, 
		template => $new_template,
	);
	if ($tpid) {
		$slashdb->setTemplate($tpid, \%template);
	} else {
		$slashdb->createTemplate(\%template);
	}

	slashdLog(sprintf "$me: %d sections refreshed", scalar @{$sections});
};

1;

