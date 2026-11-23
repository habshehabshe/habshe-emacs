#!/bin/bash
# check: brackets — every generated elisp file is paren/quote balanced.
# The tangle gate: a generated file that does not read is a build failure.
set -u
cd "$(dirname "$0")/.."
bad=0
for f in lisp/*.el init.el early-init.el; do
  [ -f "$f" ] || { echo "FAIL: missing $f (make tangle)"; bad=1; continue; }
  if emacs --batch -Q --eval "(with-temp-buffer (insert-file-contents \"$f\") (emacs-lisp-mode) (check-parens))"; then
    echo "ok:   $f"
  else
    echo "FAIL: $f — unbalanced brackets or quotes"
    bad=1
  fi
done
exit $bad
