#!/usr/bin/perl -w

###############################################################################
# authors.pl - this code displays information about site authors
#
# Copyright (C) 1997 Rob "CmdrTaco" Malda
# malda@slashdot.org
#
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License
# as published by the Free Software Foundation; either version 2
# of the License, or (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program; if not, write to the Free Software
# Foundation, Inc., 59 Temple Place - Suite 330, Boston, MA  02111-1307, USA.
#
#
#  $Id$
###############################################################################
use strict;
use vars '%I';
use Slash;

sub main {
	*I = getSlashConf();
	getSlash();
	my $SECT=getSection($I{F}{section});

	header("$I{sitename}: Authors", $SECT->{section});
	titlebar("90%","The Authors");
	print <<EOT;
<P>I keep getting asked 'Who are you guys', so to help unload
some of that extra mail from my box I have now provided
this nice little page with a summary of the active $I{sitename}
authors here, along with the number of articles that they
have posted.
EOT

	my $authors = $I{dbobject}->getAuthorDescription();

	for (@$authors) {
		my ($count, $aid, $url, $copy) = @$_;
		next if $count < 1; 
		print <<EOT;
<H2><B><A HREF="$I{rootdir}/search.pl?author=$aid">$count</A></B>
	<A HREF="$url">$aid</A></H2>
EOT
		print qq![ <A HREF="$I{rootdir}/admin.pl?op=authors&aid=$aid">edit</A> ] !
			if getCurrentUser('aseclev') > 1000;
		print $copy;
	}

	
	printf <<EOT, scalar localtime;
<P><BR><FONT SIZE="2"><CENTER>generated on %s</CENTER></FONT><BR>
EOT

	$I{dbobject}->writelog("authors");
	footer($I{F}{ssi});
}

main();
#$I{dbh}->disconnect if $I{dbh};

