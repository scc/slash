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

More to come.

=head1 OBJECT METHODS

=cut

use strict;
use base qw(Slash::Messages::DB::MySQL);
use vars qw($VERSION);
use Slash::Display;
use Slash::Utility;

($VERSION) = ' $Revision$ ' =~ /\$Revision:\s+([^\s]+)/;

use constant MSG_MODE_NOCODE => -2;
use constant MSG_MODE_NONE   => -1;
use constant MSG_MODE_EMAIL  =>  0;
use constant MSG_MODE_WEB    =>  1;


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
key.  If "subject" is a template, then pass it as a hashref,
with "template_name" as one of the keys.

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
		messagedLog(getData("type not found", { type => $type }, "messages"));
		return 0;
	}

	# check for $uid existence
	my $slashdb = getCurrentDB();
	unless ($slashdb->getUser($uid)) {
		messagedLog(getData("user not found", { uid => $uid }, "messages"));
		return 0;
	}

	if (!ref $data) {
		$message = $data;
	} elsif (ref $data eq 'HASH') {
		unless ($data->{template_name}) {
			messagedLog(getData("no template", 0, "messages"));
			return 0;
		}

		my $user = getCurrentUser();
		$data->{_NAME}    = delete($data->{template_name});
		$data->{_PAGE}    = $user->{currentPage};
		$data->{_SECTION} = $user->{currentSection};

		# set subject
		if (exists $data->{subject} && ref($data->{subject}) eq 'HASH') {
			unless ($data->{subject}{template_name}) {
				messagedLog(getData("no template subject", 0, "messages"));
				return 0;
			}

			$data->{subject}{_NAME}    = delete($data->{subject}{template_name});
			$data->{subject}{_PAGE}    = $user->{currentPage};
			$data->{subject}{_SECTION} = $user->{currentSection};
		}

		$message = $data;

	} else {
		messagedLog(getData("wrong type", { type => ref($data) }, "messages"));
		return 0;
	}

	my($msg_id) = $self->_create($uid, $code, $message, $fid, $altto);
	return $msg_id;
}

sub create_web {
	my($self, $msg) = @_;

	my($msg_id) = $self->_create_web(
		$msg->{user}{uid},
		$msg->{code},
		$msg->{message},
		(ref($msg->{fuser}) ? $msg->{fuser}{uid} : $msg->{fuser}),
		$msg->{id},
		$msg->{subject},
		$msg->{date}
	);
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

sub checkMessageCodes {
	my($self, $code, $uids);
	my @newuids;
	$code = "messagecodes_$code";
	for (@$uids) {
		push @newuids, $_ if $self->getUser($_, $code);
	}
	return \@newuids;
}

sub getMode {
	my($self, $msg) = @_;
	my $mode = $msg->{user}{deliverymodes};

	# user not set to receive this message type
	return MSG_MODE_NOCODE if !$msg->{user}{"messagecodes_$msg->{code}"};

	# user has no delivery mode set
	return MSG_MODE_NONE if	$mode == MSG_MODE_NONE
		|| !defined($mode) || $mode eq '' || $mode =~ /\D/;

	# if sending to someone outside the system, must be email
	# delivery mode (for now)
	$mode = MSG_MODE_EMAIL if $msg->{altto};

	# Can only get mail sent if registered is set
# 	if ($mode == MSG_MODE_EMAIL && !$msg->{user}{registered}) {
# 		$mode = MSG_MODE_WEB;
# 	}

	# if newsletter or headline message, must be email (or none)
	if ($msg->{code} =~ /^(?:0|1)$/) {
# 		if (!$msg->{user}{registered}) {
# 			$mode == MSG_MODE_NONE;
# 		} else {
			$mode = MSG_MODE_EMAIL;
# 		}
	}

	return $msg->{mode} = $mode;
}

sub getNewsletterUsers {
	my($self) = @_;
	return $self->_getMailingUsers(0);
}

sub getHeadlineUsers {
	my($self) = @_;
	return $self->_getMailingUsers(1);
}

# takes message ref or message ID
sub send {
	my($self, $msg) = @_;

	my $constants = getCurrentStatic();

	# if $msg is ref, assume we have the message already
	$msg = $self->get($msg) unless ref($msg);

	my $mode = $self->getMode($msg);

	# should NONE, NOCODE, UNKNOWN delete msg? -- pudge
	if ($mode == MSG_MODE_NONE) {
		messagedLog(getData("no delivery mode", {
			uid	=> $msg->{user}{uid}
		}, "messages"));
		return 0;

	} elsif ($mode == MSG_MODE_NOCODE) {
		messagedLog(getData("no message code", {
			code	=> $msg->{code},
			uid	=> $msg->{user}{uid}
		}, "messages"));
		return 0;

	} elsif ($mode == MSG_MODE_EMAIL) {
		my($addr, $content, $subject);

		unless ($constants->{send_mail}) {
			messagedLog(getData("send_mail false", 0, "messages"));
			return 0;
		}

		$addr    = $msg->{altto} || $msg->{user}{realemail};
		$content = $self->callTemplate('msg_email', $msg);
		$subject = $self->callTemplate('msg_email_subj', $msg);

		if (sendEmail($addr, $subject, $content)) {
			return 1;
		} else {
			messagedLog(getData("send mail error", {
				addr	=> $addr,
				uid	=> $msg->{user}{uid},
				error	=> $Mail::Sendmail::error
			}, "messages"));
			return 0;
		}

	} elsif ($mode == MSG_MODE_WEB) {
		if ($self->create_web($msg)) {
			return 1;
		} else {
			return 0;
		}

	} else {
		messagedLog(getData("unknown mode", {
			mode	=> $mode,
			uid	=> $msg->{user}{uid},
		}, "messages"));
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
		fuser		=> 0,
		altto		=> '',
		user		=> $slashdb->getUser($uid),
		subj		=> $subj,
		message		=> $message,
		code		=> $code,
		type		=> $type,
		date		=> time(),
		mode		=> MSG_MODE_EMAIL,
	});
}

sub getWeb {
	my($self, $msg_id) = @_;

	my $msg = $self->_get_web($msg_id) or return 0;
	$self->render($msg, 1);
	return $msg;
}

sub getWebByUID {
	my($self, $uid) = @_;
	$uid ||= $ENV{SLASH_USER};

	my $msgs = $self->_get_web_by_uid($uid) or return 0;
	$self->render($_, 1) for @$msgs;
	return $msgs;
}

sub get {
	my($self, $msg_id) = @_;

	my $msg = $self->_get($msg_id) or return 0;
	$self->render($msg);
	return $msg;
}

sub gets {
	my($self, $count) = @_;

	my $msgs = $self->_gets($count) or return 0;
	$self->render($_) for @$msgs;
	return $msgs;
}

# should we delete msgs completely?  keep a record somewhere?
sub delete {
	my($self, @ids) = @_;

	my $count;
	for (@ids) {
		$count += $self->_delete($_);
	}
	return $count;
}

sub render {
	my($self, $msg, $notemplate) = @_;
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

	# sets $msg->{mode} too
	my $mode = $self->getMode($msg);

	unless ($notemplate) {
		# set subject
		if (ref($msg->{message}) ne 'HASH' || !exists $msg->{message}{subject}) {
			my $name = $mode == MSG_MODE_EMAIL ? 'msg_email_subj' :
				   $mode == MSG_MODE_WEB   ? 'msg_web_subj'   :
				   '';
			$msg->{subject} =  $self->callTemplate($name, $msg)
		} else {
			my $subject = $msg->{message}{subject};
			if (ref($msg->{message}{subject}) eq 'HASH') {
				$msg->{subject} = $self->callTemplate({ %{$msg->{message}}, %$subject }, $msg);
			} else {
				$msg->{subject} = $subject;
			}
		}

		$msg->{message} = $self->callTemplate($msg->{message}, $msg);
	}
	
	return $msg;
}

sub callTemplate {
	my($self, $data, $msg) = @_;
	my $name;

	if (ref($data) eq 'HASH' && exists $data->{_NAME}) {
		$name = delete($data->{_NAME});
	} elsif ($data && !ref($data)) {
		$name = $data;
		$data = {};
	} else {
		return 0;
	}

	my $opt  = { 
		Return	=> 1,
		Nocomm	=> 1,
		Page	=> 'messages',
		Section => 'NONE',
	};

	# set Page and Section as from the caller
	$opt->{Page}    = delete($data->{_PAGE})    if exists $data->{_PAGE};
	$opt->{Section} = delete($data->{_SECTION}) if exists $data->{_SECTION};

	my $new = slashDisplay($name, { %$data, msg => $msg }, $opt);
	return $new;
}

# in scalar context, if numeric key, return text; if text key, return numeric
# in list context, return (numeric, text)
sub getDescription {
	my($self, $codetype, $key) = @_;

	my $codes = $self->getDescriptions($codetype);

	if ($key =~ /^\d+$/) {
		unless (exists $codes->{$key}) {
			return;
		}
		return wantarray ? ($key, $codes->{$key}) : $codes->{$key};
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
