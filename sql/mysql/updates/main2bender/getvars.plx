#!/usr/bin/perl -s
# pudge@pobox.com 2000.08.29

use strict;
use Data::Dumper;
use Slash::DB;

my $slashdb = Slash::DB->new('slash');

local $Data::Dumper::Indent = 0;  # all one one line
require 'slashdotrc.pl';
my $conf = $Slash::conf{$$};

$slashdb->sqlDo('ALTER TABLE vars MODIFY name VARCHAR(32) NOT NULL');
$slashdb->sqlDo('ALTER TABLE vars MODIFY value TEXT');
$slashdb->sqlDo('ALTER TABLE vars MODIFY description VARCHAR(127)');
$slashdb->sqlDo('ALTER TABLE vars ADD datatype VARCHAR(10)');
$slashdb->sqlDo('ALTER TABLE vars ADD dataop VARCHAR(12)');

my %skip = map {($_ => 1)} qw(
	adfu_dbpass adfu_dbuser adfu_dsn dbpass dbuser dsn fixhrefs
);

$conf->{anonymous_coward_uid} = $conf->{anonymous_coward};

for my $key (sort keys %$conf) {
	next if exists $skip{$key};
	my $val	 = $conf->{$key};
	my $type = ref $val;
	my($value, $datatype);
	if ($type) {
		$datatype = $type eq 'ARRAY' ? 'arrayref'
			: $type eq 'HASH' ? 'hashref' : 'unknown';
		($value = Dumper $val) =~ s/^\$VAR\d+ = //;
	} else {
		$datatype = 'scalar';
		$value = $val;
	}
	$value = $slashdb->{dbh}->quote($value);

	my $sql = "INSERT INTO vars VALUES ('$key',$value,'','$datatype','value')";
	print $sql, "\n";
	$slashdb->sqlDo($sql8¤ì5ô45}}9}|