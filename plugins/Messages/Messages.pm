# This code is a part of Slash, and is released under the GPL.
# Copyright 1997-2001 by Open Source Development Network. See README
# and COPYING for more information, or see http://slashcode.com/.
# $Id$

package Slash::Messages;

=head1 NAME

Slash::Messages - Send messages for Slash


=head1 SYNOPSIS

	use Slash::Utility;
	my $messages = getObject('Slash::Messages');
	my $msg_id = $messages->create($uid, $message_type, $message);

	# ...
	my $msg = $messages->get($msg_id);
	$messages->send($msg);
	$messages->delete($msg_id);

	# ...
	$messages->process($msg_id);


=head1 DESCRIPTION

LONG DESCRIPTION.


=head1 OBJECT METHODS

=cut

use strict;
use base qw(Slash::Messages::DB::MySQL);
use vars qw($VERSION);
use Slash::Display;
use Slash::Utility;

($VERSION) = ' $Revision$ ' =~ /\$Revision:\s+([^\s]+)/;

use constant MSG_MODE_EMAIL => 0;
use constant MSG_MODE_WEB   => 1;


#========================================================================

=head2 create(TO_ID, TYPE, MESSAGE [, FROM_ID, ALTTO])

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

=item ALTTO

This is an alternate "TO" address (e.g., to send a message from
a user of the system to a user outside the system).

=back

=item Return value

The created message's "id" in the message_drop table.

=item Dependencies

Whatever templates are passed in.

=back

=cut

sub create {
	my($self, $uid, $type, $data, $fid, $altto) = @_;
	my $message;

	# check well-formedness of $altto!

	# must not contain non-numeric
	if (!defined($fid) || $fid =~ /\D/) {
		$fid = 0;	# default
	}

	my $codes = $self->getDescriptions('messagecodes');
	if ($type =~ /^\d+$/) {
		unless (exists $codes->{$type}) {
			messagedLog("message type $type not found");
			return;
		}
	} else {
		my $rcodes = { map { ($codes->{$_}, $_) } %$codes };
		unless (exists $rcodes->{$type}) {
			messagedLog("message type $type not found");
			return;
		}
		$type = $rcodes->{$type};
	}

	# check for $uid existence
	my $slashdb = getCurrentDB();
	unless ($slashdb->getUser($uid)) {
		messagedLog("User $uid not found");
		return;
	}

	if (!ref $data) {
		$message = $data;
	} elsif (ref $data eq 'HASH') {
		unless ($data->{template_name}) {
			messagedLog("No template name"), return;
		}
		$message = $data;
	} else {
		messagedLog("Cannot accept data of type " . ref($data));
		return;
	}

	my($msg_id) = $self->_create($uid, $type, $message, $fid, $altto);
	return $msg_id;
}

# takes message refs or message IDs or a combination of both
sub process {
	my($self, @msgs) = @_;

	my(@success);
	for my $msg (@msgs) {
		# if $msg is ref, assume we have the message already
		$msg = $self->get($msg) unless ref($msg);
		if ($self->send($msg)) {
			push @success, $msg->{id}
				; #if $self->delete($msg->{id});
		}
	}
	return @success;
}

# takes message ref or message ID
sub send {
	my($self, $msg) = @_;

	my $constants = getCurrentStatic();

	# if $msg is ref, assume we have the message already
	$msg = $self->get($msg) unless ref($msg);

	my $mode = $msg->{user}{deliverymodes};

	# Can only get mail sent if Real Email set
# 	if ($mode == MSG_MODE_EMAIL && !$msg->{user}{realemail_valid}) {
# 		$mode = MSG_MODE_WEB;
# 	}

	# if sending to someone outside the system, must be email
	$mode = MSG_MODE_EMAIL if $msg->{altto};
	# if newsletter or headline mailer, must be email
	$mode = MSG_MODE_EMAIL if $msg->{code} =~ /^(?:0|1)$/;

	if (!defined($mode) || $mode eq '' || $mode =~ /\D/) {
		messagedLog("No delivery mode for user $msg->{user}{uid}");
		return 0;

	} elsif ($mode == MSG_MODE_EMAIL) {
		my($addr, $subject, $content, $opt);
		$opt = { 
			Return	=> 1,
			Nocomm	=> 1,
			Page	=> 'messages',
			Section => 'NONE',
		};

		$addr    = $msg->{altto} || $msg->{user}{realemail};
		$content = slashDisplay('msg_email',      { msg => $msg }, $opt);
		if (exists $msg->{subj}) {
			if (ref($msg->{subj}) eq 'HASH' && exists($msg->{subj}{template_name})) {
				my $name = delete($msg->{subj}{template_name});
				$subject = slashDisplay($name, { msg => $msg }, $opt);
			} else {
				$subject = $msg->{subj};
			}
		} else {
			$subject = slashDisplay('msg_email_subj', { msg => $msg }, $opt);
		}

		if (sendEmail($addr, $subject, $content)) {
			return 1;
		} else {
			messagedLog("Error sending to '$addr' for user $msg->{user}{uid}: $Mail::Sendmail::error");
			return 0;
		}

	} elsif ($mode == MSG_MODE_WEB) {

	} else {
		messagedLog("Unknown delivery mode '$mode' for user $msg->{user}{uid}");
		return 0;
	}

}

sub get {
	my($self, $msg_id) = @_;

	my $msg = $self->_get($msg_id) or return;
	$self->render($msg);
	return $msg;
}

sub gets {
	my($self, $count) = @_;

	my $msgs = $self->_gets($count) or return;
	$self->render($_) for @$msgs;
	return $msgs;
}

sub delete {
	my($self, @ids) = @_;
	my $count;
	for (@ids) {
		$count += $self->_delete($_);
	}
	return $count;
}

sub render {
	my($self, $msg) = @_;
	my $slashdb = getCurrentDB();
	my $codes = $self->getDescriptions('messagecodes');

	$msg->{user}  = $slashdb->getUser($msg->{user});
	$msg->{fuser} = $msg->{fuser} ? $slashdb->getUser($msg->{fuser}) : 0;
	$msg->{type}  = $codes->{ $msg->{code} };

	# optimize these calls for getDescriptions ... ?
	# they are cached already, but ...
	my $timezones   = $slashdb->getDescriptions('tzcodes');
	my $dateformats = $slashdb->getDescriptions('datecodes');
	$msg->{user}{off_set}  = $timezones -> { $msg->{user}{tzcode} };
	$msg->{user}{'format'} = $dateformats->{ $msg->{user}{dfid}   };

	if (ref($msg->{message}) eq 'HASH') {
		my $name = delete($msg->{message}{template_name});
		my $data = { %{$msg->{message}}, %$msg };

		$msg->{message} = slashDisplay($name, $data, {
			Return	=> 1,
			Nocomm	=> 1,
			Page	=> 'messages',
			Section => 'NONE',
		});
	}

	return;
}

# dispatch to proper logging function
sub messagedLog {
	goto &main::messagedLog if defined &main::messagedLog;
	goto &errorLog;
}

1;

__END__


=head1 SEE ALSO

Slash(3).

=head1 VERSION

$Id$
