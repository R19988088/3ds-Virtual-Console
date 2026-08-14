#!/bin/sh
set -eu

ROOT=$(CDPATH= cd -- "$(dirname "$0")/../.." && pwd)
SCRIPT="$ROOT/core-runtime/scripts/experiment-fbneo-object-boundary.sh"

test -x "$SCRIPT"
grep -q '2fcb2628fbfd529806e75f3559a9d82758c8a5cc' "$SCRIPT"
grep -q 'Cyclone.o' "$SCRIPT"
grep -q 'retro_common.o' "$SCRIPT"
grep -q 'burn_memory.o' "$SCRIPT"
grep -q 'make_objects' "$SCRIPT"
grep -q 'missing_objects' "$SCRIPT"
grep -q 'files.txt' "$SCRIPT"
grep -q 'targets.txt' "$SCRIPT"
grep -q 'safe.directory' "$SCRIPT"

if env FBNEO_SOURCE="$ROOT/work/FBNeo" FBNEO_COMMIT=wrong DEVKITARM=/missing \
    "$SCRIPT" >/dev/null 2>&1; then
    printf '%s\n' 'object-boundary experiment must reject an invalid commit' >&2
    exit 1
fi

printf '%s\n' 'FBNeo object-boundary contract passed.'
