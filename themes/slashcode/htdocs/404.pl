#!/usr/bin/perl -w
# This code is a part of Slash, which is Copyright 1997-2001 OSDN, and
# released under the GPL.  See README and COPYING for more information.
# $Id$

use strict;
use Slash;
use Slash::Display;
use Slash::Utility;

sub main {
	my $constants = getCurrentStatic();
	$ENV{REQUEST_URI} ||= '';

	my $url = strip_literal(substr($ENV{REQUEST_URI}, 1));
	my $admin = $constants->{adminmail};

	header('404 File Not Found', '', '404 File Not Found');

	my($new_url, $errnum) = fixHref($url, 1);

	if ($errnum && $errnum !~ /^\d+$/) {
		slashDisplay('main', {
			url	=> $new_url,
			origin	=> $url,
			message	=> $errnum,
		});
	} else {
		slashDisplay('main', {
			error	=> $errnum,
			url	=> $new_url,
			origin	=> $url,
		});
	}

	writeLog('404', '404');
	footer();
}

createEnvironment();
main();

1;
