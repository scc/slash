#!perl -w
# we could probably add these in automatically with some work, but it
# would be somewhat unreliable, so we need to keep this file up to date
# just record what module depends on what

use Data::Dumper;

my %data = (
	'Slash' => [qw(
		Slash::DB
		Slash::Display
		Slash::Utility
	)],
	'Slash::Apache' => [qw(
		Slash::DB
		Slash::Utility
	)],
	'Slash::Apache::Log' => [qw(
		Slash::Utility
	)],
	'Slash::Apache::User' => [qw(
		Slash::Utility
	)],
	'Slash::DB' => [qw(
		Slash::DB::Utility
	)],
	'Slash::DB::MySQL' => [qw(
		Slash::DB
		Slash::DB::Utility
		Slash::Utility
	)],
	'Slash::DB::Static::MySQL' => [qw(
		Slash::DB::Utility
		Slash::Utility
	)],
	'Slash::DB::Utility' => [qw(
		Slash::Utility
	)],
	'Slash::Display' => [qw(
		Slash::Display::Provider
		Slash::Utility::Data
		Slash::Utility::Environment
		Slash::Utility::System
	)],
	'Slash::Display::Plugin' => [qw(
		Slash
		Slash::Utility
	)],
	'Slash::Display::Provider' => [qw(
		Slash::Utility::Environment
	)],
	'Slash::Install' => [qw(
		Slash
		Slash::DB
		Slash::DB::Utility
	)],
	'Slash::Utility' => [qw(
		Slash::Utility::Anchor
		Slash::Utility::Data
		Slash::Utility::Display
		Slash::Utility::Environment
		Slash::Utility::PostCheck
		Slash::Utility::System
	)],
	'Slash::Utility::Anchor' => [qw(
		Slash::Display
		Slash::Utility::Data
		Slash::Utility::Display
		Slash::Utility::Environment
	)],
	'Slash::Utility::Data' => [qw(
		Slash::Utility::Environment
	)],
	'Slash::Utility::Display' => [qw(
		Slash::Display
		Slash::Utility::Environment
	)],
	'Slash::Utility::Environment' => [qw(
	)],
	'Slash::Utility::PostCheck' => [qw(
		Slash::Display
		Slash::Utility::Environment
	)],
	'Slash::Utility::System' => [qw(
		Slash::Utility::Environment
	)],
);

for my $class (keys %data) {
	my $aref = $data{$class};
	$data{$class} = { map { ($_ => 1) } @$aref };
}

my %checked;
for my $class (keys %data) {
	for my $sub (keys %{$data{$class}}) {
		check($class, $sub, [$class, $sub]);
	}
}

print "All OK!\n";

sub check {
	my($class, $sub, $trace) = @_;

	return if $checked{$class,$sub};
	$checked{$class,$sub}++;

	for (keys %{$data{$sub}}) {
		my $ntrace = [@$trace, $_, $class];
		local $" = " =>\n\t";
		if (exists $data{$_}{$class}) {
			die "damn:\n\t@$ntrace\n";
		}
		check($class, $_, [@$trace, $_]);
	}
}


__END__
