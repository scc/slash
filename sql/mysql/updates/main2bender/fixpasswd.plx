#!/usr/bin/perl
# make all passwords MD5'd ... yummy
# pudge@pobox.com, 2000.08.28 - 2000.08.29

use strict;
use Digest::MD5 'md5_hex';
use Slash::DB;

my $slashdb = Slash::DB->new('slash');

print "Modifying users.passwd ...\n";
$slashdb->sqlDo('ALTER TABLE users MODIFY passwd varchar(32) NOT NULL');
print "Adding users.newpasswd ...\n";
$slashdb->sqlDo('ALTER TABLE users ADD newpasswd varchar(32)');

print "Changing existing passwords from plaintext to MD5 ...\n";
my $c;
my $sth = $slashdb->sqlSelectMany('uid,passwd', 'users');
while (my($uid,$passwd) = $sth->fetchrow) {
	$slashdb->sqlUpdate('users', { passwd => md5_hex($passwd) },
		"uid=$uid"
	);
	$c++;
	printf "%d\n", $c if $c =~ /000$/;
}

$sth->finish;

print "Done.\n";

__END__
