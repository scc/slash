#!/usr/bin/perl -w

###############################################################################
# submit.pl - this code inputs user submission into the system to be 
# approved by authors 
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
use CGI ();

#################################################################
sub main {
	my $dbslash = getCurrentDB();
	my $constants = getCurrentStatic();
	my $user = getCurrentUser();
	my $form = getCurrentForm();

	my $id = getFormkeyId($user->{uid});
	my($section, $op, $aid) = (
		$form->{section}, $form->{op}, $user->{aid}
	);
	$user->{submit_admin} = 1 if $user->{aseclev} >= 100;

	$form->{del}	||= 0;
	$form->{op}	||= '';
	$form->{from}	= stripByMode($form->{from})  if $form->{from}; 
	$form->{subj}	= stripByMode($form->{subj})  if $form->{subj}; 
	$form->{email}	= stripByMode($form->{email}) if $form->{email}; 

	# Show submission title on browser's titlebar.
	my($tbtitle) = $form->{title};
	if ($tbtitle) {
		$tbtitle =~ s/^"?(.+?)"?$/"$1"/;
		$tbtitle = "- $tbtitle";
	}

	$section = 'admin' if $user->{submit_admin};
	header(getData('header', { tbtitle => $tbtitle } ), $section);

	if ($op eq 'list' && ($user->{submit_admin} || $constants->{submiss_view})) {
		submissionEd();

	} elsif ($op eq 'Update' && $user->{submit_admin}) {
		my @subids = $dbslash->deleteSubmission();
		submissionEd(getData('updatehead', { subids => \@subids }));

	} elsif ($op eq 'GenQuickies' && $user->{submit_admin}) {
		genQuickies();
		submissionEd(getData('quickieshead'));

	} elsif ($op eq 'PreviewStory') {
		$dbslash->insertFormkey('submissions', $id, 'submission');
		displayForm($form->{from}, $form->{email}, $form->{section},
			$id, getData('previewhead'));

	} elsif ($op eq 'viewsub' && ($user->{submit_admin} || $constants->{submiss_view})) {
		previewForm($aid, $form->{subid});

	} elsif ($op eq 'SubmitStory') {
		saveSub($id);
		yourPendingSubmissions();

	} else {
		yourPendingSubmissions();
		displayForm($user->{nickname}, $user->{fakeemail}, $form->{section},
			$id, getData('defaulthead'));
	}

	footer();
}

#################################################################
sub yourPendingSubmissions {
	my $dbslash = getCurrentDB();
	my $user = getCurrentUser();

	return if $user->{is_anon};

	if (my $submissions = $dbslash->getSubmissionsPending()) {
		my $count = $dbslash->getSubmissionCount();
		slashDisplay('submit-yourPendingSubmissions', {
			submissions	=> $submissions,
			title		=> "Your Recent Submissions (total:$count)",
			width		=> '100%',
			totalcount	=> $count,
		});
	}
}

#################################################################
sub previewForm {
	my($aid, $subid) = @_;
	my $dbslash = getCurrentDB();
	my $constants = getCurrentStatic();
	my $user = getCurrentUser();
	my $form = getCurrentForm();

	my $sub = $dbslash->getSubmission($subid,
		[qw(email name subj tid story time comment)]);
	$sub->{story} =~ s/\n\n/\n<P>/gi;
	$sub->{story} .= ' ';
	$sub->{story} =~  s{(?<!"|=|>)(http|ftp|gopher|telnet)://(.*?)(\W\s)?[\s]}
			{<A HREF="$1://$2">$1://$2</A> }gi;
	$sub->{story} =~ s/\s+$//;

	if ($sub->{email} =~ /@/) {
		$sub->{email} = "mailto:$sub->{email}"; 
	} elsif ($sub->{email} !~ /http/) {
		$sub->{email} = "http://$sub->{email}";
	}

	$dbslash->setSessionByAid($user->{aid}, { lasttitle => $sub->{subj} });

	slashDisplay('submit-previewForm', {
		submission	=> $sub,
		subid		=> $subid,
		lockTest	=> lockTest($sub->{subj}),
		section		=> $form->{section} || $constants->{defaultsection},
	});
}

#################################################################
sub genQuickies {
	my $dbslash = getCurrentDB();
	my $submissions = $dbslash->getQuickies();
	my $stuff = slashDisplay('submit-genQuickies', { submissions => $submissions }, 1, 1);
	$dbslash->setQuickies($stuff);
}

#################################################################
sub submissionEd {
	my($title) = @_;
	my $dbslash = getCurrentDB();
	my $constants = getCurrentStatic();
	my $user = getCurrentUser();
	my $form = getCurrentForm();
	my($def_section, $cur_section, $def_note, $cur_note,
		$sections, @sections, @notes,
		%all_sections, %all_notes, %sn);

	$form->{del} = 0 if $user->{submit_admin};

	$def_section	= getData('defaultsection');
	$def_note	= getData('defaultnote');
	$cur_section	= $form->{section} || $def_section;
	$cur_note	= $form->{note} || $def_note;
	$sections = $dbslash->getSubmissionsSections();

	for (@$sections) {
		my($section, $note, $cnt) = @$_;
		$all_sections{$section} = 1;
		$note ||= $def_note;
		$all_notes{$note} = 1;
		$sn{$section}{$note} = $cnt;
	}

	for my $note_str (keys %all_notes) {
		$sn{$def_section}{$note_str} = 0;
		for (grep { $_ ne $def_section } keys %sn) {
			$sn{$def_section}{$note_str} += $sn{$_}{$note_str};
		}
	}

	$all_sections{$def_section} = 1;

	@sections =	map  { [$_->[0], ($_->[0] eq $def_section ? '' : $_->[0])] }
			sort { $a->[1] cmp $b->[1] }
			map  { [$_, ($_ eq $def_section ? '' : $_)] }
			keys %all_sections;

	@notes =	map  { [$_->[0], ($_->[0] eq $def_note ? '' : $_->[0])] }
			sort { $a->[1] cmp $b->[1] }
			map  { [$_, ($_ eq $def_note ? '' : $_)] }
			keys %all_notes;

	slashDisplay('submit-submissionEdTable', {
		cur_section	=> $cur_section,
		cur_note	=> $cur_note,
		def_section	=> $def_section,
		def_note	=> $def_note,
		sections	=> \@sections,
		notes		=> \@notes,
		sn		=> \%sn,
		title		=> $title || ('Submissions ' . ($user->{submit_admin} ? 'Admin' : 'List')),
		width		=> '100%',
	});

	my(@submissions, $submissions, @selection);
	$submissions = $dbslash->getSubmissionForUser(getDateOffset('time'));
	
	for (@$submissions) {
		my $sub = $submissions[@submissions] = {};
		@{$sub}{qw(
			subid subj time tid note email
			name section comment uid karma
		)} = @$_;
		$sub->{name}  =~ s/<(.*)>//g;
		$sub->{email} =~ s/<(.*)>//g;
		$sub->{is_anon} = isAnon($sub->{uid});

		my @strs = (
			substr($sub->{subj}, 0, 35),
			substr($sub->{name}, 0, 20),
			substr($sub->{email}, 0, 20)
		);
		$strs[0] .= '...' if length($sub->{subj}) > 35;
		$sub->{strs} = \@strs;

		$sub->{ssection} = $sub->{section} ne $constants->{defaultsection}
			? "&section=$sub->{section}" : '';
		$sub->{stitle}   = '&title=' . fixparam($sub->{subj});
		$sub->{section} = ucfirst($sub->{section}) unless $user->{submit_admin};
	}

	@selection = (qw(DEFAULT Hold Quik),
		(ref $constants->{submit_categories}
			? @{$constants->{submit_categories}} : ())
	);

	my $template = $user->{submit_admin} ? 'Admin' : 'User';
	slashDisplay('submit-submissionEd' . $template, {
		submissions	=> \@submissions,
		selection	=> \@selection,
	});
}	


#################################################################
sub displayForm {
	my($username, $fakeemail, $section, $id, $title) = @_;
	my $dbslash = getCurrentDB();
	my $constants = getCurrentStatic();
	my $form = getCurrentForm();
	my $formkey_earliest = time() - $constants->{formkey_timeframe};

	if (!$dbslash->checkTimesPosted('submissions',
		$constants->{max_submissions_allowed}, $id, $formkey_earliest)
	) {
		errorMessage(getData('maxallowed'));
	}

	slashDisplay('submit-displayForm', {
		savestory	=> $form->{story} && $form->{subj},
		username	=> $form->{from} || $username,
		fakeemail	=> $form->{email} || $fakeemail,
		section		=> $form->{section} || $section || $constants->{defaultsection},
		topic		=> $dbslash->getTopic($form->{tid}),
		literalstory	=> stripByMode($form->{story}, 'literal', 1),
		width		=> '100%',
		title		=> $title,
	});
}

#################################################################
sub saveSub {
	my($id) = @_;
	my $dbslash = getCurrentDB();
	my $constants = getCurrentStatic();
	my $form = getCurrentForm();

	if (checkSubmission('submissions', $constants->{submission_speed_limit},
		$constants->{max_submissions_allowed}, $id)
	) {
		if (length($form->{subj}) < 2) {
			titlebar('100%', getData('error'));
			print getData('badsubject');
			displayForm($form->{from}, $form->{email}, $form->{section});
			return;
		}

		$dbslash->createSubmission();

		slashDisplay('submit-saveSub', {
			title		=> 'Saving',
			width		=> '100%',
			missingemail	=> length($form->{email}) < 3,
			anonsubmit	=> length($form->{from}) < 3,
			submissioncount	=> $dbslash->getSubmissionCount(),
		});
	}
}

#################################################################
# this gets little snippets of data all in grouped together in
# one template, called "submit-data"
sub getData {
	my($value, $hashref) = @_;
	$hashref ||= {};
	$hashref->{value} = $value;
	return slashDisplay('submit-data', $hashref, 1, 1);
}

main();

1;
