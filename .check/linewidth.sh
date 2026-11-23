#!/usr/bin/env bash
# check: linewidth — no source line over 78 columns.
# Scope: org prose/elisp, README, our shell scripts. Banner lines
# ("GENERATED from") are exempt: the banner format is fixed.
# The makefile is out of scope until its rework pass.
set -u

targets="$(ls org/*.org README.md .probe/*.sh .check/*.sh 2>/dev/null)"
[ -n "$targets" ] || { echo "FAIL: no source files found"; exit 1; }

bad=0
for f in $targets; do
  awk -v file="$f" 'length > 78 && $0 !~ /GENERATED from/ {
    printf "FAIL: %s:%d (%d cols): %s\n", file, NR, length, $0
    exit 1
  }' "$f" || bad=1
done

if [ $bad -ne 0 ]; then
  echo "FAIL: over-width lines present"
  exit 1
fi
echo "ok:   all lines within 78 columns"
