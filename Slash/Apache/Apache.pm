package Slash::Apache;

use strict;

use Apache::ModuleConfig;
use Slash::DB;
require DynaLoader;
require AutoLoader;
use vars qw($VERSION @ISA);

@Slash::Apache::ISA = qw(DynaLoader);
$Slash::Apache::VERSION = '1.00';

bootstrap Slash::Apache $VERSION;

sub SlashVirtualUser ($$$) {
	my($cfg, $params, $user) = @_;
	$cfg->{VirtualUser} = $user;
	$cfg->{dbslash} = Slash::DB->new($user);
	# More of a place holder to remind me that it
	# is here. The uid will be populated once Patrick
	# finishes up with slashdotrc
	# There will need to be some get var calls here
	$cfg->{anonymous_coward_uid} = '-1';
	$cfg->{anonymous_coward} = '';
	$cfg->{adminmail} = 'admin@example.com';
	$cfg->{mailfrom} = 'reply-to@example.com';
	$cfg->{siteowner} = 'slash';
	$cfg->{datadir} = '/home/slash';
	$cfg->{basedomain} = 'www.example.com';
	$cfg->{cookiedomain} =  ''; 
	$cfg->{siteadmin} = 'admin';
	$cfg->{siteadmin_name} = 'Slash Admin';
	$cfg->{smtp_server} = 'smtp.example.com';
	$cfg->{sitename} =  'Slash Site';
	$cfg->{slogan} = 'Slashdot Like Automated Storytelling Homepage';
	$cfg->{breaking} = 100;
	$cfg->{shit} = 0; #What the hell is this?
	$cfg->{mainfontface} = 'verdana;helvetica,arial',
	$cfg->{fontbase} = 0;
	$cfg->{updatemin} = 5;
	$cfg->{archive_delay} = 60;
	$cfg->{submiss_view} = 1; 
	$cfg->{submiss_ts} = 1;
	$cfg->{articles_only} = 0; 
	$cfg->{admin_timeout} = 30;
	$cfg->{allow_anonymous} = 1;
	$cfg->{use_dept} = 1;
	$cfg->{max_depth} = 7;
	$cfg->{approvedtags} = [qw(B I P A LI OL UL EM BR TT STRONG BLOCKQUOTE DIV)];
	$cfg->{defaultsection} =  'articles';  # default section for articles
	$cfg->{http_proxy} = ''; 
	$cfg->{story_expire}  = 600;
	$cfg->{titlebar_width}  = '100%';
	$cfg->{send_mail}  = 0;
	$cfg->{authors_unlimited} = 1;
	$cfg->{metamod_sum}   = 3;
	$cfg->{maxtokens}   = 40;
	$cfg->{tokensperpoint}    = 8;
	$cfg->{maxpoints}   = 5;
	$cfg->{stir}      = 3;
	$cfg->{tokenspercomment}  = 6;
	$cfg->{down_moderations}  = -6;
	$cfg->{post_limit}    = 10;
	$cfg->{max_posts_allowed} = 30;
	$cfg->{max_submissions_allowed} = 20;
	$cfg->{submission_speed_limit}  = 300;
	$cfg->{formkey_timeframe}   = 14400;
	$cfg->{submit_categories} => ['Back'];
	$cfg->{rootdir}	= "http://$cfg->{basedomain}";
	$cfg->{absolutedir}	= $cfg->{rootdir};
	$cfg->{basedir}	= $cfg->{datadir} . "/public_html";
	$cfg->{imagedir}	= "$cfg->{rootdir}/images";
	$cfg->{rdfimg}	= "$cfg->{imagedir}/topics/topicslash.gif";
	$cfg->{cookiepath}	= URI->new($cfg->{rootdir})->path . '/';
	$cfg->{m2_mincheck} 	= int $cfg->{m2_comments} / 3;
	$cfg->{m2_maxbonus}   = int $cfg->{goodkarma} / 2;

	$cfg->{fixhrefs} = [
		[
			qr/^malda/,
			sub {
				$_[0] =~ s|malda|http://cmdrtaco.net|;
				return(
					$_[0],
					"Everything that used to be in /malda is now located at http://cmdrtaco.net"
				);
			}
		],

		[
			qr/^linux/,
			sub {
				return(
					"http://cmdrtaco.net/$_[0]",
					"Everything that used to be in /linux is now located at http://cmdrtaco.net/linux"
				);
			}
		],

	];


	# who to send daily stats reports to (email => subject)
	$cfg->{stats_reports} = {
		$cfg->{adminmail}	=> "$cfg->{sitename} Stats Report",
	};


}

1;

__END__

=head1 NAME

Slash::Apache - Apache Specific handler for Slashcode

=head1 SYNOPSIS

  use Slash::Apache;

=head1 DESCRIPTION

This is what creates the SlashVirtualUser command for us
in the httpd.conf file.

=head1 AUTHOR

Brian Aker, brian@tangent.org

=head1 SEE ALSO

perl(1). Slash(3).

=cut
