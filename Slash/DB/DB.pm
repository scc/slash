# This code is a part of Slash, which is Copyright 1997-2001 OSDN, and
# released under the GPL.  See README and COPYING for more information.
# $Id$

package Slash::DB;

use strict;
use DBIx::Password;
use Slash::DB::Utility;

$Slash::DB::VERSION = '0.01';
@Slash::DB::ISA = qw[ Slash::Utility ];
@Slash::DB::ISAPg = qw[ Slash::Utility Slash::DB::PostgreSQL Slash::DB::MySQL ];
@Slash::DB::ISAMySQL = qw[ Slash::Utility Slash::DB::MySQL ];

# BENDER: Bender's a genius!

sub new {
	my($class, $user) = @_;
	my $self = {};
	my $dsn = DBIx::Password::getDriver($user);
	if ($dsn) {
		if ($dsn =~ /mysql/) {
			require Slash::DB::MySQL;
			@Slash::DB::ISA = @Slash::DB::ISAMySQL;
			unless ($ENV{GATEWAY_INTERFACE}) {
				require Slash::DB::Static::MySQL;
				push(@Slash::DB::ISA, 'Slash::DB::Static::MySQL');
				push(@Slash::DB::ISAMySQL, 'Slash::DB::Static::MySQL');
			}
#		} elsif ($dsn =~ /oracle/) {
#			require Slash::DB::Oracle;
#			push(@Slash::DB::ISA, 'Slash::DB::Oracle');
#			require Slash::DB::MySQL;
#			push(@Slash::DB::ISA, 'Slash::DB::MySQL');
#			unless ($ENV{GATEWAY_INTERFACE}) {
#				require Slash::DB::Static::Oracle;
#				push(@Slash::DB::ISA, 'Slash::DB::Static::Oracle');
## should these be here, in addition? -- pudge
## Longterm yes, right now it is pretty much pointless though --Brian
##				require Slash::DB::Static::MySQL;
##				push(@Slash::DB::ISA, 'Slash::DB::Static::MySQL');
#			}
		} elsif ($dsn =~ /Pg/) {
			require Slash::DB::PostgreSQL;
			require Slash::DB::MySQL;
			@Slash::DB::ISA = @Slash::DB::ISAPg;
			unless ($ENV{GATEWAY_INTERFACE}) {
				require Slash::DB::Static::PostgreSQL;
				push(@Slash::DB::ISA, 'Slash::DB::Static::PostgreSQL');
				push(@Slash::DB::ISA, 'Slash::DB::Static::MySQL');
# should you also push Static::PostgreSQL onto ISAPg ? -- pudge
				push(@Slash::DB::ISAPg, 'Slash::DB::Static::MySQL');
			}
		}
	} else {
		warn("We don't support the database ($dsn) specified. Using user ($user) "
			. DBIx::Password::getDriver($user));
	}
	bless($self, $class);
	$self->{virtual_user} = $user;
	$self->{db_driver} = $dsn;
	$self->SUPER::sqlConnect();
#	$self->init();
	return $self;
}

# hm.  should this really be here?  in theory, we could use anything
# we wanted, including non-DBI modules, to provide the Slash::DB API.
# but this might break that.  aside from this, Slash::DB makes no
# assumptions about how the API is implemented (well, and the sqlConnect()
# and init() calls above).  maybe instead, we could call
# $self->SUPER::disconnect(),  and have a disconnect() there that calls
# $self->{_dbh}->disconnect ... ?   -- pudge

sub DESTROY {
	my($self) = @_;
	$self->{_dbh}->disconnect
		if ! $ENV{GATEWAY_INTERFACE} && defined $self->{_dbh};
}

# This is for sites running in multiple threaded/process environments
# where you want to run two different database types
sub fixup {
	my ($self) = @_;

	if ($self->{db_driver} =~ /mysql/) {
		@Slash::DB::ISA = @Slash::DB::ISAMySQL;
	} elsif ($self->{db_driver} =~ /Pg/) {
		@Slash::DB::ISA = @Slash::DB::ISAPg;
	} 
}


1;

__END__

=head1 NAME

Slash::DB - Database Class for Slashcode

=head1 SYNOPSIS

  use Slash::DB;
  $my object = new Slash::DB("virtual_user");

=head1 DESCRIPTION

This package is the front end interface to slashcode.
By looking at the database parameter during creation
it determines what type of database to inherit from.


=head2 createComment(FORM, USER, POINTS, DEFAULT_USER)

This is an awful method. You use it to create a new
comments. This will go away. It locks tables, so
fear calling it.

=over 4

=item Parameters

=over 4

=item FORM

FORM, as in a form structure. Pretty much no
good reason why we have to pass this.

=back

=item USER

USER, as in a USER structure. Pretty much no
good reason why we have to pass this.

=back

=item POINTS

Points for the comment.

=back

=item DEFAULT_USER

Default user to use if the person is being a coward about
posting.

=back

=item Return value

Return -1 on failure, and maxcid otherwise.

=back

=head2 setModeratorLog(CID, SID, UID, VAL, REASON)

This set has some logic to it and is not a
generic set method. All values must be accounted
for or this will not work. Basically this 
creates an entry in the moderator log.

=over 4

=item Parameters

=over 4

=item CID

Comment ID.

=back

=item SID

Story ID.

=back

=item UID

UID of the user doing the moderation.

=back

=item VAL

Value for moderation

=back

=item REASON

Reason for moderation

=back

=item Return value

No defined value.

=back

=head2 getMetamodComments(KEY)

I am the default documentation, short and stout.

=over 4

=item Parameters

=over 4

=item KEY

Key, as in the KEY

=back

=item Return value

Fixed KEY.

=back

=head2 getModeratorCommentLog(KEY)

I am the default documentation, short and stout.

=over 4

=item Parameters

=over 4

=item KEY

Key, as in the KEY

=back

=item Return value

Fixed KEY.

=back

=head2 getModeratorLogID(KEY)

I am the default documentation, short and stout.

=over 4

=item Parameters

=over 4

=item KEY

Key, as in the KEY

=back

=item Return value

Fixed KEY.

=back

=head2 unsetModeratorlog(KEY)

I am the default documentation, short and stout.

=over 4

=item Parameters

=over 4

=item KEY

Key, as in the KEY

=back

=item Return value

Fixed KEY.

=back

=head2 getContentFilters()

This returns all content filters in an array of arrays.
It does not return filters that have been created but
not defined.

=over 4

=item Return value

This return an array of arrays. The order is currently
defined by the schema.

=back

=head2 createPollVoter(QID, AID)

Increment the poll count for a given answer.

=over 4

=item Parameters

=over 4

=item QID

QID is a question ID for polls.

=back

=item AID

Answer ID for the poll

=back

=item Return value

No defined value.

=back

=head2 createSubmission(FORM)

This creates a submission. Passing in the
form is optional. 

=over 4

=item Parameters

=over 4

=item FORM

Standard form structure.

=back

=item Return value

No defined value.

=back

=head2 getDiscussions(KEY)

I am the default documentation, short and stout.

=over 4

=item Parameters

=over 4

=item KEY

Key, as in the KEY

=back

=item Return value

Fixed KEY.

=back

=head2 getSessionInstance(KEY)

I am the default documentation, short and stout.

=over 4

=item Parameters

=over 4

=item KEY

Key, as in the KEY

=back

=item Return value

Fixed KEY.

=back

=head2 setContentFilter(KEY)

I am the default documentation, short and stout.

=over 4

=item Parameters

=over 4

=item KEY

Key, as in the KEY

=back

=item Return value

Fixed KEY.

=back

=head2 setSectionExtra(KEY)

I am the default documentation, short and stout.

=over 4

=item Parameters

=over 4

=item KEY

Key, as in the KEY

=back

=item Return value

Fixed KEY.

=back

=head2 createAccessLog(KEY)

I am the default documentation, short and stout.

=over 4

=item Parameters

=over 4

=item KEY

Key, as in the KEY

=back

=item Return value

Fixed KEY.

=back

=head2 getDescriptions(KEY)

I am the default documentation, short and stout.

=over 4

=item Parameters

=over 4

=item KEY

Key, as in the KEY

=back

=item Return value

Fixed KEY.

=back

=head2 getUserInstance(KEY)

I am the default documentation, short and stout.

=over 4

=item Parameters

=over 4

=item KEY

Key, as in the KEY

=back

=item Return value

Fixed KEY.

=back

=head2 deleteUser(KEY)

I am the default documentation, short and stout.

=over 4

=item Parameters

=over 4

=item KEY

Key, as in the KEY

=back

=item Return value

Fixed KEY.

=back

=head2 getUserAuthenticate(KEY)

I am the default documentation, short and stout.

=over 4

=item Parameters

=over 4

=item KEY

Key, as in the KEY

=back

=item Return value

Fixed KEY.

=back

=head2 getNewPasswd(KEY)

I am the default documentation, short and stout.

=over 4

=item Parameters

=over 4

=item KEY

Key, as in the KEY

=back

=item Return value

Fixed KEY.

=back

=head2 getUserUID(KEY)

I am the default documentation, short and stout.

=over 4

=item Parameters

=over 4

=item KEY

Key, as in the KEY

=back

=item Return value

Fixed KEY.

=back

=head2 getCommentsByUID(KEY)

I am the default documentation, short and stout.

=over 4

=item Parameters

=over 4

=item KEY

Key, as in the KEY

=back

=item Return value

Fixed KEY.

=back

=head2 createContentFilter(KEY)

I am the default documentation, short and stout.

=over 4

=item Parameters

=over 4

=item KEY

Key, as in the KEY

=back

=item Return value

Fixed KEY.

=back

=head2 createUser(KEY)

I am the default documentation, short and stout.

=over 4

=item Parameters

=over 4

=item KEY

Key, as in the KEY

=back

=item Return value

Fixed KEY.

=back

=head2 setVar(KEY)

I am the default documentation, short and stout.

=over 4

=item Parameters

=over 4

=item KEY

Key, as in the KEY

=back

=item Return value

Fixed KEY.

=back

=head2 setSession(KEY)

I am the default documentation, short and stout.

=over 4

=item Parameters

=over 4

=item KEY

Key, as in the KEY

=back

=item Return value

Fixed KEY.

=back

=head2 setBlock(KEY)

I am the default documentation, short and stout.

=over 4

=item Parameters

=over 4

=item KEY

Key, as in the KEY

=back

=item Return value

Fixed KEY.

=back

=head2 setDiscussion(KEY)

I am the default documentation, short and stout.

=over 4

=item Parameters

=over 4

=item KEY

Key, as in the KEY

=back

=item Return value

Fixed KEY.

=back

=head2 setTemplate(KEY)

I am the default documentation, short and stout.

=over 4

=item Parameters

=over 4

=item KEY

Key, as in the KEY

=back

=item Return value

Fixed KEY.

=back

=head2 getCommentCid(KEY)

I am the default documentation, short and stout.

=over 4

=item Parameters

=over 4

=item KEY

Key, as in the KEY

=back

=item Return value

Fixed KEY.

=back

=head2 deleteComment(KEY)

I am the default documentation, short and stout.

=over 4

=item Parameters

=over 4

=item KEY

Key, as in the KEY

=back

=item Return value

Fixed KEY.

=back

=head2 getCommentPid(KEY)

I am the default documentation, short and stout.

=over 4

=item Parameters

=over 4

=item KEY

Key, as in the KEY

=back

=item Return value

Fixed KEY.

=back

=head2 setSection(KEY)

I am the default documentation, short and stout.

=over 4

=item Parameters

=over 4

=item KEY

Key, as in the KEY

=back

=item Return value

Fixed KEY.

=back

=head2 setStoriesCount(KEY)

I am the default documentation, short and stout.

=over 4

=item Parameters

=over 4

=item KEY

Key, as in the KEY

=back

=item Return value

Fixed KEY.

=back

=head2 getSectionTitle(KEY)

I am the default documentation, short and stout.

=over 4

=item Parameters

=over 4

=item KEY

Key, as in the KEY

=back

=item Return value

Fixed KEY.

=back

=head2 deleteSubmission(KEY)

I am the default documentation, short and stout.

=over 4

=item Parameters

=over 4

=item KEY

Key, as in the KEY

=back

=item Return value

Fixed KEY.

=back

=head2 deleteSession(KEY)

I am the default documentation, short and stout.

=over 4

=item Parameters

=over 4

=item KEY

Key, as in the KEY

=back

=item Return value

Fixed KEY.

=back

=head2 deleteAuthor(KEY)

I am the default documentation, short and stout.

=over 4

=item Parameters

=over 4

=item KEY

Key, as in the KEY

=back

=item Return value

Fixed KEY.

=back

=head2 deleteTopic(KEY)

I am the default documentation, short and stout.

=over 4

=item Parameters

=over 4

=item KEY

Key, as in the KEY

=back

=item Return value

Fixed KEY.

=back

=head2 revertBlock(KEY)

I am the default documentation, short and stout.

=over 4

=item Parameters

=over 4

=item KEY

Key, as in the KEY

=back

=item Return value

Fixed KEY.

=back

=head2 deleteTemplate(KEY)

I am the default documentation, short and stout.

=over 4

=item Parameters

=over 4

=item KEY

Key, as in the KEY

=back

=item Return value

Fixed KEY.

=back

=head2 deleteSection(KEY)

I am the default documentation, short and stout.

=over 4

=item Parameters

=over 4

=item KEY

Key, as in the KEY

=back

=item Return value

Fixed KEY.

=back

=head2 deleteContentFilter(KEY)

I am the default documentation, short and stout.

=over 4

=item Parameters

=over 4

=item KEY

Key, as in the KEY

=back

=item Return value

Fixed KEY.

=back

=head2 saveTopic(KEY)

I am the default documentation, short and stout.

=over 4

=item Parameters

=over 4

=item KEY

Key, as in the KEY

=back

=item Return value

Fixed KEY.

=back

=head2 saveBlock(KEY)

I am the default documentation, short and stout.

=over 4

=item Parameters

=over 4

=item KEY

Key, as in the KEY

=back

=item Return value

Fixed KEY.

=back

=head2 saveColorBlock(KEY)

I am the default documentation, short and stout.

=over 4

=item Parameters

=over 4

=item KEY

Key, as in the KEY

=back

=item Return value

Fixed KEY.

=back

=head2 getSectionBlock(KEY)

I am the default documentation, short and stout.

=over 4

=item Parameters

=over 4

=item KEY

Key, as in the KEY

=back

=item Return value

Fixed KEY.

=back

=head2 getSectionBlocks(KEY)

I am the default documentation, short and stout.

=over 4

=item Parameters

=over 4

=item KEY

Key, as in the KEY

=back

=item Return value

Fixed KEY.

=back

=head2 getAuthorDescription(KEY)

I am the default documentation, short and stout.

=over 4

=item Parameters

=over 4

=item KEY

Key, as in the KEY

=back

=item Return value

Fixed KEY.

=back

=head2 getPollVoter(KEY)

I am the default documentation, short and stout.

=over 4

=item Parameters

=over 4

=item KEY

Key, as in the KEY

=back

=item Return value

Fixed KEY.

=back

=head2 savePollQuestion(KEY)

I am the default documentation, short and stout.

=over 4

=item Parameters

=over 4

=item KEY

Key, as in the KEY

=back

=item Return value

Fixed KEY.

=back

=head2 getPollQuestionList(KEY)

I am the default documentation, short and stout.

=over 4

=item Parameters

=over 4

=item KEY

Key, as in the KEY

=back

=item Return value

Fixed KEY.

=back

=head2 getPollAnswers(KEY)

I am the default documentation, short and stout.

=over 4

=item Parameters

=over 4

=item KEY

Key, as in the KEY

=back

=item Return value

Fixed KEY.

=back

=head2 getPollQuestions(KEY)

I am the default documentation, short and stout.

=over 4

=item Parameters

=over 4

=item KEY

Key, as in the KEY

=back

=item Return value

Fixed KEY.

=back

=head2 deleteStory(KEY)

I am the default documentation, short and stout.

=over 4

=item Parameters

=over 4

=item KEY

Key, as in the KEY

=back

=item Return value

Fixed KEY.

=back

=head2 deleteStoryAll(KEY)

I am the default documentation, short and stout.

=over 4

=item Parameters

=over 4

=item KEY

Key, as in the KEY

=back

=item Return value

Fixed KEY.

=back

=head2 setStory(KEY)

I am the default documentation, short and stout.

=over 4

=item Parameters

=over 4

=item KEY

Key, as in the KEY

=back

=item Return value

Fixed KEY.

=back

=head2 getSubmissionLast(KEY)

I am the default documentation, short and stout.

=over 4

=item Parameters

=over 4

=item KEY

Key, as in the KEY

=back

=item Return value

Fixed KEY.

=back

=head2 updateFormkeyId(KEY)

I am the default documentation, short and stout.

=over 4

=item Parameters

=over 4

=item KEY

Key, as in the KEY

=back

=item Return value

Fixed KEY.

=back

=head2 insertFormkey(KEY)

I am the default documentation, short and stout.

=over 4

=item Parameters

=over 4

=item KEY

Key, as in the KEY

=back

=item Return value

Fixed KEY.

=back

=head2 checkFormkey(KEY)

I am the default documentation, short and stout.

=over 4

=item Parameters

=over 4

=item KEY

Key, as in the KEY

=back

=item Return value

Fixed KEY.

=back

=head2 checkTimesPosted(KEY)

I am the default documentation, short and stout.

=over 4

=item Parameters

=over 4

=item KEY

Key, as in the KEY

=back

=item Return value

Fixed KEY.

=back

=head2 formSuccess(KEY)

I am the default documentation, short and stout.

=over 4

=item Parameters

=over 4

=item KEY

Key, as in the KEY

=back

=item Return value

Fixed KEY.

=back

=head2 formFailure(KEY)

I am the default documentation, short and stout.

=over 4

=item Parameters

=over 4

=item KEY

Key, as in the KEY

=back

=item Return value

Fixed KEY.

=back

=head2 formAbuse(KEY)

I am the default documentation, short and stout.

=over 4

=item Parameters

=over 4

=item KEY

Key, as in the KEY

=back

=item Return value

Fixed KEY.

=back

=head2 checkForm(KEY)

I am the default documentation, short and stout.

=over 4

=item Parameters

=over 4

=item KEY

Key, as in the KEY

=back

=item Return value

Fixed KEY.

=back

=head2 currentAdmin(KEY)

I am the default documentation, short and stout.

=over 4

=item Parameters

=over 4

=item KEY

Key, as in the KEY

=back

=item Return value

Fixed KEY.

=back

=head2 getTopNewsstoryTopics(KEY)

I am the default documentation, short and stout.

=over 4

=item Parameters

=over 4

=item KEY

Key, as in the KEY

=back

=item Return value

Fixed KEY.

=back

=head2 getPoll(KEY)

I am the default documentation, short and stout.

=over 4

=item Parameters

=over 4

=item KEY

Key, as in the KEY

=back

=item Return value

Fixed KEY.

=back

=head2 getSubmissionsSections(KEY)

I am the default documentation, short and stout.

=over 4

=item Parameters

=over 4

=item KEY

Key, as in the KEY

=back

=item Return value

Fixed KEY.

=back

=head2 getSubmissionsPending(KEY)

I am the default documentation, short and stout.

=over 4

=item Parameters

=over 4

=item KEY

Key, as in the KEY

=back

=item Return value

Fixed KEY.

=back

=head2 getSubmissionCount(KEY)

I am the default documentation, short and stout.

=over 4

=item Parameters

=over 4

=item KEY

Key, as in the KEY

=back

=item Return value

Fixed KEY.

=back

=head2 getPortals(KEY)

I am the default documentation, short and stout.

=over 4

=item Parameters

=over 4

=item KEY

Key, as in the KEY

=back

=item Return value

Fixed KEY.

=back

=head2 getPortalsCommon(KEY)

I am the default documentation, short and stout.

=over 4

=item Parameters

=over 4

=item KEY

Key, as in the KEY

=back

=item Return value

Fixed KEY.

=back

=head2 countComments(KEY)

I am the default documentation, short and stout.

=over 4

=item Parameters

=over 4

=item KEY

Key, as in the KEY

=back

=item Return value

Fixed KEY.

=back

=head2 countStory(KEY)

I am the default documentation, short and stout.

=over 4

=item Parameters

=over 4

=item KEY

Key, as in the KEY

=back

=item Return value

Fixed KEY.

=back

=head2 checkForModerator(KEY)

I am the default documentation, short and stout.

=over 4

=item Parameters

=over 4

=item KEY

Key, as in the KEY

=back

=item Return value

Fixed KEY.

=back

=head2 getAuthorNames(KEY)

I am the default documentation, short and stout.

=over 4

=item Parameters

=over 4

=item KEY

Key, as in the KEY

=back

=item Return value

Fixed KEY.

=back

=head2 getStoryByTime(KEY)

I am the default documentation, short and stout.

=over 4

=item Parameters

=over 4

=item KEY

Key, as in the KEY

=back

=item Return value

Fixed KEY.

=back

=head2 countStories(KEY)

I am the default documentation, short and stout.

=over 4

=item Parameters

=over 4

=item KEY

Key, as in the KEY

=back

=item Return value

Fixed KEY.

=back

=head2 setModeratorVotes(KEY)

I am the default documentation, short and stout.

=over 4

=item Parameters

=over 4

=item KEY

Key, as in the KEY

=back

=item Return value

Fixed KEY.

=back

=head2 setMetaMod(KEY)

I am the default documentation, short and stout.

=over 4

=item Parameters

=over 4

=item KEY

Key, as in the KEY

=back

=item Return value

Fixed KEY.

=back

=head2 getModeratorLast(KEY)

I am the default documentation, short and stout.

=over 4

=item Parameters

=over 4

=item KEY

Key, as in the KEY

=back

=item Return value

Fixed KEY.

=back

=head2 getModeratorLogRandom(KEY)

I am the default documentation, short and stout.

=over 4

=item Parameters

=over 4

=item KEY

Key, as in the KEY

=back

=item Return value

Fixed KEY.

=back

=head2 countUsers(KEY)

I am the default documentation, short and stout.

=over 4

=item Parameters

=over 4

=item KEY

Key, as in the KEY

=back

=item Return value

Fixed KEY.

=back

=head2 countStoriesStuff(KEY)

I am the default documentation, short and stout.

=over 4

=item Parameters

=over 4

=item KEY

Key, as in the KEY

=back

=item Return value

Fixed KEY.

=back

=head2 countStoriesAuthors(KEY)

I am the default documentation, short and stout.

=over 4

=item Parameters

=over 4

=item KEY

Key, as in the KEY

=back

=item Return value

Fixed KEY.

=back

=head2 countPollquestions(KEY)

I am the default documentation, short and stout.

=over 4

=item Parameters

=over 4

=item KEY

Key, as in the KEY

=back

=item Return value

Fixed KEY.

=back

=head2 createVar(KEY)

I am the default documentation, short and stout.

=over 4

=item Parameters

=over 4

=item KEY

Key, as in the KEY

=back

=item Return value

Fixed KEY.

=back

=head2 deleteVar(KEY)

I am the default documentation, short and stout.

=over 4

=item Parameters

=over 4

=item KEY

Key, as in the KEY

=back

=item Return value

Fixed KEY.

=back

=head2 setCommentCleanup(KEY)

I am the default documentation, short and stout.

=over 4

=item Parameters

=over 4

=item KEY

Key, as in the KEY

=back

=item Return value

Fixed KEY.

=back

=head2 countUsersIndexExboxesByBid(KEY)

I am the default documentation, short and stout.

=over 4

=item Parameters

=over 4

=item KEY

Key, as in the KEY

=back

=item Return value

Fixed KEY.

=back

=head2 getCommentReply(KEY)

I am the default documentation, short and stout.

=over 4

=item Parameters

=over 4

=item KEY

Key, as in the KEY

=back

=item Return value

Fixed KEY.

=back

=head2 getCommentsForUser(KEY)

I am the default documentation, short and stout.

=over 4

=item Parameters

=over 4

=item KEY

Key, as in the KEY

=back

=item Return value

Fixed KEY.

=back

=head2 getComments(KEY)

I am the default documentation, short and stout.

=over 4

=item Parameters

=over 4

=item KEY

Key, as in the KEY

=back

=item Return value

Fixed KEY.

=back

=head2 getNewStories(KEY)

I am the default documentation, short and stout.

=over 4

=item Parameters

=over 4

=item KEY

Key, as in the KEY

=back

=item Return value

Fixed KEY.

=back

=head2 getCommentsTop(KEY)

I am the default documentation, short and stout.

=over 4

=item Parameters

=over 4

=item KEY

Key, as in the KEY

=back

=item Return value

Fixed KEY.

=back

=head2 getQuickies(KEY)

I am the default documentation, short and stout.

=over 4

=item Parameters

=over 4

=item KEY

Key, as in the KEY

=back

=item Return value

Fixed KEY.

=back

=head2 setQuickies(KEY)

I am the default documentation, short and stout.

=over 4

=item Parameters

=over 4

=item KEY

Key, as in the KEY

=back

=item Return value

Fixed KEY.

=back

=head2 getSubmissionForUser(KEY)

I am the default documentation, short and stout.

=over 4

=item Parameters

=over 4

=item KEY

Key, as in the KEY

=back

=item Return value

Fixed KEY.

=back

=head2 getTrollAddress(KEY)

I am the default documentation, short and stout.

=over 4

=item Parameters

=over 4

=item KEY

Key, as in the KEY

=back

=item Return value

Fixed KEY.

=back

=head2 getTrollUID(KEY)

I am the default documentation, short and stout.

=over 4

=item Parameters

=over 4

=item KEY

Key, as in the KEY

=back

=item Return value

Fixed KEY.

=back

=head2 createDiscussion(KEY)

I am the default documentation, short and stout.

=over 4

=item Parameters

=over 4

=item KEY

Key, as in the KEY

=back

=item Return value

Fixed KEY.

=back

=head2 createStory(KEY)

I am the default documentation, short and stout.

=over 4

=item Parameters

=over 4

=item KEY

Key, as in the KEY

=back

=item Return value

Fixed KEY.

=back

=head2 updateStory(KEY)

I am the default documentation, short and stout.

=over 4

=item Parameters

=over 4

=item KEY

Key, as in the KEY

=back

=item Return value

Fixed KEY.

=back

=head2 getSlashConf(KEY)

I am the default documentation, short and stout.

=over 4

=item Parameters

=over 4

=item KEY

Key, as in the KEY

=back

=item Return value

Fixed KEY.

=back

=head2 autoUrl(KEY)

I am the default documentation, short and stout.

=over 4

=item Parameters

=over 4

=item KEY

Key, as in the KEY

=back

=item Return value

Fixed KEY.

=back

=head2 getUrlFromTitle(KEY)

I am the default documentation, short and stout.

=over 4

=item Parameters

=over 4

=item KEY

Key, as in the KEY

=back

=item Return value

Fixed KEY.

=back

=head2 getTime(KEY)

I am the default documentation, short and stout.

=over 4

=item Parameters

=over 4

=item KEY

Key, as in the KEY

=back

=item Return value

Fixed KEY.

=back

=head2 getDay(KEY)

I am the default documentation, short and stout.

=over 4

=item Parameters

=over 4

=item KEY

Key, as in the KEY

=back

=item Return value

Fixed KEY.

=back

=head2 getStoryList(KEY)

I am the default documentation, short and stout.

=over 4

=item Parameters

=over 4

=item KEY

Key, as in the KEY

=back

=item Return value

Fixed KEY.

=back

=head2 getPollVotesMax(KEY)

I am the default documentation, short and stout.

=over 4

=item Parameters

=over 4

=item KEY

Key, as in the KEY

=back

=item Return value

Fixed KEY.

=back

=head2 getStory(KEY)

I am the default documentation, short and stout.

=over 4

=item Parameters

=over 4

=item KEY

Key, as in the KEY

=back

=item Return value

Fixed KEY.

=back

=head2 getAuthor(KEY)

I am the default documentation, short and stout.

=over 4

=item Parameters

=over 4

=item KEY

Key, as in the KEY

=back

=item Return value

Fixed KEY.

=back

=head2 getAuthors(KEY)

I am the default documentation, short and stout.

=over 4

=item Parameters

=over 4

=item KEY

Key, as in the KEY

=back

=item Return value

Fixed KEY.

=back

=head2 getPollQuestion(KEY)

I am the default documentation, short and stout.

=over 4

=item Parameters

=over 4

=item KEY

Key, as in the KEY

=back

=item Return value

Fixed KEY.

=back

=head2 getDiscussion(KEY)

I am the default documentation, short and stout.

=over 4

=item Parameters

=over 4

=item KEY

Key, as in the KEY

=back

=item Return value

Fixed KEY.

=back

=head2 getBlock(KEY)

I am the default documentation, short and stout.

=over 4

=item Parameters

=over 4

=item KEY

Key, as in the KEY

=back

=item Return value

Fixed KEY.

=back

=head2 getTemplate(KEY)

I am the default documentation, short and stout.

=over 4

=item Parameters

=over 4

=item KEY

Key, as in the KEY

=back

=item Return value

Fixed KEY.

=back

=head2 getTemplateByName(KEY)

I am the default documentation, short and stout.

=over 4

=item Parameters

=over 4

=item KEY

Key, as in the KEY

=back

=item Return value

Fixed KEY.

=back

=head2 getTopic(KEY)

I am the default documentation, short and stout.

=over 4

=item Parameters

=over 4

=item KEY

Key, as in the KEY

=back

=item Return value

Fixed KEY.

=back

=head2 getTopics(KEY)

I am the default documentation, short and stout.

=over 4

=item Parameters

=over 4

=item KEY

Key, as in the KEY

=back

=item Return value

Fixed KEY.

=back

=head2 getTemplates(KEY)

I am the default documentation, short and stout.

=over 4

=item Parameters

=over 4

=item KEY

Key, as in the KEY

=back

=item Return value

Fixed KEY.

=back

=head2 getContentFilter(KEY)

I am the default documentation, short and stout.

=over 4

=item Parameters

=over 4

=item KEY

Key, as in the KEY

=back

=item Return value

Fixed KEY.

=back

=head2 getSubmission(KEY)

I am the default documentation, short and stout.

=over 4

=item Parameters

=over 4

=item KEY

Key, as in the KEY

=back

=item Return value

Fixed KEY.

=back

=head2 getSection(KEY)

I am the default documentation, short and stout.

=over 4

=item Parameters

=over 4

=item KEY

Key, as in the KEY

=back

=item Return value

Fixed KEY.

=back

=head2 getSections(KEY)

I am the default documentation, short and stout.

=over 4

=item Parameters

=over 4

=item KEY

Key, as in the KEY

=back

=item Return value

Fixed KEY.

=back

=head2 getModeratorLog(KEY)

I am the default documentation, short and stout.

=over 4

=item Parameters

=over 4

=item KEY

Key, as in the KEY

=back

=item Return value

Fixed KEY.

=back

=head2 getNewStory(KEY)

I am the default documentation, short and stout.

=over 4

=item Parameters

=over 4

=item KEY

Key, as in the KEY

=back

=item Return value

Fixed KEY.

=back

=head2 getVar(KEY)

I am the default documentation, short and stout.

=over 4

=item Parameters

=over 4

=item KEY

Key, as in the KEY

=back

=item Return value

Fixed KEY.

=back

=head2 setUser(KEY)

I am the default documentation, short and stout.

=over 4

=item Parameters

=over 4

=item KEY

Key, as in the KEY

=back

=item Return value

Fixed KEY.

=back

=head2 getUser(KEY)

I am the default documentation, short and stout.

=over 4

=item Parameters

=over 4

=item KEY

Key, as in the KEY

=back

=item Return value

Fixed KEY.

=back

=head2 getStories(KEY)

I am the default documentation, short and stout.

=over 4

=item Parameters

=over 4

=item KEY

Key, as in the KEY

=back

=item Return value

Fixed KEY.

=back

=head2 getSessions(KEY)

I am the default documentation, short and stout.

=over 4

=item Parameters

=over 4

=item KEY

Key, as in the KEY

=back

=item Return value

Fixed KEY.

=back

=head2 createBlock(KEY)

I am the default documentation, short and stout.

=over 4

=item Parameters

=over 4

=item KEY

Key, as in the KEY

=back

=item Return value

Fixed KEY.

=back

=head2 createTemplate(KEY)

I am the default documentation, short and stout.

=over 4

=item Parameters

=over 4

=item KEY

Key, as in the KEY

=back

=item Return value

Fixed KEY.

=back

=head2 createMenuItem(KEY)

I am the default documentation, short and stout.

=over 4

=item Parameters

=over 4

=item KEY

Key, as in the KEY

=back

=item Return value

Fixed KEY.

=back

=head2 getMenuItems(KEY)

I am the default documentation, short and stout.

=over 4

=item Parameters

=over 4

=item KEY

Key, as in the KEY

=back

=item Return value

Fixed KEY.

=back

=head2 getMenus(KEY)

I am the default documentation, short and stout.

=over 4

=item Parameters

=over 4

=item KEY

Key, as in the KEY

=back

=item Return value

Fixed KEY.

=back

=head2 sqlReplace(KEY)

I am the default documentation, short and stout.

=over 4

=item Parameters

=over 4

=item KEY

Key, as in the KEY

=back

=item Return value

Fixed KEY.

=back

=head2 getKeys(KEY)

I am the default documentation, short and stout.

=over 4

=item Parameters

=over 4

=item KEY

Key, as in the KEY

=back

=item Return value

Fixed KEY.

=back

=head2 sqlTableExists(KEY)

I am the default documentation, short and stout.

=over 4

=item Parameters

=over 4

=item KEY

Key, as in the KEY

=back

=item Return value

Fixed KEY.

=back

=head2 sqlSelectColumns(KEY)

I am the default documentation, short and stout.

=over 4

=item Parameters

=over 4

=item KEY

Key, as in the KEY

=back

=item Return value

Fixed KEY.

=back

=head2 generatesession(KEY)

I am the default documentation, short and stout.

=over 4

=item Parameters

=over 4

=item KEY

Key, as in the KEY

=back

=item Return value

Fixed KEY.

=back


=head1 SEE ALSO

Slash(3), Slash::DB::Utility(3).

=cut
