#!/usr/bin/perl -w

# Need to pass the four passed-in vars to the newxxx() routines

use strict;
use Slash;
use Slash::XML;

use vars qw( %task $me );

$task{$me}{timespec} = '13,43 * * * *';
$task{$me}{code} = sub {

	my($virtual_user, $constants, $slashdb, $user) = @_;

	my $stories = $slashdb->getBackendStories();
	if ($stories and @$stories) {
		newxml(@_, undef, $stories);
		newrdf(@_, undef, $stories);
		newwml(@_, undef, $stories);
		newrss(@_, undef, $stories);
	}

	my $sections = $slashdb->getSections();
	for (keys %$sections) {
		my($section) = $sections->{$_}->{section};
		$stories = $slashdb->getBackendStories($section);
		if ($stories and @$stories) {
			newxml(@_, $section, $stories);
			newrdf(@_, $section, $stories);
			newrss(@_, $section, $stories);
		}
	}

	return ;
};

sub save2file {
	my($f, $d) = @_;
	my $fh = gensym();
	open $fh, ">$f" or die "Can't open $f: $!";
	print $fh $d;
	close $fh;
}

sub site2file {
	my($virtual_user, $constants, $slashdb, $user, $section) = @_;
	(my $file = $section || lc $constants->{sitename}) =~ s/\W+//g;
	return $file;
}

sub newrdf {	# RSS 0.9
	my($virtual_user, $constants, $slashdb, $user, $section, $stories) = @_;

	my $file    = site2file($virtual_user, $constants, $slashdb, $user, $section);
	my $SECT    = $slashdb->getSection($section);
	my $link    = $constants->{absolutedir} .
		($section ? "/index.pl?section=$section" : '/');
	my $title   = $section
		? $SECT->{isolate}
			? $SECT->{title}
			: "$constants->{sitename}: $SECT->{title}"
		: $constants->{sitename};

	my $rss = xmlDisplay('rss', {
		version		=> 0.9,
		title		=> $title,
		'link'		=> $link,
		textinput	=> 1,
		image		=> 1,
		items		=> [ map { { story => $_ } } @$stories ],
	}, 1);
	save2file("$constants->{basedir}/$file.rdf", $rss);
}

sub newrss {	# RSS 1.0
	my($virtual_user, $constants, $slashdb, $user, $section, $stories) = @_;

	my $file    = site2file($virtual_user, $constants, $slashdb, $user, $section);
	my $SECT    = $slashdb->getSection($section);
	my $link    = $constants->{absolutedir} .
		($section ? "/index.pl?section=$section" : '/');
	my $title   = $section
		? $SECT->{isolate}
			? $SECT->{title}
			: "$constants->{sitename}: $SECT->{title}"
		: $constants->{sitename};

	my $rss = xmlDisplay('rss', {
		title		=> $title,
		'link'		=> $link,
		textinput	=> 1,
		image		=> 1,
		items		=> [ map { { story => $_ } } @$stories ],
	}, 1);
	save2file("$constants->{basedir}/$file.rss", $rss);
}

sub newwml {
	my($virtual_user, $constants, $slashdb, $user, $section, $stories) = @_;

	my $x = <<EOT;
<?xml version="1.0"?>
<!DOCTYPE wml PUBLIC "-//PHONE.COM//DTD WML 1.1//EN" "http://www.phone.com/dtd/wml11.dtd" >
<wml>
                        <head><meta http-equiv="Cache-Control" content="max-age=3600" forua="true"/></head>
<!--  Dev  -->

<!-- TOC -->
<card title="$constants->{sitename}" id="$constants->{sitename}">
<do label="Home" type="options">
<go href="/index.wml"/>
</do>
<p align="left"><b>$constants->{sitename}</b>
<select>
EOT

	my $z = 0;
	my $body;
	for my $sect (@$stories) {
		$x .= qq|<option title="View" onpick="/wml.pl?sid=$sect->{sid}">| .
			xmlencode(strip_nohtml($sect->{title})) .
			"</option>\n";
		$z++;
	}

	$x .= <<EOT;
</select>
</p>
</card>
</wml>
EOT

	my $file = site2file($virtual_user, $constants, $slashdb, $user, $section);
	save2file("$constants->{basedir}/$file.wml", $x);
}

sub newxml {
	my($virtual_user, $constants, $slashdb, $user, $section, $stories) = @_;

	my $x = <<EOT;
<?xml version="1.0"?><backslash
xmlns:backslash="$constants->{absolutedir}/backslash.dtd">

EOT

	for my $sect (@$stories) {
		my @str = (xmlencode($sect->{title}), xmlencode($sect->{dept}));
		my $author = $slashdb->getUser($sect->{uid}, 'nickname');
		$x.= <<EOT;
	<story>
		<title>$str[0]</title>
		<url>$constants->{absolutedir}/article.pl?sid=$sect->{sid}</url>
		<time>$sect->{'time'}</time>
		<author>$author</author>
		<department>$str[1]</department>
		<topic>$sect->{tid}</topic>
		<comments>$sect->{commentcount}</comments>
		<section>$sect->{section}</section>
		<image>$sect->{image}</image>
	</story>

EOT
	}

	$x .= "</backslash>\n";

	my $file = site2file($virtual_user, $constants, $slashdb, $user, $section);
	save2file("$constants->{basedir}/$file.xml", $x);
}

1;

