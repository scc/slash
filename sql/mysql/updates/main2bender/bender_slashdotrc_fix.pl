#!/usr/bin/perl -w
use strict;
use Slash::DB;
use URI;

unless ($ARGV[0]) {
	print "	\n";
	print "	This is to jumpstart you into Bender. \n";
	print "	Please rerun the command with the first \n";
	print "	argument being the VirtualUser name used \n";
	print "	for this slashsite. \n";
	print "	This will just get you started; you will still \n";
	print "	need to modify some variable in the admin interface \n";
	print "	to get your site running. \n";
	print "	\n";

	exit 0;
}
my $slashdb = Slash::DB->new($ARGV[0]);
my %answers;
my $junk;
print "What will be the install directory? (ie /usr/local/slash)\n";
$junk = <STDIN>;
chomp $junk;
$answers{datadir} = $junk;
print "What is the domain? (aka www.slashcode.com) \n";
$junk = <STDIN>;
chomp $junk;
$answers{basedomain} = $junk;
print "Good to go\n";

while (my ($key, $value) = each %answers) {
	print "Key $key\n";
	print "Value $value\n\n";
#	$slashdb->newVar($key, $value, "Not documented");
#	$slashdb->sqlInsert('vars', {name => $key, value => $slashdb->{dbh}->quote($value)}));
}

