# This code is a part of Slash, and is released under the GPL.
# Copyright 1997-2001 by Open Source Development Network. See README
# and COPYING for more information, or see http://slashcode.com/.
# $Id$

package Slash::Utility::System;

=head1 NAME

Slash::Utility::System - SHORT DESCRIPTION for Slash


=head1 SYNOPSIS

	use Slash::Utility;
	# do not use this module directly

=head1 DESCRIPTION

LONG DESCRIPTION.


=head1 EXPORTED FUNCTIONS

=cut

use strict;
use Mail::Sendmail;
use Slash::Utility::Environment;

use base 'Exporter';
use vars qw($VERSION @EXPORT @EXPORT_OK);

($VERSION) = ' $Revision$ ' =~ /\$Revision:\s+([^\s]+)/;
@EXPORT	   = qw(
	doEmail
	sendEmail
);
@EXPORT_OK = qw();

#========================================================================

=head2 sendEmail(ADDR, SUBJECT, CONTENT [, FROM, PRECEDENCE])

Takes the address, subject and an email, and does what it says.

=over 4

=item Parameters

=over 4

=item ADDR

Mail address to send to.

=item SUBJECT

Subject of mail.

=item CONTENT

Content of mail.

=item FROM

Optional separate "From" address instead of "mailfrom" constant.

=item PRECEDENCE

Optional, set to "bulk" for "bulk" precedence.  Not standard,
but widely supported.

=back

=item Return value

True if successful, false if not.

=item Dependencies

Need From address and SMTP server from vars table,
'mailfrom' and 'smtp_server'.

=back

=cut

sub sendEmail {
	my($addr, $subject, $content, $pr) = @_;
	my $constants = getCurrentStatic();

	my %data = (
		smtp	=> $constants->{smtp_server},
		subject	=> $subject,
		to	=> $addr,
		body	=> $content,
		from	=> $constants->{mailfrom}
	);

	if ($pr && $pr eq 'bulk') {
		$data{precedence} = 'bulk';
	}

	if (sendmail(%data)) {
		return 1;
	} else {
		errorLog("Can't send mail '$subject' to $addr: $Mail::Sendmail::error");
		return 0;
	}
}


sub doEmail {
	my($uid, $subject, $content, $code, $pr) = @_;

	my $messages = getObject("Slash::Messages");
	if ($messages) {
		$messages->quicksend($uid, $subject, $content, $code, $pr);
	} else {
		my $slashdb = getCurrentDB();
		my $addr = $slashdb->getUser($uid, 'realemail');
		sendEmail($addr, $subject, $content, $pr);
	}
}

1;

__END__


=head1 SEE ALSO

Slash(3), Slash::Utility(3).

=head1 VERSION

$Id$
