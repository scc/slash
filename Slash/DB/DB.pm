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


=head1 SEE ALSO

Slash(3), Slash::DB::Utility(3).

=cut
