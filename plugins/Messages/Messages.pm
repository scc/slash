# This code is a part of Slash, and is released under the GPL.
# Copyright 1997-2001 by Open Source Development Network. See README
# and COPYING for more information, or see http://slashcode.com/.
# $Id$

package Slash::Messages;

=head1 NAME

Slash::Messages - Send messages for Slash


=head1 SYNOPSIS

	# basic example of usage


=head1 DESCRIPTION

LONG DESCRIPTION.


=head1 OBJECT METHODS

=cut

use strict;
use base 'Exporter';
use vars qw($VERSION);
use Slash::Display;
use Slash::Utility;

($VERSION) = ' $Revision$ ' =~ /\$Revision:\s+([^\s]+)/;
use base qw(Slash::Messages::DB::MySQL Slash::DB::Utility);


#========================================================================

=head2 create(TO_ID, TYPE, MESSAGE [, FROM_ID])

Will drop a serialized message into message_drop.

=over 4

=item Parameters

=over 4

=item TO_ID

The UID of the user the message is sent to.  Must match a valid
uid in the users table.

=item TYPE

The message type.  Preferably a number, but will also handle strings.

=item MESSAGE

This is either the exact text to send, or it is a hashref
containing the data to send.  To override the default
"subject" of the message, pass it in as the "subject"
key.  Pass the name of the template in as the "template_name"
key.

=item FROM_ID

Either the UID of the user sending the message, or 0 to denote
a system message (0 is default).

=back

=item Return value

The created message's "id" in the message_drop table.

=item Dependencies

Whatever templates are passed in.

=back

=cut

sub create {
	my($self, $uid, $type, $data, $fid) = @_;
	my $message;

	# must not contain non-numeric
	if (!defined($fid) || $fid =~ /\D/) {
		$fid = 0;	# default
	}

	my $codes = $self->getDescriptions('messagecodes');
	if ($type =~ /^\d+$/) {
		unless (exists $codes->{$type}) {
			errorLog("message type $type not found");
			return;
		}
	} else {
		my $rcodes = { map { ($codes->{$_}, $_) } %$codes };
		unless (exists $rcodes->{$type}) {
			errorLog("message type $type not found");
			return;
		}
		$type = $rcodes->{$type};
	}

	# check for $uid existence
	my $slashdb = getCurrentDB();
	unless ($slashdb->getUser($uid)) {
		errorLog("User $uid not found");
		return;
	}

	if (!ref $data) {
		$message = $data;
	} elsif (ref $data eq 'HASH') {
		unless ($data->{template_name}) {
			errorLog("No template name"), return;
		}
		$message = $data;
	} else {
		errorLog("Cannot accept data of type " . ref($data));
		return;
	}

	my($msg_id) = $self->_create($uid, $type, $message, $fid);
	return $msg_id;
}


sub get {
	my($self, $msg_id) = @_;

	my $msg = $self->_get($msg_id) or return;
	$self->render($msg);
	return $msg;
}

sub gets {
	my($self, $count, $delete) = @_;

	my $msgs = $self->_gets($count) or return;
	$self->render($_) for @$msgs;
	return $msgs;
}

sub render {
	my($self, $msg) = @_;
	my $slashdb = getCurrentDB();
	my $codes = $self->getDescriptions('messagecodes');
	$msg->[1] = $slashdb->getUser($msg->[1]);
	$msg->[4] = $msg->[4] ? $slashdb->getUser($msg->[4]) : 0;
	$msg->[6] = $codes->{$msg->[2]};

	# optimize these calls for getDescriptions ... ?
	# they are cached already, but ...
	my $timezones   = $slashdb->getDescriptions('tzcodes');
	my $dateformats = $slashdb->getDescriptions('datecodes');
	$msg->[1]{off_set}  = $timezones->{ $msg->[1]{tzcode} };
	$msg->[1]{'format'} = $dateformats->{ $msg->[1]{dfid} };

	if (ref($msg->[3]) eq 'HASH') {
		my $name = delete($msg->[3]{template_name});
		my $data = {
			%{$msg->[3]},
			msg_id	=> $msg->[0],
			uid	=> $msg->[1],
			code	=> $msg->[2],
			fid	=> $msg->[4],
			date	=> $msg->[5],
			type	=> $msg->[6],
		};

		$msg->[3] = slashDisplay($name, $data, {
			Return	=> 1,
			Nocomm	=> 1,
			Page	=> 'messages',
			Section => 'NONE',
		});
	}
	return;
}

1;

__END__


=head1 SEE ALSO

Slash(3).

=head1 VERSION

$Id$
