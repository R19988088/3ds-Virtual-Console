#!/bin/bash
set -u

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
SOURCE="${FBNEO_SOURCE:-$ROOT/work/FBNeo}"
BUILD="${FBNEO_BUILD:-$ROOT/.core-build/full-objects}"
OUTPUT="${FBNEO_FULL_OBJECT_OUTPUT:-$ROOT/core-runtime/dist/full-objects}"
EXPECTED_COMMIT="${FBNEO_COMMIT:-2fcb2628fbfd529806e75f3559a9d82758c8a5cc}"
BOUNDARY_RUN="${OBJECT_BOUNDARY_RUN:-}"
DEVKITARM_ROOT="${DEVKITARM:-/opt/devkitpro/devkitARM}"
LIBRETRO="$BUILD/src/burner/libretro"
STATUS="$OUTPUT/status.txt"

mkdir -p "$OUTPUT"
: > "$STATUS"
record() { printf '%s=%s\n' "$1" "$2" >> "$STATUS"; }
fail() { record result failed; printf '%s\n' "$1" >&2; exit 1; }

record source "$SOURCE"
record expected_commit "$EXPECTED_COMMIT"
record object_boundary_run "$BOUNDARY_RUN"
record devkitarm "$DEVKITARM_ROOT"
if [ -z "$BOUNDARY_RUN" ]; then fail 'OBJECT_BOUNDARY_RUN is required'; fi
if [ ! -d "$SOURCE/.git" ]; then fail "missing FBNeo git checkout: $SOURCE"; fi
actual_commit="$(git -C "$SOURCE" rev-parse HEAD 2>/dev/null || true)"
record actual_commit "$actual_commit"
if [ "$actual_commit" != "$EXPECTED_COMMIT" ]; then
    fail "FBNeo commit mismatch: expected $EXPECTED_COMMIT, got ${actual_commit:-unknown}"
fi
for tool in arm-none-eabi-gcc arm-none-eabi-ar arm-none-eabi-readelf; do
    if [ ! -x "$DEVKITARM_ROOT/bin/$tool" ]; then fail "missing devkitARM tool: $tool"; fi
done

git config --global --add safe.directory "$ROOT"
git config --global --add safe.directory "$SOURCE"
git config --global --add safe.directory "$BUILD"
rm -rf "$BUILD"
mkdir -p "$BUILD"
if ! git -C "$SOURCE" archive --format=tar HEAD | tar -xf - -C "$BUILD"; then
    fail 'failed to export pinned FBNeo source'
fi

make_args=(platform=ctr SUBSET=all REGEN_HEADERS=1 INCLUDE_CHD_SUPPORT=0 SPLIT_UP_LINK=1)
make -C "$LIBRETRO" -f Makefile clean "${make_args[@]}" > "$OUTPUT/clean.stdout" 2> "$OUTPUT/clean.stderr" || true
if ! env CFLAGS='-DIOAPI_NO_64' CXXFLAGS='-include wchar.h' \
    make -C "$LIBRETRO" -f Makefile "${make_args[@]}" generate-files \
    > "$OUTPUT/generate.stdout" 2> "$OUTPUT/generate.stderr"; then
    record generate_files failed
    fail 'FBNeo header generation failed; see generate.stderr'
fi
record generate_files passed

objects_line="$(env CFLAGS='-DIOAPI_NO_64' CXXFLAGS='-include wchar.h' \
    make -C "$LIBRETRO" -f Makefile -pn -n "${make_args[@]}" \
    2> "$OUTPUT/make-plan.stderr" | sed -n 's/^OBJS := //p' | head -1)"
if [ -z "$objects_line" ]; then fail 'OBJS was not emitted by make -pn'; fi
read -r -a objects <<< "$objects_line"
record object_count "${#objects[@]}"
printf '%s\n' "${objects[@]}" > "$OUTPUT/objects.txt"
if [ "${#objects[@]}" -lt 1000 ]; then fail "unexpected object count: ${#objects[@]}"; fi

(
    set -x
    env CFLAGS='-DIOAPI_NO_64' CXXFLAGS='-include wchar.h' \
        make -C "$LIBRETRO" -f Makefile -f "$ROOT/core-runtime/scripts/fbneo-no-archive.mk" \
        --output-sync=target -j1 "${make_args[@]}" fbneo_objects
) > "$OUTPUT/make.stdout" 2> "$OUTPUT/make.stderr"
make_code=$?
record make_objects "$make_code"

digest_file() {
    if command -v sha256sum >/dev/null 2>&1; then sha256sum "$1" | awk '{print $1}';
    else shasum -a 256 "$1" | awk '{print $1}'; fi
}
: > "$OUTPUT/files.txt"
missing=0
for object in "${objects[@]}"; do
    file="$LIBRETRO/$object"
    if [ -s "$file" ]; then
        printf '%s size=%s digest=%s\n' "$object" "$(wc -c < "$file" | tr -d ' ')" "$(digest_file "$file")" >> "$OUTPUT/files.txt"
    else
        printf '%s missing\n' "$object" >> "$OUTPUT/files.txt"
        missing=$((missing + 1))
    fi
done
record missing_objects "$missing"
if [ -s "$BUILD/src/cpu/cyclone/Cyclone.o" ]; then
    "$DEVKITARM_ROOT/bin/arm-none-eabi-readelf" -h "$BUILD/src/cpu/cyclone/Cyclone.o" > "$OUTPUT/Cyclone.readelf.txt" 2> "$OUTPUT/Cyclone.readelf.stderr" || true
fi
if [ "$make_code" -eq 0 ] && [ "$missing" -eq 0 ]; then record result passed; else record result failed; fi
printf '%s\n' "full-object evidence: $OUTPUT"
exit "$([ "$make_code" -eq 0 ] && [ "$missing" -eq 0 ]; echo $?)"
