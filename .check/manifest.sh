#!/bin/bash
# check: manifest — the :tangle headers obey the build laws.
#  * every target is ../-prefixed (the generated-file filter)
#  * root targets are exactly init.el / early-init.el
#  * each org tangles at most two elisp files: one my-, one habshe-
set -u
cd "$(dirname "$0")/.."
bad=0
for org in org/*.org; do
  targets=$(grep -hoE ':tangle[[:space:]]+"[^"]+"' "$org" | sed -E 's/:tangle[[:space:]]+"//; s/"$//')
  for t in $targets; do
    case "$t" in
      ../init.el|../early-init.el) ;;
      ../lisp/my-*.el|../lisp/habshe-*.el) ;;
      *) echo "FAIL: $org tangles unlawful target: $t"; bad=1 ;;
    esac
  done
  els=$(printf '%s\n' $targets | grep -c '^../lisp/.*\.el$')
  [ "$els" -le 2 ] || { echo "FAIL: $org tangles $els elisp files (max 2)"; bad=1; }
  mys=$(printf '%s\n' $targets | grep -c '^../lisp/my-')
  habs=$(printf '%s\n' $targets | grep -c '^../lisp/habshe-')
  [ "$mys" -le 1 ] || { echo "FAIL: $org tangles more than one my- file"; bad=1; }
  [ "$habs" -le 1 ] || { echo "FAIL: $org tangles more than one habshe- file"; bad=1; }
done
[ $bad -eq 0 ] && echo "ok:   manifest lawful"
exit $bad
