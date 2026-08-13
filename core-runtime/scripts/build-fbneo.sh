#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
SOURCE="${FBNEO_SOURCE:-$ROOT/work/FBNeo}"
BUILD="${FBNEO_BUILD:-$ROOT/.core-build/fbneo}"
OUTPUT="${FBNEO_OUTPUT:-$ROOT/core-runtime/dist/fbneo}"
EXPECTED_COMMIT="${FBNEO_COMMIT:-2fcb2628fbfd529806e75f3559a9d82758c8a5cc}"
DEVKITARM_ROOT="${DEVKITARM:-/opt/devkitpro/devkitARM}"
STRIP="$DEVKITARM_ROOT/bin/arm-none-eabi-strip"
# FBNeo's all-driver target has a high peak memory footprint.  The container
# can report the host's CPU count, so use a conservative default and allow CI
# or local builds to override it explicitly.
JOBS="${JOBS:-2}"

test -d "$SOURCE/.git"
test "$(git -C "$SOURCE" rev-parse HEAD)" = "$EXPECTED_COMMIT"
for tool in arm-none-eabi-g++ arm-none-eabi-strip arm-none-eabi-readelf; do
    test -x "$DEVKITARM_ROOT/bin/$tool" || {
        printf 'missing devkitARM tool: %s/bin/%s\n' "$DEVKITARM_ROOT" "$tool" >&2
        exit 1
    }
done
git config --global --add safe.directory "$ROOT"
git config --global --add safe.directory "$SOURCE"

rm -rf "$BUILD" "$OUTPUT"
mkdir -p "$BUILD" "$OUTPUT"
git -C "$SOURCE" archive --format=tar HEAD | tar -xf - -C "$BUILD"

# FBNeo already provides the 3DS static libretro target; this wrapper only
# supplies its pinned source tree and the platform-specific build flags.
make -C "$BUILD/src/burner/libretro" -f Makefile \
    clean platform=ctr SUBSET=all >/dev/null 2>&1 || true
env \
    CFLAGS='-DIOAPI_NO_64' \
    CXXFLAGS='-include wchar.h' \
    make -C "$BUILD/src/burner/libretro" -f Makefile -j"$JOBS" \
    platform=ctr SUBSET=all REGEN_HEADERS=1 INCLUDE_CHD_SUPPORT=0

CORE="$BUILD/src/burner/libretro/fbneo_all_libretro_ctr.a"
test -s "$CORE"
cp "$CORE" "$OUTPUT/runtime.a"
printf '%s\n' "$EXPECTED_COMMIT  FBNeo source" > "$OUTPUT/SOURCE.txt"

FBNEO_CORE="$CORE" FBNEO_SOURCE="$SOURCE" FBNEO_LAUNCHER_OUTPUT="$OUTPUT/fbneo_3ds.elf" \
    "$ROOT/core-runtime/scripts/build-fbneo-launcher.sh"
HEADER=$("$DEVKITARM_ROOT/bin/arm-none-eabi-readelf" -h "$OUTPUT/fbneo_3ds.elf")
printf '%s\n' "$HEADER" | grep -Eq '^ *Class:[[:space:]]+ELF32$'
printf '%s\n' "$HEADER" | grep -Eq '^ *Data:[[:space:]]+2.s complement, little endian$'
printf '%s\n' "$HEADER" | grep -Eq '^ *Machine:[[:space:]]+ARM$'
printf '%s\n' "$HEADER" | grep -Eq '^ *Flags:[[:space:]]+0x05000000, Version5 EABI'
size=$(wc -c < "$OUTPUT/fbneo_3ds.elf")
test "$size" -lt $((16 * 1024 * 1024))
printf '%s\n' "FBNeo 3DS launcher completed: $size bytes"
