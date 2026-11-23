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
#     tidy derive their target lists by grepping the org sources; never
#     hand-maintain a file list here.
#   * We pre-create every target directory from the manifest — whether
#     org-babel mkdirs itself is version-dependent; the build owns the tree.
#   * org-babel deliberately SKIPS the disk write when tangled content is
#     byte-identical to the existing target, preserving its mtime. We
#     therefore touch every target after a successful tangle: a successful
#     tangle means the target matches its source, and the touch asserts
#     that in make semantics. Without it, mtime-only staleness could
#     never be cleared by re-tangling.
#   * No generated elisp is tracked. The repo is org/ + snipptets/ + makefile
#     + README.md + .gitignore; git status stays clean across tangle and
#     tidy cycles. Fresh clone entry point: make tangle.
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
# --- Discovery for probes and checks ---------------------------------------
PROBES := $(wildcard .probe/*.sh)
CHECKS := $(wildcard .check/*.sh)

# Manifest extractor, as a shell snippet: append an org file (or several)
# as arguments. Prints root-relative targets, deduplicated. Used both at
# parse time (ALL_TARGETS) and shell-side inside recipes.
manifest = grep -hoE ':tangle[[:space:]]+"\.\./[^"]+"' $(1) \
           | sed -E 's/:tangle[[:space:]]+"//; s/"$$//; s/^\.\.\///' | sort -u

ALL_TARGETS := $(shell $(call manifest,$(ORGS)))

.DEFAULT_GOAL := usage
.PHONY: usage help tangle status probe check try install uninstall tidy clean

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
	@echo 'Fresh clone entry point:  make tangle && make try'
	@echo ''
	@echo ''
	@echo '  make tangle              tangle every org under org/'
	@echo '  make tangle org=NAME     tangle only org/NAME.org'
	@echo ''
	@echo ''
	@echo '  make status              freshness report for every org file:'
	@echo '                           ok / STALE (org newer than target) /'
	@echo '                           MISSING. Exits nonzero if any are not ok.'
	@echo '  make status org=NAME     report for only org/NAME.org'
	@echo ''
	@echo ''
	@echo '  make probe               run every probe under probes/ - diagnostic'
	@echo '                           output; exit status informational.'
	@echo '  make probe sh=NAME       run probes/NAME.sh via bash; opts=STRING'
	@echo '                           passes STRING through as arguments.'
	@echo ''
	@echo ''
	@echo '  make check               run every check under checks/ - invariants;'
	@echo '                           exits nonzero if any check fails.'
	@echo '  make check sh=NAME       run one shell check; opts=STRING passes through.'
	@echo ''
	@echo ''
	@echo '  make try                 launch Emacs on the tangled tree with an'
	@echo '                           explicit --init-directory (never touches'
	@echo '                           the installed/legacy config). Refuses'
	@echo '                           without init.el. Warns if org sources'
	@echo '                           are newer than their tangles.'
	@echo '  make try opts=STRING     pass STRING through verbatim to the emacs'
	@echo '                           command line, after --init-directory.'
	@echo '                           e.g. opts="--debug-init" for a backtrace'
	@echo '                           on init errors, opts="--daemon", opts="-nw".'
	@echo ''
	@echo ''
	@echo '  make install             symlink ~/.config/emacs -> this repo,'
	@echo '                           making it the default Emacs. Refuses'
	@echo '                           if something already lives there.'
	@echo '  make uninstall           remove that symlink — only if it is'
	@echo '                           ours.'
	@echo ''
	@echo ''
	@echo '  make tidy                remove every generated elisp file.'
	@echo '                           Survivors: org/, snippets/, makefile, README.md,'
	@echo '                           .gitignore. Stock Emacs until re-tangled.'
	@echo '  make clean               tidy + wipe runtime state (elpa/,'
	@echo '                           eln-cache/, backups, ...).'

# --- tangle ----------------------------------------------------------
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
	  touch "$$t"; \
	done; \
	echo "tangled $(org:.org=).org:"; for t in $$targets; do echo "  $$t"; done
else
	@set -e; for o in $(ORGS); do \
	  $(MAKE) --no-print-directory tangle org=$$(basename $$o .org); \
	done
endif

# --- status ----------------------------------------------------------
# No org=  : report every org file.
# org=NAME : report only that one. Exits nonzero if anything is not ok.
status:
ifdef org
	@test -f $(ORG_DIR)/$(org:.org=).org || \
	  { echo "no such file: $(ORG_DIR)/$(org:.org=).org"; exit 1; }
	@set -e; bad=0; o=$(ORG_DIR)/$(org:.org=).org; \
	echo "$$o"; \
	targets=$$($(call manifest,$$o)); \
	for t in $$targets; do \
	  if   [ ! -f "$$t" ];      then echo "  MISSING $$t"; bad=1; \
	  elif [ "$$o" -nt "$$t" ]; then echo "  STALE   $$t"; bad=1; \
	  else                           echo "  ok      $$t"; fi; \
	done; \
	if [ $$bad -ne 0 ]; then echo 'status: NOT ok — re-tangle (make tangle)'; fi; \
	exit $$bad
else
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
endif

# --- probe ------------------------------------------------------------
# Probes observe and report (diagnostics); they never modify the tree.
# Everything is a shell script: elisp payloads wrap in a heredoc inside
# the script and run via a stock batch Emacs. No sh=: run every probe.
# sh=NAME runs probes/NAME.sh with opts=STRING passed through verbatim
# as arguments - the argumentable form. Throwaway probes stay in /tmp;
# only generalized ones live here.
probe:
ifdef sh
	@test -f ".probe/$(sh).sh" || { echo "no such probe: .probe/$(sh).sh"; exit 1; }
	@bash ".probe/$(sh).sh" $(opts)
else
	@set -e; for p in $(PROBES); do \
          echo "== probe $$p"; bash "$$p"; done
endif

# --- check -----------------------------------------------------------
# Checks enforce invariants; a check exits nonzero when violated.
# Everything is a shell script. No sh=: run every check, aggregate
# failures, exit nonzero if any. sh=NAME runs one; opts= passes through.
check:
ifdef sh
	@test -f ".check/$(sh).sh" || { echo "no such check: .check/$(sh).sh"; exit 1; }
	@bash ".check/$(sh).sh" $(opts) && echo "PASS: .check/$(sh).sh"
else
	@bad=0; for c in $(CHECKS); do \
          echo "== check $$c"; bash "$$c" || bad=1; done; \
        if [ $$bad -ne 0 ]; then echo 'check: FAILED — an invariant is violated'; exit 1; \
        else echo 'check: all invariants hold'; fi
endif

# --- run and check -----------------------------------------------------
# Launches the tangled tree via an explicit --init-directory. The check
# is pre-flight: init.el MUST exist (per the Emacs manual, --init-directory
# without init.el silently falls back to the default init file — i.e. the
# legacy config; never launch the wrong Emacs), and stale tangles produce
# a warning so you know you are trying an old build.
#
# opts=STRING passes STRING through verbatim to the emacs command line,
# appended after --init-directory. Raw passthrough — quoting is yours.
#   make try opts="--debug-init"     debugger + backtrace on init errors
#   make try opts="--daemon"         daemon instead of a frame
#   make try opts="-nw"             terminal instance
try:
	@test -f init.el || { echo 'error: no init.el — make tangle first.'; \
	  echo '(--init-directory without init.el silently falls back to the'; \
	  echo ' default init file; refusing to launch the wrong Emacs.)'; exit 1; }
	@for o in $(ORGS); do \
	  for t in $$($(call manifest,$$o)); do \
	    if [ "$$o" -nt "$$t" ]; then \
	      echo "warning: $$o newer than $$t — trying a stale build (make tangle)."; \
	    fi; \
	  done; \
	done; true
	$(EMACS) --init-directory="$(ROOT_DIR)" $(opts)

# --- install / uninstall ------------------------------------------
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

# --- tidy / clean ----------------------------------------------------
# tidy removes every generated elisp file. The kill list IS the manifest.
# Survivors: org/ sources, makefile, README.md, .gitignore — everything
# no :tangle header claims. After tidy the tree is stock Emacs (no
# init.el at all). Restore with: make tangle
tidy:
	@set -e; \
	targets='$(ALL_TARGETS)'; \
	test -n "$$targets" || { echo 'no :tangle targets found in any org'; exit 1; }; \
	echo 'tidy: removing generated sources:'; \
	for t in $$targets; do echo "  $$t"; rm -f "$$t"; done; \
	find . -mindepth 1 -type d -empty -not -name '.git' -delete; \
	echo 'tidy: tree reduced to sources — stock Emacs until re-tangled.'

# clean = tidy + runtime state.
clean: tidy
	@set -e; \
	for d in elpa eln-cache auto-save-list backup autosave; do \
	  [ -e "$$d" ] && rm -rf "$$d" || true; \
	done; \
	find . -mindepth 1 -type d -empty -not -name '.git' -delete; \
	echo 'clean: runtime state removed. Survivors: org/, makefile, README.md, .gitignore.'
