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
use Email::Valid;
use File::Spec::Functions;
use Mail::Bulkmail;
use Mail::Sendmail;
use Slash::Utility::Environment;

use base 'Exporter';
use vars qw($VERSION @EXPORT @EXPORT_OK);

($VERSION) = ' $Revision$ ' =~ /\$Revision:\s+([^\s]+)/;
@EXPORT	   = qw(
	bulkEmail
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

	unless (Email::Valid->rfc822($addr)) {
		errorLog("Can't send mail '$subject' to $addr: Invalid address");
		return 0;
	}

	my %data = (
		from	=> $constants->{mailfrom},
		smtp	=> $constants->{smtp_server},
		subject	=> $subject,
		body	=> $content,
		to	=> $addr,
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

sub bulkEmail {
	my($addrs, $subject, $content) = @_;
	my $constants = getCurrentStatic();

	my $goodfile = catfile($constants->{logdir}, 'bulk-good.log');
	my $badfile  = catfile($constants->{logdir}, 'bulk-bad.log');
	my $errfile  = catfile($constants->{logdir}, 'bulk-error.log');

	# start logging
	for my $file ($goodfile, $badfile, $errfile) {
		my $fh = gensym();
		open $fh, ">> $file\0" or errorLog("Can't open $file: $!"), return;
		printf $fh "Starting bulkmail '%s': %s\n",
			$subject, scalar localtime;
		close $fh;
	}

	my $valid = Email::Valid->new();
	my @list = grep { $valid->rfc822($_) } @$addrs;

	my $bulk = Mail::Bulkmail->new(
		From    => $constants->{mailfrom},
		Smtp	=> $constants->{smtp_server},
		Subject => $subject,
		Message => $content,
		LIST	=> \@list,
		GOOD	=> $goodfile,
		BAD	=> $badfile,
		ERRFILE	=> $errfile,
	);
	my $return = $bulk->bulkmail;

	# end logging
	for my $file ($goodfile, $badfile, $errfile) {
		my $fh = gensym();
		open $fh, ">> $file\0" or errorLog("Can't open $file: $!"), return;
		printf $fh "Ending bulkmail '%s': %s\n\n",
			$subject, scalar localtime;
		close $fh;
	}

	return $return;
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
