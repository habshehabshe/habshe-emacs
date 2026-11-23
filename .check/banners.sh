#!/bin/bash
# check: banners — every tangled file starts with the GENERATED banner
# and carries lexical-binding: t.
set -u
cd "$(dirname "$0")/.."
bad=0
targets=$(grep -hoE ':tangle[[:space:]]+"\.\./[^"]+"' org/*.org \
          | sed -E 's/:tangle[[:space:]]+"//; s/"$//; s/^\.\.\///' | sort -u)
for t in $targets; do
  [ -f "$t" ] || { echo "FAIL: missing $t (make tangle)"; bad=1; continue; }
  head -n 1 "$t" | grep -q 'GENERATED' \
    || { echo "FAIL: $t lacks the GENERATED banner"; bad=1; }
  head -n 1 "$t" | grep -q 'lexical-binding: t' \
    || { echo "FAIL: $t lacks lexical-binding"; bad=1; }
done
[ $bad -eq 0 ] && echo "ok:   banners present"
exit $bad
