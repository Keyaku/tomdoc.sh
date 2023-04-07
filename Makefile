PREFIX ?= /usr/local
DSTDIR := $(PREFIX)/bin
SHFMT_FLAGS := -i 4 -ln posix
TESTS := $(wildcard test/*.t)

TOMDOCSH_VERSION := $(shell test -d .git && command -v git >/dev/null && \
	git describe --tags --match "v[0-9]*" --abbrev=4 --dirty 2>/dev/null | cut -c2- || \
	sed -n -e "s/TOMDOCSH_VERSION=\"\(.*\)\"/\1/p" tomdoc.sh)

all:

@PHONY: lint
lint: tomdoc.sh $(TESTS)
	shellcheck -x $^
	shfmt -d $(SHFMT_FLAGS) $^
	checkbashisms --posix $^

@PHONY: fmt
fmt: tomdoc.sh $(TESTS)
	shfmt -w $(SHFMT_FLAGS) $^

test: all
	$(MAKE) -C test

install: all
	mkdir -p '$(DSTDIR)'
	sed -e "s/\(TOMDOCSH_VERSION\)=.*/\1=\"$(TOMDOCSH_VERSION)\"/" tomdoc.sh > '$(DSTDIR)/tomdoc.sh'
	chmod 755 '$(DSTDIR)/tomdoc.sh'

remove: uninstall
uninstall:
	$(RM) '$(DSTDIR)/tomdoc.sh'

.PHONY: all test install uninstall remove
