#!/usr/bin/perl -w

use strict;
my $me = 'p2f_cheesy.pl';

use vars qw( %cron );

$cron{$me}{timespec} = '51 */2 * * *';
$cron{$me}{code} = sub {

	my($virtual_user, $constants, $slashdb, $user) = @_;

	my $bd = $constants->{basedir}; # convenience
	for my $name (qw( cheesyportal )) {
		prog2file("$bd/$name.pl", "ssi=yes", "$bd/$name.shtml");
	}

};

