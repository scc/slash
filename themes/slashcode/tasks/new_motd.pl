#!/usr/bin/perl -w

use strict;
my $me = 'new_motd.pl';

use vars qw( %task );

$task{$me}{timespec} = '5 * * * *';
$task{$me}{code} = sub {

	my($virtual_user, $constants, $slashdb, $user) = @_;

	return unless -x '/usr/games/fortune';
	chomp(my $t = `/usr/games/fortune -s`);

	if ($t) {
		my $tpid = $slashdb->getTemplateByName("motd", "tpid");
		$slashdb->setTemplate($tpid, { template => $t });
	}
};

1;

