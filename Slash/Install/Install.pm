# This code is a part of Slash, and is released under the GPL.
# Copyright 1997-2001 by Open Source Development Network. See README
# and COPYING for more information, or see http://slashcode.com/.
# $Id$

package Slash::Install;
use strict;
use DBIx::Password;
use Slash;
use Slash::DB;
use File::Copy;
use File::Find;
use File::Path;
use vars qw($VERSION);
use base 'Slash::DB::Utility';

# BENDER: Like most of life's problems, this one can be solved with bending.

($VERSION) = ' $Revision$ ' =~ /\$Revision:\s+([^\s]+)/;

sub new {
	my($class, $user) = @_;
	my $self = {};
	bless($self, $class);
	$self->{virtual_user} = $user;
	$self->sqlConnect;
	$self->{slashdb} = Slash::DB->new($user);

	return $self;
}

sub create {
	my($self, $values) = @_;
	$self->sqlInsert('site_info', $values);
}

sub delete {
	my($self, $key) = @_;
	my $sql = "DELETE from site_info WHERE name = " . $self->sqlQuote($key);
	$self->sqlDo($sql);
}

sub deleteByID  {
	my($self, $key) = @_;
	my $sql = "DELETE from site_info WHERE param_id=$key";
	$self->sqlDo($sql);
}

sub get {
	my($self, $key) = @_;
	my $count = $self->sqlCount('site_info', "name=" . $self->sqlQuote($key));
	my $hash;
	if ($count > 1) {
		$hash = $self->sqlSelectAllHashref('param_id', '*', 'site_info', "name=" . $self->sqlQuote($key));
	} else {
		$hash = $self->sqlSelectHashref('*', 'site_info', "name=" . $self->sqlQuote($key));
	}

	return $hash;
}

sub exists {
	my($self, $key, $value) = @_;
	return unless $key;
	my $where;
	$where .= "name=" . $self->sqlQuote($key);
	$where .= " AND value=" . $self->sqlQuote($value) if $value;
	my $count = $self->sqlCount('site_info', $where);

	return $count;
}

sub getValue {
	my($self, $key) = @_;
	my $count = $self->sqlCount('site_info', "name=" . $self->sqlQuote($key));
	my $value;
	unless ($count > 1) {
		($value) = $self->sqlSelect('value', 'site_info', "name=" . $self->sqlQuote($key));
	} else {
		$value = $self->sqlSelectColArrayref('value', 'site_info', "name=" . $self->sqlQuote($key));
	}

	return $value;
}

sub getByID {
	my($self, $id) = @_;
	my $return = $self->sqlSelectHashref('*', 'site_info', "param_id = $id");

	return $return;
}

sub readTemplateFile {
	my($self, $filename) = @_;
	return unless -f $filename;
	my $fh = gensym;
	open($fh, "< $filename\0") or die "Can't open $filename to read from: $!";
	my @file = <$fh>;
	my %val;
	my $latch;
	for (@file) {
		if (/^__(.*)__$/) {
			$latch = $1;
			next;
		}
		$val{$latch} .= $_ if $latch;
	}
	$val{'tpid'} = undef if $val{'tpid'};
	for (qw| name page section lang seclev description title template |) {
		chomp($val{$_}) if $val{$_};
	}

	return \%val;
}

sub writeTemplateFile {
	my($self, $filename, $template) = @_;
	my $fh = gensym;
	open($fh, "> $filename\0") or die "Can't open $filename to write to: $!";
	for (keys %$template) {
		next if ($_ eq 'tpid');
		print $fh "__${_}__\n";
		$template->{$_} =~ s/\015\012/\n/g;
		print $fh "$template->{$_}\n";
	}
	close $fh;
}

sub installTheme {
	my($self, $answer, $themes, $symlink) = @_;
	$themes ||= $self->{'_themes'};

	$self->_install($themes->{$answer}, $symlink);
}

sub installPlugin {
	my($self, $answer, $plugins, $symlink) = @_;
	$plugins ||= $self->{'_plugins'};

	$self->_install($plugins->{$answer}, $symlink, 1);
}

sub installPlugins {
	my($self, $answers, $plugins, $symlink) = @_;
	$plugins ||= $self->{'_plugins'};

	for my $answer (@$answers) {
		for (keys %$plugins) {
			if ($answer eq $plugins->{$_}{order}) {
				$self->_install($plugins->{$_}, $symlink, 1);
			}
		}
	}
}

sub _install {
	my($self, $hash, $symlink, $flag) = @_;
	# Yes, performance wise this is questionable, if getValue() was
	# cached.... who cares this is the install. -Brian
	if ($self->exists('hash', $hash->{name})) {
		print STDERR "Plugin $hash->{name} has already been installed\n";
		return;
	}
	if ($flag) {
		return if $self->exists('plugin', $hash->{name});

		$self->create({
			name            => 'plugin',
			value           => $hash->{'name'},
			description     => $hash->{'description'},
		});
	} else {
		$self->create({
			name            => 'theme',
			value           => $hash->{'name'},
			description     => $hash->{'description'},
		});
	}
	my $hostname = $self->getValue('basedomain');
	my $email = $self->getValue('adminmail');
	my $driver = $self->getValue('db_driver');
	my $prefix_site = $self->getValue('site_install_directory');

	# YEs, the next bit could be cleaned up -Brian
	if ($hash->{htdoc}){
		my $filename;
		for (@{$hash->{htdoc}}) {
			if (/\//) {
				/.*\/(.*)$/;
				$filename = $1;
			} else {
				$filename = $_;
			}

			if ($symlink) {
				symlink "$hash->{dir}/$_", "$prefix_site/htdocs/$filename";
			} else {
				copy "$hash->{dir}/$_", "$prefix_site/htdocs/$filename";
				chmod 0755, "$prefix_site/htdocs/$_";
			}
		}
	}

	if ($hash->{task}){
		my $filename;
		for (@{$hash->{task}}) {
			if (/\//) {
				/.*\/(.*)$/;
				$filename = $1;
			} else {
				$filename = $_;
			}

			if ($symlink) {
				symlink "$hash->{dir}/$_", "$prefix_site/tasks/$filename";
			} else {
				copy "$hash->{dir}/$_", "$prefix_site/tasks/$filename";
				chmod 0755, "$prefix_site/tasks/$_";
			}
		}
	}

	if ($hash->{misc}){
		my $filename;
		for (@{$hash->{misc}}) {
			if (/\//) {
				/.*\/(.*)$/;
				$filename = $1;
			} else {
				$filename = $_;
			}

			if ($symlink) {
				symlink "$hash->{dir}/$_", "$prefix_site/misc/$filename";
			} else {
				copy "$hash->{dir}/$_", "$prefix_site/misc/$filename";
				chmod 0755, "$prefix_site/misc/$_";
			}
		}
	}

	if ($hash->{image}){
		my $filename;
		for (@{$hash->{image}}) {
			if (/\//) {
				/.*\/(.*)$/;
				$filename = $1;
			} else {
				$filename = $_;
			}

			if ($symlink) {
				symlink "$hash->{dir}/$_", "$prefix_site/htdocs/images/$filename";
			} else {
				copy "$hash->{dir}/$_", "$prefix_site/htdocs/images/$filename";
				chmod 0755, "$prefix_site/htdocs/images/$_";
			}
		}
	}

	if ($hash->{topic}){
		my $filename;
		for (@{$hash->{topic}}) {
			if (/\//) {
				/.*\/(.*)$/;
				$filename = $1;
			} else {
				$filename = $_;
			}

			if ($symlink) {
				symlink "$hash->{dir}/$_", "$prefix_site/htdocs/images/topics/$filename";
			} else {
				copy "$hash->{dir}/$_", "$prefix_site/htdocs/images/topics/$filename";
				chmod 0755, "$prefix_site/htdocs/images/topics/$filename";
			}
		}
	}

	my($sql, @sql, @create);

	if ($hash->{"${driver}_schema"}) {
		my $schema_file = "$hash->{dir}/" . $hash->{"${driver}_schema"};
		my $fh = gensym;
		if (open($fh, "< $schema_file\0")) {
			while (<$fh>) {
				chomp;
				next if /^#/;
				next if /^$/;
				next if /^\./;  #No hidden files! -Brian
				next if /^ $/;
				push @create, $_;
			}
			close $fh;
		} else {
			warn "Can't open $schema_file: $!";
		}

		$sql = join '', @create;
		@sql = split /;/, $sql;
	}

	if ($hash->{"${driver}_dump"}) {
		my $dump_file = "$hash->{dir}/" . $hash->{"${driver}_dump"};
		my $fh = gensym;
		if (open($fh, "< $dump_file\0")) {
			while (<$fh>) {
				next unless /^INSERT/;
				chomp;
				s/www\.example\.com/$hostname/g;
				s/admin\@example\.com/$email/g;
				push @sql, $_;
			}
			close $fh;
		} else {
 			warn "Can't open $dump_file: $!";
 		}
 	}

	for (@sql) {
		next unless $_;
		s/;$//;
		unless ($self->sqlDo($_)) {
			print "Failed on :$_:\n";
		}
	}

	if ($hash->{'plugin'}) {
		for (keys %{$hash->{'plugin'}}) {
			$self->installPlugin($_, 0, $symlink);
		}
	}

	if ($hash->{'template'}) {
		for (@{$hash->{'template'}}) {
			my $id;
			my $template = $self->readTemplateFile("$hash->{'dir'}/$_");
			if ($template and ($id = $self->{slashdb}->existsTemplate($template))) {
				$self->{slashdb}->setTemplate($id, $template);
			} elsif ($template) {
				$self->{slashdb}->createTemplate($template);
			} else {
				warn "Can't open template file $_: $!";
			}
		}
	}

	if ($hash->{"${driver}_prep"}) {
		my $prep_file = "$hash->{dir}/" . $hash->{"${driver}_prep"};
		my $fh = gensym;
		if (open($fh, "< $prep_file\0")) {
			while (<$fh>) {
				next unless /^INSERT/;
				next unless /^UPDATE/;
				next unless /^REPLACE/;
				next unless /^ALTER/;
				chomp;
				s/www\.example\.com/$hostname/g;
				s/admin\@example\.com/$email/g;
				push @sql, $_;
			}
			close $fh;
		} else {
 			warn "Can't open $prep_file: $!";
 		}
 	}

	if ($hash->{note}) {
		my $file = "$hash->{dir}/$hash->{note}";
		my $fh = gensym;
		if (open($fh, "< $file\0")) {
			print <$fh>;
			close $fh;
		} else {
			warn "Can't open $file: $!";
		}
	}
}

sub getPluginList {
	return _getList(@_, 'plugins', 'PLUGIN');
}

sub getThemeList {
	return _getList(@_, 'themes', 'THEME');
}

sub _getList {
	my($self, $prefix, $subdir, $type) = @_;
	$self->{'_install_dir'} = $prefix;

	my $dh = gensym;
	unless (opendir($dh, "$prefix/$subdir")) {
		warn "Can't opendir $prefix/$subdir: $!";
		return;
	}

	my %hash;
	while (my $dir = readdir($dh)) {
		next if $dir =~ /^\.$/;
		next if $dir =~ /^\.\.$/;
		next if $dir =~ /^CVS$/;
		my $fh = gensym;
		open($fh, "< $prefix/$subdir/$dir/$type\0") or next;
		$hash{$dir}->{'dir'} = "$prefix/$subdir/$dir";
		#This should be overridden by the actual name of the plugin
		$hash{$dir}->{'name'} = $dir;

		my @info;
		{
			local $/;
			@info = split /\015\012?|\012/, <$fh>;
		}

		for (@info) {
			next if /^#/;
			my($key, $val) = split(/=/, $_, 2);
			$key = lc $key;
			if ($key =~ /^(htdoc|template|image|task|misc|topic)s?$/) {
				push @{$hash{$dir}->{$key}}, $val;
			} elsif ($key =~ /^(plugin)s?$/) {
				$hash{$dir}->{plugin}{$val} = 1;
			} else {
				$hash{$dir}->{$key} = $val;
			}
		}
	}
	my $x = 0;
	for (sort keys %hash) {
		$x++;
		$hash{$_}->{'order'} = $x;
	}

	$self->{"_" . $subdir} = \%hash;
	return \%hash;
}

sub reloadArmors {
	my($self, $armors) = @_;
	my $count = 0;

	$self->sqlDo('DELETE FROM spamarmors');
	for (@{$armors}) {
		$_->{'-armor_id'} = 'null';
		$self->sqlInsert('spamarmors', $_) && $count++;
	}

	return $count;
}

1;

__END__

=head1 NAME

Slash::Install - Install libraries for slash

=head1 SYNOPSIS

	use Slash::Install;

=head1 DESCRIPTION

This was deciphered from crop circles.

=head1 SEE ALSO

Slash(3).

=cut
