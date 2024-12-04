LEVEL = ..
CGEN    = $(MPDIR)/src/cgen-2
MP3=1
TESTS	= $(wildcard *.cl)
all:	$(TESTS:.cl=.out)

all-exe: $(TESTS:.cl=.exe)

include ../Makefile.common

$(CGEN) ::
	make -C ../src cgen-2
