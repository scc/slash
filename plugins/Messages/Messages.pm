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

	(my($code), $type) = $self->getDescription('messagecodes', $type);
	unless (defined $code) {
		messagedLog("message type $type not found");
		return;
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

		my $user = getCurrentUser();
		$data->{_NAME}    = delete($data->{template_name});
		$data->{_PAGE}    = $user->{currentPage};
		$data->{_SECTION} = $user->{currentSection};
		$message = $data;

	} else {
		messagedLog("Cannot accept data of type " . ref($data));
		return;
	}

	my($msg_id) = $self->_create($uid, $code, $message, $fid, $altto);
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
				if $self->delete($msg->{id});
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
		$content = slashDisplay('msg_email', { msg => $msg }, $opt);
		if (exists $msg->{subj}) {
			$msg->{subj} = $self->callTemplate($msg->{subj}, $msg);
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

sub quicksend {
	my($self, $uid, $subj, $message, $code) = @_;

	($code, my($type)) = $self->getDescription('messagecodes', $code);
	return unless defined $code;

	my $slashdb = getCurrentDB();

	$self->send({
		id		=> 0,
		fuser	=> 0,
		altto	=> '',
		user	=> $slashdb->getUser($uid),
		subj	=> $subj,
		message	=> $message,
		code	=> $code,
		type	=> $type,
		date	=> time(),
	});
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

	$msg->{user}  = $slashdb->getUser($msg->{user});
	$msg->{fuser} = $msg->{fuser} ? $slashdb->getUser($msg->{fuser}) : 0;
	$msg->{type}  = $self->getDescription('messagecodes', $msg->{code});

	# optimize these calls for getDescriptions ... ?
	# they are cached already, but ...
	my $timezones   = $slashdb->getDescriptions('tzcodes');
	my $dateformats = $slashdb->getDescriptions('datecodes');
	$msg->{user}{off_set}  = $timezones -> { $msg->{user}{tzcode} };
	$msg->{user}{'format'} = $dateformats->{ $msg->{user}{dfid}   };

	$msg->{message} = $self->callTemplate($msg->{message}, $msg);
	return;
}

sub callTemplate {
	my($self, $data, $msg) = @_;
	return $data unless ref($data) eq 'HASH' && exists $data->{_NAME};

	my $name = delete($data->{_NAME});
	my $opt  = { 
		Return	=> 1,
		Nocomm	=> 1,
		Page	=> 'messages',
		Section => 'NONE',
	};

	# set Page and Section as from the caller
	$opt->{Page}    = delete($data->{_PAGE})    if exists $data->{_PAGE};
	$opt->{Section} = delete($data->{_SECTION}) if exists $data->{_SECTION};

	my $new = slashDisplay($name, { %$data, %$msg }, $opt);
	return $new;
}

sub getDescription {
	my($self, $codetype, $key) = @_;

	my $codes = $self->getDescriptions($codetype);

	if ($key =~ /^\d+$/) {
		unless (exists $codes->{$key}) {
			return;
		}
		return wantarray ? ($key, $codes->{$key}) : $key;
	} else {
		my $rcodes = { map { ($codes->{$_}, $_) } %$codes };
		unless (exists $rcodes->{$key}) {
			return;
		}
		return wantarray ? ($rcodes->{$key}, $key) : $rcodes->{key};
	}
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
