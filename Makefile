##
##  Makefile -- Current one for slashcode
##

#   the used tools
VERSION = 2.0-alpha-1
DISTNAME = slash
DISTVNAME = $(DISTNAME)-$(VERSION)

SHELL = /bin/sh
PERL = perl
NOOP = $(SHELL) -c true
RM_RF = rm -rf
SUFFIX = .gz
COMPRESS = gzip --best
TAR  = tar
TARFLAGS = cvf
PREOP = @$(NOOP)
POSTOP = @$(NOOP)
TO_UNIX = @$(NOOP)
PREFIX = /usr/local/slash


#   install the shared object file into Apache 
# We should run a script on the binaries to get the right
# version of perl. 
# I should also grab an install-sh instead of using cp
slash: 
	(cd Slash; $(PERL) Makefile.PL; make)

all: install

install: slash
# Need to toss in a script here that will fix prefix so
# that if someone wants to install in a different
# directory it will be easy
	# Lets go install the libraries
	(cd Slash; make install)

	# First we do the default sutff
	install -d $(PREFIX)/bin/ $(PREFIX)/sbin $(PREFIX)/sql/ $(PREFIX)/sql/mysql/ $(PREFIX)/sql/postgresql $(PREFIX)/themes/ $(PREFIX)/themes/slashcode/htdocs/ $(PREFIX)/themes/slashcode/sql/ $(PREFIX)/themes/slashcode/sql/postgresql $(PREFIX)/themes/slashcode/sql/mysql $(PREFIX)/themes/slashcode/backup $(PREFIX)/themes/slashcode/logs/
	install -D bin/install-slashsite $(PREFIX)/bin/
	install -D sbin/slashd sbin/portald sbin/moderatord sbin/dailyStuff $(PREFIX)/sbin/
	cp sql/mysql/slashschema_create.sql $(PREFIX)/sql/mysql/schema.sql
	cp sql/postgresql/slashschema_create.sql $(PREFIX)/sql/postgresql/schema.sql

	# Now for the default theme
	cp -r public_html/* $(PREFIX)/themes/slashcode/htdocs/
	cp sql/postgresql/slashdata_dump.sql $(PREFIX)/themes/slashcode/sql/postgresql/datadump.sql
	cp sql/postgresql/slashdata_prep.sql $(PREFIX)/themes/slashcode/sql/postgresql/prep_date.sql
	cp sql/mysql/slashdata_dump.sql $(PREFIX)/themes/slashcode/sql/mysql/datadump.sql
	cp sql/mysql/slashdata_prep.sql $(PREFIX)/themes/slashcode/sql/mysql/prep_date.sql

	# this needs to be made platform independent
	install -D utils/slashd /etc/rc.d/init.d/
	ln -s -f /etc/rc.d/init.d/slashd /etc/rc.d/rc3.d/S99slashd
	ln -s -f /etc/rc.d/init.d/slashd /etc/rc.d/rc3.d/K99slashd
	touch $(PREFIX)/slash.sites

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
