package Slash::Apache::Log;

use strict;
use Slash::DB;
use Slash::Utility;
use Apache::Constants qw(:common);

$Slash::Apache::Log::VERSION = '0.01';

# AMY: Leela's gonna kill me.
# BENDER: Naw, she'll probably have me do it.

sub handler {
	my($r) = @_;
	my $slashdb = getCurrentDB();
	my $op = $r->notes('SLASH_LOG_OPERATION');
	my $dat = $r->notes('SLASH_LOG_DATA');
	if ($op) {
		$slashdb->createAccessLog($op, $dat);
	}

	return OK;
}

1;
__END__

=head1 NAME

Slash::Apache::Log - Handles logging for slashdot

=head1 SYNOPSIS

  use Slash::Apache::Log;

=head1 DESCRIPTION

No method are provided. Basically this handles grabbing the
data out of the Apache process and logging it to the
database. 

=head1 AUTHOR

Brian Aker, brian@tangent.org

=head1 SEE ALSO

perl(1).

=cut
