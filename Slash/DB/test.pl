# Before `make install' is performed this script should be runnable with
# `make test'. After `make install' it should work as `perl test.pl'

######################### We start with some black magic to print on failure.

# Change 1..1 below to 1..last_test_to_print .
# (It may become useful if the test is moved to ./t subdirectory.)

BEGIN { $| = 1; print "1..1\n"; }
END {print "not ok 1\n" unless $loaded;}
use Slash::DB;
$loaded = 1;
print "ok 1\n";

######################### End of black magic.

# Insert your test code below (better if it prints "ok 13"
# (correspondingly "not ok 13") depending on the success of chunk 13
# of the test code):

my $object = new Slash::DB('DBI:mysql:database=slash;host=localhost', 'slash', 'newpassword');
print "ok 2\n";
$object->sqlConnect();
print "ok 3\n";
$object->sanityCheck();
print "ok 4\n";
print "Lets grab some user data\n";
my $user = $object->getUserInfo('2', 'change', 'index.pl');
while(my ($key, $val) = each %$user) {
	print "$key = $val \n";
}
print "ok 5\n";
