#!/usr/bin/perl -w

use strict;
my $me = 'run_portald.pl';

use vars qw( %cron );

$cron{$me}{timespec} = '30 * * * *';
$cron{$me}{code} = sub {

	my($virtual_user, $constants, $slashdb, $user) = @_;

	slashdLog("$me begin");
	my $portald = "$constants->{sbindir}/portald";
        if (-e $portald and -x _) {
		system("$portald $virtual_user");
	} else {
		slashdLog("$me cannot find $portald or not executable");
	}
	slashdLog("$me end");

};

1;

