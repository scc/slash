package Slash::DB;

use strict;

$Slash::DB::VERSION = '0.01';

sub new {
  my ($class, $user) = @_;
	my $self = {};
	my $dsn = 'mysql'; #This is just here for the moment.
	if(defined ($dsn)){
		if($dsn =~ /mysql/) {
			require Slash::DB::MySQL;
			push(@Slash::DB::ISA, 'Slash::DB::MySQL');
		} elsif ($dsn =~ /oracle/) {
			require Slash::DB::Oracle;
			push(@Slash::DB::ISA, 'Slash::DB::Oracle');
		}elsif ($dsn =~ /postgress/) {
			require Slash::DB::Postgress;
			push(@Slash::DB::ISA, 'Slash::DB::Postgress');
		}
	} else {
		die "We don't support the database specified";
	}
	push (@Slash::DB::EXPORT, 'sqlConnect');
	bless ($self,$class);
	$self->SUPER::sqlConnect($user);
	return $self;
}


1;

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
