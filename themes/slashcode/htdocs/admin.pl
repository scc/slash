#!/usr/bin/perl -w

###############################################################################
# admin.pl - this code runs the site's administrative tasks page 
#
# Copyright (C) 1997 Rob "CmdrTaco" Malda
# malda@slashdot.org
#
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License
# as published by the Free Software Foundation; either version 2
# of the License, or (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program; if not, write to the Free Software
# Foundation, Inc., 59 Temple Place - Suite 330, Boston, MA  02111-1307, USA.
#
#
#  $Id$
###############################################################################
use strict;
use Image::Size;
use Slash;
use Slash::Display;
use Slash::Utility;

sub main {
	my $slashdb = getCurrentDB();
	my $constants = getCurrentStatic();
	my $user = getCurrentUser();
	my $form = getCurrentForm();

	getSection('admin');

	my($tbtitle);
	if (($form->{op} =~ /^preview|edit$/) && $form->{title}) {
		# Show submission/article title on browser's titlebar.
		$tbtitle = $form->{title};
		$tbtitle =~ s/"/'/g;
		$tbtitle = " - \"$tbtitle\"";
		# Undef the form title value if we have SID defined, since the editor
		# will have to get this information from the database anyways.
		undef $form->{title} if ($form->{sid} && $form->{op} eq 'edit');
	}
	header("backSlash $user->{tzcode} $user->{offset}$tbtitle", 'admin');

	
	# Admin Menu
	print "<P>&nbsp;</P>" unless $user->{seclev};

	my $op = $form->{op};
	if (!$user->{seclev}) {
		titlebar('100%', getTitle('adminLogin-title'));
		adminLoginForm();

	} elsif ($op eq 'logout') {
		titlebar('100%', getTitle('adminLogout-title'));
		adminLoginForm();

	} elsif ($form->{topicdelete}) {
		topicDelete();
		topicEdit();

	} elsif ($form->{topicsave}) {
		topicSave();
		topicEdit();

	} elsif ($form->{topiced} || $form->{topicnew}) {
		topicEdit();

	} elsif ($op eq 'save') {
		saveStory();

	} elsif ($op eq 'update') {
		updateStory();

	} elsif ($op eq 'list') {
		titlebar('100%', getTitle('listStories-title'));
		listStories();

	} elsif ($op eq 'delete') {
		rmStory($form->{sid});
		listStories();

	} elsif ($op eq 'preview') {
		editStory();

	} elsif ($op eq 'edit') {
		editStory($form->{sid});

	} elsif ($op eq 'topics') {
		listTopics($user->{seclev});

	} elsif ($op eq 'colored' || $form->{colored} || $form->{colorrevert} || $form->{colorpreview}) {
		colorEdit($user->{seclev});
		$op = 'colored';

	} elsif ($form->{colorsave} || $form->{colorsavedef} || $form->{colororig}) {
		colorSave();
		colorEdit($user->{seclev});

	} elsif ($form->{blockdelete_cancel} || $op eq 'blocked') {
		blockEdit($user->{seclev},$form->{bid});

	} elsif ($form->{blocknew}) {
		blockEdit($user->{seclev});

	} elsif ($form->{blocked1}) {
		blockEdit($user->{seclev}, $form->{bid1});

	} elsif ($form->{blocked2}) {
		blockEdit($user->{seclev}, $form->{bid2});

	} elsif ($form->{blocksave} || $form->{blocksavedef}) {
		blockSave($form->{thisbid});
		blockEdit($user->{seclev}, $form->{thisbid});

	} elsif ($form->{blockrevert}) {
		$slashdb->revertBlock($form->{thisbid}) if $user->{seclev} < 500;
		blockEdit($user->{seclev}, $form->{thisbid});

	} elsif ($form->{blockdelete}) {
		blockEdit($user->{seclev},$form->{thisbid});

	} elsif ($form->{blockdelete1}) {
		blockEdit($user->{seclev},$form->{bid1});

	} elsif ($form->{blockdelete2}) {
		blockEdit($user->{seclev},$form->{bid2});

	} elsif ($form->{blockdelete_confirm}) {
		blockDelete($form->{deletebid});
		blockEdit($user->{seclev});

	} elsif ($op eq 'authors') {
		authorEdit($form->{thisaid});

	} elsif ($form->{authoredit}) {
		authorEdit($form->{myaid});

	} elsif ($form->{authornew}) {
		authorEdit();

	} elsif ($form->{authordelete}) {
		authorDelete($form->{myaid});

	} elsif ($form->{authordelete_confirm} || $form->{authordelete_cancel}) {
		authorDelete($form->{thisaid});
		authorEdit();

	} elsif ($form->{authorsave}) {
		authorSave();
		authorEdit($form->{myaid});

	} elsif ($op eq 'vars') {
		varEdit($form->{name});	

	} elsif ($op eq 'varsave') {
		varSave();
		varEdit($form->{name});

	} elsif ($op eq 'listfilters') {
		listFilters();

	} elsif ($form->{editfilter}) {
		titlebar("100%", getTitle('editFilter-title'));
		editFilter($form->{filter_id});

	} elsif ($form->{newfilter}) {
		updateFilter(1);

	} elsif ($form->{updatefilter}) {
		updateFilter(2);

	} elsif ($form->{deletefilter}) {
		updateFilter(3);

	} else {
		titlebar('100%', getTitle('listStories-title'));
		listStories();
	}


	# Display who is logged in right now.
	footer();
	writeLog('admin', $user->{uid}, $op, $form->{sid});
}

##################################################################
# Misc
sub adminLoginForm {	

	my $slashdb = getCurrentDB();
	my $user = getCurrentUser();
	my $form = getCurrentForm();
	my $constants = getCurrentStatic();

	slashDisplay('admin-adminLoginForm');
}

##################################################################
#  Variables Editor
sub varEdit {
	my($name) = @_;

	my $slashdb = getCurrentDB();
	my $user = getCurrentUser();
	my $form = getCurrentForm();
	my $constants = getCurrentStatic();
	my $varsref;

	my $vars = $slashdb->getDescriptions('vars');
	my $vars_select = createSelect('name', $vars, $name, 1);

	if($name) {
		$varsref = $slashdb->getVar($name);
	}

	slashDisplay('admin-varEdit', { 
			vars_select 	=> $vars_select,
			varsref		=> $varsref,
			}
	);
}

##################################################################
sub varSave {

	my $slashdb = getCurrentDB();
	my $user = getCurrentUser();
	my $form = getCurrentForm();
	my $constants = getCurrentStatic();

	if ($form->{thisname}) {
		$slashdb->saveVars();
		if ($form->{desc}) {
			print getMessage('varSave-message');
		} else {
			print getMessage('varDelete-message');
		}
	}
}

##################################################################
# Author Editor
sub authorEdit {
	my($aid) = @_;

	my $slashdb = getCurrentDB();
	my $user = getCurrentUser();
	my $form = getCurrentForm();
	my $constants = getCurrentStatic();

	return if $user->{seclev} < 500;

	my ($section_select,$author_select);
	my $deletebutton_flag = 0;

	$aid ||= $user->{uid};
	$aid = '' if $form->{authornew};

	my $authors = $slashdb->getDescriptions('authors');
	my $author = $slashdb->getAuthor($aid) if $aid;

	$author_select = createSelect('myaid', $authors, $aid, 1);
	$section_select = selectSection('section', $author->{section}, {}, 1) ;
	$deletebutton_flag = 1 if (! $form->{authornew} && $aid ne $user->{uid}) ;

	for ($author->{email}, $author->{copy}) {
		$_ = stripByMode($_, 'literal', 1);
	}

	slashDisplay('admin-authorEdit', {
			author 			=> $author,
			author_select		=> $author_select,
			section_select		=> $section_select,
			deletebutton_flag 	=> $deletebutton_flag,
			aid			=> $aid,
			}
	);	
}

##################################################################
sub authorSave {

	my $slashdb = getCurrentDB();
	my $user = getCurrentUser();
	my $form = getCurrentForm();
	my $constants = getCurrentStatic();

	return if $user->{seclev} < 500;
	if ($form->{thisaid}) {
		# And just why do we take two calls to do
		# a new user? 
		if ($slashdb->createAuthor($form->{thisaid})) {
			print getMessage('authorInsert-message');
		}
		if ($form->{thisaid}) {
			print getMessage('authorSave-message');
			my %author = (
				name	=> $form->{name},
				pwd	=> $form->{pwd},
				email	=> $form->{email},
				url	=> $form->{url},
				seclev	=> $form->{seclev},
				copy	=> $form->{copy},
				quote	=> $form->{quote},
				section => $form->{section}
			);
			$slashdb->setAuthor($form->{thisaid}, \%author);
		} else {
			print getMessage('authorDelete-message');
			$slashdb->deleteAuthor($form->{thisaid});
		}
	}
}

##################################################################
sub authorDelete {
	my $aid = shift;

	my $slashdb = getCurrentDB();
	my $user = getCurrentUser();
	my $form = getCurrentForm();
	my $constants = getCurrentStatic();

	return if $user->{seclev} < 500;

	print qq|<FORM ACTION="$ENV{SCRIPT_NAME}" METHOD="POST">|;
	print getMessage('authorDelete-confirm-msg', { aid => $aid }) if $form->{authordelete};

	if ($form->{authordelete_confirm}) {
		$slashdb->deleteAuthor($aid);
		print getMessage('authorDelete-deleted-msg', { aid => $aid }) if ! DBI::errstr;
	} elsif ($form->{authordelete_cancel}) {
		print getMessage('authorDelete-canceled-msg', { aid => $aid});
	}
}

##################################################################
# Block Editing and Saving 
# 020300 PMG modified the heck out of this code to allow editing
# of sectionblock values retrieve, title, url, rdf, section 
# to display a different form according to the type of block we're dealing with
# based on value of new column in blocks "type". Added description field to use 
# as information on the block to help the site editor get a feel for what the block 
# is for, etc... 
# Why bother passing seclev? Just pull it from the user object.
sub blockEdit {
	my($seclev, $bid) = @_;

	return if $seclev < 500;

	my $slashdb = getCurrentDB();
	my $user = getCurrentUser();
	my $form = getCurrentForm();
	my $constants = getCurrentStatic();

	my($hidden_bid) = "";
	my ($blockref, $saveflag, $block_select, $retrieve_checked, $portal_checked) ;
	my ($description_ta,$block_ta, $block_select1, $block_select2);
	my ($blockedit_flag,$blockdelete_flag, $blockform_flag) = (0,0,0);

	if ($bid) {
		$blockref = $slashdb->getBlock($bid, '', 1);
	}
	my $sectionbid = $blockref->{section}; 

	my $title = getTitle('blockEdit-title',{}, 1);

	if ($form->{blockdelete} || $form->{blockdelete1} || $form->{blockdelete2}) {
		$blockdelete_flag = 1;
	} else { 
		# get the static blocks
		my $blocks = $slashdb->getDescriptions('static_block', $seclev);
		$block_select1 = createSelect('bid1', $blocks, $bid, 1);

		$blocks = $slashdb->getDescriptions('portald_block', $seclev);
		$block_select2 = createSelect('bid2', $blocks, $bid, 1);

	}

	# if the pulldown has been selected and submitted 
	# or this is a block save and the block is a portald block
	# or this is a block edit via sections.pl
	if (! $form->{blocknew} && $bid ) {
		if ($blockref->{bid}) {
			$blockedit_flag = 1;
			$blockref->{ordernum} = "NA" if $blockref->{ordernum} eq '';
			$retrieve_checked = "CHECKED" if $blockref->{retrieve} == 1; 
			$portal_checked = "CHECKED" if $blockref->{portal} == 1; 
		}	
	}	

	$description_ta = stripByMode($blockref->{description}, 'literal', 1);
	$block_ta = stripByMode($blockref->{block}, 'literal', 1);

	$blockform_flag = 1 if ( (! $form->{blockdelete_confirm} && $bid) || $form->{blocknew}) ;

	slashDisplay('admin-blockEdit', {
			bid 			=> $bid,
			title 			=> $title,
			blockref		=> $blockref,
			blockedit_flag		=> $blockedit_flag,
			blockdelete_flag	=> $blockdelete_flag,
			block_select1		=> $block_select1,
			block_select2		=> $block_select2,
			blockform_flag		=> $blockform_flag,
			portal_checked		=> $portal_checked,
			retrieve_checked	=> $retrieve_checked,
			description_ta		=> $description_ta,
			block_ta		=> $block_ta,
			sectionbid		=> $sectionbid,
			}
	);	
			
}

##################################################################
sub blockSave {
	my($bid) = @_;

	my $slashdb = getCurrentDB();
	my $user = getCurrentUser();
	my $form = getCurrentForm();
	my $constants = getCurrentStatic();

	return if $user->{seclev} < 500;
	return unless $bid;
	my $saved = $slashdb->saveBlock($bid);

	if ($form->{save_new} && $saved > 0) {
		print getMessage('blockSave-exists-message', { bid => $bid } );
		return;
	}	

	if ($saved == 0) {
		print getMessage('blockSave-inserted-message', { bid => $bid });
	}
	print getMessage('blockSave-saved-message', { bid => $bid });
}

##################################################################
sub blockDelete {
	my($bid) = @_;

	my $slashdb = getCurrentDB();
	my $user = getCurrentUser();
	my $form = getCurrentForm();
	my $constants = getCurrentStatic();

	return if $user->{seclev} < 500;
	$slashdb->deleteBlock($bid);
	print getMessage('blockDelete-message', { bid => $bid });
}

##################################################################
sub colorEdit {

	my $slashdb = getCurrentDB();
	my $user = getCurrentUser();
	my $form = getCurrentForm();
	my $constants = getCurrentStatic();

	my($color_select,$block,$colorblock_clean,$title);
	my $colors = [];
	return if $user->{seclev} < 500;

	my $colorblock;
	$form->{color_block} ||= 'colors';

	if ($form->{colorpreview}) {
		$colorblock = 
		"$form->{fg0},$form->{fg1},$form->{fg2},$form->{fg3},$form->{bg0},$form->{bg1},$form->{bg2},$form->{bg3}";

		$colorblock_clean = $colorblock;
		# the #s will break the url 
		$colorblock_clean =~ s/#//g;

	} else {
		$colorblock = $slashdb->getBlock($form->{color_block}, 'block'); 
	}

	@{$colors} = split m/,/, $colorblock;

	$constants->{fg} = [@{$colors}->[0..3]];
	$constants->{bg} = [@{$colors}->[4..7]];

       	$title = getTitle('colorEdit-title');

	$block = $slashdb->getDescriptions('color_block');
	$color_select = createSelect('color_block', $block, $form->{color_block}, 1);
	
	slashDisplay('admin-colorEdit', {
			title 			=> $title,
			colorblock_clean	=> $colorblock_clean,
			colors			=> $colors,
			color_select		=> $color_select,
			}
	);
			
}

##################################################################
sub colorSave {

	my $slashdb = getCurrentDB();
	my $user = getCurrentUser();
	my $form = getCurrentForm();
	my $constants = getCurrentStatic();

	return if $user->{seclev} < 500;
	my $colorblock = join ',', @{$constants}{qw[fg0 fg1 fg2 fg3 bg0 bg1 bg2 bg3]};

	$slashdb->saveColorBlock($colorblock);
}

##################################################################
# Topic Editor
sub topicEdit {

	my $slashdb = getCurrentDB();
	my $user = getCurrentUser();
	my $form = getCurrentForm();
	my $constants = getCurrentStatic();

	return if $user->{seclev} < 1;
	my($topic, $topics_menu, $topics_select);
	my @available_images;
	my $image_select = "";

	my ($imageseen_flag,$images_flag) = (0,0);

	local *DIR;
	opendir(DIR, "$constants->{basedir}/images/topics");
	@available_images = grep(/.*\.gif|jpg/i, readdir(DIR)); 

	closedir(DIR);

	for(@available_images) {
		print STDERR "img $_\n";
	}

	$topics_menu = $slashdb->getDescriptions('topics');
	$topics_select = createSelect('nexttid', $topics_menu, $form->{nexttid},1);

	if (!$form->{topicdelete}) {

		$imageseen_flag = 1 if ($form->{nexttid} && ! $form->{topicnew} && ! $form->{topicdelete});

		if (!$form->{topicnew}) {
			$topic = $slashdb->getTopic($form->{nexttid});
		} else {
			$topic = {};
			$topic->{tid} = getTitle('topicEd-new-title',{},1);
		}

		if (@available_images) {
			$images_flag = 1;
			$image_select = qq|<SELECT name="image">|;
			$image_select .= qq|<OPTION value="">Select an image</OPTION>| if $form->{topicnew};
			for (@available_images) {
				my $selected = "SELECTED" if ($_ eq $topic->{'image'});
				$image_select .= qq|<OPTION value="$_" $selected>$_</OPTION>\n|;
				$selected = '';
			}
			$image_select .= '</SELECT>';
		} 
	}

	slashDisplay('admin-topicEdit', {
			imageseen_flag		=> $imageseen_flag,
			images_flag		=> $images_flag,
			topic			=> $topic,
			topics_select		=> $topics_select,
			image_select		=> $image_select
			}
	);
			
}

##################################################################
sub topicDelete {

	my $slashdb = getCurrentDB();
	my $user = getCurrentUser();
	my $form = getCurrentForm();
	my $constants = getCurrentStatic();

	my $tid = $_[0] || $form->{tid};
	print "<B>Deleted $tid!</B><BR>";
	$slashdb->deleteTopic($form->{tid});
	$form->{tid} = '';
}

##################################################################
sub topicSave {

	my $slashdb = getCurrentDB();
	my $user = getCurrentUser();
	my $form = getCurrentForm();
	my $constants = getCurrentStatic();

	if ($form->{tid}) {
		$slashdb->saveTopic();
		if (!$form->{width} && !$form->{height}) {
		    @{ $form }{'width', 'height'} = imgsize("$constants->{basedir}/images/topics/$form->{image}");
		}
	}
	
	$form->{nexttid} = $form->{tid};

	print getMessage('topicSave-message');
}

##################################################################
sub listTopics {
	my($seclev) = @_;

	my $slashdb = getCurrentDB();
	my $user = getCurrentUser();
	my $form = getCurrentForm();
	my $constants = getCurrentStatic();

	my $topics = $slashdb->getTopics();
	titlebar('100%', getTitle('listTopics-title'));

	my $x = 0;

	print qq[\n<!-- begin listtopics -->\n<TABLE WIDTH="600" ALIGN="CENTER">];
	for my $topic (values %$topics) {
		if ($x == 0) {
			print "<TR>\n";
		} elsif ($x++ % 6) {
			print "</TR><TR>\n";
		}
		print qq!\t<TD ALIGN="CENTER">\n!;

		if ($seclev > 500) {
			print qq[\t\t<A HREF="$ENV{SCRIPT_NAME}?op=topiced&nexttid=$topic->{tid}">];
		} else {
			print qq[\t\t<A NAME="">];
		}

		print qq[<IMG SRC="$constants->{imagedir}/topics/$topic->{image}" ALT="$topic->{alttext}"
			WIDTH="$topic->{width}" HEIGHT="$topic->{height}" BORDER="0"><BR>$topic->{tid}</A>\n\t</TD>\n];

	}
	print "</TR></TABLE>\n<!-- end listtopics -->\n";
}

##################################################################
# hmmm, what do we want to do with this sub ? PMG 10/18/00
sub importImage {
	# Check for a file upload
	my $section = $_[0];

	my $slashdb = getCurrentDB();
	my $user = getCurrentUser();
	my $form = getCurrentForm();
	my $constants = getCurrentStatic();

 	my $filename = $form->{'importme'};
	my $tf = getsiddir() . $filename;
	$tf =~ s|/|~|g;
	$tf = "$section~$tf";

	if ($filename) {
		local *IMAGE;
		system("mkdir /tmp/slash");
		open(IMAGE, ">>/tmp/slash/$tf");
		my $buffer;
		while (read $filename, $buffer, 1024) {
			print IMAGE $buffer;
		}
		close IMAGE;
	} else {
		return "<image:not found>";
	}

	my($w, $h) = imgsize("/tmp/slash/$tf");
	return qq[<IMG SRC="$constants->{rootdir}/$section/] .  getsiddir() . $filename
		. qq[" WIDTH="$w" HEIGHT="$h" ALT="$section">];
}

##################################################################
sub importFile {
	# Check for a file upload
	my $section = $_[0];

	my $slashdb = getCurrentDB();
	my $user = getCurrentUser();
	my $form = getCurrentForm();
	my $constants = getCurrentStatic();

 	my $filename = $form->{'importme'};
	my $tf = getsiddir() . $filename;
	$tf =~ s|/|~|g;
	$tf = "$section~$tf";

	if ($filename) {
		system("mkdir /tmp/slash");
		open(IMAGE, ">>/tmp/slash/$tf");
		my $buffer;
		while (read $filename, $buffer, 1024) {
			print IMAGE $buffer;
		}
		close IMAGE;
	} else {
		return "<attach:not found>";
	}
	return qq[<A HREF="$constants->{rootdir}/$section/] . getsiddir() . $filename
		. qq[">Attachment</A>];
}

##################################################################
sub importText {

	my $slashdb = getCurrentDB();
	my $user = getCurrentUser();
	my $form = getCurrentForm();
	my $constants = getCurrentStatic();

	# Check for a file upload
 	my $filename = $form->{'importme'};
	my($r, $buffer);
	if ($filename) {
		while (read $filename, $buffer, 1024) {
			$r .= $buffer;
		}
	}
	return $r;
}

##################################################################
# Generated the 'Related Links' for Stories
sub getRelated {
	my ($story_content) = @_;

	my $constants = getCurrentStatic();
	my $related_links = "";

	my %relatedLinks = (
		intel		=> "Intel;http://www.intel.com",
		linux		=> "Linux;http://www.linux.com",
		lycos		=> "Lycos;http://www.lycos.com",
		redhat		=> "Red Hat;http://www.redhat.com",
		'red hat'	=> "Red Hat;http://www.redhat.com",
		wired		=> "Wired;http://www.wired.com",
		netscape	=> "Netscape;http://www.netscape.com",
		lc $constants->{sitename}	=> "$constants->{sitename};$constants->{rootdir}",
		malda		=> "Rob Malda;http://CmdrTaco.net",
		cmdrtaco	=> "Rob Malda;http://CmdrTaco.net",
		apple		=> "Apple;http://www.apple.com",
		debian		=> "Debian;http://www.debian.org",
		zdnet		=> "ZDNet;http://www.zdnet.com",
		'news.com'	=> "News.com;http://www.news.com",
		cnn		=> "CNN;http://www.cnn.com"
	);

	foreach my $key (keys %relatedLinks) {
		if (exists $relatedLinks{$key} && /\W$key\W/i) {
			my($label,$url) = split m/;/, $relatedLinks{$key};
			$label =~ s/(\S{20})/$1 /g;
			$related_links .= qq[<LI><A HREF="$url">$label</A></LI>\n];
		}
	}

	# And slurp in all the URLs just for good measure
	while ($story_content =~ m|<A(.*?)>(.*?)</A>|sgi) {
		my($url, $label) = ($1, $2);
		$label =~ s/(\S{30})/$1 /g;
		$related_links .= "<LI><A$url>$label</A></LI>\n" unless $label eq "[?]";
	}
	return $related_links;
}

##################################################################
sub otherLinks {
	my($aid, $tid) = @_;

	my $slashdb = getCurrentDB();


	my $topic = $slashdb->getTopic($tid);

	return slashDisplay('admin-otherLinks', {
			aid		=> $aid,
			tid		=> $tid,
			topic		=> $topic,
			} , 1, 1
	);
}

##################################################################
# Story Editing
sub editStory {
	my($sid) = @_;

	my $slashdb = getCurrentDB();
	my $user = getCurrentUser();
	my $form = getCurrentForm();
	my $constants = getCurrentStatic();

	my ($authoredit_flag,$extracolumn_flag) = (0,0);
	my($storyref, $story, $author, $topic, $storycontent, $storybox, $locktest);
	my($editbuttons,$topic_select, $section_select, $author_select);
	my($extracolumns,$introtext,$bodytext,$relatedtext);
	my($displaystatus_select, $commentstatus_select);
	my $extracolref = {};
	my($fixquotes_check,$autonode_check,$fastforward_check) = ('off','off','off');

	foreach (keys %{$form}) { $storyref->{$_} = $form->{$_} }

	my $newarticle = 1 if (!$sid && !$form->{sid});
	
	if ($form->{title}) { 
		$slashdb->setSession($user->{nickname}, { lasttitle => $storyref->{title} });

		$storyref->{writestatus} = $slashdb->getVar('defaultwritestatus', 'value');
		$storyref->{displaystatus} = $slashdb->getVar('defaultdisplaystatus', 'value');
		$storyref->{commentstatus} = $slashdb->getVar('defaultcommentstatus', 'value');

		$storyref->{aid} ||= $user->{uid};
		$storyref->{section} = $form->{section};

		my $extracolumns = $slashdb->getKeys($storyref->{section});

		foreach (@{$extracolumns}) {
			$storyref->{$_} = $form->{$_} || $storyref->{$_};
		}

		$storyref->{writestatus} = $form->{writestatus} if exists $form->{writestatus};
		$storyref->{displaystatus} = $form->{displaystatus} if exists $form->{displaystatus};
		$storyref->{commentstatus} = $form->{commentstatus} if exists $form->{commentstatus};
		$storyref->{dept} =~ s/ /-/gi;

		$storyref->{introtext} = $slashdb->autoUrl($form->{section}, $storyref->{introtext});
		$storyref->{bodytext} = $slashdb->autoUrl($form->{section}, $storyref->{bodytext});

		$topic = $slashdb->getTopic($storyref->{tid});
		$form->{aid} ||= $user->{uid};
		$author= $slashdb->getAuthor($form->{uid});
		$sid = $form->{sid};

		if (!$form->{time} || $form->{fastforward}) {
			$storyref->{time} = $slashdb->getTime();
		} else {
			$storyref->{time} = $form->{time};
		}

		my $tmp = $constants->{currentSection};
		$constants->{currentSection} = $storyref->{section};

		$storycontent = dispStory($storyref, $author, $topic, 'Full');

		$constants->{currentSection} = $tmp;
		$storyref->{relatedtext} = getRelated("$storyref->{title} $storyref->{bodytext} $storyref->{introtext}")
			. otherLinks($slashdb->getAuthor($storyref->{aid}, 'nickname'), $storyref->{tid});

		$storybox = fancybox($constants->{fancyboxwidth}, 'Related Links', $storyref->{relatedtext},0,1);

	} elsif (defined $sid) { # Loading an existing SID
		my $tmp = $constants->{currentSection};
		($constants->{currentSection}) = $slashdb->getStory($sid, 'section');
		($story, $storyref, $author, $topic) = displayStory($sid, 'Full');
		$constants->{currentSection} = $tmp;
		$storybox = fancybox($constants->{fancyboxwidth},'Related Links', $storyref->{relatedtext},0,1);

	} else { # New Story
		$storyref->{writestatus} = $slashdb->getVar('defaultwritestatus', 'value');
		$storyref->{displaystatus} = $slashdb->getVar('defaultdisplaystatus', 'value');
		$storyref->{commentstatus} = $slashdb->getVar('defaultcommentstatus', 'value');

		$storyref->{'time'} = $slashdb->getTime();
		# hmmm. I don't like hardcoding these PMG 10/19/00
		# I would agree. How about setting defaults in vars
		# that can be override? -Brian
		$storyref->{tid} ||= 'news';
		$storyref->{section} ||= 'articles';

		$storyref->{aid} = $user->{uid};
	}
	$extracolumns =  $slashdb->getKeys($storyref->{section});

	$introtext = stripByMode($storyref->{introtext}, 'literal', 1);
	$bodytext  = stripByMode($storyref->{bodytext}, 'literal', 1);
	$relatedtext = stripByMode($storyref->{relatedtext}, 'literal', 1);
	my $SECT = getSection($storyref->{section});

	$editbuttons = editbuttons($newarticle);

	$topic_select = selectTopic('tid', $storyref->{tid}, 1);

	$section_select = selectSection('section', $storyref->{section}, $SECT, 1) unless $user->{section};

	if ($user->{seclev} > 100 and $storyref->{aid}) {
		$authoredit_flag = 1;
		my $authors = $slashdb->getDescriptions('authors');
		$author_select = createSelect('aid', $authors, $storyref->{aid},1);
	} 

	$storyref->{dept} =~ s/ /-/gi;

	$locktest = lockTest($storyref->{title});

	unless ($user->{section}) {
		my $description = $slashdb->getDescriptions('displaycodes');
		$displaystatus_select = createSelect('displaystatus', $description, $storyref->{displaystatus},1);
	}
	my $description = $slashdb->getDescriptions('commentcodes');
	$commentstatus_select = createSelect('commentstatus', $description, $storyref->{commentstatus},1);

	$fixquotes_check = "on" if $form->{fixquotes};
	$autonode_check = "on" if $form->{autonode};
	$fastforward_check = "on" if $form->{fastforward};

	if (@{$extracolumns}) {
		$extracolumn_flag = 1;

		foreach (@{$extracolumns}) {
			next if $_ eq 'sid';
			my($sect, $col) = split m/_/;
			$storyref->{$_} = $form->{$_} || $storyref->{$_};

			$extracolref->{$_}{sect} = $sect;
			$extracolref->{$_}{col} = $col;
		}
	}

# hmmmm
#Import Image (don't even both trying this yet :)<BR>
#	<INPUT TYPE="file" NAME="importme"><BR>

	slashDisplay('admin-editStory', {
			storyref 		=> $storyref,
			story			=> $story,
			storycontent		=> $storycontent,
			storybox		=> $storybox,
			sid			=> $sid,
			editbuttons		=> $editbuttons,
			topic_select		=> $topic_select,
			section_select		=> $section_select,
			author_select		=> $author_select,
			locktest		=> $locktest,
			displaystatus_select	=> $displaystatus_select,
			commentstatus_select	=> $commentstatus_select,
			fixquotes_check		=> $fixquotes_check,
			autonode_check		=> $autonode_check,
			fastforward_check	=> $fastforward_check,
			extracolumn_flag	=> $extracolumn_flag,
			extracolref		=> $extracolref,
			introtext		=> $introtext,
			bodytext		=> $bodytext,
			relatedtext		=> $relatedtext,
			user			=> $user,
			}
	);
}

##################################################################
sub listStories {

	my $slashdb = getCurrentDB();
	my $user = getCurrentUser();
	my $form = getCurrentForm();
	my $constants = getCurrentStatic();

	my($x, $first) = (0, $form->{'next'});
	my $storylist = $slashdb->getStoryList();

	my $storylistref = [];

	my($hits, $comments, $sid, $title, $aid, $time, $tid, $section, 
	$displaystatus, $writestatus, $td, $td2, $yesterday,$tbtitle,
	$count,$left,$substrtid,$substrsection,$sectionflag);

	my ($storiestoday,$not_today,$i,$display,$canedit,$storymin) = (0,0,0,0,0,0);
	my $displayoff = 1;

	my $bgcolor = '';
	
	for (@$storylist) {
		($hits, $comments, $sid, $title, $aid, $time, $tid, $section,
			$displaystatus, $writestatus, $td, $td2) = @$_;

		$substrtid = substr($tid, 0, 5);
		
		$title = substr($title, 0, 50) . '...' if (length $title > 55);
		$displayoff = 1 if($writestatus < 0 || $displaystatus < 0);

		if ($user->{uid} eq $aid || $user->{seclev} > 100) {
			$canedit = 1;
			$tbtitle = fixparam($title);
		} 

		$x++;
		$storiestoday++;
		next if $x < $first;
		last if $x > $first + 40;

		if ($td ne $yesterday && !$form->{section}) {
			$not_today = 1;

			unless ($storiestoday > 1) {
				$storymin = 1;
				$storiestoday = '' 
			}
			$storiestoday = 0;
		} 

		$yesterday = $td;

		unless ($user->{section} || $form->{section}) {
			$sectionflag = 1;
			$substrsection = substr($section,0,5) 
		}

		$storylistref->[$i] = {
			x		=> $x,
			hits		=> $hits,
			comments	=> $comments,
			sid		=> $sid,
			title		=> $title,
			aid		=> $aid,
			time		=> $time,
			canedit		=> $canedit,
			substrtid	=> $substrtid,
			section		=> $section,
			sectionflag	=> $sectionflag,
			substrsection	=> $substrsection,
			td		=> $td,
			td2		=> $td2,
			not_today	=> $not_today,
			storiestoday	=> $storiestoday,
			storymin	=> $storymin,
		}; 
		
		$i++;
	}

	$count = @$storylist;
	$left = $count - $x;

	slashDisplay('admin-listStories', {
			storylistref		=> $storylistref,
			x			=> $x,
			left			=> $left
			}
	);
		
}

##################################################################
sub rmStory {
	my($sid) = @_;

	my $slashdb = getCurrentDB();
	my $user = getCurrentUser();
	my $form = getCurrentForm();
	my $constants = getCurrentStatic();

	$slashdb->deleteStory($sid);

	titlebar('100%', getTitle('rmStory-title', {sid => $sid}));
}

##################################################################
sub listFilters {
	my($header, $footer);

	my $slashdb = getCurrentDB();
	my $user = getCurrentUser();
	my $form = getCurrentForm();
	my $constants = getCurrentStatic();

	my $title = getTitle('listFilters-title');
	my $filter_ref = $slashdb->getContentFilters();

	slashDisplay('admin-listFilters', { 
			title => $title, 
			filter_ref => $filter_ref 
			}
	);
}

##################################################################
sub editFilter {
	my($filter_id) = @_;

	my $slashdb = getCurrentDB();
	my $user = getCurrentUser();
	my $form = getCurrentForm();
	my $constants = getCurrentStatic();

	$filter_id ||= $form->{filter_id};

	my @values = qw(regex modifier field ratio minimum_match
		minimum_length maximum_length err_message);
	my $filter = $slashdb->getContentFilter($filter_id, \@values, 1);

	# this has to be here - it really screws up the block editor
	$filter->{err_message} = stripByMode($filter->{'err_message'}, 'literal', 1);

	slashDisplay('admin-editFilter', { 
				filter => $filter, 
				filter_id => $filter_id 
				}
	);

}

##################################################################
sub updateFilter {
	my($filter_action) = @_;

	my $slashdb = getCurrentDB();
	my $user = getCurrentUser();
	my $form = getCurrentForm();
	my $constants = getCurrentStatic();
	
	if ($filter_action == 1) {
		my $filter_id = $slashdb->createContentFilter();
		titlebar("100%", getTitle('updateFilter-new-title', { filter_id => $filter_id }));
		editFilter($filter_id);

	} elsif ($filter_action == 2) {
		if (!$form->{regex} || !$form->{regex}) {
			print getMessage('updateFilter-message');
			editFilter($form->{filter_id});

		} else {
			$slashdb->setContentFilter();
		}

		titlebar("100%", getTitle('updateFilter-update-title'));
		editFilter($form->{filter_id});

	} elsif ($filter_action == 3) {
		$slashdb->deleteContentFilter($form->{filter_id});
		titlebar("100%", getTitle('updateFilter-delete-title'));
		listFilters();
	}
}

##################################################################
sub editbuttons {
	my($newarticle) = @_;
	my $editbuttons = slashDisplay('admin-editbuttons',{newarticle => $newarticle},1);
	return $editbuttons
}

##################################################################
sub updateStory {

	my $slashdb = getCurrentDB();
	my $user = getCurrentUser();
	my $form = getCurrentForm();
	my $constants = getCurrentStatic();

	# Some users can only post to a fixed section
	if ($user->{section}) {
		$form->{section} = $user->{section};
		$form->{displaystatus} = 1;
	}

	$form->{writestatus} = 1;

	$form->{dept} =~ s/ /-/g;

	($form->{aid}) = $slashdb->getStory($form->{sid}, 'aid')
		unless $form->{aid};
	$form->{relatedtext} = getRelated("$form->{title} $form->{bodytext} $form->{introtext}")
		. otherLinks($slashdb->getAuthor($form->{aid}, 'nickname'), $form->{tid});

	$slashdb->updateStory();
	titlebar('100%', getTitle('updateStory-title'));
	listStories();
}

##################################################################
sub saveStory {

	my $slashdb = getCurrentDB();
	my $user = getCurrentUser();
	my $form = getCurrentForm();
	my $constants = getCurrentStatic();

	$form->{sid} = getsid();
	$form->{displaystatus} ||= 1 if $user->{section};
	$form->{section} = $user->{section} if $user->{section};
	$form->{dept} =~ s/ /-/g;
	$form->{relatedtext} = getRelated(
		"$form->{title} $form->{bodytext} $form->{introtext}"
	) . otherLinks($user->{nickname}, $form->{tid});
	$form->{writestatus} = 1 unless $form->{writestatus} == 10;

	$slashdb->saveStory();

	titlebar('100%', getTitle('saveStory-title'));
	listStories();
}

#################################################################
sub getMessage {
	my($value, $hashref,$nocomm) = @_;
	$hashref ||= {};
	$hashref->{value} = $value;
	return slashDisplay('admin-messages', $hashref, 1, $nocomm);
}
##################################################################
sub getTitle {
	my($value, $hashref,$nocomm) = @_;
	$hashref ||= {};
	$hashref->{value} = $value;
	return slashDisplay('admin-titles', $hashref, 1, $nocomm);
}
##################################################################
sub getLinks {
}


createEnvironment();
main();
1;
