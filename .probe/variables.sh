#!/bin/bash
# probe: variables — value and documentation of named variables (stock, batch).
# usage: make probe sh=variables opts="VAR..."
set -u
[ $# -gt 0 ] || { echo "usage: make probe sh=variables opts=\"VAR...\""; exit 2; }
for v in "$@"; do
  echo "=== $v ==="
  emacs --batch -Q --eval "(progn
    (require 'minibuffer)
    (require 'simple)
    (let ((sym (intern \"$v\")))
      (if (boundp sym)
          (progn
            (princ (format \"%s = %S\n\" sym (symbol-value sym)))
            (princ (or (documentation-property sym 'variable-documentation) \"NO DOC\")))
        (princ \"not bound\"))))"
  echo
done
