package Slash::Apache::User;

use strict;

use Apache; 
use Apache::Constants qw(:common);
use Apache::ModuleConfig;
use Slash::DB;
use CGI::Cookie;
use vars qw($VERSION @ISA);

require DynaLoader;
require AutoLoader;

@ISA = qw(DynaLoader);
$VERSION = '0.01';

bootstrap Slash::Apache::User $VERSION;

sub SlashUserInit ($$) {
	my($cfg, $params) = @_;
	$cfg->{user} = '';
	$cfg->{form} = '';
}

# handler method
sub handler {
	my($r) = @_;
	my $filename = $r->filename;
	unless($filename =~ /\.pl$/) {
		print STDERR "Skipping $filename \n";
		return OK;
	} else {
		print STDERR "Doing $filename \n";
	}
	my $cfg = Apache::ModuleConfig->get($r);
	my $dbcfg = Apache::ModuleConfig->get($r, 'Slash::Apache');
	# Lets do this to make it a bit easier to handle
	my $dbslash = $dbcfg->{'dbslash'};
	$dbslash->sqlConnect;

	my %params = ($r->args, $r->content);
	# Don't remove this. This solves a known bug in Apache
	$r->header_in('Content-Length' => '0');
	$r->method('GET');
	my %form;
	#
	# Ok, we are going to go on and process the form pieces
	# now since we need them. Below are all of the filters
	# for the form data. IMHO we should just pass in a
	# reference from %params to some method in a library
	# that cleans up the data  -Brian
	#

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

	my %cookies = parse CGI::Cookie($r->header_in('Cookie'));
	# So we are either going to pick the user up from 
	# the form, a cookie, or they will be anonymous
	my $uid;
	my $op = $form{'op'} || '';
	if (($op eq 'userlogin' || $form{'rlogin'} ) && length($form{upasswd}) > 1) {
		my $user = $dbslash->getUserUID($form{unickname});
		print STDERR "FORM_AUTH: $user:$form{upasswd}\n";
		$uid = userLogin($dbcfg, $user, $form{upasswd});

	} elsif ($op eq 'userclose' ) {
		setCookie('user', '');

	} elsif ($op eq 'adminclose') {
		setCookie('session', ' ');

	#This is icky, should be simplified
	} elsif ($cookies{'user'}) {
		my($user, $password) = userCheckCookie($dbcfg, $cookies{'user'}->value);
		print STDERR "COOKIE_AUTH: $user:$password\n";
		unless ($uid = $dbslash->getUserAuthenticate($user, $password)) {
			$uid = $dbcfg->{constants}{'anonymous_coward_uid'}; 
			setCookie('user', ' ');
		}
	} 

	$uid = $dbcfg->{constants}{'anonymous_coward_uid'} unless defined($uid);

	#Ok, yes we could use %ENV here, but if we did and 
	#if someone ever wrote a module in another language
	#or just a cheesy CGI, they would never see it.
	$r->subprocess_env('REMOTE_USER' => $uid);
	$cfg->{'form'} = \%form;

	print STDERR "UID: $uid\n";

	return OK;
}

# This should be turned into a private method at some point
sub fixint {
	my($int) = @_;
	$int =~ s/^\+//;
	$int =~ s/^(-?[\d.]+).*$/$1/ or return;
	return $int;
}


########################################################
# Decode the Cookie: Cookies have all the special charachters encoded
# in standard URL format.  This converts it back.  then it is split
# on '::' to get the users info.
sub userCheckCookie {
	my($cfg, $cookie) = @_;
	$cookie =~ s/%([a-fA-F0-9][a-fA-F0-9])/pack('C', hex($1))/eg;
	my($uid, $passwd) = split('::', $cookie);
	return($cfg->{constants}->{'anonymous_coward_uid'}, '') unless $uid && $passwd;
	return($uid, $passwd);
}



########################################################
sub userLogin {
	my($cfg, $name, $passwd) = @_;

	$passwd = substr $passwd, 0, 20;
	my $uid = $cfg->{'dbslash'}->getUserAuthenticate($name, $passwd);

	if ($uid != $cfg->{constants}{anonymous_coward_uid}) {
		my $cookie = $uid . '::' . $passwd;
		#$cookie =~ s/(.)/sprintf("%%%02x",ord($1))/ge;
		setCookie('user', $cookie);
		return $uid ;
	} else {
		return $cfg->{constants}{'anonymous_coward_uid'};
	}
}

########################################################
# In the future a secure flag should be set on 
# the cookie for admin users.
sub setCookie {
	my($name, $val, $session) = @_;
	my $servername = Apache->server->server_hostname;

	# this goes back in as soon as vars / slashdotrc
	# stuff is done -- pudge
# 	my $domain = ($I{cookiedomain} && $I{cookiedomain} =~ /^\..+\./)
# 		? $I{cookiedomain}
# 		: '';

	my %cookie = (
			-name   => $name,
# Add path back in when slashdotrc.pl is completed
# there may be another way to determine this
#			-path   => $I{cookiepath},
			-value    => $val || '',
	);
	$cookie{-expires} = '+1y' unless $session;

	# this goes back in as soon as vars / slashdotrc
	# stuff is done -- pudge
# 	$cookie{-domain}  = $domain if $domain;

	my $bakedcookie = CGI::Cookie->new(\%cookie);
	my $r = Apache->request;

	# huh? what is err_header?
#	$r->header_out('Set-Cookie' => $bakedcookie);
	$r->err_header_out('Set-Cookie' => $bakedcookie);
}

#sub new {
#	return bless {}, shift;
#}
#
#sub DIR_CREATE {
#	my ($class) = @_;
#	my $self = $class->new;
#	$self->{user} = '';
#	$self->{form} = '';
#	return $self;	
#}

__END__
1;

=head1 NAME

Slash::Apache::User - Apache Authenticate for slashcode user

=head1 SYNOPSIS

  use Slash::Apache::User;

=head1 DESCRIPTION

This is the user authenication system for Slash. This is
where you want to be if you want to modify slashcode's
method of authenication. The rest of slashcode depends
on finding the UID of the user in the REMOTE_USER 
environmental variable.

=head1 AUTHOR

Brian Aker, brian@tangent.org

=head1 SEE ALSO

perl(1). Slash(3).

=cut
