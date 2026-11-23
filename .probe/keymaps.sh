#!/bin/bash
# probe: keymaps — dump the bindings of named keymaps (stock Emacs, batch).
# usage: make probe sh=keymaps opts="MAP..."
# default: the completion maps. Live-config maps need a session probe
# (load a file into the running instance) — throwaways live in /tmp.
set -u
maps=(${@:-minibuffer-local-map minibuffer-local-completion-map minibuffer-local-must-match-map completion-list-mode-map})
for m in "${maps[@]}"; do
  echo "=== $m ==="
  emacs --batch -Q --eval "(progn
    (require 'minibuffer)
    (require 'simple)
    (let ((sym (intern \"$m\")))
      (if (and (boundp sym) (keymapp (symbol-value sym)))
          (princ (substitute-command-keys (format \"\\\\{%s}\" sym)))
        (princ (format \"not a bound keymap: %s\" sym)))))"
  echo
done
