package Slash::DB;

use strict;
use DBIx::Password;

$Slash::DB::VERSION = '0.01';
# Note to me (AKA Brian) GATEWAY_INTERFACE is not working. Need
# to find something else to determine this.
sub new {
	my($class, $user) = @_;
	my $self = {};
	my $dsn = DBIx::Password::getDriver($user);
	if (defined $dsn) {
		if ($dsn =~ /mysql/) {
			require Slash::DB::MySQL;
			push(@Slash::DB::ISA, 'Slash::DB::MySQL');
			if($ENV{GATEWAY_INTERFACE}) {
				require Slash::DB::Static::MySQL;
				push(@Slash::DB::ISA, 'Slash::DB::Static::MySQL');
			}
		} elsif ($dsn =~ /oracle/) {
			require Slash::DB::Oracle;
			push(@Slash::DB::ISA, 'Slash::DB::Oracle');
			if($ENV{GATEWAY_INTERFACE}) {
				require Slash::DB::Static::Oracle;
				push(@Slash::DB::ISA, 'Slash::DB::Static::Oracle');
			}
		} elsif ($dsn =~ /Pg/) {
			require Slash::DB::PostgresSQL;
			push(@Slash::DB::ISA, 'Slash::DB::PostgresSQL');
			if($ENV{GATEWAY_INTERFACE}) {
				require Slash::DB::Static::PostgresSQL;
				push(@Slash::DB::ISA, 'Slash::DB::Static::PostgresSQL');
			}
		}
	} else {
		die "We don't support the database specified";
	}
#	push(@Slash::DB::EXPORT, 'sqlConnect');
	bless($self, $class);
	$self->{virtual_user} = $user;
	$self->SUPER::sqlConnect();
	$self->SUPER::init();
	return $self;
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

=head1 AUTHOR

Brian Aker, brian@tangent.org

=head1 SEE ALSO

Slash(3).

=cut
