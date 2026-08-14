#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
SOURCE="${FBNEO_SOURCE:-$ROOT/work/FBNeo}"
BUILD="${FBNEO_BUILD:-$ROOT/.core-build/fbneo}"
OUTPUT="${FBNEO_OUTPUT:-$ROOT/core-runtime/dist/fbneo}"
FAILURE_OUTPUT="${FBNEO_FAILURE_OUTPUT:-$ROOT/core-runtime/dist/fbneo-build-diagnostic}"
EXPECTED_COMMIT="${FBNEO_COMMIT:-2fcb2628fbfd529806e75f3559a9d82758c8a5cc}"
DEVKITARM_ROOT="${DEVKITARM:-/opt/devkitpro/devkitARM}"
STRIP="$DEVKITARM_ROOT/bin/arm-none-eabi-strip"
AR="$DEVKITARM_ROOT/bin/arm-none-eabi-ar"
# FBNeo's all-driver target has a high peak memory footprint. Keep the default
# serial so a failed object compile cannot be hidden by a sibling job; callers
# may opt into parallelism with JOBS after measuring the container limit.
JOBS="${JOBS:-1}"

test -d "$SOURCE/.git"
test "$(git -C "$SOURCE" rev-parse HEAD)" = "$EXPECTED_COMMIT"
for tool in arm-none-eabi-ar arm-none-eabi-g++ arm-none-eabi-strip arm-none-eabi-readelf; do
    test -x "$DEVKITARM_ROOT/bin/$tool" || {
        printf 'missing devkitARM tool: %s/bin/%s\n' "$DEVKITARM_ROOT" "$tool" >&2
        exit 1
    }
done
git config --global --add safe.directory "$ROOT"
git config --global --add safe.directory "$SOURCE"

rm -rf "$BUILD" "$OUTPUT" "$FAILURE_OUTPUT"
mkdir -p "$BUILD" "$OUTPUT" "$FAILURE_OUTPUT"

capture_failure() {
    rc=$?
    if [ "$rc" -ne 0 ]; then
        printf 'build_exit=%s\n' "$rc" > "$FAILURE_OUTPUT/failure-exit.txt"
        cp -R "$OUTPUT"/. "$FAILURE_OUTPUT"/ 2>/dev/null || true
    fi
    exit "$rc"
}
trap capture_failure EXIT

git config --global --add safe.directory "$BUILD"
git -C "$SOURCE" archive --format=tar HEAD | tar -xf - -C "$BUILD"

# FBNeo already provides the 3DS static libretro target; this wrapper only
# supplies its pinned source tree and the platform-specific build flags.
make -C "$BUILD/src/burner/libretro" -f Makefile \
    clean platform=ctr SUBSET=all >/dev/null 2>&1 || true
CORE="$BUILD/src/burner/libretro/fbneo_all_libretro_ctr.a"
OBJECTS_LINE=$(make -C "$BUILD/src/burner/libretro" -f Makefile -pn -n \
    platform=ctr SUBSET=all REGEN_HEADERS=1 INCLUDE_CHD_SUPPORT=0 SPLIT_UP_LINK=1 \
    | sed -n 's/^OBJS := //p')
read -r -a OBJECTS <<< "$OBJECTS_LINE"
test "${#OBJECTS[@]}" -gt 0
# Avoid FBNeo's 1102-command archive recipe entirely. Generate headers first,
# then build an explicit object-only aggregate target.
if ! env \
    CFLAGS='-DIOAPI_NO_64' \
    CXXFLAGS='-include wchar.h' \
    make -C "$BUILD/src/burner/libretro" \
    -f Makefile \
    platform=ctr SUBSET=all REGEN_HEADERS=1 INCLUDE_CHD_SUPPORT=0 SPLIT_UP_LINK=1 \
    generate-files > "$OUTPUT/generate-files.stdout" 2> "$OUTPUT/generate-files.stderr"; then
    cp -R "$OUTPUT"/. "$FAILURE_OUTPUT"/
    exit 1
fi
CYCLONE_OBJECT='../../cpu/cyclone/Cyclone.o'
if ! env \
    CFLAGS='-DIOAPI_NO_64' \
    CXXFLAGS='-include wchar.h' \
    make -C "$BUILD/src/burner/libretro" \
    -f Makefile -f "$ROOT/core-runtime/scripts/fbneo-no-archive.mk" \
    --output-sync=target -j1 \
    platform=ctr SUBSET=all REGEN_HEADERS=1 INCLUDE_CHD_SUPPORT=0 SPLIT_UP_LINK=1 \
    "$CYCLONE_OBJECT" > "$OUTPUT/cyclone-preflight.stdout" 2> "$OUTPUT/cyclone-preflight.stderr"; then
    cp -R "$OUTPUT"/. "$FAILURE_OUTPUT"/
    exit 1
fi
test -s "$BUILD/src/cpu/cyclone/Cyclone.o"
if ! env \
    CFLAGS='-DIOAPI_NO_64' \
    CXXFLAGS='-include wchar.h' \
    make -C "$BUILD/src/burner/libretro" \
    -f Makefile -f "$ROOT/core-runtime/scripts/fbneo-no-archive.mk" \
    --output-sync=target -j"$JOBS" \
    platform=ctr SUBSET=all REGEN_HEADERS=1 INCLUDE_CHD_SUPPORT=0 SPLIT_UP_LINK=1 \
    fbneo_objects > "$OUTPUT/fbneo-objects.stdout" 2> "$OUTPUT/fbneo-objects.stderr"; then
    cp -R "$OUTPUT"/. "$FAILURE_OUTPUT"/
    exit 1
fi
if ! (cd "$BUILD/src/burner/libretro" && "$AR" rcs "$CORE" "${OBJECTS[@]}") \
    > "$OUTPUT/archive-create.stdout" 2> "$OUTPUT/archive-create.stderr"; then
    exit 1
fi
test -s "$CORE"
if ! (cd "$BUILD/src/burner/libretro" && "$AR" t "$CORE") \
    > "$BUILD/fbneo_archive_members.txt" 2> "$OUTPUT/archive-list.stderr"; then
    exit 1
fi
test "$(wc -l < "$BUILD/fbneo_archive_members.txt")" -eq "${#OBJECTS[@]}"
grep -Fxq '../../burner/libretro/libretro.o' "$BUILD/fbneo_archive_members.txt"
grep -Fxq '../../burner/libretro/retro_common.o' "$BUILD/fbneo_archive_members.txt"
cp "$CORE" "$OUTPUT/runtime.a"
printf '%s\n' "$EXPECTED_COMMIT  FBNeo source" > "$OUTPUT/SOURCE.txt"

if ! FBNEO_CORE="$CORE" FBNEO_SOURCE="$SOURCE" FBNEO_LAUNCHER_OUTPUT="$OUTPUT/fbneo_3ds.elf" \
    "$ROOT/core-runtime/scripts/build-fbneo-launcher.sh" \
    > "$OUTPUT/launcher.stdout" 2> "$OUTPUT/launcher.stderr"; then
    exit 1
fi
HEADER=$("$DEVKITARM_ROOT/bin/arm-none-eabi-readelf" -h "$OUTPUT/fbneo_3ds.elf")
printf '%s\n' "$HEADER" | grep -Eq '^ *Class:[[:space:]]+ELF32$'
printf '%s\n' "$HEADER" | grep -Eq '^ *Data:[[:space:]]+2.s complement, little endian$'
printf '%s\n' "$HEADER" | grep -Eq '^ *Machine:[[:space:]]+ARM$'
printf '%s\n' "$HEADER" | grep -Eq '^ *Flags:[[:space:]]+0x05000000, Version5 EABI'
size=$(wc -c < "$OUTPUT/fbneo_3ds.elf")
test "$size" -lt $((16 * 1024 * 1024))
"$ROOT/core-runtime/tests/verify-fbneo-artifact.sh" \
    "$OUTPUT/runtime.a" "$OUTPUT/fbneo_3ds.elf" "$OUTPUT/SOURCE.txt" "${#OBJECTS[@]}"
printf '%s\n' "FBNeo 3DS launcher completed: $size bytes"
