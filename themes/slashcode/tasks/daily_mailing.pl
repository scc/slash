#!/usr/bin/perl -w

use strict;

use vars qw( %task $me );

# Remember that timespec goes by the database's time, which should be
# GMT if you installed everything correctly.  So 6:07 AM GMT is a good
# sort of midnightish time for the Western Hemisphere.  Adjust for
# your audience and admins.
$task{$me}{timespec} = '7 6 * * *';
$task{$me}{timespec_panic_2} = ''; # if major panic, dailyStuff can wait
$task{$me}{code} = sub {
	my($virtual_user, $constants, $slashdb, $user) = @_;
	my $messages  = getObject('Slash::Messages');

	return unless $messages;
	my($newsletter, $headlines) = generateDailyMail(@_);
	return unless $headlines;

	# need to change for specific prefs, later
	my $h_users = $messages->getHeadlineUsers();
	my $n_users = $messages->getNewsletterUsers();

	# check for well-formed addresses
	my @h_email = map { $_->[2] } @$h_users;
	my @n_email = map { $_->[2] } @$n_users;

	slashdLog("Daily Headlines begin");
	$messages->bulksend(\@h_email, "Daily Headlines", $headlines,  1);
	slashdLog("Daily Headlines end");
	slashdLog("Daily Newsletter begin");
	$messages->bulksend(\@n_email, "Daily Stories",   $newsletter, 0);
	slashdLog("Daily Newsletter end");

	return ;
};

sub generateDailyMail {
	my($virtual_user, $constants, $slashdb, $user) = @_;
	my $data = $slashdb->getDailyMail();

	return unless @$data;

	my @stories;
	for (@$data) {
		my(%story, @ref);
		@story{qw(sid title section author tid time dept
			introtext bodytext)} = @$_;

		1 while chomp($story{introtext});
		1 while chomp($story{bodytext});

		my $asciitext = $story{introtext};
		$asciitext .= "\n\n" . $story{bodytext} if $constants->{newsletter_body};
		($story{asciitext}, @ref) = html2text($asciitext, 74);

		$story{refs} = \@ref;
		push @stories, \%story;
	}

	my $newsletter = slashDisplay("dailynews",
		{ stories => \@stories, urlize => \&urlize },
		{ Return => 1, Nocomm => 1, Page => 'messages', Section => 'NONE' }
	);

	my $headlines  = slashDisplay("dailyheadlines",
		{ stories => \@stories },
		{ Return => 1, Nocomm => 1, Page => 'messages', Section => 'NONE' }
	);

	return($newsletter, $headlines);
}

sub urlize {
	local($_) = @_;
	s/^(.{62})/$1\n/g;
	s/(\S{74})/$1\n/g;
	$_ = "<URL:" . $_ . ">";
	return $_;
}

1;

