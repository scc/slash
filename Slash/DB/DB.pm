package Slash::DB;

use strict;

$Slash::DB::VERSION = '0.01';

sub new {
  my ($class, $dsn ,$dbuser, $dbpass) = @_;
	my $self = {};
	if(defined ($dsn)){
		if($dsn =~ /mysql/) {
			eval { require Slash::DB::MySQL;};
			push(@Slash::DB::ISA, 'Slash::DB::MySQL');
		} elsif ($dsn =~ /oracle/) {
			eval { require Slash::DB::Oracle;};
			push(@Slash::DB::ISA, 'Slash::DB::Oracle');
		}elsif ($dsn =~ /postgress/) {
			eval { require Slash::DB::Postgress;};
			push(@Slash::DB::ISA, 'Slash::DB::Postgress');
		}
	} else {
		die "We don't support the database specified";
	}
	push (@Slash::DB::EXPORT, 'sqlConnect');
	bless ($self,$class);
	$self->SUPER::sqlConnect($dsn ,$dbuser, $dbpass);
	return $self;
}


1;

=head1 NAME

Slash::DB - Database Class for Slashcode

=head1 SYNOPSIS

  use Slash::DB;
  $my object = new Slash::DB("database", "user", "password");

=head1 DESCRIPTION

This package is the front end interface to slashcode.
By looking at the database parameter during creation
it determines what type of database to inherit from.

=head1 AUTHOR

Brian Aker, brian@tangent.org

=head1 SEE ALSO

Slash(3).

=cut
