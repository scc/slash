package Slash::Apache::User;

# EXPORT functions!

use strict;

use Apache; 
use Apache::Constants qw(:common REDIRECT);
use Apache::File; 
use Apache::ModuleConfig;
use AutoLoader ();
use Data::Dumper;
use DynaLoader ();
use Slash::DB;
use Slash::Utility;
use CGI::Cookie;
use vars qw($REVISION $VERSION @ISA);

# $Id$
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

	# Ok, this will make it so that we can reliably use Apache->request
	Apache->request($r);

	my $cfg = Apache::ModuleConfig->get($r);
	my $dbcfg = Apache::ModuleConfig->get($r, 'Slash::Apache');
	my $constants = $dbcfg->{constants};
	my $slashdb = $dbcfg->{slashdb};

	# let pass unless / or .pl
	unless ($cfg->{auth}){
		unless ($r->uri =~ m[(?:^/$)|(?:\.pl$)]) {
			$r->subprocess_env(SLASH_USER => $constants->{anonymous_coward_uid});
			return OK;
		}
	}

	$slashdb->sqlConnect;

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
		if ($newpass) {
			$r->err_header_out(Location =>
				"$constants->{absolutedir}/users.pl?op=edit" .
				"user&note=Please+change+your+password+now!"
			);
			return REDIRECT;
		}

	} elsif ($op eq 'userclose' ) {
		# It may be faster to just let the delete fail then test -Brian
		$slashdb->deleteSession() if ($slashdb->getUser($uid, 'seclev') >= 99);
		delete $cookies->{user};
		setCookie('user', '');

	} elsif ($cookies->{user}) {
		my($tmpuid, $password) = eatUserCookie($cookies->{user}->value);
		($uid, my($cookpasswd)) =
			$slashdb->getUserAuthenticate($tmpuid, $password);

		if ($uid) {
			# password in cookie was not encrypted, so
			# save new cookie
			setCookie('user', bakeUserCookie($uid, $cookpasswd))
				if $cookpasswd ne $password;
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

	createCurrentUser(getUser($form, $cookies, $uid));
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

	$passwd = substr $passwd, 0, 20;
	my($uid, $cookpasswd, $newpass) =
		$cfg->{slashdb}->getUserAuthenticate($name, $passwd, 1);

	if (!isAnon($uid)) {
		setCookie('user', bakeUserCookie($uid, $cookpasswd));
		return($uid, $newpass);
	} else {
		return $cfg->{constants}{anonymous_coward_uid};
	}
}

########################################################
# get all the user data, d00d
sub getUser {
	my($form, $cookies, $uid) = @_;
	my($r, $cfg, $constants, $slashdb, $user);

	$r = Apache->request;
	$cfg = Apache::ModuleConfig->get($r, 'Slash::Apache');
	$constants = $cfg->{constants};
	$slashdb = $cfg->{slashdb};

	$uid = $constants->{anonymous_coward_uid} unless defined $uid;

	if (!isAnon($uid) && ($user = $slashdb->getUser($uid))) { # getUserInstance($uid, $r->uri))) {}
		my $timezones = $slashdb->getCodes('tzcodes');
		$user->{offset} = $timezones->{ $user->{tzcode} };

		my $dateformats = $slashdb->getCodes('dateformats');
		$user->{'format'} = $dateformats->{ $user->{dfid} };

		$user->{is_anon} = 0;

	} else {
		$user = getCurrentAnonymousCoward();
		$user->{is_anon} = 1;

		if ($cookies->{anon} && $cookies->{anon}->value) {
			$user->{anon_id} = $cookies->{anon}->value;
			$user->{anon_cookie} = 1;
		} else {
			$user->{anon_id} = getAnonId();
		}

		setCookie('anon', $user->{anon_id}, 1);
	}


	my @defaults = (
		['mode', 'thread'], qw[
		savechanges commentsort threshold
		posttype noboxes light
	]);

	for my $param (@defaults) {
		my $default;
		if (ref($param) eq 'ARRAY') {
			($param, $default) = @$param;
		}

		if (defined $form->{$param}) {
			$user->{$param} = $form->{$param};
		} else {
			$user->{$param} ||= $default || 0;
		}
	}

	if ($user->{commentlimit} > $constants->{breaking}
		&& $user->{mode} ne 'archive') {
		$user->{commentlimit} = int($constants->{breaking} / 2);
		$user->{breaking} = 1;
	} else {
		$user->{breaking} = 0;
	}

	# All sorts of checks on user data
	$user->{tzcode}		= uc($user->{tzcode});
	$user->{clbig}		||= 0;
	$user->{clsmall}	||= 0;
	$user->{exaid}		= testExStr($user->{exaid}) if $user->{exaid};
	$user->{exboxes}	= testExStr($user->{exboxes}) if $user->{exboxes};
	$user->{extid}		= testExStr($user->{extid}) if $user->{extid};
	$user->{points}		= 0 unless $user->{willing}; # No points if you dont want 'em

	if ($user->{seclev} >= 99) {
		$user->{is_admin} = 1;
		$user->{aid} = $user->{nickname}; # Just here for the moment
		my $sid;
		if($cookies->{session}) {
			$sid = $slashdb->getSessionInstance($uid, $cookies->{session}->value);
		} else {
			$sid = $slashdb->getSessionInstance($uid);
		}
		setCookie('session', $sid) if $sid;
	}

#	if ($form->{op} eq 'adminlogin') {
#		my $sid = $slashdb->getAuthorAuthenticate($form->{aaid},
#			$form->{apasswd}, $user);
#		setCookie('session', $sid) if $sid;
#	} elsif ($cookies->{session} && length($cookies->{session}->value) > 3) {
#			my $value = $slashdb->getAuthorInfo(
#				$cookies->{session}->value,
#				$constants->{admin_timeout},
#				$user
#			);
#			print STDERR "Slash::Apache::User::getUser VALUE $value \n";
#	}

	return $user;
}

########################################################
# Ok, we are going to go on and process the form pieces
# now since we need them. Below are all of the filters
# for the form data. IMHO we should just pass in a
# reference from %params to some method in a library
# that cleans up the data  -Brian

sub filter_params {
	my %params = @_;
	my %form;

	# fields that are numeric only
	my %nums = map {($_ => 1)} qw(
		last next artcount bseclev cid clbig clsmall
		commentlimit commentsort commentspill commentstatus
		del displaystatus filter_id height
		highlightthresh isolate issue maillist max
		maxcommentsize maximum_length maxstories min minimum_length
		minimum_match ordernum pid
		retrieve seclev startat uid uthreshold voters width
		writestatus ratio
	);

	# regexes to match dynamically generated numeric fields
	my @regints = (qr/^reason_.+$/, qr/^votes.+$/);

	# special few
	my %special = (
		sid => sub { $_[0] =~ s|[^A-Za-z0-9/.]||g },
	);

	for (keys %params) {
		$form{$_} = $params{$_};

		# Paranoia - Clean out any embedded NULs. -- cbwood
		# hm.  NULs in a param() value mean multiple values
		# for that item.  do we use that anywhere? -- pudge
		$form{$_} =~ s/\0//g;

		# clean up numbers
		if (exists $nums{$_}) {
			$form{$_} = fixint($form{$_});
		} elsif (exists $special{$_}) {
			$special{$_}->($form{$_});
		} else {
			for my $ri (@regints) {
				$form{$_} = fixint($form{$_}) if /$ri/;
			}
		}
	}

	return \%form;
}

########################################################
# fix parameter input that should be integers
sub fixint {
	my($int) = @_;
	$int =~ s/^\+//;
	$int =~ s/^(-?[\d.]+).*$/$1/ or return;
	return $int;
}

########################################################
sub testExStr {
	local($_) = @_;
	$_ .= "'" unless m/'$/;
	return $_;
}

sub DESTROY {
}

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

=head1 AUTHOR

Brian Aker, brian@tangent.org

Chris Nandor, pudge@pobox.com

=head1 SEE ALSO

perl(1). Slash(3).

=cut
