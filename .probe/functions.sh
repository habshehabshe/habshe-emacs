#!/bin/bash
# probe: functions — arglist and docstring of named functions (stock, batch).
# usage: make probe sh=functions opts="SYM..."
set -u
[ $# -gt 0 ] || { echo "usage: make probe sh=functions opts=\"SYM...\""; exit 2; }
for f in "$@"; do
  echo "=== $f ==="
  emacs --batch -Q --eval "(progn
    (require 'minibuffer)
    (require 'simple)
    (let ((sym (intern \"$f\")))
      (if (fboundp sym)
          (progn
            (princ (format \"%s %S\n\" sym (help-function-arglist sym)))
            (princ (or (documentation sym) \"NO DOC\")))
        (princ \"not a function\"))))"
  echo
done
