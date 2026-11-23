# habshe-emacs — build system
#
# Build contract:
#   * The org :tangle headers are the build manifest. The dependency
#     edges below state the same mapping; status and the manifest
#     check catch drift between the two.
#   * Tangling always runs from the repo root with a clean Emacs
#     (-Q): no user config can influence what the org files produce.
#   * org-babel skips the disk write when tangled content is
#     byte-identical, preserving the old mtime. The post-tangle
#     touch below therefore also asserts "target matches source"
#     in make semantics: without it a target would look stale
#     forever.
#   * No generated elisp is tracked. `make tidy` reduces the tree
#     to sources; git status stays clean across tangle cycles.

EMACS       := emacs
EMACS_BATCH := $(EMACS) --batch -Q
ROOT_DIR    := $(CURDIR)
ORG_DIR     := org
DEST        := $(HOME)/.config/emacs

.DEFAULT_GOAL := usage
.PHONY: usage help tangle status probe check try install uninstall tidy clean

# Build graph. One edge per tangle target; the list mirrors the
# :tangle headers. A missing edge means the target is never built —
# status flags it as MISSING.
TANGLE_TARGETS := \
  early-init.el \
  init.el \
  lisp/my-emacs-buffers.el \
  lisp/my-emacs-completions.el \
  lisp/my-emacs-editing.el \
  lisp/my-emacs-files.el \
  lisp/my-emacs-frames.el \
  lisp/my-emacs-keybindings.el \
  lisp/my-emacs-packages.el \
  lisp/my-emacs-windows.el \
  lisp/my-marginalia.el \
  lisp/my-orderless.el \
  lisp/my-whole-line-or-region.el \
  lisp/my-yasnippet.el

early-init.el: org/early-init.org
init.el: org/init.org
lisp/my-emacs-buffers.el: org/emacs-buffers.org
lisp/my-emacs-completions.el: org/emacs-completions.org
lisp/my-emacs-editing.el: org/emacs-editing.org
lisp/my-emacs-files.el: org/emacs-files.org
lisp/my-emacs-frames.el: org/emacs-frames.org
lisp/my-emacs-keybindings.el: org/emacs-keybindings.org
lisp/my-emacs-packages.el: org/emacs-packages.org
lisp/my-emacs-windows.el: org/emacs-windows.org
lisp/my-marginalia.el: org/marginalia.org
lisp/my-orderless.el: org/orderless.org
lisp/my-whole-line-or-region.el: org/whole-line-or-region.org
lisp/my-yasnippet.el: org/yasnippet.org

# One recipe for every tangle target. The target derives its source
# org by finding the :tangle header that claims it — the headers stay
# the single source of truth, the edge list only states the graph.
$(TANGLE_TARGETS):
	@set -e; \
	src=$$(grep -lF ":tangle \"../$@\"" $(ORG_DIR)/*.org | head -1); \
	test -n "$$src" || { echo "no :tangle header claims $@"; exit 1; }; \
	mkdir -p $$(dirname "$@"); \
	echo "tangling $$src -> $@"; \
	$(EMACS_BATCH) --eval '(require (quote org))' \
	               --eval '(require (quote ob-tangle))' \
	               --eval '(setq org-confirm-babel-evaluate nil)' \
	               --eval "(org-babel-tangle-file \"$(ROOT_DIR)/$$src\")"; \
	test -f "$@" || { echo "FAILED to generate: $@"; exit 1; }; \
	touch "$@"

usage:
	@echo 'error: bare "make" is meaningless in this project.'
	@echo 'every command is explicit — run "make help" for the reference.'
	@exit 1

help: ## Print this command reference
	@grep -hE '^[a-z-]+:.*## ' $(MAKEFILE_LIST) | \
	  awk -F':.*## ' '{printf "  make %-9s %s\n", $$1, $$2}'

ifeq (,$(org))
tangle: $(TANGLE_TARGETS) ## Tangle stale targets (org=NAME forces one)
else
# Forced variant: org=NAME re-tangles that org's targets regardless
# of staleness.
tangle:
	@test -f $(ORG_DIR)/$(org:.org=).org || \
	  { echo "no such file: $(ORG_DIR)/$(org:.org=).org"; exit 1; }
	@targets=$$(grep -hoE ':tangle[[:space:]]+"\.\./[^"]+"' \
	  $(ORG_DIR)/$(org:.org=).org \
	  | sed -E 's/:tangle[[:space:]]+"//; s/"$$//; s/^\.\.\///' | sort -u); \
	test -n "$$targets" || { echo "no :tangle targets in $(org)"; exit 1; }; \
	$(MAKE) --no-print-directory --always-make $$targets
endif

status: ## Per-target freshness report; nonzero exit if not all ok
	@bad=0; \
	for t in $(TANGLE_TARGETS); do \
	  org=$$(grep -lF ":tangle \"../$$t\"" $(ORG_DIR)/*.org | head -1); \
	  if   [ ! -f "$$t" ];  then echo "  MISSING $$t (from $$org)"; bad=1; \
	  elif [ "$$org" -nt "$$t" ]; then echo "  STALE   $$t"; bad=1; \
	  else echo "  ok      $$t"; fi; \
	done; \
	if [ $$bad -ne 0 ]; then echo 'status: NOT ok — re-tangle (make tangle)'; fi; \
	exit $$bad

probe: ## Run probes (all, or sh=NAME; args= passes arguments)
ifdef sh
	@test -f ".probe/$(sh).sh" || { echo "no such probe: $(sh)"; exit 1; }
	@bash ".probe/$(sh).sh" $(args)
else
	@set -e; for p in .probe/*.sh; do echo "== probe $$p"; bash "$$p"; done
endif

check: ## Run checks; nonzero exit on any invariant violation
ifdef sh
	@test -f ".check/$(sh).sh" || { echo "no such check: $(sh)"; exit 1; }
	@bash ".check/$(sh).sh" $(args) && echo "PASS: .check/$(sh).sh"
else
	@bad=0; for c in .check/*.sh; do echo "== check $$c"; bash "$$c" || bad=1; done; \
	if [ $$bad -ne 0 ]; then echo 'check: FAILED'; exit 1; \
	else echo 'check: all invariants hold'; fi
endif

try: ## Launch Emacs on the tangled tree; args= passes to emacs
	@test -f init.el || { echo 'error: no init.el — make tangle first.'; \
	  echo '(--init-directory without init.el silently falls back to the'; \
	  echo ' default init file; refusing to launch the wrong Emacs.)'; exit 1; }
	@$(MAKE) -q $(TANGLE_TARGETS) || \
	  echo 'warning: org sources newer than their tangles (make tangle).'
	$(EMACS) --init-directory="$(ROOT_DIR)" $(args)

install: ## Symlink ~/.config/emacs to this repo (the XDG slot)
	@if [ -e "$(DEST)" ] || [ -L "$(DEST)" ]; then \
	  if [ "$(DEST)" -ef "$(ROOT_DIR)" ]; then \
	    echo "already installed: $(DEST) -> $(ROOT_DIR)"; \
	  else \
	    echo "error: $(DEST) exists and is not this repo."; \
	    echo "move it aside first, then re-run."; exit 1; \
	  fi; \
	else \
	  ln -s "$(ROOT_DIR)" "$(DEST)"; \
	  echo "installed: $(DEST) -> $(ROOT_DIR)"; \
	fi

uninstall: ## Remove the install symlink (only if it is ours)
	@if [ -L "$(DEST)" ] && [ "$(DEST)" -ef "$(ROOT_DIR)" ]; then \
	  rm "$(DEST)"; echo "uninstalled: $(DEST)"; \
	else \
	  echo "$(DEST) is not ours — not touching it."; exit 1; \
	fi

tidy: ## Remove every generated elisp file (survivors: sources only)
	@set -e; \
	for t in $(TANGLE_TARGETS); do rm -f "$$t"; done; \
	find . -mindepth 1 -type d -empty -not -name '.git' -delete; \
	echo 'tidy: tree reduced to sources — stock Emacs until re-tangled.'

clean: tidy ## tidy + wipe runtime state (elpa/, caches, backups)
	@for d in elpa eln-cache auto-save-list backup autosave; do \
	  [ -e "$$d" ] && rm -rf "$$d" || true; \
	done; \
	find . -mindepth 1 -type d -empty -not -name '.git' -delete; \
	echo 'clean: runtime state removed.'
