#!/bin/bash
# check: no-ensure — :ensure never appears in org sources;
# installation belongs to the package manifest alone.
set -u
cd "$(dirname "$0")/.."
hits=$(grep -rn ':ensure' org/)
if [ -n "$hits" ]; then echo "FAIL: :ensure found:"; echo "$hits"; exit 1; fi
echo "ok:   no :ensure"
