#!/usr/bin/perl -w

use strict;
my $me = 'p2f_hof_topics.pl';

use vars qw( %task );

$task{$me}{timespec} = '51 0-23/2 * * *';
$task{$me}{code} = sub {

	my($virtual_user, $constants, $slashdb, $user) = @_;

	my $bd = $constants->{basedir}; # convenience
	for my $name (qw( hof topics )) {
		prog2file("$bd/$name.pl", "ssi=yes", "$bd/$name.shtml");
	}

};

1;

