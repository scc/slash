#!/usr/bin/perl -w

use strict;
my $me = 'run_moderatord.pl';

use vars qw( %task );

$task{$me}{timespec} = '15 0-23/2 * * *';
$task{$me}{code} = sub {

	my($virtual_user, $constants, $slashdb, $user) = @_;

	slashdLog("$me begin");
	my $moderatord = "$constants->{sbindir}/moderatord";
        if (-e $moderatord and -x _) {
		system("$moderatord $virtual_user");
	} else {
		slashdLog("$me cannot find $moderatord or not executable");
	}
	slashdLog("$me end");

};

1;

