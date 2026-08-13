#!/bin/sh
set -eu

ROOT=$(CDPATH= cd -- "$(dirname "$0")/../.." && pwd)
PATCH="$ROOT/core-runtime/patches/fba2012-ignore-rom-crc.patch"
SOURCE=${1:-}

test -s "$PATCH"
grep -q 'FBA_IGNORE_ROM_CRC' "$PATCH"
grep -q 'rom_name_equal' "$PATCH"
grep -q 'find_rom_by_name_relaxed' "$PATCH"

if [ -n "$SOURCE" ]; then
    test -f "$SOURCE/svn-current/trunk/src/burner/libretro/libretro.cpp"
    git -C "$SOURCE" apply --check "$PATCH"
    git -C "$SOURCE" apply "$PATCH"
    grep -q 'FBA_IGNORE_ROM_CRC' "$SOURCE/svn-current/trunk/src/burner/libretro/libretro.cpp"
    grep -q 'rom_name_equal' "$SOURCE/svn-current/trunk/src/burner/libretro/libretro.cpp"
    git -C "$SOURCE" apply -R "$PATCH"
fi

printf '%s\n' 'FBA CRC bypass patch checks passed.'
