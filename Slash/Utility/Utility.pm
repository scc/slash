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
	getCurrentStatic
	getCurrentDB
	getCurrentAnonymousCoward
);
$Slash::Utility::VERSION = '0.01';


########################################################
# writes error message to apache's error_log if we're running under mod_perl
# Called wherever we have errors.
sub apacheLog {
	# ummm ... won't this fail if called while not running under
	# Apache?
	my($package, $filename, $line) = caller(1);
	if ($ENV{SCRIPT_NAME}) {
		my $r = Apache->request;
		$r->log_error("$ENV{SCRIPT_NAME}:$package:$filename:$line:@_");
	} else {
		print STDERR ("Error in library:$package:$filename:$line:@_");
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
	my($value) = @_;
	my $r = Apache->request;
	my $user_cfg = Apache::ModuleConfig->get($r, 'Slash::Apache::User');
	my $user = $user_cfg->{'user'};

	# i think we want to test defined($foo), not just $foo, right?
	if ($value) {
		return defined($user->{$value})
			? $user->{$value}
			: undef;
	} else {
		return $user;
	}
}
#################################################################
sub getCurrentForm {
	my($value) = @_;
	my $r = Apache->request;
	my $user_cfg = Apache::ModuleConfig->get($r, 'Slash::Apache::User');
	my $form = $user_cfg->{'form'};

	if ($value) {
		return defined($form->{$value})
			? $form->{$value}
			: undef;
	} else {
		return $form;
	}
}

#################################################################
sub getCurrentStatic {
	my($value) = @_;
	my $r = Apache->request;
	my $const_cfg = Apache::ModuleConfig->get($r, 'Slash::Apache');
	my $constants = $const_cfg->{'constants'};

	if ($value) {
		return defined($constants->{$value})
			? $constants->{$value}
			: undef;
	} else {
		return $constants;
	}
}

#################################################################
sub getCurrentAnonymousCoward{
	my $r = Apache->request;
	my $const_cfg = Apache::ModuleConfig->get($r, 'Slash::Apache');
	my $slashdb = $const_cfg->{'anonymous_coward'};

	return $slashdb;
}

#################################################################
sub getCurrentDB{
	my $r = Apache->request;
	my $const_cfg = Apache::ModuleConfig->get($r, 'Slash::Apache');
	my $slashdb = $const_cfg->{'dbslash'};

	return $slashdb;
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
