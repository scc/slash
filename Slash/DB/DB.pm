package Slash::DB;

use strict;
use DBIx::Password;
use Slash::DB::Utility;

$Slash::DB::VERSION = '0.01';
@Slash::DB::ISA = qw[ Slash::Utility ];

# BENDER: Bender's a genius!

sub new {
	my($class, $user) = @_;
	my $self = {};
	my $dsn = DBIx::Password::getDriver($user);
	print STDERR "DRIVER $dsn:$user \n";
	if ($dsn) {
		if ($dsn =~ /mysql/) {
#			print STDERR "Picking MySQL \n";
			require Slash::DB::MySQL;
			push(@Slash::DB::ISA, 'Slash::DB::MySQL');
			unless ($ENV{GATEWAY_INTERFACE}) {
				require Slash::DB::Static::MySQL;
				push(@Slash::DB::ISA, 'Slash::DB::Static::MySQL');
			}
		} elsif ($dsn =~ /oracle/) {
			print STDERR "Picking Oracle \n";
			require Slash::DB::Oracle;
			push(@Slash::DB::ISA, 'Slash::DB::Oracle');
			unless ($ENV{GATEWAY_INTERFACE}) {
				require Slash::DB::Static::Oracle;
				push(@Slash::DB::ISA, 'Slash::DB::Static::Oracle');
			}
		} elsif ($dsn =~ /Pg/) {
			print STDERR "Picking PostgreSQL \n";
			require Slash::DB::PostgreSQL;
			push(@Slash::DB::ISA, 'Slash::DB::PostgreSQL');
#			unless ($ENV{GATEWAY_INTERFACE}) {
#				require Slash::DB::Static::PostgreSQL;
#				push(@Slash::DB::ISA, 'Slash::DB::Static::PostgreSQL');
#			}
		}
	} else {
		warn("We don't support the database ($dsn) specified. Using user ($user) "
			. DBIx::Password::getDriver($user));
	}
	bless($self, $class);
	$self->{virtual_user} = $user;
	$self->SUPER::sqlConnect();
	$self->SUPER::init();
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
	$self->{_dbh}->disconnect if $self->{_dbh};
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

=head1 METHODS

=head2 functionName(PARAM1, PARAM2 [, OPTIONALPARAM1])

Description of functionName.

=over 4

=item Parameters

=over 4

=item PARAM1

Description of PARAM1 (including data type).

=item PARAM2

etc.

=back

=item Return value

Description of return value(s).

=item Side effects

Description of side effects.

=back

=cut

=item sqlConnect(KEY)

Creates a drop-down list in HTML.

Parameters

	KEY
	The name for the HTML entity.

Return value

	No value is returned.

=cut



=item setComment(KEY)

Creates a drop-down list in HTML.

Parameters

	KEY
	The name for the HTML entity.

Return value

	No value is returned.

=cut



=item setModeratorLog(KEY)

Creates a drop-down list in HTML.

Parameters

	KEY
	The name for the HTML entity.

Return value

	No value is returned.

=cut



=item getModeratorCommentLog(KEY)

Creates a drop-down list in HTML.

Parameters

	KEY
	The name for the HTML entity.

Return value

	No value is returned.

=cut



=item getModeratorLogID(KEY)

Creates a drop-down list in HTML.

Parameters

	KEY
	The name for the HTML entity.

Return value

	No value is returned.

=cut



=item unsetModeratorlog(KEY)

Creates a drop-down list in HTML.

Parameters

	KEY
	The name for the HTML entity.

Return value

	No value is returned.

=cut



=item getContentFilters(KEY)

Creates a drop-down list in HTML.

Parameters

	KEY
	The name for the HTML entity.

Return value

	No value is returned.

=cut



=item createPollVoter(KEY)

Creates a drop-down list in HTML.

Parameters

	KEY
	The name for the HTML entity.

Return value

	No value is returned.

=cut



=item createSubmission(KEY)

Creates a drop-down list in HTML.

Parameters

	KEY
	The name for the HTML entity.

Return value

	No value is returned.

=cut



=item createDiscussions(KEY)

Creates a drop-down list in HTML.

Parameters

	KEY
	The name for the HTML entity.

Return value

	No value is returned.

=cut



=item getDiscussions(KEY)

Creates a drop-down list in HTML.

Parameters

	KEY
	The name for the HTML entity.

Return value

	No value is returned.

=cut



=item getAdminInfo(KEY)

Creates a drop-down list in HTML.

Parameters

	KEY
	The name for the HTML entity.

Return value

	No value is returned.

=cut



=item setContentFilter(KEY)

Creates a drop-down list in HTML.

Parameters

	KEY
	The name for the HTML entity.

Return value

	No value is returned.

=cut



=item setSectionExtra(KEY)

Creates a drop-down list in HTML.

Parameters

	KEY
	The name for the HTML entity.

Return value

	No value is returned.

=cut



=item setAdminInfo(KEY)

Creates a drop-down list in HTML.

Parameters

	KEY
	The name for the HTML entity.

Return value

	No value is returned.

=cut



=item createAccessLog(KEY)

Creates a drop-down list in HTML.

Parameters

	KEY
	The name for the HTML entity.

Return value

	No value is returned.

=cut



=item getCodes(KEY)

Creates a drop-down list in HTML.

Parameters

	KEY
	The name for the HTML entity.

Return value

	No value is returned.

=cut



=item getDescriptions(KEY)

Creates a drop-down list in HTML.

Parameters

	KEY
	The name for the HTML entity.

Return value

	No value is returned.

=cut



=item getUserInstance(KEY)

Creates a drop-down list in HTML.

Parameters

	KEY
	The name for the HTML entity.

Return value

	No value is returned.

=cut



=item deleteUser(KEY)

Creates a drop-down list in HTML.

Parameters

	KEY
	The name for the HTML entity.

Return value

	No value is returned.

=cut



=item getUserAuthenticate(KEY)

Creates a drop-down list in HTML.

Parameters

	KEY
	The name for the HTML entity.

Return value

	No value is returned.

=cut



=item getNewPasswd(KEY)

Creates a drop-down list in HTML.

Parameters

	KEY
	The name for the HTML entity.

Return value

	No value is returned.

=cut



=item getUserUID(KEY)

Creates a drop-down list in HTML.

Parameters

	KEY
	The name for the HTML entity.

Return value

	No value is returned.

=cut



=item getCommentsByUID(KEY)

Creates a drop-down list in HTML.

Parameters

	KEY
	The name for the HTML entity.

Return value

	No value is returned.

=cut



=item createContentFilter(KEY)

Creates a drop-down list in HTML.

Parameters

	KEY
	The name for the HTML entity.

Return value

	No value is returned.

=cut



=item createUser(KEY)

Creates a drop-down list in HTML.

Parameters

	KEY
	The name for the HTML entity.

Return value

	No value is returned.

=cut



=item getACTz(KEY)

Creates a drop-down list in HTML.

Parameters

	KEY
	The name for the HTML entity.

Return value

	No value is returned.

=cut



=item getVars(KEY)

Creates a drop-down list in HTML.

Parameters

	KEY
	The name for the HTML entity.

Return value

	No value is returned.

=cut



=item setVar(KEY)

Creates a drop-down list in HTML.

Parameters

	KEY
	The name for the HTML entity.

Return value

	No value is returned.

=cut



=item setSessionByAid(KEY)

Creates a drop-down list in HTML.

Parameters

	KEY
	The name for the HTML entity.

Return value

	No value is returned.

=cut



=item setAuthor(KEY)

Creates a drop-down list in HTML.

Parameters

	KEY
	The name for the HTML entity.

Return value

	No value is returned.

=cut



=item setBlock(KEY)

Creates a drop-down list in HTML.

Parameters

	KEY
	The name for the HTML entity.

Return value

	No value is returned.

=cut



=item newVar(KEY)

Creates a drop-down list in HTML.

Parameters

	KEY
	The name for the HTML entity.

Return value

	No value is returned.

=cut



=item createAuthor(KEY)

Creates a drop-down list in HTML.

Parameters

	KEY
	The name for the HTML entity.

Return value

	No value is returned.

=cut



=item updateCommentTotals(KEY)

Creates a drop-down list in HTML.

Parameters

	KEY
	The name for the HTML entity.

Return value

	No value is returned.

=cut



=item getCommentCid(KEY)

Creates a drop-down list in HTML.

Parameters

	KEY
	The name for the HTML entity.

Return value

	No value is returned.

=cut



=item deleteComment(KEY)

Creates a drop-down list in HTML.

Parameters

	KEY
	The name for the HTML entity.

Return value

	No value is returned.

=cut



=item getCommentPid(KEY)

Creates a drop-down list in HTML.

Parameters

	KEY
	The name for the HTML entity.

Return value

	No value is returned.

=cut



=item setSection(KEY)

Creates a drop-down list in HTML.

Parameters

	KEY
	The name for the HTML entity.

Return value

	No value is returned.

=cut



=item setStoriesCount(KEY)

Creates a drop-down list in HTML.

Parameters

	KEY
	The name for the HTML entity.

Return value

	No value is returned.

=cut



=item getSectionTitle(KEY)

Creates a drop-down list in HTML.

Parameters

	KEY
	The name for the HTML entity.

Return value

	No value is returned.

=cut



=item deleteSubmission(KEY)

Creates a drop-down list in HTML.

Parameters

	KEY
	The name for the HTML entity.

Return value

	No value is returned.

=cut



=item deleteSession(KEY)

Creates a drop-down list in HTML.

Parameters

	KEY
	The name for the HTML entity.

Return value

	No value is returned.

=cut



=item deleteAuthor(KEY)

Creates a drop-down list in HTML.

Parameters

	KEY
	The name for the HTML entity.

Return value

	No value is returned.

=cut



=item deleteTopic(KEY)

Creates a drop-down list in HTML.

Parameters

	KEY
	The name for the HTML entity.

Return value

	No value is returned.

=cut



=item revertBlock(KEY)

Creates a drop-down list in HTML.

Parameters

	KEY
	The name for the HTML entity.

Return value

	No value is returned.

=cut



=item deleteBlock(KEY)

Creates a drop-down list in HTML.

Parameters

	KEY
	The name for the HTML entity.

Return value

	No value is returned.

=cut



=item deleteSection(KEY)

Creates a drop-down list in HTML.

Parameters

	KEY
	The name for the HTML entity.

Return value

	No value is returned.

=cut



=item deleteContentFilter(KEY)

Creates a drop-down list in HTML.

Parameters

	KEY
	The name for the HTML entity.

Return value

	No value is returned.

=cut



=item saveTopic(KEY)

Creates a drop-down list in HTML.

Parameters

	KEY
	The name for the HTML entity.

Return value

	No value is returned.

=cut



=item saveBlock(KEY)

Creates a drop-down list in HTML.

Parameters

	KEY
	The name for the HTML entity.

Return value

	No value is returned.

=cut



=item saveColorBlock(KEY)

Creates a drop-down list in HTML.

Parameters

	KEY
	The name for the HTML entity.

Return value

	No value is returned.

=cut



=item getSectionBlock(KEY)

Creates a drop-down list in HTML.

Parameters

	KEY
	The name for the HTML entity.

Return value

	No value is returned.

=cut



=item getAuthorDescription(KEY)

Creates a drop-down list in HTML.

Parameters

	KEY
	The name for the HTML entity.

Return value

	No value is returned.

=cut



=item getPollVoter(KEY)

Creates a drop-down list in HTML.

Parameters

	KEY
	The name for the HTML entity.

Return value

	No value is returned.

=cut



=item savePollQuestion(KEY)

Creates a drop-down list in HTML.

Parameters

	KEY
	The name for the HTML entity.

Return value

	No value is returned.

=cut



=item getPollQuestionList(KEY)

Creates a drop-down list in HTML.

Parameters

	KEY
	The name for the HTML entity.

Return value

	No value is returned.

=cut



=item getPollAnswers(KEY)

Creates a drop-down list in HTML.

Parameters

	KEY
	The name for the HTML entity.

Return value

	No value is returned.

=cut



=item getPollQuestions(KEY)

Creates a drop-down list in HTML.

Parameters

	KEY
	The name for the HTML entity.

Return value

	No value is returned.

=cut



=item deleteStory(KEY)

Creates a drop-down list in HTML.

Parameters

	KEY
	The name for the HTML entity.

Return value

	No value is returned.

=cut



=item deleteStoryAll(KEY)

Creates a drop-down list in HTML.

Parameters

	KEY
	The name for the HTML entity.

Return value

	No value is returned.

=cut



=item getBackendStories(KEY)

Creates a drop-down list in HTML.

Parameters

	KEY
	The name for the HTML entity.

Return value

	No value is returned.

=cut



=item clearStory(KEY)

Creates a drop-down list in HTML.

Parameters

	KEY
	The name for the HTML entity.

Return value

	No value is returned.

=cut



=item setStory(KEY)

Creates a drop-down list in HTML.

Parameters

	KEY
	The name for the HTML entity.

Return value

	No value is returned.

=cut



=item getSubmissionLast(KEY)

Creates a drop-down list in HTML.

Parameters

	KEY
	The name for the HTML entity.

Return value

	No value is returned.

=cut



=item getStaticBlock(KEY)

Creates a drop-down list in HTML.

Parameters

	KEY
	The name for the HTML entity.

Return value

	No value is returned.

=cut



=item getPortaldBlock(KEY)

Creates a drop-down list in HTML.

Parameters

	KEY
	The name for the HTML entity.

Return value

	No value is returned.

=cut



=item getColorBlock(KEY)

Creates a drop-down list in HTML.

Parameters

	KEY
	The name for the HTML entity.

Return value

	No value is returned.

=cut



=item getSectionBlocks(KEY)

Creates a drop-down list in HTML.

Parameters

	KEY
	The name for the HTML entity.

Return value

	No value is returned.

=cut



=item getLock(KEY)

Creates a drop-down list in HTML.

Parameters

	KEY
	The name for the HTML entity.

Return value

	No value is returned.

=cut



=item updateFormkeyId(KEY)

Creates a drop-down list in HTML.

Parameters

	KEY
	The name for the HTML entity.

Return value

	No value is returned.

=cut



=item insertFormkey(KEY)

Creates a drop-down list in HTML.

Parameters

	KEY
	The name for the HTML entity.

Return value

	No value is returned.

=cut



=item checkFormkey(KEY)

Creates a drop-down list in HTML.

Parameters

	KEY
	The name for the HTML entity.

Return value

	No value is returned.

=cut



=item checkTimesPosted(KEY)

Creates a drop-down list in HTML.

Parameters

	KEY
	The name for the HTML entity.

Return value

	No value is returned.

=cut



=item formSuccess(KEY)

Creates a drop-down list in HTML.

Parameters

	KEY
	The name for the HTML entity.

Return value

	No value is returned.

=cut



=item formFailure(KEY)

Creates a drop-down list in HTML.

Parameters

	KEY
	The name for the HTML entity.

Return value

	No value is returned.

=cut



=item formAbuse(KEY)

Creates a drop-down list in HTML.

Parameters

	KEY
	The name for the HTML entity.

Return value

	No value is returned.

=cut



=item checkForm(KEY)

Creates a drop-down list in HTML.

Parameters

	KEY
	The name for the HTML entity.

Return value

	No value is returned.

=cut



=item currentAdmin(KEY)

Creates a drop-down list in HTML.

Parameters

	KEY
	The name for the HTML entity.

Return value

	No value is returned.

=cut



=item getTopNewsstoryTopics(KEY)

Creates a drop-down list in HTML.

Parameters

	KEY
	The name for the HTML entity.

Return value

	No value is returned.

=cut



=item getPoll(KEY)

Creates a drop-down list in HTML.

Parameters

	KEY
	The name for the HTML entity.

Return value

	No value is returned.

=cut



=item getSubmissionsSections(KEY)

Creates a drop-down list in HTML.

Parameters

	KEY
	The name for the HTML entity.

Return value

	No value is returned.

=cut



=item getSubmissionsPending(KEY)

Creates a drop-down list in HTML.

Parameters

	KEY
	The name for the HTML entity.

Return value

	No value is returned.

=cut



=item getSubmissionCount(KEY)

Creates a drop-down list in HTML.

Parameters

	KEY
	The name for the HTML entity.

Return value

	No value is returned.

=cut



=item getPortals(KEY)

Creates a drop-down list in HTML.

Parameters

	KEY
	The name for the HTML entity.

Return value

	No value is returned.

=cut



=item getPortalsCommon(KEY)

Creates a drop-down list in HTML.

Parameters

	KEY
	The name for the HTML entity.

Return value

	No value is returned.

=cut



=item countComments(KEY)

Creates a drop-down list in HTML.

Parameters

	KEY
	The name for the HTML entity.

Return value

	No value is returned.

=cut



=item method(KEY)

Creates a drop-down list in HTML.

Parameters

	KEY
	The name for the HTML entity.

Return value

	No value is returned.

=cut



=item countStory(KEY)

Creates a drop-down list in HTML.

Parameters

	KEY
	The name for the HTML entity.

Return value

	No value is returned.

=cut



=item checkForModerator(KEY)

Creates a drop-down list in HTML.

Parameters

	KEY
	The name for the HTML entity.

Return value

	No value is returned.

=cut



=item getAuthorAids(KEY)

Creates a drop-down list in HTML.

Parameters

	KEY
	The name for the HTML entity.

Return value

	No value is returned.

=cut



=item refreshStories(KEY)

Creates a drop-down list in HTML.

Parameters

	KEY
	The name for the HTML entity.

Return value

	No value is returned.

=cut



=item getStoryByTime(KEY)

Creates a drop-down list in HTML.

Parameters

	KEY
	The name for the HTML entity.

Return value

	No value is returned.

=cut



=item countStories(KEY)

Creates a drop-down list in HTML.

Parameters

	KEY
	The name for the HTML entity.

Return value

	No value is returned.

=cut



=item setModeratorVotes(KEY)

Creates a drop-down list in HTML.

Parameters

	KEY
	The name for the HTML entity.

Return value

	No value is returned.

=cut



=item setMetaMod(KEY)

Creates a drop-down list in HTML.

Parameters

	KEY
	The name for the HTML entity.

Return value

	No value is returned.

=cut



=item getModeratorLast(KEY)

Creates a drop-down list in HTML.

Parameters

	KEY
	The name for the HTML entity.

Return value

	No value is returned.

=cut



=item getModeratorLogRandom(KEY)

Creates a drop-down list in HTML.

Parameters

	KEY
	The name for the HTML entity.

Return value

	No value is returned.

=cut



=item countUsers(KEY)

Creates a drop-down list in HTML.

Parameters

	KEY
	The name for the HTML entity.

Return value

	No value is returned.

=cut



=item countStoriesStuff(KEY)

Creates a drop-down list in HTML.

Parameters

	KEY
	The name for the HTML entity.

Return value

	No value is returned.

=cut



=item countStoriesAuthors(KEY)

Creates a drop-down list in HTML.

Parameters

	KEY
	The name for the HTML entity.

Return value

	No value is returned.

=cut



=item countPollquestions(KEY)

Creates a drop-down list in HTML.

Parameters

	KEY
	The name for the HTML entity.

Return value

	No value is returned.

=cut



=item saveVars(KEY)

Creates a drop-down list in HTML.

Parameters

	KEY
	The name for the HTML entity.

Return value

	No value is returned.

=cut



=item setCommentCleanup(KEY)

Creates a drop-down list in HTML.

Parameters

	KEY
	The name for the HTML entity.

Return value

	No value is returned.

=cut



=item countUsersIndexExboxesByBid(KEY)

Creates a drop-down list in HTML.

Parameters

	KEY
	The name for the HTML entity.

Return value

	No value is returned.

=cut



=item getCommentReply(KEY)

Creates a drop-down list in HTML.

Parameters

	KEY
	The name for the HTML entity.

Return value

	No value is returned.

=cut



=item getCommentsForUser(KEY)

Creates a drop-down list in HTML.

Parameters

	KEY
	The name for the HTML entity.

Return value

	No value is returned.

=cut



=item getComments(KEY)

Creates a drop-down list in HTML.

Parameters

	KEY
	The name for the HTML entity.

Return value

	No value is returned.

=cut



=item getStories(KEY)

Creates a drop-down list in HTML.

Parameters

	KEY
	The name for the HTML entity.

Return value

	No value is returned.

=cut



=item getCommentsTop(KEY)

Creates a drop-down list in HTML.

Parameters

	KEY
	The name for the HTML entity.

Return value

	No value is returned.

=cut



=item getQuickies(KEY)

Creates a drop-down list in HTML.

Parameters

	KEY
	The name for the HTML entity.

Return value

	No value is returned.

=cut



=item setQuickies(KEY)

Creates a drop-down list in HTML.

Parameters

	KEY
	The name for the HTML entity.

Return value

	No value is returned.

=cut



=item getSubmissionForUser(KEY)

Creates a drop-down list in HTML.

Parameters

	KEY
	The name for the HTML entity.

Return value

	No value is returned.

=cut



=item getSearch(KEY)

Creates a drop-down list in HTML.

Parameters

	KEY
	The name for the HTML entity.

Return value

	No value is returned.

=cut



=item getNewstoryTitle(KEY)

Creates a drop-down list in HTML.

Parameters

	KEY
	The name for the HTML entity.

Return value

	No value is returned.

=cut



=item getSearchUsers(KEY)

Creates a drop-down list in HTML.

Parameters

	KEY
	The name for the HTML entity.

Return value

	No value is returned.

=cut



=item getSearchStory(KEY)

Creates a drop-down list in HTML.

Parameters

	KEY
	The name for the HTML entity.

Return value

	No value is returned.

=cut



=item getTrollAddress(KEY)

Creates a drop-down list in HTML.

Parameters

	KEY
	The name for the HTML entity.

Return value

	No value is returned.

=cut



=item getTrollUID(KEY)

Creates a drop-down list in HTML.

Parameters

	KEY
	The name for the HTML entity.

Return value

	No value is returned.

=cut



=item setCommentCount(KEY)

Creates a drop-down list in HTML.

Parameters

	KEY
	The name for the HTML entity.

Return value

	No value is returned.

=cut



=item saveStory(KEY)

Creates a drop-down list in HTML.

Parameters

	KEY
	The name for the HTML entity.

Return value

	No value is returned.

=cut



=item getSlashConf(KEY)

Creates a drop-down list in HTML.

Parameters

	KEY
	The name for the HTML entity.

Return value

	No value is returned.

=cut



=item autoUrl(KEY)

Creates a drop-down list in HTML.

Parameters

	KEY
	The name for the HTML entity.

Return value

	No value is returned.

=cut



=item getUrlFromTitle(KEY)

Creates a drop-down list in HTML.

Parameters

	KEY
	The name for the HTML entity.

Return value

	No value is returned.

=cut



=item getTime(KEY)

Creates a drop-down list in HTML.

Parameters

	KEY
	The name for the HTML entity.

Return value

	No value is returned.

=cut



=item getDay(KEY)

Creates a drop-down list in HTML.

Parameters

	KEY
	The name for the HTML entity.

Return value

	No value is returned.

=cut



=item getStoryList(KEY)

Creates a drop-down list in HTML.

Parameters

	KEY
	The name for the HTML entity.

Return value

	No value is returned.

=cut



=item updateStory(KEY)

Creates a drop-down list in HTML.

Parameters

	KEY
	The name for the HTML entity.

Return value

	No value is returned.

=cut



=item getPollVotesMax(KEY)

Creates a drop-down list in HTML.

Parameters

	KEY
	The name for the HTML entity.

Return value

	No value is returned.

=cut



=item saveExtras(KEY)

Creates a drop-down list in HTML.

Parameters

	KEY
	The name for the HTML entity.

Return value

	No value is returned.

=cut



=item getKeys(KEY)

Creates a drop-down list in HTML.

Parameters

	KEY
	The name for the HTML entity.

Return value

	No value is returned.

=cut



=item getStory(KEY)

Creates a drop-down list in HTML.

Parameters

	KEY
	The name for the HTML entity.

Return value

	No value is returned.

=cut



=item getAuthor(KEY)

Creates a drop-down list in HTML.

Parameters

	KEY
	The name for the HTML entity.

Return value

	No value is returned.

=cut



=item getAuthors(KEY)

Creates a drop-down list in HTML.

Parameters

	KEY
	The name for the HTML entity.

Return value

	No value is returned.

=cut



=item getPollQuestion(KEY)

Creates a drop-down list in HTML.

Parameters

	KEY
	The name for the HTML entity.

Return value

	No value is returned.

=cut



=item getBlock(KEY)

Creates a drop-down list in HTML.

Parameters

	KEY
	The name for the HTML entity.

Return value

	No value is returned.

=cut



=item getTopic(KEY)

Creates a drop-down list in HTML.

Parameters

	KEY
	The name for the HTML entity.

Return value

	No value is returned.

=cut



=item getTopics(KEY)

Creates a drop-down list in HTML.

Parameters

	KEY
	The name for the HTML entity.

Return value

	No value is returned.

=cut



=item getContentFilter(KEY)

Creates a drop-down list in HTML.

Parameters

	KEY
	The name for the HTML entity.

Return value

	No value is returned.

=cut



=item getSubmission(KEY)

Creates a drop-down list in HTML.

Parameters

	KEY
	The name for the HTML entity.

Return value

	No value is returned.

=cut



=item getSection(KEY)

Creates a drop-down list in HTML.

Parameters

	KEY
	The name for the HTML entity.

Return value

	No value is returned.

=cut



=item getSections(KEY)

Creates a drop-down list in HTML.

Parameters

	KEY
	The name for the HTML entity.

Return value

	No value is returned.

=cut



=item getModeratorLog(KEY)

Creates a drop-down list in HTML.

Parameters

	KEY
	The name for the HTML entity.

Return value

	No value is returned.

=cut



=item getNewStory(KEY)

Creates a drop-down list in HTML.

Parameters

	KEY
	The name for the HTML entity.

Return value

	No value is returned.

=cut



=item getVar(KEY)

Creates a drop-down list in HTML.

Parameters

	KEY
	The name for the HTML entity.

Return value

	No value is returned.

=cut



=item setUser(KEY)

Creates a drop-down list in HTML.

Parameters

	KEY
	The name for the HTML entity.

Return value

	No value is returned.

=cut



=item getUser(KEY)

Creates a drop-down list in HTML.

Parameters

	KEY
	The name for the HTML entity.

Return value

	No value is returned.

=cut



=item createBlock(KEY)

Creates a drop-down list in HTML.

Parameters

	KEY
	The name for the HTML entity.

Return value

	No value is returned.

=cut



=item createMenuItem(KEY)

Creates a drop-down list in HTML.

Parameters

	KEY
	The name for the HTML entity.

Return value

	No value is returned.

=cut



=item getMenuItems(KEY)

Creates a drop-down list in HTML.

Parameters

	KEY
	The name for the HTML entity.

Return value

	No value is returned.

=cut



=item getMenus(KEY)

Creates a drop-down list in HTML.

Parameters

	KEY
	The name for the HTML entity.

Return value

	No value is returned.

=cut


=head1 AUTHOR

Brian Aker, brian@tangent.org

=head1 SEE ALSO

Slash(3).

=cut
