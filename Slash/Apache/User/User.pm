package Slash::Apache::User;

# EXPORT functions!

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

	return DECLINED unless $r->is_main;

	# Ok, this will make it so that we can reliably use Apache->request
	Apache->request($r);

	my $cfg = Apache::ModuleConfig->get($r);
	my $dbcfg = Apache::ModuleConfig->get($r, 'Slash::Apache');
	my $constants = $dbcfg->{constants};
	my $slashdb = $dbcfg->{slashdb};

	# let pass unless / or .pl
	my $uri = fixuri($r->uri, $constants->{rootdir});
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

		if ($uid != $constants->{anonymous_coward_uid}) {
			my $newurl = url2abs($newpass
				? "$constants->{rootdir}/users.pl?op=edit" .
				  "user&note=Please+change+your+password+now!"
				: $form->{returnto}
					? $form->{returnto}
					: $uri
			);
			$r->err_header_out(Location => $newurl);
			return REDIRECT;
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
# get all the user data, d00d
sub getUser {
	my($form, $cookies, $uid) = @_;
	my($r, $cfg, $constants, $slashdb, $user);

	$r = Apache->request;
	$cfg = Apache::ModuleConfig->get($r, 'Slash::Apache');
	$constants = $cfg->{constants};
	$slashdb = $cfg->{slashdb};

	$uid = $constants->{anonymous_coward_uid} unless defined($uid) && $uid ne '';

	if (!isAnon($uid) && ($user = $slashdb->getUser($uid))) { # getUserInstance($uid, $r->uri))) {}
		my $timezones = $slashdb->getDescriptions('tzcodes');
		$user->{off_set} = $timezones->{ $user->{tzcode} };

		my $dateformats = $slashdb->getDescriptions('datecodes');
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

		if (defined $form->{$param} && $form->{$param} ne '') {
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
	#$user->{tzcode}		= uc($user->{tzcode});
	$user->{exaid}		= testExStr($user->{exaid}) if $user->{exaid};
	$user->{exboxes}	= testExStr($user->{exboxes}) if $user->{exboxes};
	$user->{extid}		= testExStr($user->{extid}) if $user->{extid};
	$user->{points}		= 0 unless $user->{willing}; # No points if you dont want 'em

	# This is here so when user selects "6 ish" it
	# "posted by xxx around 6 ish" instead of "on 6 ish"
	if ($user->{'format'} eq '%i ish') {
		$user->{aton} = 'around'; # getData('atonish');
	} else {
		$user->{aton} = 'on'; # getData('aton');
	}

	my $uri = fixuri($r->uri, $constants->{rootdir});
	if ($uri =~ m[^/$]) {
		$user->{currentPage} = 'index';
	} elsif ($uri =~ m[^/(.*)\.pl$]) {
		$user->{currentPage} = $1;
	} else {
		$user->{currentPage} = 'misc';
	}

	if ($user->{seclev} >= 99) {
		$user->{is_admin} = 1;
		#$user->{aid} = $user->{nickname}; # Just here for the moment
		my $sid;
		if ($cookies->{session}) {
			$sid = $slashdb->getSessionInstance($uid, $cookies->{session}->value);
		} else {
			$sid = $slashdb->getSessionInstance($uid);
		}
		setCookie('session', $sid) if $sid;
	}

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
		writestatus ratio posttype
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

########################################################
# adjust path for non-rooted slash sites
sub fixuri {
	my($uri, $rootdir) = @_;
	if ($rootdir) {
		my $path = URI->new($rootdir)->path;
		$uri =~ s/^\Q$path//;
	}
	return $uri;
}

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

=head1 AUTHOR

Brian Aker, brian@tangent.org

Chris Nandor E<lt>pudge@pobox.comE<gt>, http://pudge.net/

=head1 SEE ALSO

perl(1). Slash(3).

=cut
