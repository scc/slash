# This code is a part of Slash, and is released under the GPL.
# Copyright 1997-2001 by Open Source Development Network. See README
# and COPYING for more information, or see http://slashcode.com/.
# $Id$

package Slash::Test;

=head1 NAME

Slash::Test - Command-line Slash testing


=head1 SYNOPSIS

	perl -MSlash::Test -e 'print Dumper $user'

	perl -MSlash::Test -e 'slashTest("virtualuser"); print Dumper $user'


=head1 DESCRIPTION

Will export everything from Slash, Slash::Utility, Slash::Display,
and Data::Dumper into the current namespace.  Will export $user, $form,
$constants, and $slashdb as global variables into the current namespace.

So use it one of those two ways (use the default Virtual User,
or pass in with slashTest()), and then
just use the Slash API in your one-liners.

It is recommended you change the hardcoded default to whatever Virtual User
you use most.

=head1 EXPORTED FUNCTIONS

=cut

use Slash;
use Slash::Display;
use Slash::Utility;
use Slash::XML;
use Data::Dumper;

use base 'Exporter';
use vars qw($VERSION @EXPORT $vuser);

($VERSION) = ' $Revision$ ' =~ /\$Revision:\s+([^\s]+)/;
@EXPORT = (
	@Slash::EXPORT,
	@Slash::Display::EXPORT,
	@Slash::Utility::EXPORT,
	@Slash::XML::EXPORT,
	@Data::Dumper::EXPORT,
	'slashTest'
);

$vuser = 'slash';
slashTest();

#========================================================================

=head2 slashTest([VIRTUALUSER])

Set up the environment, with a new Virtual User.

Called automatically when module is first used.  Should only be called
if changing the Virtual User from the default (by default, "slash").
Called without an argument, uses the default.

=over 4

=item Parameters

=over 4

=item VIRTUALUSER

Your site's virtual user.

=back

=item Return value

None.

=item Side effects

Set up the environment with createEnvironment(), export $user,
$form, $constants, and $slashdb into current namespace.

=back

=cut


sub slashTest {
	my($VirtualUser) = @_;

	$VirtualUser = $vuser unless defined $VirtualUser;

	createEnvironment($VirtualUser);
	$::slashdb   = getCurrentDB();
	$::constants = getCurrentStatic();
	$::user      = getCurrentUser();
	$::form      = getCurrentForm();
}

1;

__END__


=head1 SEE ALSO

Slash(3).

=head1 VERSION

$Id$
