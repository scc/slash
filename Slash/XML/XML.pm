# This code is a part of Slash, and is released under the GPL.
# Copyright 1997-2001 by Open Source Development Network. See README
# and COPYING for more information, or see http://slashcode.com/.
# $Id$

package Slash::XML;

=head1 NAME

Slash::XML - Perl extension for Slash.

=head1 SYNOPSIS

	use Slash::XML;
	xmlDisplay(%data);

=head1 DESCRIPTION

Slash::XML aids in creating XML.  Right now, only RSS is supported.


=head1 EXPORTED FUNCTIONS

=cut

use strict;
use Date::Manip;
use Slash;
use Slash::Utility;
use Time::Local;
use XML::RSS;

use base 'Exporter';
use vars qw($VERSION @EXPORT);

($VERSION) = ' $Revision$ ' =~ /\$Revision:\s+([^\s]+)/;
@EXPORT = qw(xmlDisplay);

# FRY: There must be layers and layers of old stuff down there!

my %types = (
	rss	=> \&create_rss,
);

#========================================================================

sub xmlDisplay {
	my($type, $param, $opt) = @_;

	return unless exists $types{$type};

	if (! ref $opt) {
		$opt = $opt == 1 ? { Return => 1 } : {};
	}

	my $content = $types{$type}->($param);
	return unless $content;

	if ($opt->{Return}) {
		return $content;
	} else {
		my $r = Apache->request;
		$r->header_out('Cache-Control', 'private');
		$r->content_type('text/xml');
		$r->status(200);
		$r->send_http_header;
		$r->rflush;
		$r->print($content);
		$r->status(200);
		return 1;
	}
}

#========================================================================

sub create_rss {
	my($param) = @_;

	return unless exists $param->{items};

	my $constants = getCurrentStatic();

	my $version  = $param->{version} || '1.0';
	my $encoding = $param->{rdfencoding} || $constants->{rdfencoding};

	my $rss = XML::RSS->new(
		version		=> $version,
		encoding	=> $encoding,
	);

	# set defaults
	my %channel = (
		title		=> $constants->{sitename},
		description	=> $constants->{slogan},
		'link'		=> $constants->{absolutedir} . '/',

		# dc
		date		=> date2iso8601(),
		subject		=> $constants->{rdfsubject},
		language	=> $constants->{rdflanguage},
		creator		=> $constants->{adminmail},
		publisher	=> $constants->{rdfpublisher},
		rights		=> $constants->{rdfrights},

		# syn
		updatePeriod	=> $constants->{rdfupdateperiod},
		updateFrequency	=> $constants->{rdfupdatefrequency},
		updateBase	=> $constants->{rdfupdatebase},
	);

	# let $param->{channel} override
	for (keys %channel) {
		my $value = defined $param->{channel}{$_}
			? $param->{channel}{$_}
			: $channel{$_};
		$channel{$_} = encode($value, $_);
	}

	if ($version >= 1.0) {
		# move from root to proper namespace
		for (qw(date subject language creator publisher rights)) {
			$channel{dc}{$_} = delete $channel{$_};
		}

		for (qw(updatePeriod updateFrequency updateBase)) {
			$channel{syn}{$_} = delete $channel{$_};
		}

		my($item) = @{$param->{items}};
		$rss->add_module(
			prefix  => 'slash',
			uri     => 'http://slashcode.com/rss/1.0/modules/Slash/',
		) if $item->{story};

	} elsif ($version >= 0.91) {
		# fix mappings for 0.91
		$channel{language}       = substr($channel{language}, 0, 2);
		$channel{pubDate}        = delete $channel{date};
		$channel{managingEditor} = delete $channel{publisher};
		$channel{webMaster}      = delete $channel{creator};
		$channel{copyright}      = delete $channel{rights};
		
	} else {  # 0.9
		for (keys %channel) {
			delete $channel{$_} unless /^(?:link|title|description)$/;
		}
	}

	# OK, now set it
	$rss->channel(%channel);

	# may be boolean
	if ($param->{image}) {
		# set defaults
		my %image = (
			title	=> $constants->{sitename},
			url	=> $constants->{rdfimg},
			'link'	=> $constants->{absolutedir} . '/',
		);

		# let $param->{image} override
		if (ref($param->{image}) eq 'HASH') {
			for (keys %image) {
				my $value = defined $param->{image}{$_}
					? $param->{image}{$_}
					: $image{$_};
				$image{$_} = encode($value, $_);
			}
		}

		# OK, now set it
		$rss->image(%image);
	}

	# may be boolean
	if ($param->{textinput}) {
		# set defaults
		my %textinput = (
			title		=> "Search " . $constants->{sitename},
			description	=> "Search " . $constants->{sitename} . " stories",
			name		=> 'query',
			'link'		=> $constants->{absolutedir} . '/search.pl',
		);

		# let $param->{textinput} override
		if (ref($param->{image}) eq 'HASH') {
			for (keys %textinput) {
				my $value = defined $param->{textinput}{$_}
					? $param->{textinput}{$_}
					: $textinput{$_};
				$textinput{$_} = encode($value, $_);
			}
		}

		# OK, now set it
		$rss->textinput(%textinput);
	}

	my @items;
	for my $item (@{$param->{items}}) {
		if ($item->{story} || ($item->{title} && $item->{'link'})) {
			my $encoded_item = {};

			# story is hashref to be deleted, containing
			# story data
			if ($item->{story}) {
				# set up story params in $encoded_item ref
				rss_story($item, $encoded_item, $version);
			}

			for my $key (keys %$item) {
				$encoded_item->{$key} = encode($item->{$key}, $key);
			}

			push @items, $encoded_item if keys %$encoded_item;
		}
	}

	return unless @items;
	for (@items) {
		$rss->add_item(%$_);
	}

	return $rss->as_string;
}

#========================================================================
# get a standard ISO 8601 time string
sub date2iso8601 {
	my($time) = @_;
	if ($time) {	# force to GMT
		$time .= ' GMT';
	} else {	# get current seconds
		$time = 'epoch ' . time();
	}

	# calculate timezone differential from GMT
	my $diff = (timelocal(localtime) - timelocal(gmtime)) / 36;
	($diff = sprintf "%+0.4d", $diff) =~ s/(\d{2})$/:$1/;

	return scalar UnixDate($time, "%Y-%m-%dT%H:%M$diff");
}

#========================================================================
# set up a story item
sub rss_story {
	my($item, $encoded_item, $version) = @_;

	# delete it so it won't be processed later
	my $story = delete $item->{story};
	my $constants = getCurrentStatic();

	$encoded_item->{title}  = encode($story->{title});
	$encoded_item->{'link'} = encode("$constants->{absolutedir}/article.pl?sid=$story->{sid}", 'link');

	if ($version >= 0.91) {
		my $desc = rss_item_description($item->{description});
		$encoded_item->{description} = encode($desc) if $desc;
	}

	if ($version >= 1.0) {
		my $slashdb   = getCurrentDB();

		$encoded_item->{dc}{date}    = encode(date2iso8601($story->{'time'}));
		$encoded_item->{dc}{subject} = encode($story->{tid});
		$encoded_item->{dc}{creator} = encode($slashdb->getUser($story->{uid}, 'nickname'));

		$encoded_item->{slash}{section}    = encode($story->{section});
		$encoded_item->{slash}{comments}   = encode($story->{commentcount});
		$encoded_item->{slash}{hitparade}  = encode($story->{hitparade});
		$encoded_item->{slash}{department} = encode($story->{dept})
			if $constants->{use_dept};
	}

	return $encoded_item;
}

#========================================================================
# set up an item description
sub rss_item_description {
	my($desc) = @_;

	my $constants = getCurrentStatic();
	
	if ($constants->{rdfitemdesc} == 1) {
		# keep $desc as-is
	} elsif ($constants->{rdfitemdesc}) {
		# limit length of $desc
		$desc = balanceTags(chopEntity($desc, $constants->{rdfitemdesc}));
		return $desc;
	} else {
		undef $desc;
	}

	return $desc;
}

#========================================================================
sub encode {
	my($value, $key) = @_;
	$key ||= '';
	my $return = $key eq 'link'
		? xmlencode_plain($value)
		: xmlencode($value);
	return $return;
}

1;

__END__

=head1 SEE ALSO

Slash(3), Slash::Utility(3), XML::Parser(3), XML::RSS(3).
