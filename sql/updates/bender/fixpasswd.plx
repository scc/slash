#!/usr/bin/perl
# make all passwords MD5'd ... yummy
# pudge@pobox.com, 2000.08.28

use strict;
use Digest::MD5 'md5_hex';
use Slash::DB;

my $slashdb = Slash::DB->new('slash');
my $sth = $slashdb->sqlSelectMany('uid,passwd', 'users');

my $c;
while (my($uid,$passwd) = $sth->fetchrow) {
	$slashdb->sqlUpdate('users', { passwd => md5_hex($passwd) },
		"uid=$uid"
	);
	$c++;
	printf "%d\n", $c if $c =~ /00$/;
}

$sth->finish;

print "Done.\n";

__END__
