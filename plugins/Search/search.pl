#!/usr/bin/perl -w

###############################################################################
# search.pl - this code is the search page 
#
# Copyright (C) 1997 Rob "CmdrTaco" Malda
# malda@slashdot.org
#
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License
# as published by the Free Software Foundation; either version 2
# of the License, or (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program; if not, write to the Free Software
# Foundation, Inc., 59 Temple Place - Suite 330, Boston, MA  02111-1307, USA.
#
#
#  $Id$
###############################################################################
use strict;
use Slash;
use Slash::Display;
use Slash::Search;
use Slash::Utility;

#################################################################
sub main {
	my %ops = (
		comments => \&commentSearch,
		users => \&userSearch,
		stories => \&storySearch
	);

	my $constants = getCurrentStatic();
	my $form = getCurrentForm();
	my $slashdb = getCurrentDB();

	# Set some defaults
	$form->{query}		||= '';
	$form->{section}	||= '';
	$form->{min}		||= 0;
	$form->{max}		||= 30;
	$form->{threshold}	||= getCurrentUser('threshold');
	$form->{'last'}		||= $form->{min} + $form->{max};

	# get rid of bad characters
	$form->{query} =~ s/[^A-Z0-9'. ]//gi;

	header("$constants->{sitename}: Search $form->{query}", $form->{section});
	titlebar("99%", "Searching $form->{query}");

	my $op = $form->{op} ? $form->{op} : 'stories';
	my $authors = _authors();
	slashDisplay('searchform', {
		section => getSection($form->{section}),
		tref =>$slashdb->getTopic($form->{topic}),
		op => $op,
		authors => $authors
	});

	#searchForm($form);

	if($ops{$form->{op}}) {
		$ops{$form->{op}}->($form);
	} 

	writeLog("search", $form->{query})
		if $form->{op} =~ /^(?:comments|stories|users)$/;
	footer();	
}


#################################################################
# Ugly isn't it?
sub _authors {
	my $slashdb = getCurrentDB();
	my $authors = $slashdb->getDescriptions('authors');
	$authors->{''} = 'All Authors';

	return $authors;
}

#################################################################
sub linkSearch {
	my ($count) = @_;
	my $form = getCurrentForm();
	my $r;

	foreach (qw[threshold query min author op sid topic section total hitcount]) {
		my $x = "";
		$x =  $count->{$_} if defined $count->{$_};
		$x =  $form->{$_} if defined $form->{$_} && $x eq "";
		$x =~ s/ /+/g;
		$r .= "$_=$x&" unless $x eq "";
	}
	$r =~ s/&$//;

	$r = qq!<A HREF="$ENV{SCRIPT_NAME}?$r">$count->{'link'}</A>!;
}


#################################################################
sub commentSearch {
	my ($form) = @_;
	my $slashdb = getCurrentDB();
	my $constants = getCurrentStatic();
	my $searchDB = Slash::Search->new(getCurrentSlashUser());

	my $comments = $searchDB->findComments($form);
	slashDisplay('commentsearch', {
		comments => $comments
	});

	my $prev = $form->{min} - $form->{max};
	slashDisplay('linksearch', {
		prev => $prev,
		linksearch => \&linksearch
	}) if $prev => 0;
}

#################################################################
sub userSearch {
	my ($form) = @_;
	my $constants = getCurrentStatic();
	my $searchDB = Slash::Search->new(getCurrentSlashUser());

	my $users = $searchDB->findUsers($form, [getCurrentAnonymousCoward('nickname')]);
	slashDisplay('usersearch', {
		users => $users
	});
	
	my $x = @$users;

	my $prev = $form->{min} - $form->{max};
	slashDisplay('linksearch', {
		prev => $prev,
		linksearch => \&linksearch
	}) if $prev => 0;
}

#################################################################
sub storySearch {
	my ($form) = @_;
	my $searchDB = Slash::Search->new(getCurrentSlashUser());


	my($x, $cnt) = 0;

	my $stories = $searchDB->findStory($form);
	slashDisplay('storysearch', {
		stories => $stories
	});

	my $prev = $form->{min} - $form->{max};
	slashDisplay('linksearch', {
		prev => $prev,
		linksearch => \&linksearch
	}) if $prev => 0;
}

#################################################################
createEnvironment();
main();

1;
