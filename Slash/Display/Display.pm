package Slash::Display;

use strict;
use base 'Exporter';
use vars qw($REVISION $VERSION @EXPORT);
use Exporter ();
use Slash::Display::Provider;
use Slash::Utility;
use Template;

# $Id$
($REVISION)	= ' $Revision$ ' =~ /\$Revision:\s+([^\s]+)/;
($VERSION)	= $REVISION =~ /^(\d+\.\d+)/;
@EXPORT		= qw(slashDisplay getDisplayBlock);

my $template = Template->new(
	TRIM		=> 1,
	PRE_CHOMP	=> 1,
	POST_CHOMP	=> 1,
	LOAD_TEMPLATES	=> [ Slash::Display::Provider->new ],
	PLUGINS		=> { Slash => 'Slash::Display::Plugin' },
);

sub slashDisplay {
	my($name, $hashref, $return, $nocomm) = @_;
	my(@comments, $ok, $out);
	return unless $name;
	$hashref ||= {};
	_populate($hashref);

	@comments = (
		"\n\n<!-- start template: $name -->\n\n",
		"\n\n<!-- end template: $name -->\n\n"
	);

	if ($return) {
		$ok = $template->process($name, $hashref, \$out);
		$out = join '', $comments[0], $out, $comments[1]
			unless $nocomm;
		
	} else {
		print $comments[0] unless $nocomm;
		$ok = $template->process($name, $hashref);
		print $comments[1] unless $nocomm;
	}

	apacheLog($template->error) unless $ok;

	return $return ? $out : $ok;
}

# put universal data stuff into each template:
# constants, user, form, env.  each can be overriden
# by passing a hash key of the same name to slashDisplay()
sub _populate {
	my($hashref) = @_;
	$hashref->{constants} = getCurrentStatic()
		unless exists $hashref->{constants};
	$hashref->{user} = getCurrentUser() unless exists $hashref->{user};
	$hashref->{form} = getCurrentForm() unless exists $hashref->{form};
	$hashref->{env} = { map { (lc $_, $ENV{$_}) } keys %ENV }
		unless exists $hashref->{env}; 
}

1;

__END__

=head1 NAME

Slash::Display - Display library for Slash


=head1 SYNOPSIS

	slashDisplay('some template', { key => $val });
	my $data = slashDisplay('template', $hashref, 1);


=head1 DESCRIPTION

Process and display a template using the data passed in.
In addition to whatever data is passed in the hashref, the contents
of the user, form, and static objects, as well as the %ENV hash,
are available.

C<slashDisplay()> will print by default to STDOUT, but will
instead return the data if the third parameter is true.  If the fourth
parameter is true, HTML comments surrounding the template will NOT
be printed or returned.  That is, if the fourth parameter is false,
HTML comments noting the beginning and end of the template will be
printed or returned along with the template.

L<Template> for more information about templates.


=head1 EXPORT

One function is exported: slashDisplay.


=head1 AUTHOR

Chris Nandor E<lt>pudge@pobox.comE<gt>, http://pudge.net/


=head1 SEE ALSO

Template, Slash, Slash::Utility, Slash::Display::Plugin.
