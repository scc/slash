##
##  Makefile -- Current one for slashcode
##

#   the used tools
VERSION = 1.1.1-bender
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
PREFIX = /usr/local/slash
INIT = /etc/rc.d
USER = nobody
GROUP = nobody


#   install the shared object file into Apache 
# We should run a script on the binaries to get the right
# version of perl. 
# I should also grab an install-sh instead of using cp
slash: 
	(cd Slash; $(PERL) Makefile.PL; make)

plugins: 
	(cd plugins/Slash-Search; $(PERL) Makefile.PL; make)
	(cd plugins/Slash-Journal; $(PERL) Makefile.PL; make)

all: install

install: slash plugins 
# Need to toss in a script here that will fix prefix so
# that if someone wants to install in a different
# directory it will be easy
	# Lets go install the libraries
	(cd Slash; make install)
	# Lets go install the plugin's libraries
	(cd plugins/Slash-Search; $(PERL) Makefile.PL; make install)
	(cd plugins/Slash-Journal; $(PERL) Makefile.PL; make install)

	# First we do the default sutff
	install -d $(PREFIX)/bin/ $(PREFIX)/sbin $(PREFIX)/sql/ $(PREFIX)/sql/mysql/ $(PREFIX)/sql/postgresql $(PREFIX)/themes/ $(PREFIX)/themes/slashcode/htdocs/ $(PREFIX)/themes/slashcode/sql/ $(PREFIX)/themes/slashcode/sql/postgresql $(PREFIX)/themes/slashcode/sql/mysql $(PREFIX)/themes/slashcode/backup $(PREFIX)/themes/slashcode/logs/ $(PREFIX)/plugins/ $(PREFIX)/httpd/
	install -D bin/install-slashsite bin/tailslash bin/template-editor $(PREFIX)/bin/
	install -D sbin/slashd sbin/portald sbin/moderatord sbin/dailyStuff $(PREFIX)/sbin/
	cp sql/mysql/slashschema_create.sql $(PREFIX)/sql/mysql/schema.sql
	cp sql/postgresql/slashschema_create.sql $(PREFIX)/sql/postgresql/schema.sql
	cp httpd/slash.conf $(PREFIX)/httpd/slash.conf

	# Now for the default theme (be nice when this goes in themes)
	cp -r plugins/* $(PREFIX)/plugins/
	# Now all other themes
	cp -r themes/* $(PREFIX)/themes

	# this needs to be made platform independent
	install utils/slashd $(INIT)/init.d/
	ln -s -f $(INIT)/init.d/slashd $(INIT)/rc3.d/S99slashd
	ln -s -f $(INIT)/init.d/slashd $(INIT)/rc6.d/K99slashd
	touch $(PREFIX)/slash.sites
	chown $(USER):$(GROUP) $(PREFIX)
	chown -R $(USER):$(GROUP) $(PREFIX)/themes
	chown -R $(USER):$(GROUP) $(PREFIX)/sbin
	chown -R $(USER):$(GROUP) $(PREFIX)/bin
	chown -R $(USER):$(GROUP) $(PREFIX)/sql
	chown -R $(USER):$(GROUP) $(PREFIX)/plugins
	# Add a @ to suppress output of the echo's
	@echo "+--------------------------------------------------------+"; \
	echo "| All done.                                              |"; \
	echo "| If you want to let slash handle your httpd.conf file   |"; \
	echo "| go add:                                                |"; \
	echo "|                                                        |"; \
	echo "| Include $(PREFIX)/httpd/slash.conf                     |"; \
	echo "|                                                        |"; \
	echo "| to your httpd.conf for apache.                         |"; \
	echo "| If not, cat its content into your httpd.conf file.     |"; \
	echo "|                                                        |"; \
	echo "| Thanks for installing slashcode.                       |"; \
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


