#!/bin/sh
# Check that the existing mappers behave exactly as upstream: run tb_trace.v on this
# tree and on a checkout of the upstream commit, and compare the traces case by case.
#   ./compare_upstream.sh <upstream-tree>     (e.g. a `git worktree add` of master)
set -e
cd "$(dirname "$0")"
UP=$1
status=0
for c in 0 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16 17 18; do
	BUILD=build/new ./run.sh trace $c 2>/dev/null | grep -v '\$finish' > build/new-$c.txt
	SRC="$UP/src" MAW=23 BUILD=build/old ./run.sh trace $c 2>/dev/null | grep -v '\$finish' > build/old-$c.txt
	lines=$(wc -l < build/new-$c.txt | tr -d ' ')
	if cmp -s build/new-$c.txt build/old-$c.txt; then echo "case $c: identical ($lines lines)"
	else echo "case $c: DIFFERENT"; status=1; fi
done
exit $status
