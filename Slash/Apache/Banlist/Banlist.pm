# This code is a part of Slash, and is released under the GPL.
# Copyright 1997-2001 by Open Source Development Network. See README
# and COPYING for more information, or see http://slashcode.com/.
# $Id$

package Slash::Apache::Banlist;

use strict;
use Slash::Utility;
use Digest::MD5 'md5_hex';
use Apache::Constants qw(:common);
use vars qw($VERSION);

($VERSION) = ' $Revision$ ' =~ /\$Revision:\s+([^\s]+)/;

sub handler {
	my($r) = @_;

	my $r = Apache->request;
	my $isbanned = 0;

	return DECLINED unless $r->is_main;

	# Ok, this will make it so that we can reliably use Apache->request
	Apache->request($r);
	my $hostip = $r->connection->remote_ip; 
	my $cur_ipid = md5_hex($hostip);

	my $constants = getCurrentStatic();
	my $slashdb = getCurrentDB();
	$slashdb->sqlConnect();
	
	$slashdb->getBanList();

	$isbanned = $slashdb->isBanned($cur_ipid);
	if ($isbanned) {
		$r->custom_response(FORBIDDEN, "The ipid $cur_ipid is banned from this site");
		return FORBIDDEN;
	}

	return OK;
}


sub DESTROY { }

1;

__END__

=head1 NAME

Slash::Apache::Banlist- Handles user banning via ipid 

=head1 SYNOPSIS

	use Slash::Apache::Banlist;

=head1 DESCRIPTION

No method are provided. Basically this handles comparing
md5 hash of a given IP and checks the banned hashref for 
the existence of the key that is the current ipid 

=head1 SEE ALSO

Slash(3), Slash::Apache(3).

=cut
