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
	setCurrentUser
	setCurrentForm
	setCurrentStatic
	setCurrentDB
	setCurrentAnonymousCoward
	isAnon
	getAnonId
	getFormkey
);
$Slash::Utility::VERSION = '0.01';

# These are package variables that are used when you need to use the
# set methods when not running under mod_perl
my $static_user;
my $static_form;
my $static_constants;
my $static_db;
my $static_anonymous_coward;

########################################################
sub getAnonId {
	return '-1-' . getFormkey();
}

########################################################
sub getFormkey {
	my @rand_array = ( 'a' .. 'z', 'A' .. 'Z', 0 .. 9 );
	return join("", map { $rand_array[rand @rand_array] }  0 .. 9);
}

########################################################
# writes error message to apache's error_log if we're running under mod_perl
# Called wherever we have errors.
# This needs to be renamed since it works both in and outside of Apache
sub apacheLog {
	# ummm ... won't this fail if called while not running under
	# Apache?
	# Nope.... 	-Brian
	my($package, $filename, $line) = caller(1);
	if ($ENV{GATEWAY_INTERFACE}) {
		my $r = Apache->request;
		$r->log_error("$ENV{SCRIPT_NAME}:$package:$filename:$line:@_");
		($package, $filename, $line) = caller(2);
		$r->log_error ("Which was called by:$package:$filename:$line:@_\n");
	} else {
		print STDERR ("Error in library:$package:$filename:$line:@_\n");
		($package, $filename, $line) = caller(2);
		print STDERR ("Which was called by:$package:$filename:$line:@_\n");
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
	my $user;

	if($ENV{GATEWAY_INTERFACE}) {
		my $r = Apache->request;
		my $user_cfg = Apache::ModuleConfig->get($r, 'Slash::Apache::User');
		$user = $user_cfg->{'user'};
	} else {
		$user = $static_user;
	}

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
sub setCurrentUser {
	($static_user) = @_;
}

#################################################################
sub getCurrentForm {
	my($value) = @_;
	my $form;

	if($ENV{GATEWAY_INTERFACE}) {
		my $r = Apache->request;
		my $user_cfg = Apache::ModuleConfig->get($r, 'Slash::Apache::User');
		$form = $user_cfg->{'form'};
	} else {
		$form = $static_form;
	}

	if ($value) {
		return defined($form->{$value})
			? $form->{$value}
			: undef;
	} else {
		return $form;
	}
}

#################################################################
sub setCurrentForm {
	($static_form) = @_;
}

#################################################################
sub getCurrentStatic {
	my($value) = @_;
	my $constants;

	if($ENV{GATEWAY_INTERFACE}) {
	my $r = Apache->request;
	my $const_cfg = Apache::ModuleConfig->get($r, 'Slash::Apache');
	$constants = $const_cfg->{'constants'};
	} else {
		$constants = $static_constants;
	}

	if ($value) {
		return defined($constants->{$value})
			? $constants->{$value}
			: undef;
	} else {
		return $constants;
	}
}

#################################################################
sub setCurrentStatic {
	($static_constants) = @_;
}

#################################################################
sub getCurrentAnonymousCoward {
	my $anonymous_coward;

	if($ENV{GATEWAY_INTERFACE}) {
		my $r = Apache->request;
		my $const_cfg = Apache::ModuleConfig->get($r, 'Slash::Apache');
		$anonymous_coward = $const_cfg->{'anonymous_coward'};
	} else {
		$anonymous_coward = $static_anonymous_coward;
	}

	return $anonymous_coward;
}

#################################################################
sub setCurrentAnonymousCoward {
	($static_anonymous_coward) = @_;
}

#################################################################
sub getCurrentDB {
	my $slashdb;

	if($ENV{GATEWAY_INTERFACE}) {
		my $r = Apache->request;
		my $const_cfg = Apache::ModuleConfig->get($r, 'Slash::Apache');
		my $slashdb = $const_cfg->{'dbslash'};
	} else {
		$slashdb = $static_db;
	}

	return $slashdb;
}

#################################################################
sub setCurrentDB {
	($static_db) = @_;
}

#################################################################
# This is the Chris method, since I bet he won't want to call
# all of the other methods independtly :)
sub setCurrentAll {
	($static_user, $static_form, $static_constants, $static_db, $static_anonymous_coward) 
		= @_;
}

#################################################################
sub isAnon {
	my ($uid) = @_;
	my $anonymous_coward_uid = getCurrentStatic('anonymous_coward_uid');

	return $anonymous_coward_uid == $uid ? 1 : 0;
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
