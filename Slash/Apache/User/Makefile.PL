package Slash::Apache::User;
use ExtUtils::MakeMaker;

use Apache::ExtUtils qw (command_table);
use Apache::src ();

my @directives = (
	{ name      => 'SlashUserInit',
		errmsg      => 'Takes no arguments',
		args_how    => 'NO_ARGS',
		req_overrive => 'ACCESS_CONF'
	}

);

command_table(\@directives);


WriteMakefile(
	'NAME'	=> 'Slash::Apache::User',
	'VERSION_FROM' => 'User.pm',
	'INC'       => Apache::src->new->inc,
);
