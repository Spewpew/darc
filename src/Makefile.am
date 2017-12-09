bin_PROGRAMS=darc
CLEANFILES=main.c
BUILT_SOURCES=main.c
main.c:$(srcdir)/loe.pl $(srcdir)/main.loe.pl.c
	$(srcdir)/loe.pl --mutate=$(srcdir)/main.loe.pl.c:main.c
darc_SOURCES=main.c
darc_CFLAGS=$(ZLIB_CFLAGS) 
darc_LDADD=$(ZLIB_LIBS) 
EXTRA_DIST=loe.pl main.loe.pl.c configure.ac.shadow Makefile.am.shadow
dist-hook:
if SHADOW
	mv $(distdir)/Makefile.am.shadow $(distdir)/Makefile.am
	mv $(distdir)/configure.ac.shadow $(top_distdir)/configure.ac
	rm $(distdir)/loe.pl $(distdir)/main.loe.pl.c
	cd $(distdir)/..; autoreconf -i
endif
