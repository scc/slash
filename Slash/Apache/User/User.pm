# This code is a part of Slash, and is released under the GPL.
# Copyright 1997-2001 by Open Source Development Network. See README
# and COPYING for more information, or see http://slashcode.com/.
# $Id$

package Slash::Apache::User;

use strict;
use Apache; 
use Apache::Constants qw(:common REDIRECT);
use Apache::File; 
use Apache::ModuleConfig;
use AutoLoader ();
use CGI::Cookie;
use DynaLoader ();
use Slash::DB;
use Slash::Utility;
use URI ();
use vars qw($REVISION $VERSION @ISA);

($REVISION) = ' $Revision$ ' =~ /\$Revision:\s+([^\s]+)/;
$VERSION = '0.01';
@ISA = qw(DynaLoader);

bootstrap Slash::Apache::User $VERSION;

# BENDER: Oh, so, just 'cause a robot wants to kill humans
# that makes him a radical?

sub SlashEnableENV ($$$) {
	my($cfg, $params, $flag) = @_;
	$cfg->{env} = $flag;
}

sub SlashAuthAll ($$$) {
	my($cfg, $params, $flag) = @_;
	$cfg->{auth} = $flag;
}

# handler method
sub handler {
	my($r) = @_;

	return DECLINED unless $r->is_main;

	# Ok, this will make it so that we can reliably use Apache->request
	Apache->request($r);

	my $cfg = Apache::ModuleConfig->get($r);
	my $dbcfg = Apache::ModuleConfig->get($r, 'Slash::Apache');
	my $constants = $dbcfg->{constants};
	my $slashdb = $dbcfg->{slashdb};

	# let pass unless / or .pl
	my $uri = $r->uri;
	if ($constants->{rootdir}) {
		my $path = URI->new($constants->{rootdir})->path;
		$uri =~ s/^\Q$path//;
	}

	unless ($cfg->{auth}) {
		unless ($uri =~ m[(?:^/$)|(?:\.pl$)]) {
			$r->subprocess_env(SLASH_USER => $constants->{anonymous_coward_uid});
			return OK;
		}
	}

	$slashdb->sqlConnect;
	#Ok, this solves the annoying issue of not having true OOP in perl
	# You can comment this out if you want if you only use one database type
	# long term, it might be nice to create new classes for each slashdb
	# object, and set @ISA for each class, or make each other class inherit
	# from Slash::DB instead of vice versa ...
	$slashdb->fixup;

	my $method = $r->method;
	# Don't remove this. This solves a known bug in Apache -- brian
	$r->method('GET');

	my $form = filter_params($r->args, $r->content);
	my $cookies = CGI::Cookie->parse($r->header_in('Cookie'));

	# So we are either going to pick the user up from 
	# the form, a cookie, or they will be anonymous
	my $uid;
	my $op = $form->{op} || '';

	if (($op eq 'userlogin' || $form->{rlogin} ) && length($form->{upasswd}) > 1) {
		my $tmpuid = $slashdb->getUserUID($form->{unickname});
		($uid, my($newpass)) = userLogin($tmpuid, $form->{upasswd});

		# here we want to redirect only if the user has posted via
		# GET, and the user has logged in successfully

		if ($method eq 'GET' && $uid && ! isAnon($uid)) {
			$form->{returnto} = url2abs($newpass
				? "$constants->{rootdir}/users.pl?op=edit" .
				  "user&note=Please+change+your+password+now!"
				: $form->{returnto}
					? $form->{returnto}
					: $uri
			);
			# not working ... move out into users.pl and index.pl
#			$r->err_header_out(Location => $newurl);
#			return REDIRECT;
		}

	} elsif ($op eq 'userclose' ) {
		# It may be faster to just let the delete fail then test -Brian
		# well, uid is undef here ... can't use it to test
		# until it is defined :-) -- pudge
		# Went boom without if. --Brian
		#$slashdb->deleteSession(); #  if $slashdb->getUser($uid, 'seclev') >= 99;
		delete $cookies->{user};
		setCookie('user', '');

	} elsif ($cookies->{user}) {
		my($tmpuid, $password) = eatUserCookie($cookies->{user}->value);
		($uid, my($cookpasswd)) =
			$slashdb->getUserAuthenticate($tmpuid, $password);

		if ($uid) {
			# password in cookie was not encrypted, so
			# save new cookie
			setCookie('user', bakeUserCookie($uid, $cookpasswd),
				$slashdb->getUser($uid, 'session_login')
			) if $cookpasswd ne $password;
		} else {
			$uid = $constants->{anonymous_coward_uid};
			delete $cookies->{user};
			setCookie('user', '');
		}
	} 

	$uid = $constants->{anonymous_coward_uid} unless defined $uid;

	# Ok, yes we could use %ENV here, but if we did and 
	# if someone ever wrote a module in another language
	# or just a cheesy CGI, they would never see it.
	$r->subprocess_env(SLASH_USER => $uid);

	return DECLINED if $cfg->{auth} && isAnon($uid);

	createCurrentUser(prepareUser($uid, $form, $uri, $cookies));
	createCurrentForm($form);
	createEnv($r) if $cfg->{env};

	return OK;
}

########################################################
sub createEnv {
	my($r) = @_;

	my $user = getCurrentUser();
	my $form = getCurrentForm();

	while (my($key, $val) = each %$user) {
		$r->subprocess_env("USER_$key" => $val);
	}

	while (my($key, $val) = each %$form) {
		$r->subprocess_env("FORM_$key" => $val);
	}

}

########################################################
sub userLogin {
	my($name, $passwd) = @_;
	my $r = Apache->request;
	my $cfg = Apache::ModuleConfig->get($r, 'Slash::Apache');
	my $slashdb = getCurrentDB();

	# Do we want to allow logins with encrypted passwords? -- pudge
#	$passwd = substr $passwd, 0, 20;
	my($uid, $cookpasswd, $newpass) =
		$slashdb->getUserAuthenticate($name, $passwd); #, 1

	if (!isAnon($uid)) {
		setCookie('user', bakeUserCookie($uid, $cookpasswd));
		return($uid, $newpass);
	} else {
		return getCurrentStatic('anonymous_coward_uid');
	}
}

########################################################
#
sub DESTROY { }

1;

__END__

=head1 NAME

Slash::Apache::User - Apache Authenticate for slashcode user

=head1 SYNOPSIS

  use Slash::Apache::User;

=head1 DESCRIPTION

This is the user authenication system for Slash. This is
where you want to be if you want to modify slashcode's
method of authenication. The rest of slashcode depends
on finding the UID of the user in the SLASH_USER 
environmental variable.

=head1 SEE ALSO

Slash(3), Slash::Apache(3).

=cut
