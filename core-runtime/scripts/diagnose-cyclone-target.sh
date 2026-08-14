#!/bin/bash
set -u

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
SOURCE="${FBNEO_SOURCE:-$ROOT/work/FBNeo}"
BUILD="${FBNEO_BUILD:-$ROOT/.core-build/cyclone-target}"
OUTPUT="${CYCLONE_TARGET_OUTPUT:-$ROOT/core-runtime/dist/cyclone-target}"
EXPECTED_COMMIT="${FBNEO_COMMIT:-2fcb2628fbfd529806e75f3559a9d82758c8a5cc}"
DEVKITARM_ROOT="${DEVKITARM:-/opt/devkitpro/devkitARM}"
CC="$DEVKITARM_ROOT/bin/arm-none-eabi-gcc"
AS="$DEVKITARM_ROOT/bin/arm-none-eabi-as"
AR="$DEVKITARM_ROOT/bin/arm-none-eabi-ar"
READELF="$DEVKITARM_ROOT/bin/arm-none-eabi-readelf"
LIBRETRO="$BUILD/src/burner/libretro"
TARGET='../../cpu/cyclone/Cyclone.o'
STATUS="$OUTPUT/status.txt"

mkdir -p "$OUTPUT"
: > "$STATUS"

record() { printf '%s=%s\n' "$1" "$2" >> "$STATUS"; }
fail() {
    record result failed
    printf '%s\n' "$1" >&2
    exit 1
}

record source "$SOURCE"
record expected_commit "$EXPECTED_COMMIT"
record devkitarm "$DEVKITARM_ROOT"
record target "$TARGET"
if [ ! -d "$SOURCE/.git" ]; then fail "missing FBNeo git checkout: $SOURCE"; fi
actual_commit="$(git -C "$SOURCE" rev-parse HEAD 2>/dev/null || true)"
record actual_commit "$actual_commit"
if [ "$actual_commit" != "$EXPECTED_COMMIT" ]; then
    fail "FBNeo commit mismatch: expected $EXPECTED_COMMIT, got ${actual_commit:-unknown}"
fi
for tool in "$CC" "$AS" "$AR" "$READELF"; do
    if [ ! -x "$tool" ]; then fail "missing devkitARM tool: $tool"; fi
done

{
    printf 'source=%s\nsource_commit=%s\ndevkitarm=%s\n' "$SOURCE" "$actual_commit" "$DEVKITARM_ROOT"
    printf 'image=%s\nimage_digest=%s\n' "${DEVKITARM_IMAGE:-unknown}" "${DEVKITARM_IMAGE_DIGEST:-unknown}"
    printf '\n[uname]\n'; uname -a 2>&1 || true
    printf '\n[ulimit]\n'; ulimit -a 2>&1 || true
    printf '\n[df]\n'; df -h 2>&1 || true
    printf '\n[meminfo]\n'
    if [ -r /proc/meminfo ]; then sed -n '1,40p' /proc/meminfo; else printf '%s\n' '/proc/meminfo unavailable'; fi
    printf '\n[gcc]\n'; "$CC" --version 2>&1 || true
    printf '\n[as]\n'; "$AS" --version 2>&1 || true
    printf '\n[ar]\n'; "$AR" --version 2>&1 || true
    printf '\n[readelf]\n'; "$READELF" --version 2>&1 || true
    printf '\n[make]\n'; make --version 2>&1 | head -4 || true
} > "$OUTPUT/resource.txt"

rm -rf "$BUILD"
mkdir -p "$BUILD"
git config --global --add safe.directory "$ROOT"
git config --global --add safe.directory "$SOURCE"
git config --global --add safe.directory "$BUILD"
if ! git -C "$SOURCE" archive --format=tar HEAD | tar -xf - -C "$BUILD"; then
    fail "failed to export pinned FBNeo source"
fi

make_args=(platform=ctr SUBSET=all REGEN_HEADERS=1 INCLUDE_CHD_SUPPORT=0 SPLIT_UP_LINK=1)
make -C "$LIBRETRO" -f Makefile clean "${make_args[@]}" > "$OUTPUT/clean.stdout" 2> "$OUTPUT/clean.stderr" || true
if ! env CFLAGS='-DIOAPI_NO_64' CXXFLAGS='-include wchar.h' \
    make -C "$LIBRETRO" -f Makefile "${make_args[@]}" generate-files \
    > "$OUTPUT/generate.stdout" 2> "$OUTPUT/generate.stderr"; then
    record generate_files failed
    fail "FBNeo header generation failed; see generate.stderr"
fi
record generate_files passed

dryrun="$OUTPUT/make-dry-run.txt"
env CFLAGS='-DIOAPI_NO_64' CXXFLAGS='-include wchar.h' \
    make -C "$LIBRETRO" -f Makefile -f "$ROOT/core-runtime/scripts/fbneo-no-archive.mk" \
    --output-sync=target -B -j1 -n "${make_args[@]}" "$TARGET" \
    > "$dryrun" 2> "$OUTPUT/make-dry-run.stderr"
dryrun_code=$?
record make_dry_run "$dryrun_code"
cyclone_line="$(grep -E 'arm-none-eabi-gcc([^ ]*)?.*cpu/cyclone/Cyclone\.S' "$dryrun" | head -1 || true)"
if [ -z "$cyclone_line" ]; then
    record cyclone_command missing
    record result collected
    printf '%s\n' "diagnostic files: $OUTPUT"
    exit 0
fi
printf '%s\n' "$cyclone_line" > "$OUTPUT/command.txt"

(
    set -x
    env CFLAGS='-DIOAPI_NO_64' CXXFLAGS='-include wchar.h' \
        make -C "$LIBRETRO" -f Makefile -f "$ROOT/core-runtime/scripts/fbneo-no-archive.mk" \
        --output-sync=target -B -j1 "${make_args[@]}" "$TARGET"
) > "$OUTPUT/make.stdout" 2> "$OUTPUT/make.stderr"
make_code=$?
record make_target "$make_code"

(
    cd "$LIBRETRO"
    /bin/sh -c "$cyclone_line"
) > "$OUTPUT/driver.stdout" 2> "$OUTPUT/driver.stderr"
driver_code=$?
record gcc_driver "$driver_code"

PREPROCESSED="$OUTPUT/preprocessed.s"
preprocess_line="$(printf '%s\n' "$cyclone_line" | sed -E "s|[[:space:]]-c[[:space:]]| -E -x assembler-with-cpp |; s|[[:space:]]-o[[:space:]]+[^[:space:]]+| -o $PREPROCESSED|")"
printf '%s\n' "$preprocess_line" > "$OUTPUT/preprocess-command.txt"
(
    cd "$LIBRETRO"
    /bin/sh -c "$preprocess_line"
) > "$OUTPUT/preprocess.stdout" 2> "$OUTPUT/preprocess.stderr"
preprocess_code=$?
record preprocessor "$preprocess_code"

AS_FLAGS="${CYCLONE_AS_FLAGS:--march=armv6k}"
printf '%s\n' "$AS $AS_FLAGS $PREPROCESSED -o $OUTPUT/Cyclone.as.o" > "$OUTPUT/as-command.txt"
"$AS" $AS_FLAGS "$PREPROCESSED" -o "$OUTPUT/Cyclone.as.o" > "$OUTPUT/as.stdout" 2> "$OUTPUT/as.stderr"
as_code=$?
record direct_as "$as_code"

digest_file() {
    if command -v sha256sum >/dev/null 2>&1; then sha256sum "$1" | awk '{print $1}';
    else shasum -a 256 "$1" | awk '{print $1}'; fi
}
record_file() {
    local name="$1" file="$2"
    if [ -s "$file" ]; then
        printf '%s size=%s digest=%s\n' "$name" "$(wc -c < "$file" | tr -d ' ')" "$(digest_file "$file")" >> "$OUTPUT/files.txt"
    else
        printf '%s missing\n' "$name" >> "$OUTPUT/files.txt"
    fi
}
: > "$OUTPUT/files.txt"
record_file make_object "$BUILD/src/cpu/cyclone/Cyclone.o"
record_file direct_as_object "$OUTPUT/Cyclone.as.o"
record_file preprocessed "$PREPROCESSED"
if [ -s "$BUILD/src/cpu/cyclone/Cyclone.o" ]; then
    "$READELF" -h "$BUILD/src/cpu/cyclone/Cyclone.o" > "$OUTPUT/Cyclone.readelf.txt" 2> "$OUTPUT/Cyclone.readelf.stderr" || true
fi
record result collected
printf '%s\n' "diagnostic files: $OUTPUT"
exit 0
