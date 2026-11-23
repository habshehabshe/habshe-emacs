#!/bin/bash
# check: bindings-locality — keybindings are set only in
# org/emacs-keybindings.org. Modules expose commands; they never bind.
set -u
cd "$(dirname "$0")/.."
hits=$(grep -rnE 'keymap-(global|local|set)|define-keymap' org/*.org \
       | grep -v '^org/emacs-keybindings.org:')
if [ -n "$hits" ]; then echo "FAIL: bindings outside keybindings:"; echo "$hits"; exit 1; fi
echo "ok:   bindings confined to keybindings"
