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

sub SlashVirtualUser ($$$) {
	my($cfg, $params, $user) = @_;
	$cfg->{VirtualUser} = $user;
	$cfg->{dbslash} = Slash::DB->new($user);
	$cfg->{constants} = $cfg->{dbslash}->getSlashConf();
	my $anonymous_coward = 
			$cfg->{dbslash}->getUser($cfg->{constants}->{anonymous_coward_uid});
	my $actz =  
			$cfg->{dbslash}->getACTz($anonymous_coward->{tzcode}, $anonymous_coward->{dfid});
	for(keys %$actz) {
		$anonymous_coward->{$_} =  $actz->{$_};
	}
	$cfg->{anonymous_coward} = $anonymous_coward; 
}

1;

__END__

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
