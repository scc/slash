#!perl -w
# we could probably add these in automatically with some work, but it
# would be somewhat unreliable, so we need to keep this file up to date
# just record what module depends on what
my %data = (
	'Slash' => {
		'Slash::DB'		=> 1,
		'Slash::Display'		=> 1,
		'Slash::Utility'		=> 1,
	},
	'Slash::Apache' => {
		'Slash::DB'			=> 1,
		'Slash::Utility'		=> 1,
	},
	'Slash::Apache::Log' => {
		'Slash::Utility'		=> 1,
	},
	'Slash::Apache::User' => {
		'Slash::Utility'		=> 1,
	},
	'Slash::DB' => {
		'Slash::DB::Utility'		=> 1,
	},
	'Slash::DB::MySQL' => {
		'Slash::DB'			=> 1,
		'Slash::DB::Utility'		=> 1,
		'Slash::Utility'		=> 1,
	},
	'Slash::DB::Static::MySQL' => {
		'Slash::DB::Utility'		=> 1,
		'Slash::Utility'		=> 1,
	},
	'Slash::DB::Utility' => {
		'Slash::Utility'		=> 1,
	},
	'Slash::Display' => {
		'Slash::Display::Provider'	=> 1,
		'Slash::Utility::Data'		=> 1,
		'Slash::Utility::Environment'	=> 1,
		'Slash::Utility::System'	=> 1,
	},
	'Slash::Display::Plugin' => {
		'Slash'				=> 1,
		'Slash::Utility'		=> 1,
	},
	'Slash::Display::Provider' => {
		'Slash::Utility::Environment'	=> 1,
	},
	'Slash::Install' => {
		'Slash'				=> 1,
		'Slash::DB'			=> 1,
		'Slash::DB::Utility'		=> 1,
	},
	'Slash::Utility' => {
		'Slash::Utility::Anchor'	=> 1,
		'Slash::Utility::Data'		=> 1,
		'Slash::Utility::Display'	=> 1,
		'Slash::Utility::Environment'	=> 1,
		'Slash::Utility::PostCheck'	=> 1,
		'Slash::Utility::System'	=> 1,
	},
	'Slash::Utility::Anchor' => {
		'Slash::Display'		=> 1,
		'Slash::Utility::Data'		=> 1,
		'Slash::Utility::Display'	=> 1,
		'Slash::Utility::Environment'	=> 1,
	},
	'Slash::Utility::Data' => {
		'Slash::Utility::Environment'	=> 1,
	},
	'Slash::Utility::Display' => {
		'Slash::Display'		=> 1,
		'Slash::Utility::Environment'	=> 1,
	},
	'Slash::Utility::Environment' => {
	},
	'Slash::Utility::PostCheck' => {
		'Slash::Utility::Environment'	=> 1,
	},
	'Slash::Utility::System' => {
		'Slash::Utility::Environment'	=> 1,
	},
);

for my $class (keys %data) {
	for my $sub (keys %{$data{$class}}) {
		check($class, $sub, [$class, $sub]);
	}
}

print "All OK!\n";

sub check {
	my($class, $sub, $trace) = @_;
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
