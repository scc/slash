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


#   the default target
all: install

#   install the shared object file into Apache 
# We should run a script on the binaries to get the right
# version of perl. 
# I should also grab an install-sh instead of using cp
slash: 
	(cd Slash; $(PERL) Makefile.PL; make)

install: slash
# Need to toss in a script here that will fix prefix so
# that if someone wants to install in a different
# directory it will be easy
	(cd Slash; make install)
	install -d $(PREFIX)/bin/ $(PREFIX)/sql/ $(PREFIX)/default/ $(PREFIX)/backups $(PREFIX)/logs
	install -CD slashd portald moderatord dailyStuff bin/install-slashsite $(PREFIX)/bin/
	cp -r public_html/* $(PREFIX)/default/
	cp -r sql/* $(PREFIX)/sql/
	install -CD utils/slashd /etc/rc.d/init.d/
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
