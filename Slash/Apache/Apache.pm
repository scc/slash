package Slash::Apache;

use strict;

use Apache::ModuleConfig;
use Slash::DB;
require DynaLoader;
require AutoLoader;
use vars qw($VERSION @ISA);

@Slash::Apache::ISA = qw(DynaLoader);
$Slash::Apache::VERSION = '1.00';

bootstrap Slash::Apache $VERSION;

sub SlashVirtualUser ($$$){
	my ($cfg, $params, $user) = @_;
	$cfg->{VirtualUser} = $user;
	$cfg->{dbslash} = new Slash::DB($user);
	# More of a place holder to remind me that it
	# is here. The uid will be populated once Patrick
	# finishes up with slashdotrc
	# There will need to be some get var calls here
	$cfg->{anonymous_coward_uid} = '-1';
	$cfg->{anonymous_coward} = '';
	$cfg->{authors_unlimited} = '1';
}
__END__
1;

=head1 NAME

Slash::Apache - Apache Specific handler for Slashcode

=head1 SYNOPSIS

  use Slash::Apache;

=head1 DESCRIPTION

This is what creates the SlashVirtualUser command for us
in the httpd.conf file.

=head1 AUTHOR

Brian Aker, brian@tangent.org

=head1 SEE ALSO

perl(1). Slash(3).

=cut
