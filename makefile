# ==========================================================================
# habshe-emacs — build system (org/babel edition)
#
# Division of labor:
#   * make        dispatches commands, owns discovery, enforces invariants.
#   * org-babel   extracts every target from org/<name>.org  ("tangle").
#   * emacs       runs the tangled tree (--init-directory) or installs it.
#
# Interface: every command is explicit; bare `make` is an error. A command
# given an argument acts on that one thing; given no argument it acts on
# ALL of them. Extensions are always inferred: org= takes a bare name.
#
# Invariants:
#   * Tangling ALWAYS runs from the repo root with a clean Emacs (-Q):
#     no user config can influence what the org files produce.
#   * org-babel resolves :tangle paths relative to the ORG FILE's
#     directory. Repo-root targets therefore MUST carry a "../" prefix
#     (e.g. :tangle "../init.el"). Only "../"-prefixed targets count as
#     generated — the prefix doubles as the manifest filter, so
#     :tangle "no" can never enter the kill list.
#   * The org :tangle headers are the build manifest. tangle, status and
#     detangle derive their target lists by grepping the org sources;
#     never hand-maintain a file list here.
#   * We pre-create every target directory from the manifest — whether
#     org-babel mkdirs itself is version-dependent; the build owns the tree.
#   * No generated elisp is tracked. The repo is org/ + makefile +
#     README.md + .gitignore; git status stays clean across tangle and
#     detangle cycles. Fresh clone entry point: make tangle.
# ==========================================================================

EMACS       := emacs
EMACS_BATCH := $(EMACS) --batch -Q
ROOT_DIR    := $(CURDIR)
ORG_DIR     := org
DEST        := $(HOME)/.config/emacs

# --- Discovery (parse-time; loud failure on empty org/ is intentional) ----
ORGS := $(wildcard $(ORG_DIR)/*.org)
ifeq ($(strip $(ORGS)),)
$(error No .org sources found under org/. Expected org/<name>.org.)
endif

# Manifest extractor, as a shell snippet: append an org file (or several)
# as arguments. Prints root-relative targets, deduplicated. Used both at
# parse time (ALL_TARGETS) and shell-side inside recipes.
manifest = grep -hoE ':tangle[[:space:]]+"\.\./[^"]+"' $(1) \
           | sed -E 's/:tangle[[:space:]]+"//; s/"$$//; s/^\.\.\///' | sort -u

ALL_TARGETS := $(shell $(call manifest,$(ORGS)))

.DEFAULT_GOAL := usage
.PHONY: usage help tangle status run verify install uninstall detangle clean

# --------------------------------------------------------------------------
usage:
	@echo 'error: bare "make" is meaningless in this project.'
	@echo 'every command is explicit — run "make help" for the reference.'
	@exit 1

help:
	@echo 'habshe-emacs build system — command reference'
	@echo '================================================'
	@echo 'Scope rule: with an argument a command acts on that one thing;'
	@echo 'with no argument it acts on ALL of them. Extensions inferred:'
	@echo 'org= takes a bare name (init, not init.org).'
	@echo ''
	@echo 'Fresh clone entry point:  make tangle && make run'
	@echo ''
	@echo '  make tangle              tangle every org under org/'
	@echo '  make tangle org=NAME     tangle only org/NAME.org'
	@echo ''
	@echo '  make status              freshness report: for every tangle'
	@echo '                           target, ok / STALE (org newer than'
	@echo '                           target) / MISSING. Exits nonzero if'
	@echo '                           any are not ok.'
	@echo ''
	@echo '  make run                 test-drive the tangled tree with an'
	@echo '                           explicit --init-directory (never'
	@echo '                           touches the installed/legacy config)'
	@echo '  make verify              batch-load init.el to catch load-time'
	@echo '                           errors without launching a frame'
	@echo ''
	@echo '  make install             symlink ~/.config/emacs -> this repo,'
	@echo '                           making it the default Emacs. Refuses'
	@echo '                           if something already lives there.'
	@echo '  make uninstall           remove that symlink — only if it is'
	@echo '                           ours.'
	@echo ''
	@echo '  make detangle            remove every generated elisp file.'
	@echo '                           Survivors: org/, makefile, README.md,'
	@echo '                           .gitignore. Stock Emacs until re-tangled.'
	@echo '  make clean               detangle + wipe runtime state'
	@echo '                           (elpa/, eln-cache/, backups, ...).'

# --- Tangle ----------------------------------------------------------------
# No org=  : tangle every org under org/.
# org=NAME : tangle only that one. NAME may carry an .org suffix (stripped).
tangle:
ifdef org
	@test -f $(ORG_DIR)/$(org:.org=).org || \
	  { echo "no such file: $(ORG_DIR)/$(org:.org=).org"; exit 1; }
	@set -e; \
	targets=$$($(call manifest,$(ORG_DIR)/$(org:.org=).org)); \
	test -n "$$targets" || { echo "no :tangle targets in $(org:.org=).org"; exit 1; }; \
	for t in $$targets; do mkdir -p "$$(dirname "$$t")"; done; \
	$(EMACS_BATCH) --eval '(require (quote org))' \
	               --eval '(require (quote ob-tangle))' \
	               --eval '(setq org-confirm-babel-evaluate nil)' \
	               --eval "(org-babel-tangle-file \"$(ROOT_DIR)/$(ORG_DIR)/$(org:.org=).org\")"; \
	for t in $$targets; do \
	  test -f "$$t" || { echo "FAILED to generate: $$t"; exit 1; }; \
	done; \
	echo "tangled $(org:.org=).org:"; for t in $$targets; do echo "  $$t"; done
else
	@set -e; for o in $(ORGS); do \
	  $(MAKE) --no-print-directory tangle org=$$(basename $$o .org); \
	done
endif

# --- Status: is every tangle fresh? ----------------------------------------
status:
	@set -e; bad=0; \
	for o in $(ORGS); do \
	  echo "$$o"; \
	  targets=$$($(call manifest,$$o)); \
	  for t in $$targets; do \
	    if   [ ! -f "$$t" ];      then echo "  MISSING $$t"; bad=1; \
	    elif [ "$$o" -nt "$$t" ]; then echo "  STALE   $$t"; bad=1; \
	    else                           echo "  ok      $$t"; fi; \
	  done; \
	done; \
	if [ $$bad -ne 0 ]; then echo 'status: NOT ok — re-tangle (make tangle)'; fi; \
	exit $$bad

# --- Run / Verify -----------------------------------------------------------
run:
	@test -f init.el || echo 'warning: no init.el — make tangle first (stock Emacs will start).'
	$(EMACS) --init-directory "$(ROOT_DIR)"

verify:
	@test -f init.el || { echo 'no init.el — make tangle first'; exit 1; }
	$(EMACS_BATCH) --eval "(progn (setq user-emacs-directory (file-name-as-directory \"$(ROOT_DIR)\")) (load \"$(ROOT_DIR)/init.el\" nil t) (message \"verify: init.el loads cleanly\"))"

# --- Install / Uninstall ----------------------------------------------------
# install makes this repo the default Emacs via one symlink at the XDG
# slot (~/.config/emacs), which outranks any ~/.emacs.d. It refuses to
# touch an occupied slot — moving the legacy config aside is a deliberate
# human act, never a build side effect.
install:
	@if [ -e "$(DEST)" ] || [ -L "$(DEST)" ]; then \
	  if [ "$(DEST)" -ef "$(ROOT_DIR)" ]; then \
	    echo "already installed: $(DEST) -> $(ROOT_DIR)"; \
	  else \
	    echo "error: $(DEST) exists and is not this repo."; \
	    echo "move it aside first (e.g. mv $(DEST) $(DEST)-legacy), then re-run."; \
	    exit 1; \
	  fi; \
	else \
	  ln -s "$(ROOT_DIR)" "$(DEST)"; \
	  echo "installed: $(DEST) -> $(ROOT_DIR)"; \
	fi

# uninstall removes the symlink ONLY if it points at this repo.
uninstall:
	@if [ -L "$(DEST)" ] && [ "$(DEST)" -ef "$(ROOT_DIR)" ]; then \
	  rm "$(DEST)"; echo "uninstalled: $(DEST)"; \
	else \
	  echo "$(DEST) is not ours — not touching it."; exit 1; \
	fi

# --- Detangle: the generated-source nuke ------------------------------------
# The kill list IS the manifest. Survivors: org/ sources, makefile,
# README.md, .gitignore — everything no :tangle header claims.
# After detangle the tree is stock Emacs (no init.el at all).
# Restore with: make tangle
detangle:
	@set -e; \
	targets='$(ALL_TARGETS)'; \
	test -n "$$targets" || { echo 'no :tangle targets found in any org'; exit 1; }; \
	echo 'detangle: removing generated sources:'; \
	for t in $$targets; do echo "  $$t"; rm -f "$$t"; done; \
	find . -mindepth 1 -type d -empty -not -name '.git' -delete; \
	echo 'detangle: tree reduced to sources — stock Emacs until re-tangled.'

# --- Clean: detangle + runtime state ----------------------------------------
clean: detangle
	@set -e; \
	for d in elpa eln-cache auto-save-list backup autosave; do \
	  [ -e "$$d" ] && rm -rf "$$d" || true; \
	done; \
	find . -mindepth 1 -type d -empty -not -name '.git' -delete; \
	echo 'clean: runtime state removed. Survivors: org/, makefile, README.md, .gitignore.'
