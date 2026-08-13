#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
SOURCE="${FBNEO_SOURCE:-$ROOT/work/FBNeo-libretro-2}"
BUILD="${FBNEO_BUILD:-$ROOT/.core-build/fbneo}"
OUTPUT="${FBNEO_OUTPUT:-$ROOT/core-runtime/dist/fbneo}"
RETROARCH="${RETROARCH_SOURCE:-$ROOT/work/RetroArch}"
RETROARCH_PATCH="${VCOVEN_RETROARCH_PATCH:-$ROOT/core-runtime/retroarch-vcoven.patch}"
EXPECTED_COMMIT="${FBNEO_COMMIT:-2fcb2628fbfd529806e75f3559a9d82758c8a5cc}"
DEVKITARM_ROOT="${DEVKITARM:-/opt/devkitpro/devkitARM}"
STRIP="$DEVKITARM_ROOT/bin/arm-none-eabi-strip"
JOBS="${JOBS:-$(getconf _NPROCESSORS_ONLN 2>/dev/null || printf 2)}"

test -d "$SOURCE/.git"
test "$(git -C "$SOURCE" rev-parse HEAD)" = "$EXPECTED_COMMIT"
for tool in arm-none-eabi-g++ arm-none-eabi-strip arm-none-eabi-readelf; do
    test -x "$DEVKITARM_ROOT/bin/$tool" || {
        printf 'missing devkitARM tool: %s/bin/%s\n' "$DEVKITARM_ROOT" "$tool" >&2
        exit 1
    }
done
test -d "$RETROARCH"
git config --global --add safe.directory "$ROOT"
git config --global --add safe.directory "$SOURCE"
git config --global --add safe.directory "$RETROARCH"

rm -rf "$BUILD" "$OUTPUT"
mkdir -p "$BUILD" "$OUTPUT"
git -C "$SOURCE" archive --format=tar HEAD | tar -xf - -C "$BUILD"

# FBNeo already provides the 3DS static libretro target; this wrapper only
# supplies its pinned source tree and the platform-specific build flags.
make -C "$BUILD/src/burner/libretro" -f Makefile \
    clean platform=ctr SUBSET=all >/dev/null 2>&1 || true
make -C "$BUILD/src/burner/libretro" -f Makefile -j"$JOBS" \
    platform=ctr SUBSET=all REGEN_HEADERS=1 INCLUDE_CHD_SUPPORT=0 \
    CFLAGS='-fomit-frame-pointer -O3 -ffunction-sections -fdata-sections -DIOAPI_NO_64' \
    CXXFLAGS='-fomit-frame-pointer -O3 -ffunction-sections -fdata-sections -fno-rtti -fno-exceptions'

CORE="$BUILD/src/burner/libretro/fbneo_all_libretro_ctr.a"
test -s "$CORE"
cp "$CORE" "$OUTPUT/runtime.a"
printf '%s\n' "$EXPECTED_COMMIT  FBNeo source" > "$OUTPUT/SOURCE.txt"

if ! git -C "$RETROARCH" apply --check --whitespace=error "$RETROARCH_PATCH"; then
    printf '%s\n' "RetroArch source already contains the vcoven patch or is not clean: $RETROARCH" >&2
    exit 1
fi
git -C "$RETROARCH" apply --whitespace=error "$RETROARCH_PATCH"
cp "$CORE" "$RETROARCH/libretro_ctr.a"

if [ -z "${DEVKITTOOLS:-}" ] && [ -x "${DEVKITPRO:-/opt/devkitpro}/tools/bin/picasso" ]; then
    export DEVKITTOOLS="${DEVKITPRO:-/opt/devkitpro}/tools"
fi

rm -rf "$RETROARCH/vcoven-romfs"
mkdir -p "$RETROARCH/vcoven-romfs/content"
printf '%s\n' placeholder > "$RETROARCH/vcoven-romfs/content/game.zip"

MAKE_ARGS=(
    LIBRETRO=fbneo
    VCOVEN_ARCADE_ROMFS=1
    LOAD_WITHOUT_CORE_INFO=1
    APP_SYSTEM_MODE=80MB
    APP_SYSTEM_MODE_EXT=124MB
    APP_ROMFS="$RETROARCH/vcoven-romfs"
)
make -C "$RETROARCH" -f Makefile.ctr clean >/dev/null 2>&1 || true
make -C "$RETROARCH" -f Makefile.ctr -j"$JOBS" "${MAKE_ARGS[@]}"

"$STRIP" --strip-debug "$RETROARCH/retroarch_3ds.elf"
HEADER=$("$DEVKITARM_ROOT/bin/arm-none-eabi-readelf" -h "$RETROARCH/retroarch_3ds.elf")
printf '%s\n' "$HEADER" | grep -Eq '^ *Class:[[:space:]]+ELF32$'
printf '%s\n' "$HEADER" | grep -Eq '^ *Data:[[:space:]]+2.s complement, little endian$'
printf '%s\n' "$HEADER" | grep -Eq '^ *Machine:[[:space:]]+ARM$'
printf '%s\n' "$HEADER" | grep -Eq '^ *Flags:[[:space:]]+0x05000000, Version5 EABI'
size=$(wc -c < "$RETROARCH/retroarch_3ds.elf")
test "$size" -lt $((16 * 1024 * 1024))
make -C "$RETROARCH" -f Makefile.ctr "${MAKE_ARGS[@]}" retroarch_3ds.cia

cp "$RETROARCH/retroarch_3ds.elf" "$OUTPUT/fbneo_3ds.elf"
cp "$RETROARCH/retroarch_3ds.cia" "$OUTPUT/retroarch-fbneo-template.cia"
printf '%s\n' "FBNeo 3DS launcher completed: $size bytes"
