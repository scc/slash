package Slash::Apache;
use ExtUtils::MakeMaker;

#Kinda weird looking ain't it? -Brian

use Apache::ExtUtils qw (command_table);
use Apache::src ();

my @directives = (
	{ name			=> 'SlashVirtualUser',
	errmsg			=> 'Takes a DBIx::Password virtual name',
	args_how		=> 'TAKE1',
	req_overrive => 'RSRC_CONF'
	}
);

command_table(\@directives);

WriteMakefile(
    'NAME'	=> 'Slash::Apache',
    'VERSION_FROM' => 'Apache.pm',
    'INC'	=> Apache::src->new->inc, 
#		'INSTALLSITEARCH'	=> '/usr/local/apache/lib/perl',
#		'INSTALLSITELIB'	=> '/usr/local/apache/lib/perl',
);
