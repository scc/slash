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
use CGI ();
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
	if ($form->{op} =~ /^preview|edit$/ && $form->{title}) {
		# Show submission/article title on browser's titlebar.
		$tbtitle = $form->{title};
		$tbtitle =~ s/"/'/g;
		$tbtitle = " - \"$tbtitle\"";
		# Undef the form title value if we have SID defined, since the editor
		# will have to get this information from the database anyways.
		undef $form->{title} if $form->{sid} && $form->{op} eq 'edit';
	}
	header("backSlash $user->{tzcode} $user->{offset}$tbtitle", 'admin');

	# Admin Menu
	print "<P>&nbsp;</P>" unless $user->{aseclev};

	my $op = $form->{op};
	if (!$user->{aseclev}) {
		titlebar('100%', 'back<I>Slash</I> Login');
		adminLoginForm();

	} elsif ($op eq 'logout') {
		$slashdb->deleteSession();
		titlebar('100%', 'back<I>Slash</I> Buh Bye');
		adminLoginForm();

	} elsif ($form->{topicdelete}) {
		topicDelete();
		topicEd();

	} elsif ($form->{topicsave}) {
		topicSave();
		topicEd();

	} elsif ($form->{topiced} || $op eq 'topiced' || $form->{topicnew}) {
		topicEd();

	} elsif ($op eq 'save') {
		saveStory();

	} elsif ($op eq 'update') {
		updateStory();

	} elsif ($op eq 'list') {
		titlebar('100%', 'Story List', 'c');
		listStories();

	} elsif ($op eq 'delete') {
		rmStory($form->{sid});
		listStories();

	} elsif ($op eq 'preview') {
		editstory('');

	} elsif ($op eq 'edit') {
		editstory($form->{sid});

	} elsif ($op eq 'topics') {
		listTopics($user->{aseclev});

	} elsif ($op eq 'colored' || $form->{colored} || $form->{colorrevert} || $form->{colorpreview}) {
		colorEdit($user->{aseclev});

	} elsif ($form->{colorsave} || $form->{colorsavedef} || $form->{colororig}) {
		colorSave();
		colorEdit($user->{aseclev});

	} elsif ($form->{blockdelete_cancel} || $op eq "blocked") {
		blockEdit($user->{aseclev},$form->{bid});

	} elsif ($form->{blocknew}) {
		blockEdit($user->{aseclev});

	} elsif ($form->{blocked1}) {
		blockEdit($user->{aseclev}, $form->{bid1});

	} elsif ($form->{blocked2}) {
		blockEdit($user->{aseclev}, $form->{bid2});

	} elsif ($form->{blocksave} || $form->{blocksavedef}) {
		blockSave($form->{thisbid});
		blockEdit($user->{aseclev}, $form->{thisbid});

	} elsif ($form->{blockrevert}) {
		$slashdb->revertBlock($form->{thisbid}) if $user->{aseclev} < 500;
		blockEdit($user->{aseclev}, $form->{thisbid});

	} elsif ($form->{blockdelete}) {
		blockEdit($user->{aseclev},$form->{thisbid});

	} elsif ($form->{blockdelete1}) {
		blockEdit($user->{aseclev},$form->{bid1});

	} elsif ($form->{blockdelete2}) {
		blockEdit($user->{aseclev},$form->{bid2});

	} elsif ($form->{blockdelete_confirm}) {
		blockDelete($form->{deletebid});
		blockEdit($user->{aseclev});

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

	} elsif ($form->{varedit}) {
		varEdit($form->{name});	

	} elsif ($form->{varsave}) {
		varSave();
		varEdit($form->{name});

	} elsif ($op eq "listfilters") {
		titlebar("100%","List of comment filters","c");
		listFilters();

	} elsif ($form->{editfilter}) {
		titlebar("100%","Edit Comment Filter","c");
		editFilter($form->{filter_id});

	} elsif ($form->{updatefilter}) {
		updateFilter("update");

	} elsif ($form->{newfilter}) {
		updateFilter("new");

	} elsif ($form->{deletefilter}) {
		updateFilter("delete");

	} else {
		titlebar('100%', 'Story List', 'c');
		listStories();
	}


	# Display who is logged in right now.
	footer();
	writeLog('admin', $user->{aid}, $op, $form->{sid});
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
	my $var;

	print qq[\n<!-- begin variables editor form -->\n<FORM ACTION="$ENV{SCRIPT_NAME}" METHOD="POST">\n];
	my $vars = $slashdb->getDescriptions('vars');
	my $vars_select = createSelect('name', $vars, $name, 1);

	if($name) {
		$var = $slashdb->getVar($name, ['name','value','description','datatype','dataop']);
	}

	slashDisplay('admin-varEdit',{ 
			vars_select 	=> $vars_select,
			var		=> $var,
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
			print "Saved $form->{thisname}<BR>\n";
		} else {
			print "<B>Deleted $form->{thisname}!</B><BR>\n";
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


	return if $user->{aseclev} < 500;

	$aid ||= $user->{aid};
	$aid = '' if $form->{authornew};

	print qq!<FORM ACTION="$ENV{SCRIPT_NAME}" METHOD="POST">!;
	my $authors = $slashdb->getDescriptions('authors');
	createSelect('myaid', $authors, $aid);

	
	my $author = $slashdb->getAuthor($aid) if $aid;

	for ($author->{email}, $author->{copy}) {
		$_ = stripByMode($_, 'literal', 1);
	}

	print <<EOT;
<INPUT TYPE="submit" VALUE="Select Author" NAME="authoredit"><BR>
<TABLE BORDER="0">
	<TR>
		<TD>Aid</TD><TD><INPUT TYPE="text" NAME="thisaid" VALUE="$aid"></TD>
	</TR>
	<TR>
		<TD>Name</TD><TD><INPUT TYPE="text" NAME="name" VALUE="$author->{name}"></TD>
	</TR>
	<TR>
		<TD>URL</TD><TD><INPUT TYPE="text" NAME="url" VALUE="$author->{url}"></TD>
	</TR>
	<TR>
		<TD>Email</TD><TD><INPUT TYPE="text" NAME="email" VALUE="$author->{email}"></TD>
	</TR>
	<TR>
		<TD>Quote</TD><TD><TEXTAREA NAME="quote" COLS="50" ROWS="4">$author->{email}</TEXTAREA></TD>
	</TR>
	<TR>
		<TD>Copy</TD><TD><TEXTAREA NAME="copy" COLS="50" ROWS="5">$author->{copy}</TEXTAREA></TD>
	</TR>
	<TR>
		<TD>Passwd</TD><TD><INPUT TYPE="password" NAME="pwd" VALUE="$author->{pwd}"></TD>
	</TR>
	<TR>
		<TD>Seclev</TD><TD><INPUT TYPE="text" NAME="seclev" VALUE="$author->{seclev}"></TD>
	</TR>
</TABLE>
		Restrict to Section
EOT

	selectSection('section', $author->{section}) ;

	print <<EOT;
<TABLE BORDER="0">
	<TR>
		<TD><BR><INPUT TYPE="SUBMIT" VALUE="Save Author" NAME="authorsave"></TD>
EOT
	print <<EOT if ! $form->{authornew};
		<TD><BR><INPUT TYPE="SUBMIT" VALUE="Create Author" NAME="authornew"></TD>
EOT
	print <<EOT if (! $form->{authornew} && $aid ne $user->{aid}) ;
		<TD><BR><INPUT TYPE="SUBMIT" VALUE="Delete Author" NAME="authordelete"></TD>
EOT

print qq|\t</TR>\n</TABLE>\n</FORM>\n|;

}

##################################################################
sub authorSave {

	my $slashdb = getCurrentDB();
	my $user = getCurrentUser();
	my $form = getCurrentForm();
	my $constants = getCurrentStatic();

	return if $user->{aseclev} < 500;
	if ($form->{thisaid}) {
		# And just why do we take two calls to do
		# a new user? 
		if ($slashdb->createAuthor($form->{thisaid})) {
			print "Inserted $form->{thisaid}<BR>";
		}
		if ($form->{thisaid}) {
			print "Saved $form->{thisaid}<BR>";
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
			print "<B>Deleted $form->{thisaid}!</B><BR>";
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

	return if $user->{aseclev} < 500;

	print qq|<FORM ACTION="$ENV{SCRIPT_NAME}" METHOD="POST">|;
	print <<EOT if $form->{authordelete};
		<B>Do you really want to delete $aid?</B><BR> 
		<INPUT TYPE="HIDDEN" VALUE="$aid" NAME="thisaid">
		<INPUT TYPE="SUBMIT" VALUE="Cancel delete $aid" NAME="authordelete_cancel">
		<INPUT TYPE="SUBMIT" VALUE="Delete $aid" NAME="authordelete_confirm">
EOT
		if ($form->{authordelete_confirm}) {
			$slashdb->deleteAuthor($aid);
			print "<B>Deleted $aid!</B><BR>" if ! DBI::errstr;
		} elsif ($form->{authordelete_cancel}) {
			print "<B>Canceled Deletion of $aid!</B><BR>";
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

	my $slashdb = getCurrentDB();
	my $user = getCurrentUser();
	my $form = getCurrentForm();
	my $constants = getCurrentStatic();


	return if $seclev < 500;
	my($hidden_bid) = "";
	my $saveflag;
	my $section = {};

        titlebar("100%","Site Block Editor","c");

	print <<EOT;
<!-- begin block editing form -->
<FORM ACTION="$ENV{SCRIPT_NAME}" METHOD="POST">
EOT

	if (! $form->{blockdelete} && ! $form->{blockdelete1} && ! $form->{blockdelete2}) {
		print <<EOT;
<P>Select a block to edit. 
<UL>
	<LI>You can only edit static blocks.</LI> 
	<LI>Blocks that are portald type blocks are written by portald</LI>
</UL>
</P>
<TABLE>
	<TR>
		<TD><B>Static Blocks</B></TD><TD>
EOT

		# get the static blocks
		my $block = $slashdb->getStaticBlock($seclev);
		createSelect('bid1', $block, $bid);

		print qq[</TD><TD><INPUT TYPE="SUBMIT" VALUE="Edit Block" NAME="blocked1"></TD>
		<TD><INPUT TYPE="SUBMIT" VALUE="Delete Block" NAME="blockdelete1"></TD>\n\t</TR>\n];
		# get the portald blocks
		print qq[\t<TR><TD><B>Portald Blocks</B></TD><TD>];
		my $second_block = $slashdb->getPortaldBlock($seclev);
		createSelect('bid2', $second_block, $bid);
		print qq[</TD><TD><INPUT TYPE="SUBMIT" VALUE="Edit Block" NAME="blocked2"></TD>
		<TD><INPUT TYPE="SUBMIT" VALUE="Delete Block" NAME="blockdelete2"></TD>\n\t</TR>\n</TABLE>\n];
	}


	if ($form->{blockdelete} || $form->{blockdelete1} || $form->{blockdelete2}) {
		print <<EOT;
<INPUT TYPE="HIDDEN" NAME="deletebid" VALUE="$bid">
<TABLE BORDER="0">
	<TR>
		<TD><B>Do you really want to delete Block $bid?</B></TD>
		<TD><INPUT TYPE="SUBMIT" VALUE="Cancel Delete of $bid" NAME="blockdelete_cancel"></TD>
		<TD><INPUT TYPE="SUBMIT" VALUE="Really Delete $bid!" NAME="blockdelete_confirm"></TD>
	</TR>
</TABLE>
EOT
	}

	# if the pulldown has been selected and submitted 
	# or this is a block save and the block is a portald block
	# or this is a block edit via sections.pl
	if (! $form->{blocknew} && $bid ) {
		# getSection() is cached so you might as well grab it all
		$section = $slashdb->getSection($bid, '', 1);

		if ($section->{'bid'}) {
			$section->{'title'} = qq[<TR>\n\t\t<TD><B>Title</B></TD><TD COLSPAN="2"><INPUT TYPE="TEXT" SIZE="70" NAME="title" VALUE="$section->{'title'}"></TD>\n\t</TR>];
			$section->{'url'} = qq[<TR>\n\t\t<TD><B>URL</B></TD><TD COLSPAN="2"><INPUT TYPE="TEXT" SIZE="70" NAME="url" VALUE="$section->{'url'}"></TD>\n\t</TR>];
			$section->{'rdf'} = qq[<TR>\n\t\t<TD><B>RDF</B></TD><TD COLSPAN="2"><INPUT TYPE="TEXT" SIZE="70" NAME="rdf" VALUE="$section->{'rdf'}"></TD>\n\t</TR>];
			$section->{'section'} = qq[<TR>\n\t\t<TD><B>Section</B></TD><TD COLSPAN="2"><INPUT TYPE="TEXT" SIZE="10" NAME="section" VALUE="$section->{'section'}"></TD>\n\t</TR>];
			$section->{'ordernum'} = "NA" if $section->{'ordernum'} eq '';
			$section->{'ordernum'} = qq[<TR>\n\t\t<TD><B>Ordernum</B></TD><TD COLSPAN="2"><INPUT TYPE="TEXT" SIZE="3" NAME="ordernum" VALUE="$section->{'ordernum'}"></TD>\n\t</TR>];
			my $checked = "CHECKED" if $section->{'retrieve'} == 1; 
			$section->{'retrieve'} = qq[<TR>\n\t\t<TD><B>Retrieve</B></TD><TD COLSPAN="2"><INPUT TYPE="CHECKBOX" VALUE="1" NAME="retrieve" $checked></TD>\n\t</TR>];
			$checked = "";
			$checked = "CHECKED" if $section->{'portal'} == 1; 
			$section->{'portal'} = qq[<TR>\n\t\t<TD><B>Portal - check if this is a slashbox.</B></TD><TD COLSPAN="2"><INPUT TYPE="CHECKBOX" VALUE="1" NAME="portal" $checked></TD>\n\t</TR>];
			$saveflag = qq[<INPUT TYPE="HIDDEN" NAME="save_existing" VALUE="1">];
			$checked = "";
		}	
	}	
	# if this is a new block, we want an empty form 
	else {
		$section->{'title'} = qq[<TR>\n\t\t<TD><B>Title</B></TD><TD COLSPAN="2"><INPUT TYPE="TEXT" SIZE="70" NAME="title" VALUE=""></TD>\n\t</TR>];
		$section->{'url'} = qq[<TR>\n\t\t<TD><B>URL</B></TD><TD COLSPAN="2"><INPUT TYPE="TEXT" SIZE="70" NAME="url" VALUE=""></TD>\n\t</TR>];
		$section->{'rdf'} = qq[<TR>\n\t\t<TD><B>RDF</B></TD><TD COLSPAN="2"><INPUT TYPE="TEXT" SIZE="70" NAME="rdf" VALUE=""></TD>\n\t</TR>];
		$section->{'section'} = qq[<TR>\n\t\t<TD><B>Section</B></TD><TD COLSPAN="2"><INPUT TYPE="TEXT" SIZE="10" NAME="section" VALUE=""></TD>\n\t</TR>];
		$section->{'ordernum'} = qq[<TR>\n\t\t<TD><B>Ordernum</B></TD><TD COLSPAN="2"><INPUT TYPE="TEXT" SIZE="3" NAME="ordernum" VALUE=""></TD>\n\t</TR>];
		$section->{'retrieve'} = qq[<TR>\n\t\t<TD><B>Retrieve</B></TD><TD COLSPAN="2"><INPUT TYPE="CHECKBOX" VALUE="1" NAME="retrieve"></TD>\n\t</TR>];
		$section->{'portal'} = qq[<TR>\n\t\t<TD><B>Portal - check if this is a slashbox. </B></TD><TD COLSPAN="2"><INPUT TYPE="CHECKBOX" VALUE="1" NAME="portal"></TD>\n\t</TR>];
		$saveflag = qq[<INPUT TYPE="HIDDEN" NAME="save_new" VALUE="1">];
	}

	my $bidblock;
	if ($bid) {
		$bidblock = $slashdb->getBlock($bid, '', 1);
	}

	my $description_ta = stripByMode($bidblock->{'description'}, 'literal', 1);
	my $block_ta = stripByMode($bidblock->{'block'}, 'literal', 1);

	# main table
	print <<EOT;
<TABLE BORDER="0">
EOT

	# if there's a block description, print it
	print <<EOT if $bidblock->{'description'};
	<TR>
		<TD COLSPAN="3">
		<TABLE BORDER="2" CELLPADDING="4" CELLSPACING="0" BGCOLOR="$constants->{fg}[1]" WIDTH="80%">
			<TR>
				<TD BGCOLOR="$constants->{bg}[2]"><BR><B>Block ID: $bid</B><BR>
				<P>$bidblock->{'description'}</P><BR>
				</TD>
			</TR>
		</TABLE>
		<BR>
		</TD>
	</TR>
EOT

# print the form if this is a new block, submitted block, or block edit via sections.pl
	print <<EOT if ( (! $form->{blockdelete_confirm} && $bid) || $form->{blocknew}) ;
	<TR>	
		<TD><B>Block ID</B></TD>
		<TD><INPUT TYPE="TEXT" NAME="thisbid" VALUE="$bid"></TD>
	</TR>
		$section->{'title'}
	<TR>	
		<TD><B>Seclev</B></TD><TD><INPUT TYPE="TEXT" NAME="bseclev" VALUE="$bidblock->{'seclev'}" SIZE="6"></TD>
	</TR>
	<TR>	
		<TD><B>Type</B></TD><TD><INPUT TYPE="TEXT" NAME="type" VALUE="$bidblock->{'type'}" SIZE="10"></TD>
	</TR>
		$section->{'section'}
		$section->{'ordernum'}
		$section->{'portal'}
		$section->{'retrieve'}
		$section->{'url'}
		$section->{'rdf'}
		$saveflag
	<TR>
		<TD VALIGN="TOP"><B>Description</B></TD>
		<TD ALIGN="left" COLSPAN="2">
		<TEXTAREA ROWS="6" COLS="70" NAME="description">$description_ta</TEXTAREA>
		</TD>
	</TR>
	<TR>	
		<TD VALIGN="TOP"><B>Block</B><BR>
		<P>
			<INPUT TYPE="SUBMIT" VALUE="Save Block" NAME="blocksave"><BR>
			<INPUT TYPE="SUBMIT" NAME="blockrevert" VALUE="Revert to default">
			<BR><INPUT TYPE="SUBMIT" NAME="blocksavedef" VALUE="Save as default">
			(Make sure this is what you want!)
		</P>
		</TD>
		<TD ALIGN="left" COLSPAN="2">
		<TEXTAREA ROWS="15" COLS="100" NAME="block">$block_ta</TEXTAREA>
		</TD>
	</TR>
EOT

# print the delete button if this is anything other than 
# a new form, or initial submission from author menu
print <<EOT if (! $form->{blocknew} && $form->{blockdelete_cancel} && ! $form->{blockdelete} && ! $form->{blockdelete1} && ! $form->{blockdelete2});
	<TR>	
		<TD COLSPAN="3">
		<INPUT TYPE="SUBMIT" VALUE="Delete Block" NAME="blockdelete"></P>
		</TD>
	</TR>
EOT

# print the new block if this isn't already a new block
print <<EOT if (! $form->{blocknew});
	<TR>	
		<TD COLSPAN="3">
		<INPUT TYPE="SUBMIT" VALUE="Create a new block" NAME="blocknew"></P>
		</TD>
	</TR>
EOT

print <<EOT;
</TABLE>
</FORM>
<!-- end block editing form -->
EOT

	my $sectionbid = $slashdb->getSection($bid, 'section');
	print <<EOT;
<B><A HREF="$constants->{rootdir}/sections.pl?section=$sectionbid&op=editsection">$sectionbid</A></B>
(<A HREF="$constants->{rootdir}/users.pl?op=preview&bid=$bid">preview</A>)
EOT
}

##################################################################
sub blockSave {
	my($bid) = @_;

	my $slashdb = getCurrentDB();
	my $user = getCurrentUser();
	my $form = getCurrentForm();
	my $constants = getCurrentStatic();

	return if $user->{aseclev} < 500;
	return unless $bid;
	my $saved = $slashdb->saveBlock($bid);

	if ($form->{save_new} && $saved > 0) {
		print qq[<P><B>This block, $bid, already exists! <BR>Hit the "back" button, and try another bid (look at the blocks pulldown to see if you are using an existing one.)</P>]; 
		return;
	}	

	if ($saved == 0) {
		print "Inserted $bid<BR>";
	}
	print "Saved $bid<BR>";
}

##################################################################
sub blockDelete {
	my($bid) = @_;

	my $slashdb = getCurrentDB();
	my $user = getCurrentUser();
	my $form = getCurrentForm();
	my $constants = getCurrentStatic();

	return if $user->{aseclev} < 500;
	print "<B>Deleted $bid!</B><BR>";
	$slashdb->deleteBlock($bid);
}

##################################################################
sub colorEdit {

	my $slashdb = getCurrentDB();
	my $user = getCurrentUser();
	my $form = getCurrentForm();
	my $constants = getCurrentStatic();

	return if $user->{aseclev} < 500;

	my $colorblock;
	$form->{color_block} ||= 'colors';

	if ($form->{colorpreview}) {
		$colorblock = 
		"$form->{fg0},$form->{fg1},$form->{fg2},$form->{fg3},$form->{bg0},$form->{bg1},$form->{bg2},$form->{bg3}";

		my $colorblock_clean = $colorblock;
		# the #s will break the url 
		$colorblock_clean =~ s/#//g;
		print <<EOT
	<br>
	<a href="$constants->{rootdir}/index.pl?colorblock=$colorblock_clean">
	<p><b>Click here to see the site in these colors!</a></b> 
	 (Hit the <b>"back"</b> button to get back to this page.)</p>
	
EOT
	} else {
		$colorblock = $slashdb->getBlock($form->{color_block}, 'block'); 
	}

	my @colors = split m/,/, $colorblock;

	$constants->{fg} = [@colors[0..3]];
	$constants->{bg} = [@colors[4..7]];
	print "<P>You may need to reload the page a couple of times to see a change in the color scheme.
		<BR>If you can restart the webserver, that's the quickest way to see your changes.</P>";

       	titlebar("100%","Site Color Editor","c");
	print <<EOT;
<FORM ACTION="$ENV{SCRIPT_NAME}" METHOD="POST">
<P>Shown are the site colors. If you make a change to any one of them, 
you will need to restart the webserver for the change(s) to show up.</P>
<P>Note: make sure you use a valid color value, or the color will not work properly.</P>
Select the color block to edit: 
EOT
	my $block = $slashdb->getColorBlock();
	createSelect('color_block', $block, $form->{color_block});

print <<EOT;
	<INPUT TYPE="submit" name="colored" value="Edit Colors">
EOT

print <<EOT if $form->{color_block};
<TABLE BORDER="0">
	<TR>
		<TD>Foreground color 0 \$constants->{fg}[0]</TD>
		<TD><INPUT TYPE="TEXT" WIDTH="12" NAME="fg0" VALUE="$colors[0]"></TD>
		<TD><FONT FACE="ARIAL,HELVETICA" SIZE="+1" COLOR="$colors[0]">Foreground color 0 \$constants->{fg}[0]</FONT></TD>
		<TD BGCOLOR="$colors[0]">&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;</TD>
	</TR>
	<TR>
		<TD>Foreground color 1 \$constants->{fg}[1]</TD>
		<TD><INPUT TYPE="TEXT" WIDTH="12" NAME="fg1" VALUE="$colors[1]"></TD>
		<TD><FONT FACE="ARIAL,HELVETICA" SIZE="+1" COLOR="$colors[1]">Foreground color 1 \$constants->{fg}[1]</FONT></TD>
		<TD BGCOLOR="$colors[1]">&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;</TD>
	</TR>
	<TR>
		<TD>Foreground color 2 \$constants->{fg}[2]</TD>
		<TD><INPUT TYPE="TEXT" WIDTH="12" NAME="fg2" VALUE="$colors[2]"></TD>
		<TD><FONT FACE="ARIAL,HELVETICA" SIZE="+1" COLOR="$colors[2]">Foreground color 2 \$constants->{fg}[2]</FONT></TD>
		<TD BGCOLOR="$colors[2]">&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;</TD>
	</TR>
	<TR>
		<TD>Foreground color 3 \$constants->{fg}[3]</TD>
		<TD><INPUT TYPE="TEXT" WIDTH="12" NAME="fg3" VALUE="$colors[3]"></TD>
		<TD><FONT FACE="ARIAL,HELVETICA" SIZE="+1" COLOR="$colors[3]">Foreground color 3 \$constants->{fg}[3]</FONT></TD>
		<TD BGCOLOR="$colors[3]">&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;</TD>
	</TD>
	<TR>
		<TD>Background color 0 \$constants->{bg}[0]</TD>
		<TD><INPUT TYPE="TEXT" WIDTH="12" NAME="bg0" VALUE="$colors[4]"></TD>
		<TD><FONT FACE="ARIAL,HELVETICA" SIZE="+1" COLOR="$colors[4]">Background color 0 \$constants->{bg}[0]</FONT></TD>
		<TD BGCOLOR="$colors[4]">&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;</TD>
	</TR>
	<TR>
		<TD>Background color 1 \$constants->{bg}[1]</TD>
		<TD><INPUT TYPE="TEXT" WIDTH="12" NAME="bg1" VALUE="$colors[5]"></TD>
		<TD><FONT FACE="ARIAL,HELVETICA" SIZE="+1" COLOR="$colors[5]">Background color 1 \$constants->{bg}[1]</FONT></TD>
		<TD BGCOLOR="$colors[5]">&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;</TD>
	</TD>
	<TR>
		<TD>Background color 2 \$constants->{bg}[2]</TD>
		<TD><INPUT TYPE="TEXT" WIDTH="12" NAME="bg2" VALUE="$colors[6]"></TD>
		<TD><FONT FACE="ARIAL,HELVETICA" SIZE="+1" COLOR="$colors[6]">Background color 2 \$constants->{bg}[2]</FONT></TD>
		<TD BGCOLOR="$colors[6]">&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;</TD>
	</TR>
	<TR>
		<TD>Background color 3 \$constants->{bg}[3]</TD>
		<TD><INPUT TYPE="TEXT" WIDTH="12" NAME="bg3" VALUE="$colors[7]"></TD>
		<TD><FONT FACE="ARIAL,HELVETICA" SIZE="+1" COLOR="$colors[7]">Background color 3 \$constants->{bg}[3]</FONT></TD>
		<TD BGCOLOR="$colors[7]">&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;</TD>
	</TR>
	<TR>
		<TD><INPUT TYPE="SUBMIT" NAME="colorpreview" VALUE="Preview"></TD>
		<TD><INPUT TYPE="SUBMIT" NAME="colorsave" VALUE="Save Colors"></TD>
		<TD><INPUT TYPE="SUBMIT" NAME="colorrevert" VALUE="Revert to saved"></TD>
		<TD><INPUT TYPE="SUBMIT" NAME="colororig" VALUE="Revert to default">
		<BR><INPUT TYPE="SUBMIT" NAME="colorsavedef" VALUE="Save as default">
		 (Make sure this is what you want!) 
		</TD>
	</TR>
</TABLE>
</FORM>
EOT
}

##################################################################
sub colorSave {

	my $slashdb = getCurrentDB();
	my $user = getCurrentUser();
	my $form = getCurrentForm();
	my $constants = getCurrentStatic();

	return if $user->{aseclev} < 500;
	my $colorblock = join ',', @{$constants}{qw[fg0 fg1 fg2 fg3 bg0 bg1 bg2 bg3]};

	$slashdb->saveColorBlock($colorblock);
}

##################################################################
# Topic Editor
sub topicEd {

	my $slashdb = getCurrentDB();
	my $user = getCurrentUser();
	my $form = getCurrentForm();
	my $constants = getCurrentStatic();

	return if $user->{aseclev} < 1;
	my($topic, @available_images);

	local *DIR;
	opendir(DIR, "$constants->{basedir}/images/topics");
	@available_images = grep(!/^\./, readdir(DIR)); 
	closedir(DIR);

	print <<EOT;
<!-- begin topic editor form -->
<FORM ACTION="$ENV{SCRIPT_NAME}" METHOD="POST">
EOT

	my $topics_menu = $slashdb->getDescriptions('topics');
	createSelect('nexttid', $topics_menu, $form->{nexttid});

	print '<INPUT TYPE="SUBMIT" NAME="topiced" VALUE="Select topic"><BR>';
	print '<INPUT TYPE="SUBMIT" NAME="topicnew" VALUE="Create new topic"><BR>';

	if (!$form->{topicdelete}) {
		if (!$form->{topicnew}) {
			$topic = $slashdb->getTopic($form->{nexttid});
		} else {
			$topic = {};
			$topic->{'tid'} = 'new topic';
		}

		print qq|<BR>Image as seen: <BR><BR><IMG SRC="$constants->{imagedir}/topics/$topic->{'image'}" ALT="$topic->{'alttext'}" WIDTH="$topic->{'width'}" HEIGHT="$topic->{'height'}">|
			if ($form->{nexttid} && ! $form->{topicnew} && ! $form->{topicdelete});

		print <<EOT;
		<BR><BR>Tid<BR><INPUT TYPE="TEXT" NAME="tid" VALUE="$topic->{'tid'}"><BR>
		<BR>Dimensions (leave blank to determine automatically)<BR>
		Width: <INPUT TYPE="TEXT" NAME="width" VALUE="$topic->{'width'}" SIZE="4">
		Height: <INPUT TYPE="TEXT" NAME="height" VALUE="$topic->{'height'}" SIZE="4"><BR>
		<BR>Alt Text<BR>
		<INPUT TYPE="TEXT" NAME="alttext" VALUE="$topic->{'alttext'}"><BR>
		<BR>Image<BR>
EOT

		if (@available_images) {
			print qq|<SELECT name="image">|;
			print qq|<OPTION value="">Select an image</OPTION>| if $form->{topicnew};
			for (@available_images) {
				my($selected);
				$selected = "SELECTED" if ($_ eq $topic->{'image'});
				print qq|<OPTION value="$_" $selected>$_</OPTION>\n|;
				$selected = '';
			}
			print '</SELECT>';
		} else {
			# If we don't have images in the proper place, print a message
			# and use a regular text input field.
			print <<EOT;
<P>No images were found in the topic images directory (&lt;basedir&gt;/images/topics).<BR>
<INPUT TYPE="TEXT" NAME="image" VALUE="$topic->{'image'}"><BR><BR>
EOT
		}

		print <<EOT;
			<INPUT TYPE="SUBMIT" NAME="topicsave" VALUE="Save Topic">
			<INPUT TYPE="SUBMIT" NAME="topicdelete" VALUE="Delete Topic">
EOT
	}

print qq|</FORM>\n<!-- end topic editor form -->\n|;




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
	print "<B>Saved $form->{tid}!</B><BR>" if ! DBI::errstr;
	$form->{nexttid} = $form->{tid};
}

##################################################################
sub listTopics {
	my($seclev) = @_;

	my $slashdb = getCurrentDB();
	my $user = getCurrentUser();
	my $form = getCurrentForm();
	my $constants = getCurrentStatic();

	my $topics = $slashdb->getTopics();
	titlebar('100%', 'Topic Lister');

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
sub linkNode {
	my $n = shift;
	return '[?]' if $n eq '?';
	return $n . '<SUP><A HREF="http://www.everything2.com/index.pl?node='
		. CGI::escape($n) . '">[?]</A></SUP>';
}

##################################################################
# Generated the 'Related Links' for Stories
sub getRelated {

	my $slashdb = getCurrentDB();
	my $user = getCurrentUser();
	my $form = getCurrentForm();
	my $constants = getCurrentStatic();

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


	local($_) = @_;
	my $r;
	foreach my $key (keys %relatedLinks) {
		if (exists $relatedLinks{$key} && /\W$key\W/i) {
			my($t,$u) = split m/;/, $relatedLinks{$key};
			$t =~ s/(\S{20})/$1 /g;
			$r .= qq[<LI><A HREF="$u">$t</A></LI>\n];
		}
	}

	# And slurp in all the URLs just for good measure
	while (m|<A(.*?)>(.*?)</A>|sgi) {
		my($u, $t) = ($1, $2);
		$t =~ s/(\S{30})/$1 /g;
		$r .= "<LI><A$u>$t</A></LI>\n" unless $t eq "[?]";
	}
	return $r;
}

##################################################################
sub otherLinks {
	my($aid, $tid) = @_;

	my $slashdb = getCurrentDB();
	my $user = getCurrentUser();
	my $form = getCurrentForm();
	my $constants = getCurrentStatic();


	my $topic = $slashdb->getTopic($tid);

	return <<EOT;
<LI><A HREF="$constants->{rootdir}/search.pl?topic=$tid">More on $topic->{alttext}</A></LI>
<LI><A HREF="$constants->{rootdir}/search.pl?author=$aid">Also by $aid</A></LI>
EOT

}

##################################################################
# Story Editing
sub editstory {
	my($sid) = @_;

	my $slashdb = getCurrentDB();
	my $user = getCurrentUser();
	my $form = getCurrentForm();
	my $constants = getCurrentStatic();

	my($S, $A, $T);

	foreach (keys %{$form}) { $S->{$_} = $form->{$_} }

	my $newarticle = 1 if !$sid && !$form->{sid};
	
	print <<EOT;

<!-- begin editstory -->

<FORM ENCTYPE="multipart/form-data" ACTION="$ENV{SCRIPT_NAME}" METHOD="POST">
EOT

	if ($form->{title}) { 
		# Preview Mode
		print qq!<INPUT TYPE="HIDDEN" NAME="subid" VALUE="$form->{subid}">!
			if $form->{subid};

		$slashdb->setSessionByAid($user->{aid}, { lasttitle => $S->{title} });

		($S->{writestatus}, $S->{displaystatus}, $S->{commentstatus}) =
			$slashdb->getVars('defaultwritestatus','defaultdisplaystatus',
			'defaultcommentstatus');

		$S->{aid} ||= $user->{aid};
		$S->{section} = $form->{section};

		my $extracolumns = $slashdb->getKeys($S->{section});

		foreach (@{$extracolumns}) {
			$S->{$_} = $form->{$_} || $S->{$_};
		}

		$S->{writestatus} = $form->{writestatus} if exists $form->{writestatus};
		$S->{displaystatus} = $form->{displaystatus} if exists $form->{displaystatus};
		$S->{commentstatus} = $form->{commentstatus} if exists $form->{commentstatus};
		$S->{dept} =~ s/ /-/gi;

		$S->{introtext} = $slashdb->autoUrl($form->{section}, $S->{introtext});
		$S->{bodytext} = $slashdb->autoUrl($form->{section}, $S->{bodytext});

		$T = $slashdb->getTopic($S->{tid});
		$form->{aid} ||= $user->{aid};
		$A = $slashdb->getAuthor($form->{aid});
		$sid = $form->{sid};

		if (!$form->{'time'} || $form->{fastforward}) {
			$S->{'time'} = $slashdb->getTime();
		} else {
			$S->{'time'} = $form->{'time'};
		}

		print '<TABLE><TR><TD>';
		my $tmp = $constants->{currentSection};
		$constants->{currentSection} = $S->{section};
		print dispStory($S, $A, $T, 'Full');
		$constants->{currentSection} = $tmp;
		print '</TD><TD WIDTH="210" VALIGN="TOP">';
		$S->{relatedtext} = getRelated("$S->{title} $S->{bodytext} $S->{introtext}")
			. otherLinks($S->{aid}, $S->{tid});

		fancybox($constants->{fancyboxwidth}, 'Related Links', $S->{relatedtext});
		CGI::param('relatedtext', $S->{relatedtext});
		CGI::hidden('relatedtext');

		print <<EOT;
</TD></TR></TABLE>

<P><IMG SRC="$constants->{imagedir}/greendot.gif" WIDTH="80%" ALIGN="CENTER" HSPACE="20" HEIGHT="1"></P>

EOT

	} elsif (defined $sid) { # Loading an Old SID
		print '<TABLE><TR><TD>';
		my $tmp = $constants->{currentSection};
		($constants->{currentSection}) = $slashdb->getStory($sid, 'section');
		(my($story), $S, $A, $T) = displayStory($sid, 'Full');
		$constants->{currentSection} = $tmp;
		print $story, '</TD><TD WIDTH="220" VALIGN="TOP">';

		fancybox($constants->{fancyboxwidth},'Related Links', $S->{relatedtext});
		CGI::param('relatedtext', $S->{relatedtext});

		print '</TD></TR></TABLE>';

	} else { # New Story
		$S->{writestatus} = $slashdb->getVar('defaultwritestatus', 'value');
		$S->{displaystatus} = $slashdb->getVar('defaultdisplaystatus', 'value');
		$S->{commentstatus} = $slashdb->getVar('defaultcommentstatus', 'value');

		$S->{'time'} = $slashdb->getTime();
		$S->{tid} ||= 'news';
		$S->{section} ||= 'articles';
		$S->{aid} = $user->{aid};
	}
	my $extracolumns =  $slashdb->getKeys($S->{section});

	my $introtext = stripByMode($S->{introtext}, 'literal', 1);
	my $bodytext  = stripByMode($S->{bodytext}, 'literal', 1);
	my $SECT = getSection($S->{section});

	print '<TABLE BORDER="0" CELLPADDING="2" CELLSPACING="0">';
	print qq!<TR><TD BGCOLOR="$constants->{bg}[3]">&nbsp; </TD><TD BGCOLOR="$constants->{bg}[3]"><FONT COLOR="$constants->{fg}[3]">!;
	editbuttons($newarticle);
	selectTopic('tid', $S->{tid});
	unless ($user->{asection}) {
		selectSection('section', $S->{section}, $SECT) unless $user->{asection};
	}
	print qq!\n<INPUT TYPE="HIDDEN" NAME="writestatus" VALUE="$S->{writestatus}">!;

	if ($user->{aseclev} > 100 and $S->{aid}) {
		my $authors = $slashdb->getDescriptions('authors');
		createSelect('aid', $authors, $S->{aid});
	} elsif ($S->{aid}) {
		print qq!\n<INPUT TYPE="HIDDEN" NAME="aid" VALUE="$S->{aid}">!;
	}

	# print qq!\n<INPUT TYPE="HIDDEN" NAME="aid" VALUE="$S->{aid}">! if $S->{aid};
	print qq!\n<INPUT TYPE="HIDDEN" NAME="sid" VALUE="$S->{sid}">! if $S->{sid};

	print '</FONT></TD></TR>';


	$S->{dept} =~ s/ /-/gi;
	print qq!<TR><TD BGCOLOR="$constants->{bg}[3]"><FONT COLOR="$constants->{fg}[3]"> <B>Title</B> </FONT></TD>\n<TD BGCOLOR="$constants->{bg}[2]"> !,
		CGI::textfield(-name => 'title', -default => $S->{title}, -size => 50, -override => 1),
		'</TD></TR>';

	if ($constants->{use_dept}) {
		print qq!<TR><TD BGCOLOR="$constants->{bg}[3]"><FONT COLOR="$constants->{fg}[3]"> <B>Dept</B> </FONT></TD>\n!,
			qq!<TD BGCOLOR="$constants->{bg}[2]"> !,
			CGI::textfield(-name => 'dept', -default => $S->{dept}, -size => 50),
			qq!</TD></TR>\n!;
	}

	print qq!<TR><TD BGCOLOR="$constants->{bg}[3]">&nbsp; </TD>\n!,
		qq!<TD BGCOLOR="$constants->{bg}[2]"><FONT COLOR="$constants->{fg}[2]">!,
		lockTest($S->{title});

	unless ($user->{asection}) {
		my $description = $slashdb->getDescriptions('displaycodes');
		createSelect('displaystatus', $description, $S->{displaystatus});
	}
	my $description = $slashdb->getDescriptions('commentcodes');
	createSelect('commentstatus', $description, $S->{commentstatus});

	print qq!<INPUT TYPE="TEXT" NAME="time" VALUE="$S->{'time'}" size="16"> <BR>!;

	printf "\t[ %s | %s", CGI::checkbox('fixquotes'), CGI::checkbox('autonode');
	printf(qq! | %s | <A HREF="$constants->{rootdir}/pollBooth.pl?qid=$sid&op=edit">Related Poll</A>!,
		CGI::checkbox('fastforward')) if $sid;
	print " ]\n";

	print <<EOT;
</FONT></TD></TR></TABLE>
<BR>Intro Copy<BR>
	<TEXTAREA WRAP="VIRTUAL" NAME="introtext" COLS="70" ROWS="10">$S->{introtext}</TEXTAREA><BR>
EOT

	if (@{$extracolumns}) {
		print <<EOT;

<TABLE BORDER="0" CELLPADDING="2" CELLSPACING="0">
	<TR><TD ALIGN="RIGHT" COLSPAN="2" BGCOLOR="$constants->{bg}[3]">
		<FONT COLOR="$constants->{fg}[3]"> <B>Extra Data for This Section</B> </FONT>
	</TD></TR>
EOT

		foreach (@{$extracolumns}) {
			next if $_ eq 'sid';
			my($sect, $col) = split m/_/;
			$S->{$_} = $form->{$_} || $S->{$_};

			printf <<EOT, CGI::textfield({ -name => $_, -value => $S->{$_}, -size => 64 });

	<TR><TD BGCOLOR="$constants->{bg}[3]">
		<FONT COLOR="$constants->{fg}[3]"> <B>$col</B> </FONT>
	</TD><TD BGCOLOR="$constants->{bg}[2]">
		<FONT SIZE="${\( $constants->{fontbase} + 2 )}"> %s </FONT>
	</TD></TR>
EOT

		}
		print "</TABLE>\n";
	}


	editbuttons($newarticle);
	print <<EOT;

Extended Copy<BR>
	<TEXTAREA NAME="bodytext" COLS="70" WRAP="VIRTUAL" ROWS="10">$S->{bodytext}</TEXTAREA><BR>

<!-- end edit story -->

EOT

#Import Image (don't even both trying this yet :)<BR>
#	<INPUT TYPE="file" NAME="importme"><BR>

	editbuttons($newarticle);
}

##################################################################
sub listStories {

	my $slashdb = getCurrentDB();
	my $user = getCurrentUser();
	my $form = getCurrentForm();
	my $constants = getCurrentStatic();

	my($x, $first) = (0, $form->{'next'});
	my $storylist = $slashdb->getStoryList();

	my $yesterday;
	my $storiestoday = 0;

	print <<EOT;

<!-- begin liststories -->

<TABLE BORDER="0" CELLPADDING="2" CELLSPACING="0" WIDTH="100%">
EOT

	for (@$storylist) {
		my($hits, $comments, $sid, $title, $aid, $time, $tid, $section,
			$displaystatus, $writestatus, $td, $td2) = @$_;

		$x++;
		$storiestoday++;
		next if $x < $first;
		last if $x > $first + 40;

		if ($td ne $yesterday && !$form->{section}) {
			$storiestoday = '' unless $storiestoday > 1;
			print <<EOT;

	<TR><TD ALIGN="RIGHT" BGCOLOR="$constants->{bg}[2]">
		<FONT SIZE="${\( $constants->{fontbase} + 1 )}">$storiestoday</FONT>
	</TD><TD COLSPAN="7" ALIGN="right" BGCOLOR="$constants->{bg}[3]">
		<FONT COLOR="$constants->{fg}[3]" SIZE="${\( $constants->{fontbase} + 1 )}">$td</FONT>
	</TD></TR>
EOT

		    $storiestoday = 0;
		} 

		$yesterday = $td;

		if (length $title > 55) {
			$title = substr($title, 0, 50) . '...';
		}

		my $bgcolor = '';
		if ($displaystatus > 0) {
			$bgcolor = '#CCCCCC';
		} elsif ($writestatus < 0 or $displaystatus < 0) {
			$bgcolor = '#999999';
		}

		print qq[\t<TR BGCOLOR="$bgcolor"><TD ALIGN="RIGHT">\n];
		if ($user->{aid} eq $aid || $user->{aseclev} > 100) {
			my $tbtitle = fixparam($title);
			print qq!\t\t[<A HREF="$ENV{SCRIPT_NAME}?title=$tbtitle&op=edit&sid=$sid">$x</A>\n]!;

		} else {
			print "\t\t[$x]\n"
		}

		printf <<EOT, substr($tid, 0, 5);
	</TD><TD>
		<A HREF="$constants->{rootdir}/article.pl?sid=$sid">$title&nbsp;</A>
	</TD><TD>
		<FONT SIZE="${\( $constants->{fontbase} + 2 )}"><B>$aid</B></FONT>
	</TD><TD>
		<FONT SIZE="${\( $constants->{fontbase} + 2 )}">%s</FONT>
	</TD>
EOT

		printf <<EOT, substr($section,0,5) unless $user->{asection} || $form->{section};
	<TD>
		<FONT SIZE="${\( $constants->{fontbase} + 2 )}"><A HREF="$ENV{SCRIPT_NAME}?section=$section">%s</A>
	</TD>
EOT

		print <<EOT;
	<TD ALIGN="RIGHT">
		<FONT SIZE="${\( $constants->{fontbase} + 2 )}">$hits</FONT>
	</TD><TD>
		<FONT SIZE="${\( $constants->{fontbase} + 2 )}">$comments</FONT>
	</TD>
EOT

		print qq[\t<TD><FONT SIZE="${\( $constants->{fontbase} + 2 )}">$td2</TD>\n] if $form->{section};
		print qq[\t<TD><FONT SIZE="${\( $constants->{fontbase} + 2 )}">$time</TD></TR>\n];
	}

	my $count = @$storylist;
	my $left = $count - $x;

	print "</TABLE>\n";

	if ($x > 0) {
		print <<EOT;
<P ALIGN="RIGHT"><B><A HREF="$ENV{SCRIPT_NAME}?section=$form->{section}&op=list&next=$x">$left More</A></B></P>
EOT
	}

	print "\n<!-- end liststories -->\n\n";
}

##################################################################
sub rmStory {
	my($sid) = @_;

	my $slashdb = getCurrentDB();
	my $user = getCurrentUser();
	my $form = getCurrentForm();
	my $constants = getCurrentStatic();

	$slashdb->deleteStory($sid);
	
	titlebar('100%', "$sid will probably be deleted in 60 seconds.");
}

##################################################################
sub listFilters {
	my($header, $footer);

	my $slashdb = getCurrentDB();
	my $user = getCurrentUser();
	my $form = getCurrentForm();
	my $constants = getCurrentStatic();

	my $filter_hashref = $slashdb->getContentFilters();

	$header = getWidgetBlock('list_filters_header');
	print eval $header;

        for (@$filter_hashref) {
                print <<EOT;
        <TR>
                <TD>[<A HREF="$ENV{SCRIPT_NAME}?editfilter=1&filter_id=$_->[0]">$_->[0]</A>]</TD>
                <TD><FONT FACE="courier" size="+1">$_->[1]</FONT></TD>
                <TD> $_->[2] </TD>
                <TD> $_->[3] </TD>
                <TD> $_->[4] </TD>
                <TD> $_->[5] </TD>
                <TD> $_->[6] </TD>
                <TD> $_->[8] </TD>
                <TD> $_->[7] </TD>
        </TR>
EOT
        }

	$footer = getEvalBlock('list_filters_footer');
	print $footer;

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

	slashDisplay('admin-editFilter', { filter => $filter });

}

##################################################################
sub updateFilter {
	my($filter_action) = @_;

	my $slashdb = getCurrentDB();
	my $user = getCurrentUser();
	my $form = getCurrentForm();
	my $constants = getCurrentStatic();


	if ($filter_action eq "new") {
		my $filter_id = $slashdb->createContentFilter();

		# damn damn damn!!!! wish I could use sth->insertid !!!
		# ewww.....
		titlebar("100%", "New filter# $filter_id.", "c");
		editFilter($filter_id);

	} elsif ($filter_action eq "update") {
		if (!$form->{regex} || !$form->{regex}) {
			print "<B>You haven't typed in a regex.</B><BR>\n" if ! $form->{regex};
			print "<B>You haven't typed in a form field.</B><BR>\n" if ! $form->{field};

			editFilter($form->{filter_id});

		} else {
			$slashdb->setContentFilter();
		}

		titlebar("100%", "Filter# $form->{filter_id} saved.", "c");
		editFilter($form->{filter_id});
	} elsif ($filter_action eq "delete") {
		$slashdb->deleteContentFilter($form->{filter_id});

		titlebar("100%","<B>Deleted filter# $form->{filter_id}!</B>","c");
		listFilters();
	}
}

##################################################################
sub editbuttons {
	my($newarticle) = @_;

	my $slashdb = getCurrentDB();
	my $user = getCurrentUser();
	my $form = getCurrentForm();
	my $constants = getCurrentStatic();

	print "\n\n<!-- begin editbuttons -->\n\n";
	print qq[<INPUT TYPE="SUBMIT" NAME="op" VALUE="save"> ] if $newarticle;
	print qq[<INPUT TYPE="SUBMIT" NAME="op" VALUE="preview"> ];
	print qq[<INPUT TYPE="SUBMIT" NAME="op" VALUE="update"> ],
		qq[<INPUT TYPE="SUBMIT" NAME="op" VALUE="delete">] unless $newarticle;
	print "\n\n<!-- end editbuttons -->\n\n";
}

##################################################################
sub updateStory {

	my $slashdb = getCurrentDB();
	my $user = getCurrentUser();
	my $form = getCurrentForm();
	my $constants = getCurrentStatic();

	# Some users can only post to a fixed section
	if ($user->{asection}) {
		$form->{section} = $user->{asection};
		$form->{displaystatus} = 1;
	}

	$form->{writestatus} = 1;

	$form->{dept} =~ s/ /-/g;

	($form->{aid}) = $slashdb->getStory($form->{sid}, 'aid')
		unless $form->{aid};
	$form->{relatedtext} = getRelated("$form->{title} $form->{bodytext} $form->{introtext}")
		. otherLinks($form->{aid}, $form->{tid});

	$slashdb->updateStory();
	titlebar('100%', "Article $form->{sid} Saved", 'c');
	listStories();
}

##################################################################
sub saveStory {

	my $slashdb = getCurrentDB();
	my $user = getCurrentUser();
	my $form = getCurrentForm();
	my $constants = getCurrentStatic();

	$form->{sid} = getsid();
	$form->{displaystatus} ||= 1 if $user->{asection};
	$form->{section} = $user->{asection} if $user->{asection};
	$form->{dept} =~ s/ /-/g;
	$form->{relatedtext} = getRelated(
		"$form->{title} $form->{bodytext} $form->{introtext}"
	) . otherLinks($user->{aid}, $form->{tid});
	$form->{writestatus} = 1 unless $form->{writestatus} == 10;

	$slashdb->saveStory();

	titlebar('100%', "Inserted $form->{sid} $form->{title}");
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


main();
1;
