#!/bin/sh
set -eu

ROOT=$(CDPATH= cd -- "$(dirname "$0")/../.." && pwd)
PATCH="$ROOT/core-runtime/patches/fba2012-ignore-rom-crc.patch"

test -s "$PATCH"
grep -q '^+#if defined(FBA_IGNORE_ROM_CRC)' "$PATCH"
grep -q 'index = find_rom_by_name_relaxed' "$PATCH"
grep -q 'find_rom_by_crc(g_find_list\[i\].ri.nCrc' "$PATCH"
# The patch only changes ROM mapping; the existing nLen checks remain in the
# surrounding upstream function and are covered by apply/reverse verification.
grep -q 'FBA_DEFINES=.*FBA_IGNORE_ROM_CRC=1' "$ROOT/core-runtime/scripts/build-fba2012.sh"
grep -q 'EXPECTED_COMMIT=.*0ce31536bef3162fe7e69ff5f555334ec4913cef' "$ROOT/core-runtime/scripts/build-fba2012.sh"
test -s "$ROOT/.github/workflows/build-fba2012.yml"
grep -q '0ce31536bef3162fe7e69ff5f555334ec4913cef' "$ROOT/.github/workflows/build-fba2012.yml"
grep -q 'core-runtime/scripts/build-fba2012.sh' "$ROOT/.github/workflows/build-fba2012.yml"
grep -q 'devkitpro/devkitarm:latest' "$ROOT/.github/workflows/build-fba2012.yml"

if grep -q '^+.*return true;' "$PATCH"; then
    printf '%s\n' 'unexpected unconditional success in CRC patch' >&2
    exit 1
fi
printf '%s\n' 'FBA CRC behavior contract passed.'
