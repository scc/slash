#!/usr/bin/perl -w

use strict;
my $me = 'run_messaged.pl';

use vars qw( %task );

$task{$me}{timespec} = '5-59/10 * * * *';
$task{$me}{code} = sub {

	my($virtual_user, $constants, $slashdb, $user) = @_;

	slashdLog("$me begin");
	my $messaged = "$constants->{sbindir}/messaged";
	if (-e $messaged and -x _) {
		system("$messaged -u $virtual_user &");
	} else {
		slashdLog("$me cannot find $messaged or not executable");
	}
	slashdLog("$me end");

};

1;

