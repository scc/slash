#!/usr/bin/perl -w
# This code is a part of Slash, and is released under the GPL.
# Copyright 1997-2001 by Open Source Development Network. See README
# and COPYING for more information, or see http://slashcode.com/.
# $Id$

use strict;
use Slash 2.001;	# require Slash 2.1
use Slash::Display;
use Slash::Utility;
use Slash::XML;
use vars qw($VERSION);

($VERSION) = ' $Revision$ ' =~ /\$Revision:\s+([^\s]+)/;

use constant ALLOWED	=> 0;
use constant FUNCTION	=> 1;
use constant MSG_CODE_JOURNAL_FRIEND => 5;

sub main {
	my $journal   = getObject('Slash::Journal');
	my $constants = getCurrentStatic();
	my $slashdb   = getCurrentDB();
	my $user      = getCurrentUser();
	my $form      = getCurrentForm();

	my $top_ok    = $constants->{journal_top} && (
		$constants->{journal_top_posters} ||
		$constants->{journal_top_friend}  ||
		$constants->{journal_top_recent}
	);

	# possible value of "op" parameter in form
	my %ops = (
		list		=> [ 1,			\&listArticle		],
		display		=> [ 1,			\&displayArticle	],
		preview		=> [ !$user->{is_anon},	\&editArticle		],
		setprefs	=> [ !$user->{is_anon},	\&setPrefs		],		
		edit		=> [ !$user->{is_anon},	\&editArticle		],
		save		=> [ !$user->{is_anon},	\&saveArticle		],
		remove		=> [ !$user->{is_anon},	\&removeArticle		],
		'delete'	=> [ !$user->{is_anon},	\&deleteFriend		],
		add		=> [ !$user->{is_anon},	\&addFriend		],
		top		=> [ $top_ok,		\&displayTop		],
		searchusers	=> [ 1,			\&searchUsers		],
		friends		=> [ 1,			\&displayFriends	],
		default		=> [ 1,			\&displayFriends	],
	);

	my $op = $form->{'op'};
	if (!$op || !exists $ops{$op} || !$ops{$op}[ALLOWED]) {
		$op = 'default';
	}

	# hijack RSS feeds
	if ($form->{content_type} eq 'rss') {
		if ($op eq 'top' && $top_ok) {
			displayTopRSS($journal, $constants, $user, $form, $slashdb);
		} else {
			displayRSS($journal, $constants, $user, $form, $slashdb);
		}
	} else {
		# rethink all this ... give more control
		# by allowing menu to not display there, and by
		# putting text in templates
		if ($op eq 'display') {
			my $nickname = $form->{uid}
				? $slashdb->getUser($form->{uid}, 'nickname')
				: $user->{'nickname'};
			header("${nickname}'s Journal");
			titlebar("100%", "${nickname}'s Journal");
		} else {
			header("$constants->{sitename} Journal System");
			titlebar("100%", "Journal System");
		}

		print createMenu('journal');

		$ops{$op}[FUNCTION]->($journal, $constants, $user, $form, $slashdb);

		footer();
	}
}

sub displayTop {
	my($journal, $constants, $user, $form) = @_;
	my $journals;

	if ($constants->{journal_top_posters}) {
		$journals = $journal->top();
		slashDisplay('journaltop', { journals => $journals, type => 'top' });
	}

	if ($constants->{journal_top_friend}) {
		$journals = $journal->topFriends();
		slashDisplay('journaltop', { journals => $journals, type => 'friend' });
	}

	if ($constants->{journal_top_recent}) {
		$journals = $journal->topRecent();
		slashDisplay('journaltop', { journals => $journals, type => 'recent' });
	}
}

sub displayFriends {
	my($journal, $constants, $user, $form, $slashdb) = @_;
	my $friends = $journal->friends();
	if (@$friends) {
		slashDisplay('journalfriends', { friends => $friends });
	} else {
		print getData('nofriends');
		slashDisplay('searchusers');
	}

}

sub searchUsers {
	my($journal, $constants, $user, $form, $slashdb) = @_;

	if (!$form->{nickname}) {
		slashDisplay('searchusers');
		return;
	}

	my $results = $journal->searchUsers($form->{nickname});

	if (!$results || @$results < 1) {
		print getData('nousers'); # not
		slashDisplay('searchusers');
	} elsif (@$results == 1) {
		# clean up a bit, just in case
		for (keys %$form) {
			delete $form->{$_} unless $_ eq 'op';
		}
		$form->{uid} = $results->[0][1];
		displayArticle(@_);
	} else {
		slashDisplay('journalfriends', {
			friends => $results,
			search	=> 1,
		});
	}
}

sub displayRSS {
	my($journal, $constants, $user, $form, $slashdb) = @_;

	$user		= $slashdb->getUser($form->{uid}, ['nickname', 'fakeemail']) if $form->{uid};
	my $uid		= $form->{uid} || $user->{uid};
	my $nickname	= $user->{nickname};

	my $articles = $journal->getsByUid($uid, 0, 15);
	my @items;
	for my $article (@$articles) {
		push @items, {
			title		=> $article->[2],
# needs a var controlling this ... what to use as desc?
#			description	=> timeCalc($article->[0]),
#			description	=> "$nickname wrote: " . strip_mode($article->[1], $article->[4]),
			'link'		=> "$constants->{absolutedir}/journal.pl?op=display&uid=$uid&id=$article->[3]"
		};
	}

	my $usertext = $nickname;
	$usertext .= " <$user->{fakeemail}>" if $user->{fakeemail};
	xmlDisplay(rss => {
		channel => {
			title		=> "$constants->{sitename} Journals",
			description	=> "${nickname}'s Journal",
			'link'		=> "$constants->{absolutedir}/journal.pl?op=display&uid=$uid",
			creator		=> $usertext,
		},
		image	=> 1,
		items	=> \@items
	});
}

sub displayTopRSS {
	my($journal, $constants, $user, $form) = @_;

	my $journals;
	if ($form->{type} eq 'count' && $constants->{journal_top_posters}) {
		$journals = $journal->top();
	} elsif ($form->{type} eq 'friends' && $constants->{journal_top_friend}) {
		$journals = $journal->topFriends();
	} elsif ($constants->{journal_top_recent}) {
		$journals = $journal->topRecent();
	}

	my @items;
	for my $entry (@$journals) {
		my $time = timeCalc($entry->[3]);
		push @items, {
			title	=> "$entry->[1] ($time)",
			'link'	=> "$constants->{absolutedir}/journal.pl?op=display&uid=$entry->[2]"
		};
	}

	xmlDisplay(rss => {
		channel => {
			title		=> "$constants->{sitename} Journals",
			description	=> "Top $constants->{journal_top} Journals",
			'link'		=> "$constants->{absolutedir}/journal.pl?op=top",
		},
		image	=> 1,
		items	=> \@items
	});
}

sub displayArticle {
	my($journal, $constants, $user, $form, $slashdb) = @_;
	my($date, $forward, $back, @sorted_articles);
	my $collection = {};

	$user		= $slashdb->getUser($form->{uid}, ['nickname']) if $form->{uid};
	my $uid		= $form->{uid} || $user->{uid};
	my $nickname	= $user->{nickname};

	# clean it up
	my $start = fixint($form->{start}) || 0;
	my $articles = $journal->getsByUid($uid, $start,
		$constants->{journal_default_display} + 1, $form->{id}
	);

	unless ($articles && @$articles) {
		print getData('noentries_found');
		return;
	}

	# check for extra articles ... we request one more than we need
	# and if we get the extra one, we know we have extra ones, and
	# we pop it off
	if (@$articles == $constants->{journal_default_display} + 1) {
		pop @$articles;
		$forward = $start + $constants->{journal_default_display};
	} else {
		$forward = 0;
	}

	# if there are less than journal_default_display remaning,
	# just set it to 0
	if ($start > 0) {
		$back = $start - $constants->{journal_default_display};
		$back = $back > 0 ? $back : 0;
	} else {
		$back = -1;
	}

	my $topics = $slashdb->getTopics();
	for my $article (@$articles) {
		my($date_current) = timeCalc($article->[0], "%A %B %d, %Y");
		if ($date ne $date_current) {
			push @sorted_articles, $collection if ($date and (keys %$collection));
			$collection = {};
			$date = $date_current;
			$collection->{day} = $article->[0];
		}

		# should get comment count, too -- pudge
		push @{$collection->{article}}, {
			article		=> strip_mode($article->[1], $article->[4]),
			date		=> $article->[0],
			description	=> $article->[2],
			topic		=> $topics->{$article->[5]},
			discussion	=> $article->[6],
			id		=> $article->[3],
		};
	}

	push @sorted_articles, $collection;
	my $theme = $slashdb->getUser($uid, 'journal_theme');
	$theme ||= $constants->{journal_default_theme};

	slashDisplay($theme, {
		articles	=> \@sorted_articles,
		uid		=> $uid,
		back		=> $back,
		forward		=> $forward,
	});
}

sub setPrefs {
	my($journal, $constants, $user, $form, $slashdb) = @_;

	my %prefs;
	for my $name (qw(journal_discuss journal_theme)) {
		$prefs{$name} = $user->{$name} = $form->{$name}
			if defined $form->{$_};
	}

	$slashdb->setUser($user->{uid}, \%prefs);
	
	listArticle(@_);
}

sub listArticle {
	my($journal, $constants, $user, $form, $slashdb) = @_;

	my $list 	= $journal->list($form->{uid} || $ENV{SLASH_USER});
	my $themes	= $journal->themes;
	my $theme	= $user->{'journal_theme'} || $constants->{journal_default_theme};
	my $nickname	= $form->{uid}
		? $slashdb->getUser($form->{uid}, 'nickname')
		: $user->{nickname};

	if (@$list) {
		slashDisplay('journallist', {
			default		=> $theme,
			themes		=> $themes,
			articles	=> $list,
			uid		=> $form->{uid},
			nickname	=> $nickname,
		});
	} else {
		print getData('noentries');
	}
}

sub saveArticle {
	my($journal, $constants, $user, $form, $slashdb) = @_;
	my $description = strip_nohtml($form->{description});

	if ($form->{id}) {
		my %update;
		my $article = $journal->get($form->{id});

		# note: comments_on is a special case where we are
		# only turning on comments, not saving anything else
		if ($constants->{journal_comments} && $form->{journal_discuss} && !$article->{discussion}) {
			my $rootdir = $constants->{'rootdir'};
			if ($form->{comments_on}) {
				$description = $article->{description};
				$form->{tid} = $article->{tid};
			}
			my $did = $slashdb->createDiscussion('', $description, $slashdb->getTime(), 
				"$rootdir/journal.pl?op=display&id=$form->{id}", $form->{tid}
			);
			$update{discussion}  = $did;

		# update description if changed
		} elsif (!$form->{comments_on} && $article->{discussion} && $article->{description} ne $description) {
			$slashdb->setDiscussion($article->{discussion}, { description => $description });
		}

		unless ($form->{comments_on}) {
			for (qw(description article tid posttype)) {
				$update{$_} = $form->{$_} if $form->{$_};
			}
		}

		$journal->set($form->{id}, \%update);

	} else {
		my $id = $journal->create($description,
			$form->{article}, $form->{posttype}, $form->{tid});

		unless ($id) {
			print getData('create_failed');
			listArticle(@_);
		}

		if ($constants->{journal_comments} && $form->{journal_discuss}) {
			my $rootdir = $constants->{'rootdir'};
			my $did = $slashdb->createDiscussion('', $description, $slashdb->getTime(), 
				"$rootdir/journal.pl?op=display&id=$id", $form->{tid}
			);
			$journal->set($id, { discussion => $did });
		}

		# create messages
		my $messages = getObject('Slash::Messages');
		if ($messages) {
			my $friends   = $journal->message_friends;
			my $data = {
				template_name	=> 'messagenew',
				subject		=> { template_name => 'messagenew_subj' },
				journal		=> {
					description	=> $description,
					article		=> $form->{article},
					posttype	=> $form->{posttype},
					id		=> $id,
					uid		=> $user->{uid},
					nickname	=> $user->{nickname},
				}
			};

			for (@$friends) {
				$messages->create($_, MSG_CODE_JOURNAL_FRIEND, $data);
			}
		}
	}
	listArticle(@_);
}

sub removeArticle {
	my($journal, $constants, $user, $form) = @_;
	$journal->remove($form->{id}) if $form->{id};
	listArticle(@_);
}

sub addFriend {
	my($journal, $constants, $user, $form) = @_;

	$journal->add($form->{uid}) if $form->{uid};
	displayFriends(@_);
}

sub deleteFriend {
	my($journal, $constants, $user, $form) = @_;

	$journal->delete($form->{uid}) if $form->{uid} ;
	displayFriends(@_);
}

sub editArticle {
	my($journal, $constants, $user, $form, $slashdb) = @_;
	# This is where we figure out what is happening
	my $article = {};
	my $posttype;

	if ($form->{state}) {
		$article->{date}	= scalar(localtime(time()));
		$article->{article}	= $form->{article};
		$article->{description}	= $form->{description};
		$article->{id}		= $form->{id};
		$article->{tid}		= $form->{tid};
		$posttype		= $form->{posttype};
	} else {
		$article  = $journal->get($form->{id}) if $form->{id};
		$posttype = $article->{posttype};
	}

	$posttype ||= $user->{'posttype'};

	if ($article->{article}) {
		my $strip_art = strip_mode($article->{article}, $posttype);
		my $strip_desc = strip_nohtml($article->{description});
		my $disp_article = {
			date		=> $article->{date},
			article		=> $strip_art,
			description	=> $strip_desc,
			id		=> $article->{id},
			topic		=> $slashdb->getTopic($article->{tid})
		};

		my $theme = $user->{'journal_theme'};
		$theme ||= $constants->{journal_default_theme};
		slashDisplay($theme, {
			articles	=> [{ day => $article->{date}, article => [ $disp_article ] }],
			uid		=> $article->{uid},
			back		=> -1,
			forward		=> 0,
		});
	}

	my $formats = $slashdb->getDescriptions('postmodes');
	my $format_select = createSelect('posttype', $formats, $posttype, 1);

	slashDisplay('journaledit', {
		article		=> $article,
		format_select	=> $format_select,
	});
}

createEnvironment();
main();
1;
