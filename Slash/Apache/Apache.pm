# This code is a part of Slash, and is released under the GPL.
# Copyright 1997-2001 by Open Source Development Network. See README
# and COPYING for more information, or see http://slashcode.com/.
# $Id$

package Slash::Apache;

use strict;
use Apache;
use Apache::SIG ();
use Apache::ModuleConfig;
use Apache::Constants qw(:common);
use Slash::DB;
use Slash::Display;
use Slash::Utility;
require DynaLoader;
require AutoLoader;
use vars qw($REVISION $VERSION @ISA);

@ISA		= qw(DynaLoader);
$VERSION	= '2.001000';	# v2.1.0
($REVISION)	= ' $Revision$ ' =~ /\$Revision:\s+([^\s]+)/;

bootstrap Slash::Apache $VERSION;

# BENDER: There's nothing wrong with murder, just as long
# as you let Bender whet his beak.

sub SlashVirtualUser ($$$) {
	my($cfg, $params, $user) = @_;
	$cfg->{VirtualUser} = $user;
	$cfg->{slashdb} = Slash::DB->new($user);
	$cfg->{constants} = $cfg->{slashdb}->getSlashConf($user);

	# placeholders ... store extra placeholders in DB?  :)
	for (qw[user form themes template cookie objects]) {
		$cfg->{$_} = '';
	}

	my $anonymous_coward = $cfg->{slashdb}->getUser(
		$cfg->{constants}{anonymous_coward_uid}
	);

	# Lets just do this once
	my $timezones = $cfg->{slashdb}->getDescriptions('tzcodes');
	$anonymous_coward->{off_set} = $timezones->{ $anonymous_coward->{tzcode} };
	my $dateformats = $cfg->{slashdb}->getDescriptions('datecodes');
	$anonymous_coward->{'format'} = $dateformats->{ $anonymous_coward->{dfid} };

	$cfg->{anonymous_coward} = $anonymous_coward;
	$cfg->{menus} = $cfg->{slashdb}->getMenus();
	# If this is not here this will go poorly.
	$cfg->{slashdb}->{_dbh}->disconnect;
}

sub CompileTemplates {
	my $slashdb   = getCurrentDB();
	my $constants = getCurrentStatic();

	# caching must be on, along with unlimited
	# cache size, and we can't have already done
	# this in this child
	return unless $constants->{cache_enabled}
		  && !$constants->{template_already_cached}
		  && !$constants->{template_cache_size};

	my $templates = $slashdb->getTemplateNameCache();

	# temporarily turn off warnings and errors, see errorLog()
	local $Slash::Utility::NO_ERROR_LOG = 1;
	local $SIG{__WARN__} = 'IGNORE';

	# this will call every template in turn, and it will
	# then be compiled; now, we will get errors in
	# the error log for templates that don't check
	# the input values; that can't easily be helped
	for my $t (keys %$templates) {
		my($name, $page, $section) = split /$;/, $t;
		slashDisplay($name, 0, {
			Page	=> $page,
			Section	=> $section,
			Return	=> 1,
			Nocomm	=> 1
		});
	}

	# don't y'all come back now, y'hear?
	$constants->{template_already_cached} = 1;
}

sub IndexHandler {
	my($r) = @_;

	my $constants = getCurrentStatic();
	my $uri = $r->uri;
	if ($constants->{rootdir}) {
		my $path = URI->new($constants->{rootdir})->path;
		$uri =~ s/^\Q$path//;
	}

	if ($uri eq '/') {
		my $filename  = $r->filename;
		my $basedir   = $constants->{basedir};

		# cookie data will begin with word char or %
		if ($r->header_in('Cookie') =~ /\b(?:user)=[%\w]/) {
			$r->uri('/index.pl');
			$r->filename("$basedir/index.pl");
			return OK;
		} else {
			$r->uri('/index.shtml');
			$r->filename("$basedir/index.shtml");
			writeLog('shtml');
			return OK;
		}
	}

	return DECLINED;
}

sub DESTROY { }


1;

__END__

=head1 NAME

Slash::Apache - Apache Specific handler for Slash

=head1 SYNOPSIS

	use Slash::Apache;

=head1 DESCRIPTION

This is what creates the SlashVirtualUser command for us
in the httpd.conf file.

=head1 SEE ALSO

Slash(3).

=cut
