#!/usr/bin/perl -w
use strict;
use Slash;
use Slash::DB;
use Slash::Utility;
use Slash::Journal;
use Slash::Display;


sub main {
	my %ops = (
		list => \&listArticle,
		preview => \&editArticle,
		edit => \&editArticle,
		get => \&getArticle,
		display => \&displayArticle,
		save => \&saveArticle,
		delete => \&deleteFriend,
		add => \&addFriend,
		top => \&displayTop,
		friends => \&displayFriends,
		default => \&displayDefault,
		);

	my $journal = Slash::Journal->new(getCurrentSlashUser());
	my $form = getCurrentForm();
	my $op = $form->{'op'};
	$op = 'default' unless $ops{$op};
	my $uid = $form->{'uid'};
	header();
	if($op eq 'display') {
		my $slashdb = getCurrentDB();
		my $nickname = $slashdb->getUser($form->{uid}, 'nickname');
		titlebar("100%","${nickname}'s Journal");
	} else {
		titlebar("100%","Journal System");
	}

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
	my $nickname = $slashdb->getUser($form->{uid}, 'nickname');
	my $articles = $journal->gets($form->{uid},[qw|date article  description|]);
	for my $article (@$articles) {
		slashDisplay('journalentry', {
			article => $article,
			author => $nickname,
		});
	}
	slashDisplay('journaladdfriend', {
		uid => $form->{uid},
		url => '/journal.pl',
	});
}

sub listArticle {
	my ($form, $journal) = @_;
	my $list = $journal->gets(getCurrentUser('uid'),[qw| id date description |]);
	slashDisplay('journallist', {
		articles => $list,
		url => '/journal.pl',
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
