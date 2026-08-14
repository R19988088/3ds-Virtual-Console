#!/bin/bash
set -u

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
SOURCE="${FBNEO_SOURCE:-$ROOT/work/FBNeo}"
BUILD="${FBNEO_BUILD:-$ROOT/.core-build/cyclone-diagnostic}"
OUTPUT="${CYCLONE_DIAGNOSTIC_OUTPUT:-$ROOT/core-runtime/dist/cyclone-diagnostic}"
EXPECTED_COMMIT="${FBNEO_COMMIT:-2fcb2628fbfd529806e75f3559a9d82758c8a5cc}"
DEVKITARM_ROOT="${DEVKITARM:-/opt/devkitpro/devkitARM}"
CC="$DEVKITARM_ROOT/bin/arm-none-eabi-gcc"
AS="$DEVKITARM_ROOT/bin/arm-none-eabi-as"
AR="$DEVKITARM_ROOT/bin/arm-none-eabi-ar"
LIBRETRO="$BUILD/src/burner/libretro"
STATUS="$OUTPUT/status.txt"

mkdir -p "$OUTPUT"
: > "$STATUS"

record() {
    printf '%s=%s\n' "$1" "$2" >> "$STATUS"
}

fail() {
    record result failed
    printf '%s\n' "$1" >&2
    exit 1
}

record source "$SOURCE"
record expected_commit "$EXPECTED_COMMIT"
record devkitarm "$DEVKITARM_ROOT"

if [ ! -d "$SOURCE/.git" ]; then
    fail "missing FBNeo git checkout: $SOURCE"
fi

actual_commit="$(git -C "$SOURCE" rev-parse HEAD 2>/dev/null || true)"
record actual_commit "$actual_commit"
if [ "$actual_commit" != "$EXPECTED_COMMIT" ]; then
    fail "FBNeo commit mismatch: expected $EXPECTED_COMMIT, got ${actual_commit:-unknown}"
fi

for tool in "$CC" "$AS" "$AR"; do
    if [ ! -x "$tool" ]; then
        fail "missing devkitARM tool: $tool"
    fi
done

{
    printf 'source=%s\n' "$SOURCE"
    printf 'source_commit=%s\n' "$actual_commit"
    printf 'devkitarm=%s\n' "$DEVKITARM_ROOT"
    printf 'image=%s\n' "${DEVKITARM_IMAGE:-unknown}"
    printf 'image_digest=%s\n' "${DEVKITARM_IMAGE_DIGEST:-unknown}"
    printf '\n[environment]\n'
    uname -a 2>&1 || true
    printf '\n[gcc]\n'
    "$CC" --version 2>&1 || true
    printf '\n[as]\n'
    "$AS" --version 2>&1 || true
    printf '\n[ar]\n'
    "$AR" --version 2>&1 || true
    printf '\n[make]\n'
    make --version 2>&1 | head -4 || true
} > "$OUTPUT/toolchain.txt"

rm -rf "$BUILD"
mkdir -p "$BUILD"
git config --global --add safe.directory "$ROOT"
git config --global --add safe.directory "$SOURCE"
git config --global --add safe.directory "$BUILD"
if ! git -C "$SOURCE" archive --format=tar HEAD | tar -xf - -C "$BUILD"; then
    fail "failed to export pinned FBNeo source"
fi

make_args=(
    platform=ctr
    SUBSET=all
    REGEN_HEADERS=1
    INCLUDE_CHD_SUPPORT=0
    SPLIT_UP_LINK=1
)

make -C "$LIBRETRO" -f Makefile clean "${make_args[@]}" > "$OUTPUT/clean.stdout" 2> "$OUTPUT/clean.stderr" || true
if ! env CFLAGS='-DIOAPI_NO_64' CXXFLAGS='-include wchar.h' \
    make -C "$LIBRETRO" -f Makefile "${make_args[@]}" generate-files \
    > "$OUTPUT/generate.stdout" 2> "$OUTPUT/generate.stderr"; then
    record generate_files failed
    fail "FBNeo header generation failed; see generate.stderr"
fi
record generate_files passed

dryrun="$OUTPUT/make-dry-run.txt"
if ! env CFLAGS='-DIOAPI_NO_64' CXXFLAGS='-include wchar.h' \
    make -C "$LIBRETRO" -f Makefile -f "$ROOT/core-runtime/scripts/fbneo-no-archive.mk" \
    --output-sync=target -j1 -n "${make_args[@]}" fbneo_objects \
    > "$dryrun" 2> "$OUTPUT/make-dry-run.stderr"; then
    record make_dry_run failed
    fail "Make dry-run failed; see make-dry-run.stderr"
fi

cyclone_line="$(grep -E 'arm-none-eabi-gcc([^ ]*)?.*cpu/cyclone/Cyclone\.S' "$dryrun" | head -1 || true)"
if [ -z "$cyclone_line" ]; then
    record cyclone_command missing
    fail "Make dry-run did not expose the Cyclone.S compile command"
fi
printf '%s\n' "$cyclone_line" > "$OUTPUT/command.txt"

run_driver() {
    (
        cd "$LIBRETRO"
        /bin/sh -c "$cyclone_line"
    ) > "$OUTPUT/driver.stdout" 2> "$OUTPUT/driver.stderr"
}

if run_driver; then
    record gcc_driver passed
else
    record gcc_driver failed
fi

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
"$AS" $AS_FLAGS "$PREPROCESSED" -o "$OUTPUT/Cyclone.as.o" \
    > "$OUTPUT/as.stdout" 2> "$OUTPUT/as.stderr"
as_code=$?
record direct_as "$as_code"

find "$BUILD" "$OUTPUT" -maxdepth 8 -type f -name '*Cyclone*.o' -print 2>/dev/null | sort > "$OUTPUT/files.txt"
record result collected
printf '%s\n' "diagnostic files: $OUTPUT"
exit 0
