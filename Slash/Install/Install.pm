# This code is a part of Slash, which is Copyright 1997-2001 OSDN, and
# released under the GPL.  See README and COPYING for more information.
# $Id$

package Slash::Install;
use strict;
use vars qw($VERSION @ISA @EXPORT @EXPORT_OK);
use DBIx::Password;
use Slash;
use Slash::DB::Utility;
use File::Copy;
use File::Find;
use File::Path;

# BENDER: Like most of life's problems, this one can be solved with bending.

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

sub getValue{
	my ($self, $key) = @_;
	my $count = $self->sqlCount('site_info', "name=" . $self->sqlQuote($key));
	my $value;
	unless($count > 1) {
		($value) = $self->sqlSelect('value', 'site_info', "name=" . $self->sqlQuote($key));
	} else {
		$value = $self->sqlSelectColArrayref('value', 'site_info', "name=" . $self->sqlQuote($key));
	}

	return $value;
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

sub installPlugin {
	my ($self, $answers, $plugins) = @_;
	$plugins ||= $self->{'_plugins'};
	for(@$answers) {
		my $answer = $_;
		for(keys %$plugins) {
			if($answer eq $plugins->{$_}{order}) {
				_install($self,$plugins->{$_});
			}
		}
	}
}

sub _install {
	my ($self, $plugin) = @_;
	# Yes, performance wise this is questionable, if getValue() was
	# cached.... who cares this is the install. -Brian
	my $hostname = $self->getValue('basedomain');
	my $email = $self->getValue('adminmail');
	my $driver = $self->getValue('db_driver');
	my $prefix_site = $self->getValue('site_install_directory');
	for(@{$plugin->{'htdoc'}}) {
		copy "$plugin->{'dir'}/$_", "$prefix_site/htdocs";
		chmod(0755, "$prefix_site/htdocs/$_");
	}
	my($sql, @sql, @create);

	if ($plugin->{"${driver}_schema"}) {
		if (my $schema_file = "$plugin->{dir}/" . $plugin->{"${driver}_schema"}) {
			open(CREATE, "< $schema_file");
			while (<CREATE>) {
				chomp;
				next if /^#/;
				next if /^$/;
				next if /^ $/;
				push @create, $_;
			}
			close (CREATE);

			$sql = join '', @create;
			@sql = split /;/, $sql;
		}
	}

	if ($plugin->{"${driver}_dump"}) {
		if (my $dump_file = "$plugin->{dir}/" . $plugin->{"${driver}_dump"}) {
			open(DUMP,"< $dump_file");
			while(<DUMP>) {
				next unless /^INSERT/;
				chomp;
				s/www\.example\.com/$hostname/g;
				s/admin\@example\.com/$email/g;
				push @sql, $_;
			}
			close(DUMP);
		}
	}

	for (@sql) {
		next unless $_;
		unless ($self->sqlDo($_)) {
			print "Failed on :$_:\n";
		}
	}

	for(@{$plugin->{'htdoc'}}) {
		copy "$plugin->{'dir'}/$_", "$prefix_site/htdocs";
	}

	for(@{$plugin->{'image'}}) {
		copy "$plugin->{'dir'}/$_", "$prefix_site/htdocs/images";
	}
	if ($plugin->{note}) {
		my $file = "$plugin->{dir}/$plugin->{note}";  
		open(FILE, $file);
		while(<FILE>) {
			print;
			}
		}
}

sub getPluginList {
	my ($self, $prefix) = @_;
	$self->{'_install_dir'} = $prefix;
	opendir(PLUGINDIR, "$prefix/plugins");
	my %plugins;
	while(my $dir = readdir(PLUGINDIR)) {
		chomp($dir);
		next if $dir =~ /^\.$/;
		next if $dir =~ /^\.\.$/;
		next if $dir =~ /^CVS$/;
		open(PLUGIN,"<$prefix/plugins/$dir/PLUGIN") or next; 
		$plugins{$dir}->{'dir'} = "$prefix/plugins/$dir/";
		$plugins{$dir}->{'name'} = $dir;
		my @info = <PLUGIN>;
		chomp(@info);
		for(@info) {
			my ($key, $val) = split(/=/, $_, 2);
			$key = lc($key);
			if( $key eq 'htdoc' ) {
				push (@{$plugins{$dir}->{$key}}, $val);
			} elsif ( $key eq 'image' ){
			} else {
				$plugins{$dir}->{$key} = $val;
			}
		}
	}
	my $x = 0;
	for(sort keys %plugins) {
		$x++;
		$plugins{$_}->{'order'} = $x;
	}

	$self->{'_plugins'} = \%plugins;
	return \%plugins;
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
