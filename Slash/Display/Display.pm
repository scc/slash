package Slash::Display;

use strict;
use vars qw($VERSION @EXPORT @ISA);
use Exporter ();
use Slash::Display::Provider;
use Slash::Utility;
use Template;

@ISA = 'Exporter';
$VERSION = '0.01';
@EXPORT = qw(slashDisplay getDisplayBlock);

my $template = Template->new(
	TRIM		=> 1,
	PRE_CHOMP	=> 1,
	POST_CHOMP	=> 1,
	COMPILE_DIR	=> '/home/slash/display/',  # needs to be virtual user
	LOAD_TEMPLATES	=> [
		Slash::Display::Provider->new,
	],
#	PLUGINS		=> {
#		Slash	=> 'Slash::Display::Plugin'
#	}
);

sub template { $template }

sub slashDisplay {
	my($name, $hashref, $return) = @_;
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
		$out = join '', $comments[0], $out, $comments[1];
		
	} else {
		print $comments[0];
		$ok = $template->process($name, $hashref);
		print $comments[1];
	}

	apacheLog($template->error) unless $ok;

	return $return ? $out : $ok;
}

sub _populate {
	my($hashref) = @_;
	$hashref->{user} = getCurrentUser() unless exists $hashref->{user};
	$hashref->{form} = getCurrentForm() unless exists $hashref->{form};
	$hashref->{constants} = getCurrentStatic()
		unless exists $hashref->{constants};
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
instead return the data if the third parameter is true.

L<Template> for more information about templates.

The C<Slash.display()> method can be called in a template to process
and display another template.  L<Slash::Display::Plugin> for more
information.

=head1 EXPORT

One function is exported: slashDisplay.

=head1 AUTHOR

Chris Nandor E<lt>pudge@pobox.comE<gt>, http://pudge.net/

=head1 SEE ALSO

Template, Slash, Slash::Utility, Slash::Display::Plugin.
