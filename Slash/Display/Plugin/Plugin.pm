package Slash::Display::Plugin;

use strict;
use vars qw($REVISION $VERSION $AUTOLOAD);
use Slash ();
use Slash::Utility ();
use Template::Plugin ();
use base qw(Template::Plugin);

# $Id$
($REVISION)	= ' $Revision$ ' =~ /\$Revision:\s+([^\s]+)/;
($VERSION)	= $REVISION =~ /^(\d+\.\d+)/;

# BENDER: Forget your stupid theme park!  I'm gonna make my own!
# With hookers!  And blackjack!  In fact, forget the theme park!

my %subs;
sub _populate {
	return if %subs;
	# mmmmmm, agic
	no strict 'refs';
	for my $pkg (qw(Slash Slash::Utility)) {
		@subs{@{"${pkg}::EXPORT"}} =
			map { *{"${pkg}::$_"}{CODE} } @{"${pkg}::EXPORT"};
	}
}

sub new {
	_populate();
	my($class, $context, $name) = @_;
	return bless {
		_CONTEXT => $context,
	}, $class;
}

sub db { Slash::Utility::getCurrentDB() }

sub AUTOLOAD {
	# pull off class name before sending to function;
	# that's the whole reason we have AUTOLOAD here at all
	shift;
	(my $name = $AUTOLOAD) =~ s/^.*://;
	return if $name eq 'DESTROY';

	if (exists $subs{$name}) {
		goto &{$subs{$name}};
	} else {
		warn "Can't find $name";
		return;
	}
}

1;

__END__

=head1 NAME

Slash::Display::Plugin - Template Toolkit plugin for Slash


=head1 SYNOPSIS

	[% USE Slash %]
	[% Slash.someFunction('some data') %]
	[% Slash.db.someMethod(var1, var2) %]


=head1 DESCRIPTION

Call functions in Slash and Slash::Utility.  Also call methods from Slash::DB
with the C<db> method.  Invoke with C<[% USE Slash %]>.


=head1 AUTHOR

Chris Nandor E<lt>pudge@pobox.comE<gt>, http://pudge.net/


=head1 SEE ALSO

Template, Slash, Slash::Utility, Slash::Display.
