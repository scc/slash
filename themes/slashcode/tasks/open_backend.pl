#!/usr/bin/perl -w

# Need to pass the four passed-in vars to the newxxx() routines

use XML::Parser::Expat;
use XML::RSS 0.95;

use strict;
my $me = 'open_backend.pl';

use vars qw( %cron );

$cron{$me}{timespec} = '10 * * * *';
$cron{$me}{code} = sub {

	my($virtual_user, $constants, $slashdb, $user) = @_;

	newxml(@_);
	newrdf(@_);
	newwml(@_);
	newrss(@_);

	my $sections = $slashdb->getSections();
	for (keys %$sections) {
		my($section) = $sections->{$_}->{section};
		newxml(@_, $section);
		newrdf(@_, $section);
	}

};

sub save2file {
	my($f, $d) = @_;
	local *FH;
	open FH, ">$f" or die "Can't open $f: $!";
	print FH $d;
	close FH;
}

sub site2file {
	my($virtual_user, $constants, $slashdb, $user, $section) = @_;
	(my $file = $section || lc $constants->{sitename}) =~ s/\W+//g;
	return $file;
}

sub date2iso8601 {
	my($time) = @_;
	if ($time) {    # force to GMT
		$time .= ' GMT';
	} else {        # get current seconds
		$time = 'epoch ' . time();
	}

	# calculate timezone differential from GMT
	my $diff = (timelocal(localtime) - timelocal(gmtime)) / 36;
	($diff = sprintf "%+0.4d", $diff) =~ s/(\d{2})$/:$1/;

	return scalar UnixDate($time, "%Y-%m-%dT%H:%M$diff");
}

sub newrdf {	# RSS 0.9
	my($virtual_user, $constants, $slashdb, $user, $section) = @_;
	my $stories_and_topics = $slashdb->getBackendStories($section);
	my $rss = XML::RSS->new(
		version => '0.9',
		$constants->{rdfencoding} ? (encoding => $constants->{rdfencoding}) : ()
	);

	my $SECT = getSection($section);
	my $title = $SECT->{isolate}
		? $SECT->{title}
		: "$constants->{sitename}: $SECT->{title}";

	$rss->channel(
		title		=> xmlencode($title),
		'link'		=> xmlencode_plain($constants->{absolutedir} . ($section ? "/index.pl?section=$section" : '/')),
#		language	=> $constants->{rdflanguage},
		description	=> xmlencode($constants->{slogan}),
	);

	$rss->image(
		title		=> xmlencode($constants->{sitename}),
		url		=> xmlencode($constants->{rdfimg}),
		'link'		=> xmlencode_plain($constants->{absolutedir} . '/'),
	);


	for my $section (@$stories_and_topics) {
		$rss->add_item(
			title	=> xmlencode($section->{title}),
			'link'	=> xmlencode_plain("$constants->{absolutedir}/article.pl?sid=$section->{sid}"),
		);
	}

	my $file = site2file($virtual_user, $constants, $slashdb, $user, $section);
	$rss->save("$constants->{basedir}/$file.rdf");
}

sub newrss {	# RSS 1.0
	my($virtual_user, $constants, $slashdb, $user, $section) = @_;
	my $rss = XML::RSS->new(
		version => '1.0',
		$constants->{rdfencoding}
			? (encoding => $constants->{rdfencoding})
			: ()
	);

	$rss->add_module(
		prefix	=> 'slash',
		uri	=> 'http://slashcode.com/rss/1.0/modules/Slash/',
	);

	my $SECT = getSection($section);
	my $title = $section
		? $SECT->{isolate}
			? $SECT->{title}
			: "$constants->{sitename}: $SECT->{title}"
		: $constants->{sitename};

	$rss->channel(
		title		=> xmlencode($title),
		description	=> xmlencode($constants->{slogan}),
		'link'		=> xmlencode_plain($constants->{absolutedir} .
			($section ? "/index.pl?section=$section" : '/')),

		dc => {
			date		=> date2iso8601(),
			subject		=> xmlencode($constants->{rdfsubject}),
			language	=> $constants->{rdflanguage},
			creator		=> xmlencode($constants->{adminmail}),
			publisher	=> xmlencode($constants->{rdfpublisher}),
			rights		=> xmlencode($constants->{rdfrights}),
		},

		syn => {
			updatePeriod	=> $constants->{rdfupdateperiod},
			updateFrequency	=> $constants->{rdfupdatefrequency},
			updateBase	=> $constants->{rdfupdatebase},
		},
	);

	$rss->image(
		title		=> xmlencode($constants->{sitename}),
		url		=> xmlencode($constants->{rdfimg}),
		'link'		=> xmlencode_plain($constants->{absolutedir} . '/'),
	);

	$rss->textinput(
		title		=> 'Search ' . xmlencode($constants->{sitename}),
		description	=> 'Search ' . xmlencode($constants->{sitename}) . ' stories',
		name		=> 'query',
		'link'		=> xmlencode_plain("$constants->{absolutedir}/search.pl"),
	);

	my $stories_and_topics = $slashdb->getBackendStories($section);
	for my $story (@$stories_and_topics) {
		my $desc;
		if ($constants->{rdfitemdesc} == 1) {
			$desc = $story->{introtext};
		} elsif ($constants->{rdfitemdesc}) {
			$desc = balanceTags(
				chopEntity($story->{introtext}, $constants->{rdfitemdesc})
			);
		}

		my %data = (
			title		=> xmlencode($story->{title}),
			'link'		=> xmlencode_plain("$constants->{absolutedir}/article.pl?sid=$story->{sid}"),

			dc => {
				date		=> date2iso8601($story->{'time'}),
				subject		=> xmlencode($story->{tid}),
				creator		=> xmlencode($slashdb->getUser($story->{uid}, 'nickname')),
			},

			slash => {
				section		=> xmlencode($story->{section}),
				comments	=> $story->{commentcount},
				hitparade	=> $story->{hitparade},
			},
		);

		$data{description}       = xmlencode($desc) if $desc;
		$data{slash}{department} = xmlencode($story->{dept}) if $constants->{use_dept};

		$rss->add_item(%data);
	}

	my $file = site2file($virtual_user, $constants, $slashdb, $user, $section);
	$rss->save("$constants->{basedir}/$file.rss");
}

sub newwml {
	my($virtual_user, $constants, $slashdb, $user, $section) = @_;
	my $stories_and_topics = $slashdb->getBackendStories($section);

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
	for my $section (@$stories_and_topics) {
		$x .= qq|<option title="View" onpick="/wml.pl?sid=$section->{sid}">| .
			xmlencode(strip_nohtml($section->{title})) . 
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
	my($virtual_user, $constants, $slashdb, $user, $section) = @_;
	my $stories_and_topics = $slashdb->getBackendStories($section);

	my $x = <<EOT;
<?xml version="1.0"?><backslash
xmlns:backslash="$constants->{rootdir}/backslash.dtd">

EOT

	for my $section (@$stories_and_topics) {
		my @str = (xmlencode($section->{title}), xmlencode($section->{dept}));
		$x.= <<EOT;
	<story>
		<title>$str[0]</title>
		<url>$constants->{rootdir}/article.pl?sid=$section->{sid}</url>
		<time>$section->{'time'}</time>
		<author>$section->{aid}</author>
		<department>$str[1]</department>
		<topic>$section->{tid}</topic>
		<comments>$section->{commentcount}</comments>
		<section>$section->{section}</section>
		<image>$section->{image}</image>
	</story>

EOT
	}

	$x .= "</backslash>\n";

	my $file = site2file($virtual_user, $constants, $slashdb, $user, $section);
	save2file("$constants->{basedir}/$file.xml", $x);
}

1;

