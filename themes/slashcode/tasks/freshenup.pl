#!/usr/bin/perl -w

use File::Path;

use strict;
my $me = 'freshenup.pl';

use vars qw( %task );

my $total_freshens = 0;

$task{$me}{timespec} = '4-59/5 * * * *';
$task{$me}{code} = sub {

	my($virtual_user, $constants, $slashdb, $user) = @_;

	my $bd = $constants->{basedir}; # convenience
	my %updates;
	my $stories = $slashdb->getStoriesForSlashdb(1);
	my @updatedsids;

	for (@$stories){
		my($sid, $title, $section) = @$_;
		slashdLog("Updating $title $sid");
		$updates{$section} = 1;
		makeDir($bd, $section, $sid);
		++$total_freshens;
		push @updatedsids, $sid;
	}

#	$slashdb->setStoryIndex(@updatedsids); # no longer needed with story_heap

	my $x = 0;
	# this deletes stories that have a writestatus of 5,
	# which is the delete writestatus
	$stories = $slashdb->getStoriesForSlashdb(5);
	for my $aryref (@$stories) {
		my($sid, $title, $section) = @$aryref;
		$x++;
		$updates{$section} = 1;
		$slashdb->deleteStoryAll($sid);
		slashdLog("$me Deleting $sid");
	}

# Are we still using this var? I see it in datadump.sql but it doesn't
# seem to get set anywhere except here.  (The writestatus field in the
# 'stories' table gets read and written all the time, but that's not
# really related.) - JRM 2001/05/04
	my $w = $slashdb->getVar('writestatus', 'value');
#       if ($updates{articles} ne "" || $w ne "0") {
		$slashdb->setVar("writestatus", "0");
		prog2file("$bd/index.pl", "ssi=yes", "$bd/index.shtml");
#       }

	foreach my $key (keys %updates) {
		next unless $key;
		prog2file("$bd/index.pl", "ssi=yes section=$key", "$bd/$key/index.shtml");
	}

	slashdLog("$me total_freshens $total_freshens");

};

sub makeDir {
	my($bd, $section, $sid) = @_;

	my $monthid = substr($sid, 3, 2);
	my $yearid = substr($sid, 0, 2);
	my $dayid = substr($sid, 6, 2);

	mkpath "$bd/$section/$yearid/$monthid/$dayid", 0, 0755;
}

1;

