package Slash::Display::Provider;

use strict;
use vars qw($REVISION $VERSION $DEBUG);
use base qw(Template::Provider);
use Slash::Utility;
use Template::Provider;

# $Id$
($REVISION)	= ' $Revision$ ' =~ /\$Revision:\s+([^\s]+)/;
($VERSION)	= $REVISION =~ /^(\d+\.\d+)/;
$DEBUG		= $Template::Provider::DEBUG || 0 unless defined $DEBUG;

# BENDER: Oh, no room for Bender, huh?  Fine.  I'll go build my own lunar
# lander.  With blackjack.  And hookers.  In fact, forget the lunar lander
# and the blackjack!  Ah, screw the whole thing.

use constant PREV => 0;
use constant NAME => 1;
use constant DATA => 2; 
use constant LOAD => 3;
use constant NEXT => 4;

# store names for non-named templates by using text of template as
# hash key
my($anon_num, %anon_template);
sub _get_anon_name {
	my($text) = @_;
	return $anon_template{$text} if exists $anon_template{$text};
	return $anon_template{$text} = 'anon_' . ++$anon_num; 
}

sub fetch {
	my($self, $text) = @_;
	my($name, $siteid, $savename, $data, $error, $slot);
	$siteid = getCurrentStatic('siteid');

	if (ref $text eq 'SCALAR') {
		$savename = $name = _get_anon_name($text);
	} else {
		$name = $text;
		undef $text;

		# $; is multidimensional array emulation separator
		$savename = $siteid . $; . $name;
	}

	print STDERR "fetch($name [$savename])\n" if $DEBUG;

	if ($slot = $self->{ LOOKUP }{ $savename }) {
		# cached entry exists, so refresh slot and extract data
		($data, $error) = $self->_refresh($slot);
		$data = $slot->[ DATA ] unless $error;

	} else {
		# hm ... don't need to compile to disk unless we want
		# a persistent cache ... so forget it for now

		# nothing in cache so try to load, compile and cache
		($data, $error) = $self->_load($name, $text);
		($data, $error) = $self->_compile($data) unless $error; # , $compfile
		$data = $self->_store($savename, $data) unless $error;
	}

	return($data, $error);
}

sub _load {
	my($self, $name, $text) = @_;
	my($data, $error, $now, $slashdb, $siteid, $savename);
	$now = time;
	$siteid = getCurrentStatic('siteid');
	# $; is multidimensional array emulation separator
	$savename = $siteid . $; . $name;

	if (defined $text) {
		$text = $$text;
	} else {
		$slashdb = getCurrentDB();
		$text = $slashdb->getTemplate($name, 'template');
	}

	print STDERR "_load($name [$savename])\n" if $DEBUG;

	if ($text) {
		$data = {
			name	=> $savename,
			text	=> $text,
			'time'	=> $now,   # get cache timestamp!
			load	=> $now,
		};
	}

	return($data, $error);
}

# hm, refresh is almost what we want, except we want to override
# the logic for deciding whether to reload ... can that be determined
# without reimplementing the whole method?
sub _refresh {
	my($self, $slot) = @_;
	my($head, $file, $data, $error);

	print STDERR "_refresh([ @$slot ])\n" if $DEBUG;

	# compare load time with current file modification time to see if
	# its modified and we need to reload it

	# get cache timestamp!  don't refresh until we get it ... somehow ...
	if (0) {
		print STDERR "refreshing cache file ", $slot->[ NAME ], "\n"
			if $DEBUG;

		($data, $error) = $self->_load($slot->[ NAME ]);
		($data, $error) = $self->_compile($data) unless $error;
		$slot->[ DATA ] = $data->{ data } unless $error;
	}

	# remove existing slot from usage chain...
	if ($slot->[ PREV ]) {
		$slot->[ PREV ]->[ NEXT ] = $slot->[ NEXT ];
	} else {
		$self->{ HEAD } = $slot->[ NEXT ];
	}

	if ($slot->[ NEXT ]) {
		$slot->[ NEXT ]->[ PREV ] = $slot->[ PREV ];
	} else {
		$self->{ TAIL } = $slot->[ PREV ];
	}
    
	# ... and add to start of list
	$head = $self->{ HEAD };
	$head->[ PREV ] = $slot if $head;
	$slot->[ PREV ] = undef;
	$slot->[ NEXT ] = $head;
	$self->{ HEAD } = $slot;

	return($data, $error);
}

1;

__END__

=head1 NAME

Slash::Display::Provider - Template Toolkit provider for Slash

=head1 SYNOPSIS

	use Slash::Display::Provider;
	my $template = Template->new(
		LOAD_TEMPLATES	=> [ Slash::Display::Provider->new ]
	);


=head1 DESCRIPTION

This here module provides templates to a Template Toolkit processor
by way of the Slash API (which basically means that it grabs templates
from the blocks table in the database).  It caches them, too.  It also
can process templates passed in as text, like the base Provider module,
but this one will create a unique name for the "anonymous" template so
it can be cached.  Overriden methods include C<fetch>, C<_load>,
and C<_refresh>.


=head1 BUGS

=over 4

=item *

Crap, I think right now caching is not done per virtual host.

=item *

I am not sure how useful the caching is right now, especially the LRU
part.  Rethink.

=item *

We need to find a way to speed up execution of cached templates, if
possible.

=back


=head1 AUTHOR

Chris Nandor E<lt>pudge@pobox.comE<gt>, http://pudge.net/


=head1 SEE ALSO

Template, Template::Provider, Slash, Slash::Utility, Slash::Display.
