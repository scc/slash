package Slash::Utility;

use strict;
use Apache;
use Digest::MD5 'md5_hex';
require Exporter;

@Slash::Utility::ISA = qw(Exporter);
@Slash::Utility::EXPORT = qw(
	addToMenu
	apacheLog	
	stackTrace
	changePassword
	getDateFormat
	getDateOffset
	getCurrentUser
	getCurrentForm
	getCurrentStatic
	getCurrentDB
	getCurrentMenu
	getCurrentAnonymousCoward
	createCurrentUser
	createCurrentForm
	createCurrentStatic
	createCurrentDB
	createCurrentAnonymousCoward
	setCurrentUser
	isAnon
	getAnonId
	getFormkey
	encryptPassword
	bakeUserCookie
	eatUserCookie
	setCookie
	writeLog
);
$Slash::Utility::VERSION = '0.01';

# These are package variables that are used when you need to use the
# set methods when not running under mod_perl
my($static_user, $static_form, $static_constants, $static_db,
	$static_anonymous_coward);

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
	my($col) = @_;
	my $offset = getCurrentUser('offset');
	return $col unless $offset;
	return " DATE_ADD($col, INTERVAL $offset SECOND) ";
}

sub getDateFormat {
	my($col, $as) = @_;
	$as = 'time' unless $as;
	my $user = getCurrentUser();

	$user->{'format'} ||= '%A %B %d, @%I:%M%p ';
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
sub addToMenu {
	my($menu, $name, $data) = @_;
	my $user = getCurrentUser();

	return unless ref $data eq 'HASH';

	my $menus = getCurrentMenu($menu);
	$data->{menuorder} = @$menus;

	$user->{menus}{$menu}{$name} = $data;
}

#################################################################
sub getCurrentMenu {
	my($menu) = @_;
	my $user = getCurrentUser();

	unless ($menu) {
		($menu = $ENV{SCRIPT_NAME}) =~ s/\.pl$//;
	}

	my $r = Apache->request;
	my $cfg = Apache::ModuleConfig->get($r, 'Slash::Apache');
	my @menus = @{$cfg->{menus}{$menu}};

	if (my $user_menu = $user->{menus}{$menu}) {
		push @menus, values %$user_menu;
	}

	return \@menus;
}

#################################################################
sub getCurrentUser {
	my($value) = @_;
	my $user;

	if ($ENV{GATEWAY_INTERFACE}) {
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
	my($key, $value) = @_;
	my $user;

	if ($ENV{GATEWAY_INTERFACE}) {
		my $r = Apache->request;
		my $user_cfg = Apache::ModuleConfig->get($r, 'Slash::Apache::User');
		$user = $user_cfg->{'user'};
	} else {
		$user = $static_user;
	}

	$user->{$key} = $value;
}

#################################################################
sub createCurrentUser {
	($static_user) = @_;
}

#################################################################
sub getCurrentForm {
	my($value) = @_;
	my $form;

	if ($ENV{GATEWAY_INTERFACE}) {
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
sub createCurrentForm {
	($static_form) = @_;
}

#################################################################
sub getCurrentStatic {
	my($value) = @_;
	my $constants;

	if ($ENV{GATEWAY_INTERFACE}) {
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
sub createCurrentStatic {
	($static_constants) = @_;
}

#################################################################
sub getCurrentAnonymousCoward {
	my($value) = @_;

	if ($ENV{GATEWAY_INTERFACE}) {
		my $r = Apache->request;
		my $const_cfg = Apache::ModuleConfig->get($r, 'Slash::Apache');
		if ($value) {
			return $const_cfg->{'anonymous_coward'}{$value};
		} else {
			my %coward = %{$const_cfg->{'anonymous_coward'}};
			return \%coward;
		}
	} else {
		if ($value) {
			return $static_anonymous_coward->{$value};
		} else {
			my %coward = %{$static_anonymous_coward};
			return \%coward;
		}
	}
}

#################################################################
sub createCurrentAnonymousCoward {
	($static_anonymous_coward) = @_;
}

#################################################################
sub getCurrentDB {
	my $slashdb;

	if ($ENV{GATEWAY_INTERFACE}) {
		my $r = Apache->request;
		my $const_cfg = Apache::ModuleConfig->get($r, 'Slash::Apache');
		$slashdb = $const_cfg->{'dbslash'};
	} else {
		$slashdb = $static_db;
	}

	return $slashdb;
}

#################################################################
sub createCurrentDB {
	($static_db) = @_;
}

#################################################################
sub isAnon {
	my($uid) = @_;
	return $uid == getCurrentStatic('anonymous_coward_uid');
}

#################################################################
# do the MD5 thang (could use other method in the future)
sub encryptPassword {
	my($passwd) = @_;
	return md5_hex($passwd);
}

#################################################################
# create a user cookie from ingredients
sub bakeUserCookie {
	my($uid, $passwd) = @_;
	my $cookie = $uid . '::' . $passwd;
	$cookie =~ s/(.)/sprintf("%%%02x", ord($1))/ge;
	return $cookie;
}

#################################################################
# digest a user cookie, returning it back to its original ingredients
sub eatUserCookie {
	my($cookie) = @_;
	$cookie =~ s/%([a-fA-F0-9][a-fA-F0-9])/pack('C', hex($1))/ge;
	my($uid, $passwd) = split(/::/, $cookie, 2);
	return($uid, $passwd);
}

########################################################
# In the future a secure flag should be set on 
# the cookie for admin users. -- brian
# well, it should be an option, of course ... -- pudge
sub setCookie {
	# for some reason, we need to pass in $r, because Apache->request
	# was returning undef!  ack! -- pudge
	my($name, $val, $session) = @_;
	return unless $name;

	# no need to getCurrent*, only works under Apache anyway
	my $r = Apache->request;
	my $dbcfg = Apache::ModuleConfig->get($r, 'Slash::Apache');
	my $constants = $dbcfg->{constants};

	# We need to actually determine domain from preferences,
	# not from the server.  ask me why. -- pudge
	my $cookiedomain = $constants->{cookiedomain};
	my $cookiepath = $constants->{cookiepath};
	my $cookiesecure = 0;

	# domain must start with a '.' and have one more '.'
	# embedded in it, else we ignore it
 	my $domain = ($cookiedomain && $cookiedomain =~ /^\..+\./)
 		? $cookiedomain
 		: '';

	my %cookie = (
		-name	=> $name,
		-path	=> $cookiepath,
		-value	=> $val || '',
		-secure	=> $cookiesecure,
	);

	$cookie{-expires} = '+1y' unless $session;
 	$cookie{-domain}  = $domain if $domain;

	my $bakedcookie = CGI::Cookie->new(\%cookie);

	# we need to support multiple cookies, like my tummy does
	$r->err_headers_out->add('Set-Cookie' => $bakedcookie);
}

########################################################
sub writeLog {
	my $op = shift;
	my $dat = join("\t", @_);

	my $r = Apache->request;

	$r->notes('SLASH_LOG_OPERATION', $op);
	$r->notes('SLASH_LOG_DATA', $dat);
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
