package Bundle::Slash;

$Bundle::Slash::VERSION = '2.10';

1;

__END__

=head1 NAME

Bundle::Slash - A bundle to install all modules used for Slash


=head1 SYNOPSIS

C<perl -MCPAN -e 'install "Bundle::Slash"'>

=head1 CONTENTS

Net::Cmd                - libnet

Digest::MD5             - Instead of Bundle::CPAN

MD5

Compress::Zlib          - ditto

Archive::Tar            - ditto

File::Spec              - ditto

Storable

MIME::Base64            - why after URI if URI needs it?

Bundle::LWP		- URI,HTML::Parser,MIME::Base64

XML::Parser

XML::RSS

DBI

DBI::FAQ

Data::ShowTable

J/JW/JWIED/Msql-Mysql-modules-1.2216.tar.gz    - instead of Bundle::DBD::mysql (Data::ShowTable)

DBIx::Password

Apache::DBI

Apache::Cookie

AppConfig		- Should be installed with TT, but sometimes not?

Template		- Template Toolkit

Mail::Sendmail

Mail::Address

Email::Valid

Getopt::Long

Image::Size

Date::Manip             - Still needed, but not for long

Date::Parse		- TimeDate

Time::ParseDate         - Time-modules

Time::HiRes

Schedule::Cron


=head1 DESCRIPTION

mod_perl must be installed by hand, because of the special configuration
required for it.

You might want to do C<force install Net::Cmd> to start the process,
until libnet tests are fixed.

=cut
