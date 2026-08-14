#!/bin/sh
set -eu

ROOT=$(CDPATH= cd -- "$(dirname "$0")/../.." && pwd)
SCRIPT="$ROOT/core-runtime/scripts/diagnose-cyclone.sh"

test -x "$SCRIPT"
grep -q 'FBNEO_SOURCE' "$SCRIPT"
grep -q 'FBNEO_COMMIT' "$SCRIPT"
grep -q 'DEVKITARM' "$SCRIPT"
grep -q 'toolchain.txt' "$SCRIPT"
grep -q 'command.txt' "$SCRIPT"
grep -q 'driver.stderr' "$SCRIPT"
grep -q 'preprocessed.s' "$SCRIPT"
grep -q 'as.stderr' "$SCRIPT"
grep -q 'status.txt' "$SCRIPT"
grep -q 'files.txt' "$SCRIPT"
grep -q 'arm-none-eabi-as' "$SCRIPT"
grep -q 'assembler-with-cpp' "$SCRIPT"
grep -q 'cpu/cyclone/Cyclone' "$SCRIPT"
grep -q '2fcb2628fbfd529806e75f3559a9d82758c8a5cc' "$SCRIPT"

if env FBNEO_SOURCE="$ROOT/work/FBNeo" FBNEO_COMMIT=wrong DEVKITARM=/missing "$SCRIPT" >/dev/null 2>&1; then
    printf '%s\n' 'diagnostic must reject an invalid commit' >&2
    exit 1
fi

printf '%s\n' 'Cyclone diagnostic contract passed.'
