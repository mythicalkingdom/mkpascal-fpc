# MKPascal-FPC build.  Requires Free Pascal 3.2.x (fpc).
FPC     ?= fpc
FLAGS   = -Mobjfpc -Sh -O2 -vewn -Fu$(CURDIR)/src -FU$(CURDIR)/build -FE$(CURDIR)/bin
SRC     = $(wildcard src/*.pas src/*.inc)

all: bin/mkpas bin/runtests bin/test_api bin/embed

bin/mkpas: src/mkpas.pas $(SRC)
	$(FPC) $(FLAGS) src/mkpas.pas

bin/runtests: tests/runtests.pas $(SRC)
	$(FPC) $(FLAGS) tests/runtests.pas

bin/test_api: tests/test_api.pas $(SRC)
	$(FPC) $(FLAGS) tests/test_api.pas

bin/embed: examples/embed.pas $(SRC)
	$(FPC) $(FLAGS) examples/embed.pas

test: all
	bin/runtests tests/cases
	bin/test_api

clean:
	rm -rf build/* bin/*

.PHONY: all test clean
