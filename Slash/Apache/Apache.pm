package Slash::Apache;

use strict;
use vars qw($VERSION @ISA @EXPORT @EXPORT_OK);

use Apache::ModuleConfig;
use Slash::DB;
require DynaLoader;
require AutoLoader;

@Slash::Apache::ISA = qw(DynaLoader);
$Slash::Apache::VERSION = '0.01';

bootstrap Slash::Apache $VERSION;

sub SlashVirtualUser ($$$){
	my ($cfg, $params, $user) = @_;
	$cfg->{Apache}{VirtualUser} = $user;
	$cfg->{Apache}{dbslash} = new Slash::DB($user);
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
