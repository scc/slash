#!/usr/bin/perl -w
use strict;
use Slash::DB;
use URI;

# note!  this will NOT take care of stuff like OSDN, where we have added
# new fields to sectionblocks.  we may want to ask MySQL for the column
# names for both tables, check for conflicts (aside from bid, of course),
# and then fail if there are conflicts, and proceed if there are not.
# i dunno, just a thought.  -- pudge

# this script adds all the columns that exist in sectionblocks
# into blocks, and then selects all the data from blocks and 
# inserts the data into the new fields, so that there's only 
# one blocks table
my $slashdb = Slash::DB->new("slash");

my $sectionblocks_arrayref = $slashdb->sqlSelectAll("bid,section,ordernum,title,portal,url,rdf,retrieve","sectionblocks");

$slashdb->sqlDo("alter table blocks add column section varchar(30) NOT NULL DEFAULT ''");
$slashdb->sqlDo("alter table blocks add column ordernum tinyint(4) DEFAULT 0");
$slashdb->sqlDo("alter table blocks add column title varchar(128)");
$slashdb->sqlDo("alter table blocks add column portal tinyint(4) DEFAULT 0");
$slashdb->sqlDo("alter table blocks add column url varchar(128)");
$slashdb->sqlDo("alter table blocks add column rdf varchar(255)");
$slashdb->sqlDo("alter table blocks add column retrieve int(1) DEFAULT 0");
$slashdb->sqlDo("alter table blocks add index section(section)");

for (@{$sectionblocks_arrayref}) {
	my($bid,$section,$ordernum,$title,$portal,$url,$rdf,$retrieve) = @{$_};
	print "bid $bid\n";
	$slashdb->sqlUpdate('blocks', 
		{ 
		section		=> $section,
		ordernum 	=> $ordernum,
		title		=> $title,
		portal		=> $portal,
		url		=> $url,
		rdf		=> $rdf,
		retrieve	=> $retrieve
		},
		"bid = '$bid'");
}

# not needed
#$slashdb->finish;
$slashdb->disconnect;
exit(0);
