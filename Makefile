# This code is a part of Slash, and is released under the GPL.
# Copyright 1997-2001 by Open Source Development Network. See README
# and COPYING for more information, or see http://slashcode.com/.
# $Id$

##
##  Makefile -- Current one for Slash
##

#   the used tools
VERSION = 1.1.5-bender
DISTNAME = slash
DISTVNAME = $(DISTNAME)-$(VERSION)

SHELL = /bin/sh
PERL = perl
NOOP = $(SHELL) -c true
RM_RF = rm -rf
RM = rm -f
SUFFIX = .gz
COMPRESS = gzip --best
TAR  = tar
TARFLAGS = cvf
PREOP = @$(NOOP)
POSTOP = @$(NOOP)
TO_UNIX = @$(NOOP)
SLASH_PREFIX = /usr/local/slash
INIT = /etc
USER = nobody
GROUP = nobody
CP = cp


#   install the shared object file into Apache 
# We should run a script on the binaries to get the right
# version of perl. 
# I should also grab an install-sh instead of using $(CP)
slash:
	if ! [ $(RPM) ] ; then \
		(cd Slash; $(PERL) Makefile.PL; make); \
	else \
		(cd Slash; $(PERL) Makefile.PL INSTALLSITEARCH=/var/tmp/slash-buildroot/usr/local/lib/perl/5.6.0 INSTALLSITELIB=/var/tmp/slash-buildroot/usr/local/share/perl/5.6.0; make); \
	fi

plugins: 
	if ! [ $(RPM) ] ; then \
		(cd plugins/Search; $(PERL) Makefile.PL; make); \
		(cd plugins/Journal; $(PERL) Makefile.PL; make); \
		(cd plugins/Ladybug; $(PERL) Makefile.PL; make); \
	else \
		(cd plugins/Search; $(PERL) Makefile.PL INSTALLSITEARCH=/var/tmp/slash-buildroot/usr/local/lib/perl/5.6.0 INSTALLSITELIB=/var/tmp/slash-buildroot/usr/local/share/perl/5.6.0; make); \
		(cd plugins/Journal; $(PERL) Makefile.PL INSTALLSITEARCH=/var/tmp/slash-buildroot/usr/local/lib/perl/5.6.0 INSTALLSITELIB=/var/tmp/slash-buildroot/usr/local/share/perl/5.6.0; make); \
		(cd plugins/Ladybug; $(PERL) Makefile.PL  INSTALLSITEARCH=/var/tmp/slash-buildroot/usr/local/lib/perl/5.6.0 INSTALLSITELIB=/var/tmp/slash-buildroot/usr/local/share/perl/5.6.0; make); \
	fi

all: install

install: slash plugins
# Need to toss in a script here that will fix prefix so
# that if someone wants to install in a different
# directory it will be easy
	# Lets go install the libraries
	(cd Slash; make install)
	# Lets go install the plugin's libraries
	if ! [ $(RPM) ] ; then \
		(cd plugins/Search; $(PERL) Makefile.PL; make install); \
		(cd plugins/Journal; $(PERL) Makefile.PL; make install); \
		(cd plugins/Ladybug; $(PERL) Makefile.PL; make install); \
	else \
		(cd plugins/Search; $(PERL) Makefile.PL INSTALLSITEARCH=/var/tmp/slash-buildroot/usr/local/lib/perl/5.6.0 INSTALLSITELIB=/var/tmp/slash-buildroot/usr/local/share/perl/5.6.0; make install); \
		(cd plugins/Journal; $(PERL) Makefile.PL INSTALLSITEARCH=/var/tmp/slash-buildroot/usr/local/lib/perl/5.6.0 INSTALLSITELIB=/var/tmp/slash-buildroot/usr/local/share/perl/5.6.0; make install); \
		(cd plugins/Ladybug; $(PERL) Makefile.PL INSTALLSITEARCH=/var/tmp/slash-buildroot/usr/local/lib/perl/5.6.0 INSTALLSITELIB=/var/tmp/slash-buildroot/usr/local/share/perl/5.6.0; make install); \
	fi

	# First we do the default stuff
	install -d $(SLASH_PREFIX)/bin/ $(SLASH_PREFIX)/sbin $(SLASH_PREFIX)/sql/ $(SLASH_PREFIX)/sql/mysql/ $(SLASH_PREFIX)/sql/postgresql $(SLASH_PREFIX)/themes/ $(SLASH_PREFIX)/themes/slashcode/htdocs/ $(SLASH_PREFIX)/themes/slashcode/sql/ $(SLASH_PREFIX)/themes/slashcode/sql/postgresql $(SLASH_PREFIX)/themes/slashcode/sql/mysql $(SLASH_PREFIX)/plugins/ $(SLASH_PREFIX)/httpd/
	install -D bin/install-slashsite bin/install-plugin bin/tailslash bin/template-tool $(SLASH_PREFIX)/bin/
	install -D sbin/slashd sbin/portald sbin/moderatord sbin/dailyStuff $(SLASH_PREFIX)/sbin/
	$(CP) sql/mysql/slashschema_create.sql $(SLASH_PREFIX)/sql/mysql/schema.sql
	$(CP) sql/postgresql/slashschema_create.sql $(SLASH_PREFIX)/sql/postgresql/schema.sql

	if [ -f $(SLASH_PREFIX)/httpd/slash.conf ]; then\
		echo "Preserving old slash.conf"; \
	else \
		$(CP) httpd/slash.conf $(SLASH_PREFIX)/httpd/slash.conf; \
	fi

	$(CP) httpd/slash.conf $(SLASH_PREFIX)/httpd/slash.conf.def 


	# Now for the default theme (be nice when this goes in themes)
	(cd plugins; make clean)
	$(CP) -r plugins/* $(SLASH_PREFIX)/plugins/
	# Now all other themes
	$(CP) -r themes/* $(SLASH_PREFIX)/themes

	# this needs BSD support
	if [ -d /etc/init.d ]; then \
		install utils/slashd /etc/init.d/; \
		ln -s -f /etc/init.d/slashd /etc/rc3.d/S99slashd; \
		ln -s -f /etc/init.d/slashd /etc/rc6.d/K99slashd; \
	elif [ -d /etc/rc.d ]; then \
		install utils/slashd /etc/rc.d/init.d/; \
		ln -s -f /etc/rc.d/init.d/slashd /etc/rc.d/rc3.d/S99slashd; \
		ln -s -f /etc/rc.d/init.d/slashd /etc/rc.d/rc6.d/K99slashd; \
	else \
		echo "This is either BSD or some other OS I do not understand"; \
		echo "You will need to look at how to install utils/slash"; \
	fi

	touch $(SLASH_PREFIX)/slash.sites
	chown $(USER):$(GROUP) $(SLASH_PREFIX)
	chown -R $(USER):$(GROUP) $(SLASH_PREFIX)/themes
	chown -R $(USER):$(GROUP) $(SLASH_PREFIX)/sbin
	chown -R $(USER):$(GROUP) $(SLASH_PREFIX)/bin
	chown -R $(USER):$(GROUP) $(SLASH_PREFIX)/sql
	chown -R $(USER):$(GROUP) $(SLASH_PREFIX)/plugins
# Add a @ to suppress output of the echo's
	@echo "+--------------------------------------------------------+"; \
	echo "| All done.                                              |"; \
	echo "| If you want to let Slash handle your httpd.conf file   |"; \
	echo "| go add:                                                |"; \
	echo "|                                                        |"; \
	echo "| Include $(SLASH_PREFIX)/httpd/slash.conf              |"; \
	echo "|                                                        |"; \
	echo "| to your httpd.conf for apache.                         |"; \
	echo "| If not, cat its content into your httpd.conf file.     |"; \
	echo "|                                                        |"; \
	echo "| Thanks for installing Slash.                           |"; \
	echo "+--------------------------------------------------------+"; \


reload: install
	apachectl stop
	apachectl start
#   cleanup
clean:

dist: $(DISTVNAME).tar$(SUFFIX)

$(DISTVNAME).tar$(SUFFIX) : distdir
	$(PREOP)
	$(TO_UNIX)
	$(TAR) $(TARFLAGS) $(DISTVNAME).tar $(DISTVNAME)
	$(RM_RF) $(DISTVNAME)
	$(COMPRESS) $(DISTVNAME).tar
	$(POSTOP)

distdir :
	$(RM_RF) $(DISTVNAME)
	$(PERL) -MExtUtils::Manifest=manicopy,maniread \
	-e "manicopy(maniread(),'$(DISTVNAME)', '$(DIST_CP)');"

manifest :
	(cd Slash; make distclean)
	$(PERL) -MExtUtils::Manifest -e 'ExtUtils::Manifest::mkmanifest'

rpm :
	rpm -ba slash.spec

