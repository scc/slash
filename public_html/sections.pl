#!/usr/bin/perl -w

###############################################################################
# sections.pl - this page displays the sections of the site for the admin 
# user, allows editing of the sections 
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
use Slash::Utility;

#################################################################
sub main {
	my $user = getCurrentUser();
	my $form = getCurrentForm();

	my $op = $form->{op};
	my $seclev = $user->{aseclev};

	header(getData('head'), 'admin');

	if ($seclev < 100) {
		print getData('notadmin');
		footer();
		return;
	}

	if ($op eq 'rmsub' && $seclev > 99) {  # huh?

	} elsif ($form->{addsection}) {
		titlebar("100%", "Add Section");
		editSection();

	} elsif ($form->{deletesection} || $form->{deletesection_cancel} || $form->{deletesection_confirm}) {
		delSection($form->{section});
		listSections($user);

	} elsif ($op eq "editsection" || $form->{editsection}) {
		titlebar("100%", "Editing $form->{section} Section");
		editSection($form->{section});

	} elsif ($form->{savesection}) {
		titlebar("100%", "Saving $form->{section}");
		saveSection($form->{section});
		listSections($user);

	} elsif ((! defined $op || $op eq 'list') && $seclev > 499) {
		titlebar("100%", "Sections");
		listSections($user);
	}

	footer();
}

#################################################################
sub listSections {
	my($user) = @_;
	my $dbslash = getCurrentDB();

	if ($user->{asection}) {
		editSection($user->{asection});
		return;
	}

	slashDisplay('sections-listSections', {
		sections => $dbslash->getSectionTitle()
	});
}

#################################################################
sub delSection {
	my($section) = @_;
	my $dbslash = getCurrentDB();
	my $form = getCurrentForm();

	if ($form->{deletesection}) {
		slashDisplay('sections-delSection', {
			section	=> $section
		});
	} elsif ($form->{deletesection_cancel}) {
		slashDisplay('sections-delSectionCancel', {
			section	=> $section
		});
	} elsif ($form->{deletesection_confirm}) {
		slashDisplay('sections-delSectionConfirm', {
			section	=> $section,
			title	=> "Deleted $section Section",
			width	=> '100%'
		});
		$dbslash->deleteSection($section);
	}
}

#################################################################
sub editSection {
	my($section) = @_;
	my $dbslash = getCurrentDB();
	my $user = getCurrentUser();
	my $form = getCurrentForm();

	my(@blocks, $this_section);
	if ($form->{addsection}) {
		$this_section = {};
	} else {
		$this_section = $dbslash->getSection($section);
		my $blocks = $dbslash->getSectionBlock($section);

		for (@$blocks) {
			my $block = $blocks[@blocks] = {};
			@{$block}{qw(section bid ordernum title portal url)} = @$_;
			$block->{title} =~ s/<(.*?)>//g;

		}
	}

	my $qid = createSelect('qid', $dbslash->getPollQuestions(),
		$this_section->{qid}, 1);
	my $isolate = createSelect('isolate', $dbslash->getDescriptions('isolatemodes'),
		$this_section->{isolate}, 1);
	my $issue = createSelect('issue', $dbslash->getDescriptions('issuemodes'),
		$this_section->{issue}, 1);

	slashDisplay('sections-editSection', {
		section		=> $section,
		seclev		=> $user->{aseclev},
		this_section	=> $this_section,
		qid		=> $qid,
		isolate		=> $isolate,
		issue		=> $issue,
		blocks		=> \@blocks,
	});
}

#################################################################
sub saveSection {
	my($section) = @_;
	my $dbslash = getCurrentDB();
	my $form = getCurrentForm();

	# Non alphanumerics are not allowed in the section key.
	# And I don't see a reason for underscores either, but 
	# dashes should be allowed.
	$section =~ s/[^A-Za-z0-9\-]//g;

	my $status = $dbslash->setSection(
		@{$form}{qw(section qid title issue isolate artcount)}
	);

	unless ($status) {
		print getData('insert', { section => $section });
	}

	print getData('update', { section => $section })
		unless $dbslash->{dbh}->errstr;  # ack!  no can do this! -- pudge
}

#################################################################
# this gets little snippets of data all in grouped together in
# one template, called "sections-data"
sub getData {
	my($value, $hashref) = @_;
	$hashref ||= {};
	$hashref->{value} = $value;
	return slashDisplay('sections-data', $hashref, 1, 1);
}

#################################################################
main();

1;
