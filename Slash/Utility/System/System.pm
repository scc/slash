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
	errorLog
	sendEmail
	writeLog
);
@EXPORT_OK = qw();

#========================================================================

=head2 errorLog()

Generates an error that either goes to Apache's error log
or to STDERR. The error consists of the package and
and filename the error was generated and the same information
on the previous caller.

=over 4

=item Return value

Returns 0;

=back

=cut

sub errorLog {
	my($package, $filename, $line) = caller(1);
	if ($ENV{GATEWAY_INTERFACE}) {
		my $r = Apache->request;
		if ($r) {
			$r->log_error("$ENV{SCRIPT_NAME}:$package:$filename:$line:@_");
			($package, $filename, $line) = caller(2);
			$r->log_error ("Which was called by:$package:$filename:$line:@_\n");

			return 0;
		}
	}
	print STDERR ("Error in library:$package:$filename:$line:@_\n");
	($package, $filename, $line) = caller(2);
	print STDERR ("Which was called by:$package:$filename:$line:@_\n") if $package;

	return 0;
}

#========================================================================

=head2 writeLog(DATA)

Places optional data in the accesslog.

=over 4

=item Parameters

=over 4

=item DATA

Strings that are concatenated together to be used in the SLASH_LOG_DATA field.

=back

=item Return value

No value is returned.

=back

=cut

sub writeLog {
	return unless $ENV{GATEWAY_INTERFACE};
	my $dat = join("\t", @_);

	my $r = Apache->request;

	# Notes has a bug (still in apache 1.3.17 at
	# last look). Apache's directory sub handler
	# is not copying notes. Bad Apache!
	# -Brian
	$r->err_header_out(SLASH_LOG_DATA => $dat);
}

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
	my($addr, $subject, $content, $from, $pr) = @_;
	my $constants = getCurrentStatic();

	my %data = (
		smtp	=> $constants->{smtp_server},
		subject	=> $subject,
		to	=> $addr,
		body	=> $content,
		from	=> $from || $constants->{mailfrom}
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

1;

__END__


=head1 SEE ALSO

Slash(3), Slash::Utility(3).

=head1 VERSION

$Id$
