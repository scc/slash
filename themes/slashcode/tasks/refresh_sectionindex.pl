# refresh_sectionindex.pl
# SlashD Task (c) OSDN 2001
# $Id$
#!/usr/bin/perl -w

use strict;
my $me = 'refresh_sectionindex.pl';

use vars qw( %task );

$task{$me}{timespec} = '*/10 * * * *';
$task{$me}{code} = sub {
	my($virtual_user, $constants, $slashdb, $user) = @_;
	my $sections = getSectionInfo();

	my $new_template = slashDisplay('sectionindex', {
		sections => $sections,
	}, 1);

	my $tpid = $slashdb->getTemplateByName('sectionindex_display','tpid');
	my %template = ( tpid => $tpid, template => $new_template );
	# If it exists, we update it, if not, we create it.
	if ($tpid) {
		$slashdb->setTemplate($tpid, \%template);
	} else {
		$slashdb->createTemplate(\%template);
	}

	slashdLog("$me: %d sections refreshed");
}

1;

