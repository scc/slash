#!/usr/bin/perl -w
# This code is a part of Slash, which is Copyright 1997-2001 OSDN, and
# released under the GPL.  See README and COPYING for more information.
# $Id$

use strict;
use Slash;
use Slash::DB;
use Slash::Utility;
use Slash::Journal;
use Slash::Display;
use Date::Manip;


sub main {
	my %ops = (
		list => \&listArticle,
		preview => \&editArticle,
		edit => \&editArticle,
		get => \&getArticle,
		display => \&displayArticle,
		save => \&saveArticle,
		remove => \&removeArticle,
		delete => \&deleteFriend,
		add => \&addFriend,
		top => \&displayTop,
		friends => \&displayFriends,
		default => \&displayDefault,
		);
	my %safe = (
		list => 1,
		get => 1,
		display => 1,
		top => 1,
		friends => 1,
		default => 1,
		);

	my $journal = Slash::Journal->new(getCurrentSlashUser());
	my $form = getCurrentForm();
	my $op = $form->{'op'};
	$op = 'default' unless $ops{$op};
	if (getCurrentUser('is_anon')) {
		$op = 'default' unless $safe{$op};
	}
	my $uid = $form->{'uid'};
	header();
	if($op eq 'display') {
		my $slashdb = getCurrentDB();
		my $nickname = $slashdb->getUser($form->{uid}, 'nickname') if $form->{uid};
		$nickname ||= getCurrentUser('nickname');
		titlebar("100%","${nickname}'s Journal");
	} else {
		titlebar("100%","Journal System");
	}

	print createMenu('journal');

	$ops{$op}->($form, $journal);

	footer();
}

sub displayDefault {
	displayFriends(@_);
}

sub displayTop {
	my ($form, $journal) = @_;
	my $journals = $journal->top(30);
	slashDisplay('journaltop', {
		journals => $journals,
		url => '/journal.pl',
	});
}

sub displayFriends {
	my ($form, $journal) = @_;
	my $friends = $journal->friends();
	slashDisplay('journalfriends', {
		friends => $friends,
		url => '/journal.pl',
	});
}

sub displayArticle {
	my ($form, $journal) = @_;
	my $slashdb = getCurrentDB();
	my $uid;
	my $nickname;
	if($form->{uid}) {
		$nickname = $slashdb->getUser($form->{uid}, 'nickname');
		$uid = $form->{uid};
	} else {
		$nickname = getCurrentUser('nickname');
		$uid = getCurrentUser('uid');
	}
	my $articles = $journal->gets($uid,[qw|date article  description|]);
	my @sorted_articles;
	my $date;
	my $collection = {};
	for my $article (@$articles) {
		my ($date_current, $time) =  split / /, $article->[0], 2;	
		if($date eq $date_current) {
			push @{$collection->{article}} , { article =>  $article->[1], date =>  $article->[0], description => $article->[2]};
		}else {
			push @sorted_articles, $collection if $date;
			$collection = {};
			$date = $date_current;
			$collection->{day} = $date;
			push @{$collection->{article}} , { article =>  $article->[1], date =>  $article->[0], description => $article->[2]};
		}
	}
	for(@sorted_articles) {
		print STDERR "$_->{day}\n";
	}
	my $theme = $slashdb->getUser($uid, 'journal-theme');
	$theme ||= 'generic';
	slashDisplay($theme, {
		articles => \@sorted_articles,
		uid => $form->{uid},
		url => '/journal.pl',
	});
}

sub listArticle {
	my ($form, $journal) = @_;
	my $list = $journal->gets(getCurrentUser('uid'),[qw| id date description |]);
	my $themes = $journal->themes;
	if($form->{theme}) {
		my $db = getCurrentDB();
		$db->setUser(getCurrentUser('uid'), { 'journal-theme' => $form->{theme} }) 
			if (grep /$form->{theme}/, @$themes);
	}
	my $theme = getCurrentUser('journal-theme');
	$theme ||= 'journalpage-grey';
	slashDisplay('journallist', {
		articles => $list,
		url => '/journal.pl',
		default => $theme,
		themes => $themes,
	});
}

sub saveArticle {
	my ($form, $journal) = @_;
	if($form->{id}) {
		$journal->set($form->{id}, { 
			description => $form->{description},
			article => $form->{article},
		});
	} else {
		$journal->create($form->{description},$form->{article});
	}
	listArticle(@_);
}

sub removeArticle {
	my ($form, $journal) = @_;
	$journal->remove($form->{id}) if $form->{id};
	listArticle(@_);
}

sub addFriend {
	my ($form, $journal) = @_;

	$journal->add($form->{uid}) if $form->{uid};
	displayDefault(@_);
}

sub deleteFriend {
	my ($form, $journal) = @_;

	$journal->delete($form->{uid}) if $form->{uid} ;
	displayDefault(@_);
}

sub editArticle {
	my ($form, $journal) = @_;
	# This is where we figure out what is happening
	my $article = {};
	if($form->{state}){
		$article->{date} = scalar(localtime(time()));
		$article->{article} = $form->{article};
		$article->{description} = $form->{description};
		$article->{id} = $form->{id};
	}  else {
		$article = $journal->get($form->{id}) if $form->{id};
	}
	my $disp_article = [$article->{date}, $article->{article}, $article->{description}] if ($article->{article});
	slashDisplay('journalentry', {
		article => $disp_article,
		author => getCurrentUser('nickname'),
	}) if ($article->{article});
	slashDisplay('journaledit', {
		form => $article,
	});
}

sub getArticle {
	my ($form, $journal) = @_;
	# This is where we figure out what is happening
	my $article = $journal->get($form->{id}, [ qw( article date description uid) ]);
	my $slashdb = getCurrentDB();
	my $nickname = $slashdb->getUser($article->{uid}, 'nickname');
	my $disp_article = [$article->{date}, $article->{article}, $article->{description}] if ($article->{article});
	slashDisplay('journalentry', {
		article => $disp_article,
		author => $nickname,
	});
}

main();
