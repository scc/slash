package Slash::Display::Plugin;

use strict;
use vars qw($VERSION);
use base qw(Template::Plugin);
use Slash::Display ();
use Slash::Utility;
use Template::Plugin;

$VERSION = '0.01';

sub new {
	my($class, $context, $name) = @_;
	return bless {
		_CONTEXT => $context,
	}, $class;
}

sub display {
	my($self, $name, $args) = @_;
	my $context = $self->{_CONTEXT};
	my $block = Slash::Display::getDisplayBlock($name);
	my $ok = $context->process(\$block, $args);
	apacheLog($context->error) unless defined $ok;
	return $ok;
}

1;

__END__

=head1 NAME

Slash::Display::Plugin - Template Toolkit plugin for Slash

=head1 SYNOPSIS

DEPRECATED, PLACEHOLDER FOR FUTURE USE

	[% USE Slash %]
	[% Slash.display('some template') %]

=head1 DESCRIPTION

Process and display a template by name from inside another
template.  The USE directive should be unnecessary, as it is
called automatically.

=head1 AUTHOR

Chris Nandor E<lt>pudge@pobox.comE<gt>, http://pudge.net/

=head1 SEE ALSO

Template, Slash, Slash::Utility, Slash::Display.
