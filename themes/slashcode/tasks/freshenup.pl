#!/usr/bin/perl -w

use File::Path;

use strict;
my $me = 'freshenup.pl';

use vars qw( %task );

my $total_freshens = 0;

$task{$me}{timespec} = '1-59/3 * * * *';
$task{$me}{code} = sub {
	my($virtual_user, $constants, $slashdb, $user) = @_;
	my %updates;

	my $x = 0;
	# this deletes stories that have a writestatus of 5 (now delete), 
	# which is the delete writestatus
	my $deletable = $slashdb->getStoriesWithFlag('delete');
	for (@$deletable) {
		my($sid, $title, $section) = @$_;
		$x++;
		$updates{$section} = 1;
		$slashdb->deleteStoryAll($sid);
		slashdLog("Deleting $sid ($title)");
	}
	my $stories = $slashdb->getStoriesWithFlag('dirty');
	my @updatedsids;
	my $totalChangedStories = 0;

	for (@$stories){
		my($sid, $title, $section) = @$_;
		slashdLog("Updating $sid");
		$updates{$section} = 1;
		$totalChangedStories++;
		push @updatedsids, $sid;
		if ($section) {
			makeDir($constants->{basedir}, $section, $sid);
			prog2file("$constants->{basedir}/article.pl",
			"ssi=yes sid='$sid' section='$section'",
			"$constants->{basedir}/$section/$sid.shtml");
			slashdLog("$me updated $section:$sid ($title)");
		} else {
			prog2file("$constants->{basedir}/article.pl",
			"ssi=yes sid='$sid'",
			"$constants->{basedir}/$sid.shtml");
			slashdLog("$me updated $sid ($title)");
		}
		$slashdb->setStory($sid, { writestatus => 'ok'});
	}

	my $w  = $slashdb->getVar('writestatus', 'value');

	if ($updates{$constants->{defaultsection}} ne "" || $w ne "ok") {
		$slashdb->setVar("writestatus", "ok");
		prog2file("$constants->{basedir}/index.pl", "ssi=yes", "$constants->{basedir}/index.shtml");
	}

	foreach my $key (keys %updates) {
		next unless $key;
		prog2file("$constants->{basedir}/index.pl", "ssi=yes section=$key",
			"$constants->{basedir}/$key/index.shtml");
	}
};

sub makeDir {
	my($bd, $section, $sid) = @_;

	my $monthid = substr($sid, 3, 2);
	my $yearid = substr($sid, 0, 2);
	my $dayid = substr($sid, 6, 2);

	mkpath "$bd/$section/$yearid/$monthid/$dayid", 0, 0775;
}

1;
