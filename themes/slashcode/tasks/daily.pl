#!/usr/bin/perl -w

use strict;
my $me = 'daily.pl';

use vars qw( %task );

# Remember that timespec goes by the database's time, which should be
# GMT if you installed everything correctly.  So 6 AM GMT is a good
# sort of midnightish time for the Western Hemisphere.  Adjust for
# your audience and admins.
$task{$me}{timespec} = '0 6 * * *';
$task{$me}{code} = sub {

	my($virtual_user, $constants, $slashdb, $user) = @_;

	system("$constants->{sbindir}/dailyStuff $virtual_user &");

};

1;

