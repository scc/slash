#!/usr/bin/perl -w
# This code is a part of Slash, and is released under the GPL.
# Copyright 1997-2001 by Open Source Development Network. See README
# and COPYING for more information, or see http://slashcode.com/.
# $Id$

# this program does some really cool stuff.
# so i document it here.  yay for me!

use strict;
use Slash;
use Slash::Display;
use Slash::Utility;
use vars qw($VERSION);

($VERSION) = ' $Revision$ ' =~ /\$Revision:\s+([^\s]+)/;


# this is an example main().  feel free to use what you think
# works best for your program, just make it readable and clean.

use constant ALLOWED	=> 0;
use constant FUNCTION	=> 1;

sub main {
	my $messages  = getObject('Slash::Messages');
	my $constants = getCurrentStatic();
	my $user      = getCurrentUser();
	my $form      = getCurrentForm();

	# possible value of "op" parameter in form
	my %ops = (
		display_prefs	=> [ !$user->{is_anon},	\&display_prefs		],
		saveprefs	=> [ !$user->{is_anon},	\&save_prefs		],
		save_prefs	=> [ !$user->{is_anon},	\&save_prefs		],
		list_messages	=> [ !$user->{is_anon},	\&list_messages		],
		list		=> [ !$user->{is_anon},	\&list_messages		],
		display_message	=> [ !$user->{is_anon},	\&display_message	],
		display		=> [ !$user->{is_anon},	\&display_message	],
		delete_message	=> [ !$user->{is_anon},	\&delete_message	],
		'delete'	=> [ !$user->{is_anon},	\&delete_message	],
		default		=> [ 1,			\&display_prefs		]
	);

	# prepare op to proper value if bad value given
	my $op = $form->{op};
	if (!$op || !exists $ops{$op} || !$ops{$op}[ALLOWED]) {
		$op = 'default';
	}

	# dispatch of op
	$ops{$op}[FUNCTION]->($messages, $constants, $user, $form);

	# writeLog('SOME DATA');	# if appropriate
}

sub display_prefs {
	my($messages, $constants, $user, $form, $note) = @_;

	my $deliverymodes = $messages->getDescriptions('deliverymodes');
	my $messagecodes  = $messages->getDescriptions('messagecodes');

	header(getData('header'));
	slashDisplay('display_prefs', {
		note		=> $note,
		messagecodes	=> $messagecodes,
		deliverymodes	=> $deliverymodes,
	});
	footer();
}

sub save_prefs {
	my($messages, $constants, $user, $form) = @_;

	my %params;
	$params{'deliverymodes'} = fixint($form->{'deliverymodes'});

	my $messagecodes = $messages->getDescriptions('messagecodes');
	for (keys %$messagecodes) {
		my $key = 'messagecodes_' . $_;
		$params{$key} = $form->{$key} ? 1 : 0;
	}

	$messages->setUser($user->{uid}, \%params);
	@{$user}{keys %params} = values %params;

	display_prefs(@_, getData('prefs saved'));
}

sub default {	# ???
	my($messages, $constants, $user, $form) = @_;
	# ...

	header(getData('header'));
	footer();
}

sub list_messages {
	my($messages, $constants, $user, $form, $note) = @_;

	my $messagecodes = $messages->getDescriptions('messagecodes');
	my $message_list = $messages->getWebByUID();

	header(getData('header'));
	slashDisplay('list_messages', {
		note		=> $note,
		messagecodes	=> $messagecodes,
		message_list	=> $message_list,
	});
	footer();
}

sub list_message_rss {
	my($messages, $constants, $user, $form) = @_;
	# ...
}

sub display_message {
	my($messages, $constants, $user, $form) = @_;

	my $message = $messages->getWeb($form->{id});

	header(getData('header'));
	slashDisplay('display', {
		message		=> $message,
	});
	footer();
}

sub delete_message {
	my($messages, $constants, $user, $form) = @_;
	my $note;

	if ($messages->_delete_web($form->{id})) {
		$note = getData('delete good', { id => $form->{id} });
	} else {
		$note = getData('delete bad',  { id => $form->{id} });
	}

	list_messages(@_, $note);
}


# etc.

createEnvironment();
main();

1;

#deliverymodes

