#!/usr/bin/perl -w

use File::Path;

use strict;

use vars qw( %task $me );

my $total_freshens = 0;

# Task options
# 	limit = max. number of archived stories to process
# 	dir   = direction of progression, one of: ASC, or DESC

$task{$me}{timespec} = '7 7 * * *';
$task{$me}{timespec_panic_2} = '';
$task{$me}{code} = sub {
	my($virtual_user, $constants, $slashdb, $user) = @_;

	my $limit = $constants->{task_options}{limit} || 10;
	my $dir = $constants->{task_options}{dir};
	$dir = 'ASC' if $dir !~ /^(ASC|DESC)$/i;

	my $stories = $slashdb->getStoriesWithFlag('archived', $dir, $limit);
	my $totalChangedStories = 0;

	for (@$stories) {
		my($sid, $title, $section) = @$_;
		slashdLog("Archiving $sid") if verbosity() >= 2;
		$totalChangedStories++;
		my $args = "ssi=yes sid='$sid' mode=archive"; 

		# Use backup database handle only if told to and if it is 
		# different than the current virtual user.
		my $vu;
		$vu .= "virtual_user=$constants->{backup_db_user}"
			if $constants->{backup_db_user} &&
			   ($virtual_user ne $constants->{backup_db_user}) &&
			   $constants->{archive_use_backup_db};
		$vu ||= "virtual_user=$virtual_user";
		$args .= " $vu"; 

		my @rc;
		if ($section) {
			$args .= " section=$section";
			makeDir($constants->{basedir}, $section, $sid);
			# Note the change in prog2file() invocation.
			@rc = prog2file(
				"$constants->{basedir}/article.pl",
				$args,
				"$constants->{basedir}/$section/$sid.shtml",
				verbosity(), 1
			);
			if (verbosity() >= 2) {
				my $log="$me archived $section:$sid ($title)";
				slashdLog($log);
				slashdLog("Error channel:\n$rc[1]")
					if verbosity() >= 3;
			}
		} else {
			# Note the change in prog2file() invocation.
			@rc = prog2file(
				"$constants->{basedir}/article.pl",
				$args,
				"$constants->{basedir}/$sid.shtml",
				verbosity(), 1
			);
			if (verbosity() >= 2) {
				slashdLog("$me archived $sid ($title)");
				slashdLog("Error channel:\n$rc[1]")
					if verbosity() >= 3;
			}
		}

		# Now we extract what we need from the error channel.
		slashdLog("$me *** Update data not in error channel!")
			unless $rc[1] =~ /count (\d+), hitparade (.+)$/;

		my $cc = $1 || 0;
		my $hp = $2 || 0;
		$slashdb->setStory($sid, { 
			writestatus  => 'ok',
			commentcount => $cc,
			hitparade    => $hp,
		});
	}

	return $totalChangedStories ?
	      	"totalArchivedStories $totalChangedStories" : '';
};

sub makeDir {
	my($bd, $section, $sid) = @_;

	my $monthid = substr($sid, 3, 2);
	my $yearid = substr($sid, 0, 2);
	my $dayid = substr($sid, 6, 2);

	mkpath "$bd/$section/$yearid/$monthid/$dayid", 0, 0775;
}

1;
