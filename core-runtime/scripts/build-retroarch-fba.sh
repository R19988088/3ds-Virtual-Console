#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
RETROARCH="${RETROARCH_SOURCE:-$ROOT/work/RetroArch}"
CORE="${FBA_CORE:-$ROOT/core-runtime/dist/fba2012/runtime.a}"
OUTPUT="${FBA_OUTPUT:-$ROOT/core-runtime/dist/fba2012}"

test -d "$RETROARCH"
test -s "$CORE"
PATCH_FILE="${VCOVEN_RETROARCH_PATCH:-$ROOT/core-runtime/retroarch-vcoven.patch}"
if ! git -C "$RETROARCH" apply --check --whitespace=error "$PATCH_FILE"; then
    printf '%s\n' "RetroArch source already contains the vcoven patch or is not clean: $RETROARCH" >&2
    exit 1
fi
git -C "$RETROARCH" apply --whitespace=error "$PATCH_FILE"
cp "$CORE" "$RETROARCH/libretro_ctr.a"

# Recent devkitPro images keep picasso/bin2s in the shared tools package,
# while older RetroArch makefiles default to DEVKITARM/bin.
if [ -z "${DEVKITTOOLS:-}" ] && [ -x "${DEVKITPRO:-/opt/devkitpro}/tools/bin/picasso" ]; then
    export DEVKITTOOLS="${DEVKITPRO:-/opt/devkitpro}/tools"
fi

rm -rf "$RETROARCH/vcoven-romfs"
mkdir -p "$RETROARCH/vcoven-romfs/content"
printf '%s\n' 'placeholder' > "$RETROARCH/vcoven-romfs/content/game.zip"

make -C "$RETROARCH" -f Makefile.ctr clean >/dev/null 2>&1 || true
make -C "$RETROARCH" -f Makefile.ctr -j"${JOBS:-$(getconf _NPROCESSORS_ONLN 2>/dev/null || printf 2)}" \
    LIBRETRO=fbalpha2012 VCOVEN_ARCADE_ROMFS=1 APP_SYSTEM_MODE=80MB APP_SYSTEM_MODE_EXT=124MB APP_ROMFS="$RETROARCH/vcoven-romfs"

mkdir -p "$OUTPUT"
cp "$RETROARCH/retroarch_3ds.elf" "$OUTPUT/fba2012_3ds.elf"
cp "$RETROARCH/retroarch_3ds.cia" "$OUTPUT/retroarch-fba-template.cia"
printf '%s\n' 'RetroArch FBA launcher build completed.'
