package Slash::Utility;

use strict;
use Apache;
require Exporter;

@Slash::Utility::ISA = qw(Exporter);
@Slash::Utility::EXPORT = qw(
	apacheLog	
	stackTrace
	changePassword
	getDateFormat
	getDateOffset
	getCurrentUser
	getCurrentForm
);
$Slash::Utility::VERSION = '0.01';


########################################################
# writes error message to apache's error_log if we're running under mod_perl
# Called wherever we have errors.
sub apacheLog {
	# ummm ... won't this fail if called while not running under
	# Apache?
	my $r = Apache->request;
	if ($ENV{SCRIPT_NAME}) {
		$r->log_error("$ENV{SCRIPT_NAME}:@_");
	} else {
		$r->log_error("Error in library:@_");
	}
	return 0;
}

sub stackTrace {
	my ($number) = @_;
	$number |= 1;
	if ($ENV{SCRIPT_NAME}) {
		my $r = Apache->request;
		print STDERR "\n";
		for(1..$number) {
			my @caller_values = caller($_);
#			$r->log_error("$ENV{SCRIPT_NAME}:$package:$filename:$line:$subname:");
			my $error_string = join ':', @caller_values;
			print STDERR ("$error_string\n");
		print STDERR "\n";
		}
	} else {
		for(1..$number) {
			my ($package, $filename, $line, $subname) = caller($_);
			print("$package:$filename:$line:$subname:\n");
		}
	}
	return 0;
}

################################################################################
# SQL Timezone things
sub getDateOffset {
	my $col = shift || return;
	my ($user) = @_;

	return $col unless $user->{offset};
	return " DATE_ADD($col, INTERVAL $user->{offset} SECOND) ";
}

sub getDateFormat {
	my $col = shift || return;
	my $as = shift || 'time';
	my ($user) = @_;


	$user->{'format'} ||= '%W %M %d, @%h:%i%p ';
	unless ($user->{tzcode}) {
		$user->{tzcode} = 'EDT';
		$user->{offset} = '-14400';
	}

	$user->{offset} ||= '0';
	return ' CONCAT(DATE_FORMAT(' . getDateOffset($col) .
		qq!,"$user->{'format'}")," $user->{tzcode}") as $as !;
}
#################################################################
# This may get moved
sub changePassword {
	my @chars = grep !/[0O1Iil]/, 0..9, 'A'..'Z', 'a'..'z';
	return join '', map { $chars[rand @chars] } 0 .. 7;
}

#################################################################
sub getCurrentUser {
	my $r = Apache->request;
	my $user_cfg = Apache::ModuleConfig->get($r, 'Slash::Apache::User');
	my $user = $user_cfg->{'user'};

	return $user;
}
#################################################################
sub getCurrentForm {
	my $r = Apache->request;
	my $user_cfg = Apache::ModuleConfig->get($r, 'Slash::Apache::User');
	my $form = $user_cfg->{'form'};

	return $form;
}

#################################################################
sub getCurrentStatic{
	my ($value) = @_;
	my $r = Apache->request;
	my $constants = Apache::ModuleConfig->get($r, 'Slash::Apache');

	return $constants? ($value == undef) : $constants->{$value};
}

1;

=head1 NAME

Slash::Utility - Generic Perl routines for SlashCode

=head1 SYNOPSIS

  use Slash::Utility;

=head1 DESCRIPTION

Generic routines that are used throughout Slashcode.

=head1 AUTHOR

Brian Aker, brian@tangent.org

=head1 SEE ALSO

Slash(3).

=cut
