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

	# Mark discussions with new comment data as needing to be freshened.
	my $discussions = getDiscussionsWithFlag($slashdb, "hitparade_dirty");
	# Mark stories with new data as needing to be freshened.
	my $stories = getStoriesWithFlag($slashdb, "data_dirty");
	for my $info (@$discussions, @$stories){
		my($sid, $title, $section) = @$info;
		next unless $sid;	# XXX for now, skip poll/journal discussions since we don't know how to write their hitparades in yet
		$updates{section}{$section} = 1;	# need to update its section
		$updates{story}{$sid} = [@$info];	# need to update the story itself
	}

	# Delete stories marked as needing such
	$stories = getStoriesWithFlag($slashdb, "delete_me");
	for my $info (@$stories) {
		my($sid, $title, $section) = @$info;
		$slashdb->finalDeleteStory($sid);
		$updates{section}{$section} = 1;	# need to update its section
		delete $updates{story}{$sid};		# no need to update story anymore
		slashdLog("$me deleted $sid");
		++$total_freshens;
	}

	# Freshen changed stories (that haven't been deleted)
	for my $sid (sort keys %{$updates{story}}) {
slashdLog("sid '$sid'");
		my($sid, $title, $section) = @{$updates{story}{$sid}};
slashdLog("sid '$sid' title '$title' section '$section'");
		if ($section) {
			makeDir($bd, $section, $sid);
			prog2file("$bd/article.pl",
				"ssi=yes sid='$sid' section='$section'",
				"$bd/$section/$sid.shtml");
			slashdLog("$me updated $section:$sid $title");
		} else {
			prog2file("$bd/article.pl",
				"ssi=yes sid='$sid'",
				"$bd/$sid.shtml");
			slashdLog("$me updated $sid $title");
		}
	}

# Are we still using this var? I see it in datadump.sql but it doesn't
# seem to get set anywhere except here. - Jamie 2001/05/04
#	my $w = $slashdb->getVar('writestatus', 'value');
#       if ($updates{articles} ne "" || $w ne "0") {
#		$slashdb->setVar("writestatus", "0");
		prog2file("$bd/index.pl", "ssi=yes", "$bd/index.shtml");
#       }

	foreach my $key (keys %{$updates{section}}) {
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

sub getDiscussionsWithFlag {
	my($slashdb, $flag) = @_;
	my $flag_quoted = $slashdb->sqlQuote($flag);
	my $story_table = getCurrentStatic('mysql_heap_table') ? 'story_heap' : 'stories';
	return $slashdb->sqlSelectAll(
		"discussions.sid, discussions.title, $story_table.section",
		"discussions, $story_table",
		"FIND_IN_SET($flag_quoted, discussions.flags) AND discussions.id = $story_table.discussion",
	);
}

sub getStoriesWithFlag {
	my($slashdb, $flag) = @_;
	my $flag_quoted = $slashdb->sqlQuote($flag);
	my $story_table = getCurrentStatic('mysql_heap_table') ? 'story_heap' : 'stories';
	return $slashdb->sqlSelectAll(
		"sid, title, section",
		$story_table,
		"FIND_IN_SET($flag_quoted, flags)"
	);
}

1;

