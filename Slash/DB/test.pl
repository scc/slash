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
########################################################################
$object->sqlConnect();
print "ok 3\n";
########################################################################
$object->sanityCheck();
print "ok 4\n";
########################################################################
print "Lets grab some user data\n";
my $user = $object->getUserInfo('2', 'change', 'index.pl');
print "Should dump the data for an user now\n";
while(my ($key, $val) = each %$user) {
	print "$key = $val \n";
}
print "ok 5\n";
########################################################################
print "Testing getStoryBySid()\n";
my $story = $object->getStoryBySid('00/01/25/1236215');
print "Should dump the data for a story now\n";
while(my ($key, $val) = each %$story) {
	print "\t$key = $val \n";
}
print "ok 6\n";
########################################################################
print "Testing getAuthor()\n";
my $author = $object->getAuthor('God');
print "Should dump the data for an author now\n";
while(my ($key, $val) = each %$author) {
	print "\t$key = $val \n";
}
print "ok 7\n";
########################################################################
print "Testing setStoryBySid()\n";
$object->setStoryBySid('00/01/25/1236215', 'nuts', 'flavored');
$story = $object->getStoryBySid('00/01/25/1236215');
print "Should dump the data for the story now\n";
while(my ($key, $val) = each %$story) {
	print "\t$key = $val \n";
}
print "ok 8\n";
########################################################################
print "Testing clearStory()\n";
$object->clearStory();
$story = $object->getStoryBySid('00/01/25/1236215');
print "Should dump the data for the story now\n";
while(my ($key, $val) = each %$story) {
	print "\t$key = $val \n";
}
if($story->{'nuts'} eq 'flavored') {
	print "Something is up, stories were not removed from cache\n";
	print "Failed 9\n";
	exit(1);
} else {
	print "ok 9\n";
}
########################################################################
print "Testing getSectionBank()\n";
my $section  = $object->getSectionBank();
for (keys %$section) {
	print "\t$_ : $section->{$_}\n";
}
print "ok 11\n";
########################################################################
print "Testing currentAdmin()\n";
my $section  = $object->currentAdmin();
for (@$section) {
	my($aid, $lastsecs, $lasttitle) = @$_;
	print "\t$aid : $lastsecs \n";
}
print "ok 11\n";
########################################################################
print "Testing getTopic()\n";
print "\tNow lets try to grab everything()\n";
my $topics  = $object->getTopic();
for (keys %$topics) {
	print "\t\t$_ : $topics->{$_}\n";
}
print "\tNow lets try to grab the details on 'news'\n";
my $topic  = $object->getTopic('news');
for (keys %$topic) {
	print "\t\t$_ : $topic->{$_}\n";
}
print "ok 12\n";

########################################################################
print "Testing getCodes() \n";
print "\tTrying sortcodes\n";
my $codes = $object->getCodes('sortcodes');
for (keys %$codes) {
	print "\t\t$_ : $codes->{$_}\n";
}
print "\tTrying tzcodes\n";
$codes = $object->getCodes('tzcodes');
for (keys %$codes) {
	print "\t\t$_ : $codes->{$_}\n";
}
print "\tTrying dateformats\n";
$codes = $object->getCodes('dateformats');
for (keys %$codes) {
	print "\t\t$_ : $codes->{$_}\n";
}
print "\tTrying commentmodes\n";
$codes = $object->getCodes('commentmodes');
for (keys %$codes) {
	print "\t\t$_ : $codes->{$_}\n";
}
print "ok 13\n";
########################################################################
print "Testing getSubmissionCount() \n";
print "\tSubmissions :" . $object->getSubmissionCount(0) . "\n";
print "ok 14\n";
########################################################################
print "Testing getTopNewsstoryTopics() & countStory() \n";
my $newsstories = $object->getTopNewsstoryTopics(1);
# Broke at the moment
#for my $newsstories (@$newsstories) {
#	print "\tSubmissions :" . $object->countStory($newsstories->{tid}) . "\n";
#}
print "ok 15\n";
########################################################################
print "Testing getAuthorDescription()\n";
my $authordescriptions = $object->getAuthorDescription();
for my $authordescriptions (@$authordescriptions) {
	print "\tAuthorDescription :@$authordescriptions\n";
}
print "ok 16\n";
