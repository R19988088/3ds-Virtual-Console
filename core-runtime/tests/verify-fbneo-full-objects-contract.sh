#!/bin/sh
set -eu

ROOT=$(CDPATH= cd -- "$(dirname "$0")/../.." && pwd)
SCRIPT="$ROOT/core-runtime/scripts/experiment-fbneo-full-objects.sh"

test -x "$SCRIPT"
grep -q 'OBJECT_BOUNDARY_RUN' "$SCRIPT"
grep -q 'fbneo_objects' "$SCRIPT"
grep -q 'object_count' "$SCRIPT"
grep -q 'missing_objects' "$SCRIPT"
grep -q 'objects.txt' "$SCRIPT"
grep -q 'files.txt' "$SCRIPT"
grep -q '2fcb2628fbfd529806e75f3559a9d82758c8a5cc' "$SCRIPT"
if env FBNEO_SOURCE="$ROOT/work/FBNeo" DEVKITARM=/missing \
    OBJECT_BOUNDARY_RUN=31773213035 "$SCRIPT" >/dev/null 2>&1; then
    printf '%s\n' 'full-object experiment must reject a missing toolchain' >&2
    exit 1
fi
printf '%s\n' 'FBNeo full-object contract passed.'
