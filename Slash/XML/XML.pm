package Slash::XML;

use strict;
use Slash;
use XML::RSS;

require Exporter;

@Slash::XML::ISA = qw(Exporter AutoLoader);
@Slash::XML::EXPORT = qw( 
	xmlDisplay
);
$Slash::XML::VERSION = '0.01';

sub xmlDisplay {
	my ($type, $type_param, $param) = @_;
	#Until I get around to adding XML::OCS $type is ignored

	my $content = create_rss($type_param);
	return unless $content;

	if($param->{apache}) {
		my $r = Apache->request;
		$r->header_out('Cache-Control', 'private');
		$r->content_type('text/xml');
		$r->status(200);
		$r->send_http_header;
		$r->rflush;
		$r->print($content);
		$r->status(200);
	}
}

sub create_rss {
	my ($param) = @_;

	my $constants = getCurrentStatic();

	my $version = $param->{version} ? $param->{version} : '1.0';
	my $encoding = $param->{rdfencoding} ? $param->{rdfencoding} : $constants->{rdfencoding};

	my $rss = XML::RSS->new(
		version		=> $version,
		encoding	=> $encoding,
	);

	if($param->{channel}) {
		my $title = $param->{channel}{title} ? $param->{channel}{title} : $constants->{sitename};
		my $description = $param->{channel}{description} ? $param->{channel}{description} : $constants->{sitename};
		my $link = $param->{channel}{link} ? $param->{channel}{link} : $constants->{sitename};

		$rss->channel(
			title		=> xmlencode($title),
			description	=> xmlencode($description),
			'link'		=> xmlencode_plain($link),
		);
	} else {
		return;
	}

	if($param->{image}) {
		my $title = $param->{image}{title} ? $param->{image}{title} : $constants->{sitename};
		my $description = $param->{image}{description} ? $param->{image}{description} : $constants->{sitename};
		my $link = $param->{image}{link} ? $param->{image}{link} : $constants->{sitename};

		$rss->image(
			title		=> xmlencode($title),
			description	=> xmlencode($description),
			'link'		=> xmlencode_plain($link),
		);
	}


	if($param->{items}) {
		for my $item (@{$param->{items}}) {
			if( $item->{title} and $item->{link}) {
				my $encoded_item;
				for my $key (keys %$item) {
					$encoded_item->{$key} = ($key eq 'link') ? xmlencode_plain($item->{$key}) : xmlencode($item->{$key});
				}
				$rss->add_item($encoded_item);
			}
		}
	} else {
		return;
	}

	return $rss->as_string;
}

1;
__END__
# Below is the stub of documentation for your module. You better edit it!

=head1 NAME

Slash::XML - Perl extension for Slash.

=head1 SYNOPSIS

  use Slash::XML;
  xmlDisplay();

=head1 DESCRIPTION

Take the red one first before trying to understand.

=head1 AUTHOR

Arthur Dent, lost@clue.no

=head1 SEE ALSO

perl(1).

=cut
