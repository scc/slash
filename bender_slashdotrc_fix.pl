#!/usr/bin/perl -w
use strict;
use Slash::DB;
use URI;

unless ($ARGV[0]) {
	print "	\n";
	print "	This is to jumpstart you into Bender. \n";
	print "	Please rerun the command with the first \n";
	print "	argument being the VirtualUser name used \n";
	print "	for this slashsite. \n";
	print "	This will just get you started; you will still \n";
	print "	need to modify some variable in the admin interface \n";
	print "	to get your site running. \n";
	print "	\n";

	exit 0;
}
my $slashdb = Slash::DB->new($ARGV[0]);
my %answers;
my $junk;
print "What will be the install directory? (ie /usr/local/slash)\n";
$junk = <STDIN>;
chomp $junk;
$answers{datadir} = $junk;
print "What is the domain? (aka www.slashcode.com) \n";
$junk = <STDIN>;
chomp $junk;
$answers{basedomain} = $junk;
print "Loading other defaults now.\n";
print "Good to go\n";
$answers{anonymous_coward_uid} = '-1';
$answers{adminmail} = 'admin@example.com';
$answers{mailfrom} = 'reply-to@example.com';
$answers{siteowner} = 'slash';
$answers{cookiedomain} =  ''; 
$answers{siteadmin} = 'admin';
$answers{siteadmin_name} = 'Slash Admin';
$answers{smtp_server} = 'smtp.example.com';
$answers{sitename} =  'Slash Site';
$answers{slogan} = 'Slashdot Like Automated Storytelling Homepage';
$answers{breaking} = 100;
$answers{shit} = 0;
$answers{mainfontface} = 'verdana;helvetica,arial';
$answers{fontbase} = 0;
$answers{updatemin} = 5;
$answers{archive_delay} = 60;
$answers{submiss_view} = 1; 
$answers{run_ads} = 1; 
$answers{submiss_ts} = 1;
$answers{articles_only} = 0; 
$answers{admin_timeout} = 30;
$answers{allow_anonymous} = 1;
$answers{use_dept} = 1;
$answers{max_depth} = 7;
$answers{defaultsection} =  'articles';  # default section for articles
$answers{http_proxy} = ''; 
$answers{story_expire}  = 600;
$answers{titlebar_width}  = '100%';
$answers{send_mail}  = 0;
$answers{authors_unlimited} = 1;

$answers{m2_comments} = 10;
$answers{m2_maxunfair} = 0.5;
$answers{m2_toomanyunfair} = 0.3;
$answers{m2_bonus} = '+1';
$answers{m2_penalty} = '-1';
$answers{m2_userpercentage} = 0.9;
$answers{comment_minscore} = -1;
$answers{comment_maxscore} = 5;
$answers{submission_bonus} = 3;
$answers{goodkarma} = 25;
$answers{badkarma} = -10;
$answers{maxkarma} = 50;

$answers{metamod_sum}   = 3;
$answers{maxtokens}   = 40;
$answers{tokensperpoint}    = 8;
$answers{maxpoints}   = 5;
$answers{stir}      = 3;
$answers{tokenspercomment}  = 6;
$answers{down_moderations}  = -6;

$answers{post_limit}    = 10;
$answers{max_posts_allowed} = 30;
$answers{max_submissions_allowed} = 20;
$answers{submission_speed_limit}  = 300;
$answers{formkey_timeframe}   = 14400;
$answers{rootdir}	= "http://" . $answers{basedomain};
$answers{absolutedir}	= $answers{rootdir};
$answers{basedir}	= $answers{datadir} . "/public_html";
$answers{imagedir}	= "$answers{rootdir}/images";
$answers{rdfimg}	= "$answers{imagedir}/topics/topicslash.gif";
$answers{cookiepath}	= URI->new($answers{rootdir})->path . '/';
$answers{m2_mincheck} 	= int $answers{m2_comments} / 3;
$answers{m2_maxbonus}   = int $answers{goodkarma} / 2;

while (my ($key, $value) = each %answers) {
	print "Key $key\n";
	print "Value $value\n\n";
	$slashdb->newVar($key, $value, "Not documented");
#	$slashdb->sqlInsert('vars', {name => $key, value => $slashdb->{dbh}->quote($value)}));
}
