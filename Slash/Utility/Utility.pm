package Slash::Utility;

use strict;
use Apache;
require Exporter;

@Slash::Utility::ISA = qw(Exporter);
@Slash::Utility::EXPORT = qw(
	apacheLog	
);
$Slash::Utility::VERSION = '0.01';


########################################################
# writes error message to apache's error_log if we're running under mod_perl
# Called wherever we have errors.
sub apacheLog {
	if ($ENV{SCRIPT_NAME}) {
		my $r = Apache->request;
		$r->log_error("$ENV{SCRIPT_NAME}:@_");
	} else {
		print @_, "\n";
	}
	return 0;
}
1;

=head1 NAME

Slash::Utility - Generic Perl routines for SlashCode

=head1 SYNOPSIS

  use Slash::Utility;

=head1 DESCRIPTION

Generic routines that are used throughout Slashcode.

=head1 AUTHOR

Brian Aker, brian@tangent.org

=head1 SEE ALSO

Slash(3).

=cut
