#!/usr/bin/perl -w

use strict;
my $me = 'new_motd.pl';

use vars qw( %cron );

$cron{$me}{timespec} = '5 * * * *';
$cron{$me}{code} = sub {

	my($virtual_user, $constants, $slashdb, $user) = @_;

	return unless -x '/usr/games/fortune';
	chomp(my $t = `/usr/games/fortune -s`);
	$slashdb->setBlock('motd', {block => $t}) if $t;

};

1;

