package Slash::Display::Provider;

use strict;
use vars qw($VERSION $DEBUG);
use base qw(Template::Provider);
use Slash::Utility;
use Template::Provider;

$VERSION = '0.01';

$DEBUG = 0 unless defined $DEBUG;
$Template::Provider::DEBUG = $DEBUG;

use constant PREV => 0;
use constant NAME => 1;
use constant DATA => 2; 
use constant LOAD => 3;
use constant NEXT => 4;

sub fetch {
	my($self, $name) = @_;
	my($data, $error, $slot);

	print STDERR "fetch($name)\n" if $DEBUG;

	if ($slot = $self->{ LOOKUP }{$name}) {
		# cached entry exists, so refresh slot and extract data
		($data, $error) = $self->_refresh($slot);
		$data = $slot->[ DATA ] unless $error;

	} else {
		# hm ... don't need to compile to disk unless we want
		# a persistent cache ... so forget it for now

		# nothing in cache so try to load, compile and cache
		($data, $error) = $self->_load($name);
		($data, $error) = $self->_compile($data) unless ($error); # , $compfile
		$data = $self->_store($name, $data) unless $error;
	}

	return($data, $error);
}

sub _load {
	my($self, $name) = @_;
	my($data, $error);
	my $now = time;

	print STDERR "_load($name)\n" if $DEBUG;

	my $dbslash = getCurrentDB();
	my $text = $dbslash->getBlock($name, 'block');

	if ($text) {
		$data = {
			name	=> $name,
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



=head1 DESCRIPTION



=head1 AUTHOR

Chris Nandor E<lt>pudge@pobox.comE<gt>, http://pudge.net/

=head1 SEE ALSO

Template, Template::Provider, Slash, Slash::Utility, Slash::Display.
