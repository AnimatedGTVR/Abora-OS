BINDIR ?= $(HOME)/.local/share/omarchy/bin
EXTRA_BINDIR ?= $(HOME)/.local/bin
BINARY ?= mint
ALIAS ?= gum

.PHONY: build check install uninstall

build:
	go build -o bin/$(BINARY) .

check:
	go test ./...

install: build
	install -d $(BINDIR)
	install -m 0755 bin/$(BINARY) $(BINDIR)/$(BINARY)
	ln -sf $(BINARY) $(BINDIR)/$(ALIAS)
	install -d $(EXTRA_BINDIR)
	install -m 0755 bin/$(BINARY) $(EXTRA_BINDIR)/$(BINARY)
	ln -sf $(BINARY) $(EXTRA_BINDIR)/$(ALIAS)
	@echo "Installed $(BINARY) to $(BINDIR)/$(BINARY)"
	@echo "Linked $(ALIAS) to $(BINDIR)/$(ALIAS)"
	@echo "Installed $(BINARY) to $(EXTRA_BINDIR)/$(BINARY)"
	@echo "Linked $(ALIAS) to $(EXTRA_BINDIR)/$(ALIAS)"
	@case ":$$PATH:" in \
		*":$(BINDIR):"*) ;; \
		*) echo "Note: $(BINDIR) is not in PATH. Add it or run: export PATH=\"$(BINDIR):$$PATH\"" ;; \
	esac

uninstall:
	rm -f $(BINDIR)/$(BINARY)
	rm -f $(BINDIR)/$(ALIAS)
	rm -f $(EXTRA_BINDIR)/$(BINARY)
	rm -f $(EXTRA_BINDIR)/$(ALIAS)
