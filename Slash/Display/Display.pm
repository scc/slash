package Slash::Display;

=head1 NAME

Slash::Display - Display library for Slash


=head1 SYNOPSIS

	slashDisplay('some template', { key => $val });
	my $data = slashDisplay('template', $hashref, 1);


=head1 DESCRIPTION

Slash::Display uses Slash::Display::Provider to provide the
template data from the Slash::DB API.

It will process and display a template using the data passed in.
In addition to whatever data is passed in the hashref, the contents
of the user, form, and static objects, as well as the %ENV hash,
are available.

C<slashDisplay> will print by default to STDOUT, but will
instead return the data if the third parameter is true.  If the fourth
parameter is true, HTML comments surrounding the template will NOT
be printed or returned.  That is, if the fourth parameter is false,
HTML comments noting the beginning and end of the template will be
printed or returned along with the template.

L<Template> for more information about templates.

=head1 EXPORTED FUNCTIONS

=over 4

=cut

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
@EXPORT		= qw(slashDisplay slashDisplaySection);

# BENDER: Well I don't have anything else planned for today, let's get drunk!

#========================================================================

=item slashDisplay(NAME [, DATA, RETURN, NOCOMM])

Processes a template.

Parameters

	NAME
	Can be either the name of a template block in the Slash DB,
	or a reference to a scalar containing a template to be
	processed.  In both cases, the template will be compiled
	and the processed, unless it has previously been compiled,
	in which case the cached, compiled template will be pulled
	out and processed.

	DATA
	Hashref of additional parameters to pass to the template.
	Default passed parameters include constants, env, user, and
	form, which can be overriden (see C<_populate>).

	RETURN
	Boolean for whether to print (false) or return (true) the
	processed template data.

	NOCOMM
	Boolean for whether to print (true) or not print (false)
	HTML comments surrounding template, stating what template
	block this is.

Return value

	If RETURN is true, the processed template data.  Otherwise,
	returns true/false for success/failure.

Side effects

	Compiles templates and caches them.

=cut

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

	my $template = _template();

	if ($return) {
		$ok = $template->process($name, $hashref, \$out);
		$out = join '', $comments[0], $out, $comments[1]
			unless $nocomm;
		
	} else {
		print $comments[0] unless $nocomm;
		$ok = $template->process($name, $hashref);
		print $comments[1] unless $nocomm;
	}

	errorLog($template->error) unless $ok;

	return $return ? $out : $ok;
}

#========================================================================

=item slashDisplaySection(NAME [, DATA, RETURN, NOCOMM])

Processes a template by section.  Determines proper name to use,
then calls C<slashDisplay>.

Should C<slashDisplay> do this automatically?  If it had a persistent
hash or quick way to look up block IDs, we could do it efficiently.
Also, is there ever a time we don't want a section block to override
the default if it exists?

Parameters

	NAME
	We try to find a template block of this name in the current
	section (or if the user has "light" mode, we use that).  If
	NAME is not a reference, and there is a current section, and
	there is a section block for that section and NAME, then
	that NAME (SECTION_NAME) is used.  Otherwise, the NAME by
	itself is used.  Then all the passed data (with the new
	NAME) is passed to slashDisplay.

	DATA
	See slashDisplay.

	RETURN
	See slashDisplay.

	NOCOMM
	See slashDisplay.

Return value

	See slashDisplay.

Side effects

	See slashDisplay.

=cut

sub slashDisplaySection {
	my $name = shift;  # yes, shift
	my $slashdb = getCurrentDB();
	my $thissect = getCurrentUser('light') ? 'light' : getCurrentStatic('currentSection');

	if (!ref $name && $thissect && $slashdb->getBlock($thissect . "_$name", 'block')) {
		slashDisplay($thissect . "_$name", @_);
	} else {
		slashDisplay($name, @_);
	}
}

#========================================================================

=back

=head2 PRIVATE FUNCTIONS

=over 4

=item _populate(DATA)

Private function.  Put universal data stuff into each template:
constants, user, form, env.  Each can be overriden
by passing a hash key of the same name to C<slashDisplay>.

Parameters

	DATA
	A hashref to be populated.

Return value

	Populated hashref.

=cut

sub _populate {
	my($hashref) = @_;
	$hashref->{constants} = getCurrentStatic()
		unless exists $hashref->{constants};
	$hashref->{user} = getCurrentUser() unless exists $hashref->{user};
	$hashref->{form} = getCurrentForm() unless exists $hashref->{form};
	$hashref->{env} = { map { (lc $_, $ENV{$_}) } keys %ENV }
		unless exists $hashref->{env}; 
}

#========================================================================

=item _template()

Return a Template object.

Return value

	A Template object (see below).

=cut

my $filters;

sub _template {
	Template->new(
		TRIM		=> 1,
		PRE_CHOMP	=> 1,
		POST_CHOMP	=> 1,
		LOAD_FILTERS	=> $filters,
		LOAD_TEMPLATES	=> [ Slash::Display::Provider->new ],
		PLUGINS		=> { Slash => 'Slash::Display::Plugin' },
	);
}

=back

=head1 TEMPLATE ENVIRONMENT

The template has the options TRIM, PRE_CHOMP, and POST_CHOMP set by default.
Its provider is Slash::Display::Provider, and the plugin module
Slash::Display::Plugin can be referenced by simply "Slash".

Additional scalar ops (which are global, so they are in effect
for every Template object created, from this or any other module)
include C<uc>, C<lc>, C<ucfirst>, and C<lcfirst>,
which all do what you think.

	[% myscalar.uc %]  # return upper case myscalar

Additional list ops include C<rand>, which returns a random element
from the given list.

	[% mylist.rand %]  # return single random element from mylist

Also provided are some filters.  The C<fixurl>, C<fixparam>, and
C<stripByMode> filters are just frontends to the functions of those
names in the Slash API:

	[% FILTER stripByMode('literal') %]
		I think that 1 > 2!
	[% END %]

	<A HREF="[% env.script_name %]?op=[% FILTER fixparam %][% form.op %][% END %]">

=cut

require Template::Filters;

$filters = Template::Filters->new({
	FILTERS => {
		fixparam	=> \&fixparam,
		fixurl		=> \&fixurl,
		stripByMode	=> [ \&myStripByMode => 1 ]
	}
});

sub myStripByMode {
	my($context, @args) = @_;
	return sub { stripByMode($_[0], @args) };
}


require Template::Stash;

$Template::Stash::LIST_OPS->{'rand'} = sub {
	my $list = shift;
	return $list->[rand @$list];
};

$Template::Stash::SCALAR_OPS->{'uc'} = sub { uc $_[0] };
$Template::Stash::SCALAR_OPS->{'lc'} = sub { lc $_[0] };
$Template::Stash::SCALAR_OPS->{'ucfirst'} = sub { ucfirst $_[0] };
$Template::Stash::SCALAR_OPS->{'lcfirst'} = sub { lcfirst $_[0] };

1;

__END__


=head1 AUTHOR

Chris Nandor E<lt>pudge@pobox.comE<gt>, http://pudge.net/


=head1 SEE ALSO

Template, Slash, Slash::Utility, Slash::DB, Slash::Display::Plugin.
