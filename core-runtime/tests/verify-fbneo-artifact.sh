#!/bin/bash
set -euo pipefail

ARCHIVE="${1:?usage: verify-fbneo-artifact.sh runtime.a launcher.elf [source.txt] [expected-object-count]}"
ELF="${2:?usage: verify-fbneo-artifact.sh runtime.a launcher.elf [source.txt] [expected-object-count]}"
SOURCE_FILE="${3:-}"
EXPECTED_OBJECT_COUNT="${4:-${FBNEO_EXPECTED_OBJECT_COUNT:-}}"
DEVKITARM_ROOT="${DEVKITARM:-/opt/devkitpro/devkitARM}"
AR="$DEVKITARM_ROOT/bin/arm-none-eabi-ar"
NM="$DEVKITARM_ROOT/bin/arm-none-eabi-nm"
READELF="$DEVKITARM_ROOT/bin/arm-none-eabi-readelf"

for tool in "$AR" "$NM" "$READELF"; do
    test -x "$tool"
done
test -s "$ARCHIVE"
test -s "$ELF"

members="$(mktemp)"
header="$(mktemp)"
symbols="$(mktemp)"
trap 'rm -f "$members" "$header" "$symbols"' EXIT

"$AR" t "$ARCHIVE" > "$members"
member_count="$(wc -l < "$members" | tr -d ' ')"
if [ -n "$EXPECTED_OBJECT_COUNT" ]; then
    test "$member_count" -eq "$EXPECTED_OBJECT_COUNT"
fi
for required in '../../burner/libretro/libretro.o' '../../burner/libretro/retro_common.o' '../../cpu/cyclone/Cyclone.o'; do
    grep -Fxq "$required" "$members"
done

"$NM" -g "$ARCHIVE" > "$symbols"
for symbol in retro_init retro_deinit retro_load_game retro_run retro_get_memory_data; do
    grep -Eq "[[:space:]]T[[:space:]]${symbol}$" "$symbols"
done

"$READELF" -h "$ELF" > "$header"
grep -Eq '^ *Class:[[:space:]]+ELF32$' "$header"
grep -Eq '^ *Data:[[:space:]]+2.s complement, little endian$' "$header"
grep -Eq '^ *Machine:[[:space:]]+ARM$' "$header"
grep -Eq '^ *Flags:[[:space:]]+0x05000000, Version5 EABI' "$header"
test "$(wc -c < "$ELF")" -lt $((16 * 1024 * 1024))

if [ -n "$SOURCE_FILE" ]; then
    test -s "$SOURCE_FILE"
    grep -Eq '^[0-9a-f]{40}[[:space:]]+FBNeo source$' "$SOURCE_FILE"
fi

printf '%s\n' "FBNeo artifact passed: members=$member_count elf_bytes=$(wc -c < "$ELF")"
