#!/usr/bin/perl -w
# This code is a part of Slash, and is released under the GPL.
# Copyright 1997-2001 by Open Source Development Network. See README
# and COPYING for more information, or see http://slashcode.com/.
# $Id$

use strict;
use File::Spec::Functions;
use Slash 2.001;	# require Slash 2.1
use Slash::Messages;
use Slash::Utility;

my $me = 'message_delivery.pl';

use vars qw( %task );

$task{$me}{timespec} = '5-59/5 * * * *';
$task{$me}{code} = sub {
	my($virtual_user, $constants, $slashdb, $user) = @_;

	slashdLog("$me begin");
	messagedLog("$me begin");

	my $messages = getObject('Slash::Messages');

	my $count = $constants->{message_process_count} || 10;
	my $msgs  = $messages->gets($count);
	my @good  = $messages->process(@$msgs);

	my %msgs  = map { ($_->{id}, $_) } @$msgs;

	for (@good) {
		messagedLog("msg \#$_ sent successfully.");
		delete $msgs{$_};
	}

	for (sort { $a <=> $b } keys %msgs) {
		messagedLog("Error: msg \#$_ not sent successfully.");
	}

	messagedLog("$me end");
	slashdLog("$me end");
};

sub messagedLog {
	local *LOG;
	my $dir = getCurrentStatic('logdir');
	my $log = catfile($dir, "messaged.log");
	open LOG, ">> $log\0" or die "Can't append to $log: $!";
	print LOG localtime() . "\t", join("\t", @_), "\n";
	close LOG;
}

1;
