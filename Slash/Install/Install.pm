package Slash::Install;
use strict;
use vars qw($VERSION @ISA @EXPORT @EXPORT_OK);
use DBIx::Password;
use Slash;
use Slash::DB::Utility;


@Slash::Install::ISA = qw(Slash::DB::Utility);
@Slash::Install::EXPORT = qw();
$Slash::Install::VERSION = '0.01';

sub new {
	my ($class, $user) = @_;
	my $self = {};
	bless ($self,$class);
	$self->{virtual_user} = $user;
	$self->sqlConnect;

	return $self;
}

sub create {
	my ($self, $values) = @_;
	$self->sqlInsert('site_info', $values);
}

sub delete {
	my ($self, $key) = @_;
	my $sql = "DELETE from site_info WHERE name = " . $self->sqlQuote($key);
	$self->sqlDo($sql);
}

sub deleteByID  {
	my ($self, $key) = @_;
	my $sql = "DELETE from site_info WHERE param_id=$key";
	$self->sqlDo($sql);
}

sub get{
	my ($self, $key) = @_;
	my $count = $self->sqlCount('site_info', "name=" . $self->sqlQuote($key));
	my $hash;
	if($count > 1) {
		$hash = $self->sqlSelectAllHashref('param_id', '*', 'site_info', "name=" . $self->sqlQuote($key));
	} else {
		$hash = $self->sqlSelectHashref('*', 'site_info', "name=" . $self->sqlQuote($key));
	}

	return $hash;
}

sub getByID {
	my ($self, $id) = @_;
	my $return = $self->sqlSelectHashref('*', 'site_info', "param_id = $id");

	return $return;
}

sub DESTROY {
	my ($self) = @_;
	$self->{_dbh}->disconnect unless ($ENV{GATEWAY_INTERFACE});
}


1;
__END__

=head1 NAME

Slash::Install - Install libraries for slash

=head1 SYNOPSIS

  use Slash::Install;
  blah blah blah

=head1 DESCRIPTION

Stub documentation for Slash::Install was created by h2xs. It looks like the
author of the extension was negligent enough to leave the stub
unedited.

Blah blah blah.

=head1 AUTHOR

A. U. Thor, a.u.thor@a.galaxy.far.far.away

=head1 SEE ALSO

perl(1).

=cut
