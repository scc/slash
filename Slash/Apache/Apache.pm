package Slash::Apache;

use strict;
use Apache::ModuleConfig;
use Apache::Constants qw(:common);
use Slash::DB;
use Slash::Utility;
require DynaLoader;
require AutoLoader;
use vars qw($VERSION @ISA);

@ISA = qw(DynaLoader);
$VERSION = '1.00';

bootstrap Slash::Apache $VERSION;

# BENDER: There's nothing wrong with murder, just as long
# as you let Bender whet his beak.

sub SlashVirtualUser ($$$) {
	my($cfg, $params, $user) = @_;
	$cfg->{VirtualUser} = $user;
	$cfg->{slashdb} = Slash::DB->new($user);
	$cfg->{constants} = $cfg->{slashdb}->getSlashConf();

	# Backwards compatibility
	my $anonymous_coward = $cfg->{slashdb}->getUserInstance(
		$cfg->{constants}{anonymous_coward_uid}
	);
	my $actz = $cfg->{slashdb}->getACTz(
		$anonymous_coward->{tzcode}, $anonymous_coward->{dfid}
	);
	@{$anonymous_coward}{keys %$actz} = values %$actz;

	$cfg->{anonymous_coward} = $anonymous_coward; 
	$cfg->{menus} = $cfg->{slashdb}->getMenus();
}

sub IndexHandler {
	my($r) = @_;
	if ($r->uri eq '/') {
		# cookie data will begin with word char or %
		if ($r->header_in('Cookie') =~ /\b(?:user|session)=[%\w]/) {
			$r->filename($r->document_root . '/index.pl');
			return OK;
		} else {
			$r->filename($r->document_root . '/index.shtml');
			return OK;
		}
	}
	
	return DECLINED;
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
