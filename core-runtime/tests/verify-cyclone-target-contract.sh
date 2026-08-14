#!/bin/sh
set -eu

ROOT=$(CDPATH= cd -- "$(dirname "$0")/../.." && pwd)
SCRIPT="$ROOT/core-runtime/scripts/diagnose-cyclone-target.sh"

test -x "$SCRIPT"
grep -q 'FBNEO_SOURCE' "$SCRIPT"
grep -q 'FBNEO_COMMIT' "$SCRIPT"
grep -q 'Cyclone' "$SCRIPT"
grep -q 'Cyclone.o' "$SCRIPT"
grep -q 'command.txt' "$SCRIPT"
grep -q 'make.stdout' "$SCRIPT"
grep -q 'make.stderr' "$SCRIPT"
grep -q 'driver.stderr' "$SCRIPT"
grep -q 'as.stderr' "$SCRIPT"
grep -q 'resource.txt' "$SCRIPT"
grep -q 'status.txt' "$SCRIPT"
grep -q 'safe.directory' "$SCRIPT"
grep -q -- '--trace' "$SCRIPT"
grep -q 'trace.stdout' "$SCRIPT"
grep -q 'trace.stderr' "$SCRIPT"
grep -q 'ulimit -a' "$SCRIPT"
grep -q '/proc/meminfo' "$SCRIPT"
grep -q '2fcb2628fbfd529806e75f3559a9d82758c8a5cc' "$SCRIPT"

if env FBNEO_SOURCE="$ROOT/work/FBNeo" FBNEO_COMMIT=wrong DEVKITARM=/missing \
    "$SCRIPT" >/dev/null 2>&1; then
    printf '%s\n' 'target diagnostic must reject an invalid commit' >&2
    exit 1
fi

printf '%s\n' 'Cyclone target diagnostic contract passed.'
