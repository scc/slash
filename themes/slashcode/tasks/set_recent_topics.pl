#!/usr/bin/perl -w

use strict;
my $me = 'set_recent_topics.pl';

use vars qw( %task );

$task{$me}{timespec} = '1-59/15 * * * *';
$task{$me}{code} = sub {

	my($virtual_user, $constants, $slashdb, $user) = @_;

	my $sth = $slashdb->getNewStoryTopic();
	my($cur_tid, $last_tid) = ('', '_not_a_topic_');
	my $num_stories = 0;
	my $html = '';

	while (my $cur_story = $sth->fetchrow_hashref) {
		my $cur_tid = $cur_story->{tid};
		next if $cur_tid eq $last_tid; # don't show two in a row

# This really should be in a template.
		$html .= <<EOT;
	<TD><A HREF="$constants->{rootdir}/search.pl?topic=$cur_tid"><IMG
		SRC="$constants->{imagedir}/topics/$cur_story->{image}"
		WIDTH="$cur_story->{width}" HEIGHT="$cur_story->{height}"
		BORDER="0" ALT="$cur_story->{alttext}"></A>
	</TD>
EOT
		last if ++$num_stories >= 5;
		$last_tid = $cur_tid;
	}
	$sth->finish();
	my($tpid) = $slashdb->getTemplateByName('recentTopics', 'tpid');
	$slashdb->setTemplate($tpid, { template => $html });

};

1;

