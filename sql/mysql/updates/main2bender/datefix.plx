#!/usr/bin/perl
# datefix.plx convert dateformats to perl Date::Manip 
# formats

use strict;
use Slash::DB;

my $timeformats = {
	'%M' => '%B',
	'%W' => '%A',
	'%D' => '%E',
	'%Y' => '%Y',
	'%y' => '%y',
	'%a' => '%a',
	'%d' => '%d',
	'%e' => '%e',
	'%c' => '%f',
	'%m' => '%m',
	'%b' => '%b',
	'%j' => '%j',
	'%H' => '%H',
	'%k' => '%k',
	'%h' => '%I',
	'%I' => '%I',
	'%l' => '%i',
	'%i' => '%M',
	'%r' => '%r',
	'%T' => '%T',
	'%S' => '%S',
	'%s' => '%S',
	'%p' => '%p',
	'%w' => '%w',
	'%U' => '%U',
	'%u' => '%W',
	'%%' => '%%'
};
my $slashdb = Slash::DB->new('slash');

my $dateformats_arrayref = $slashdb->sqlSelectAll("*","dateformats");
print "Changing dateformats from mysql format to perl Date::Manip format...\n";

for (@{$dateformats_arrayref}) {
	my $perl_format = $_->[1];
	print "mysql format: $_->[1] ";
	$perl_format =~ s/(\%\w)/$timeformats->{$1}/g;
	print "perl format: $perl_format\n";
	$slashdb->sqlUpdate('dateformats', { format => $perl_format, }, "id = '$_->[0]'");
}

print "Done.\n";
exit(0);
