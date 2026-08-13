#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
SOURCE="${FBNEO_SOURCE:-$ROOT/work/FBNeo}"
CORE="${FBNEO_CORE:-$ROOT/.core-build/fbneo/src/burner/libretro/fbneo_all_libretro_ctr.a}"
OUTPUT="${FBNEO_LAUNCHER_OUTPUT:-$ROOT/core-runtime/dist/fbneo/fbneo_3ds.elf}"
DEVKITARM_ROOT="${DEVKITARM:-/opt/devkitpro/devkitARM}"
DEVKITPRO_ROOT="${DEVKITPRO:-/opt/devkitpro}"
CC="$DEVKITARM_ROOT/bin/arm-none-eabi-gcc"
CXX="$DEVKITARM_ROOT/bin/arm-none-eabi-g++"

test -x "$CC"
test -x "$CXX"
test -s "$CORE"
test -f "$ROOT/core-runtime/launcher-3ds/fbneo_launcher.c"

BUILD="${FBNEO_LAUNCHER_BUILD:-$ROOT/.core-build/fbneo-launcher}"
rm -rf "$BUILD"
mkdir -p "$BUILD" "$(dirname "$OUTPUT")"

ARCH='-march=armv6k -mtune=mpcore -mfloat-abi=hard -marm -mfpu=vfp -mtp=soft'
COMMON="-D__3DS__ -D__LIBRETRO__ -ffunction-sections -fdata-sections -fomit-frame-pointer -O3"
INCLUDES="-I$SOURCE/src/burner/libretro/libretro-common/include -I$SOURCE/src/burner/libretro -I$SOURCE/src -I$DEVKITPRO_ROOT/libctru/include"

COMMON_SOURCES=(
    file/file_path.c
    file/file_path_io.c
    file/retro_dirent.c
    encodings/encoding_utf.c
    compat/compat_posix_string.c
    compat/compat_strcasestr.c
    compat/compat_strl.c
    compat/compat_strldup.c
    compat/fopen_utf8.c
    string/stdstring.c
    streams/file_stream.c
    streams/file_stream_transforms.c
    features/features_cpu.c
    file/config_file.c
    file/config_file_userdata.c
    lists/string_list.c
    memmap/memalign.c
    time/rtime.c
    vfs/vfs_implementation.c
)

"$CC" $ARCH $COMMON $INCLUDES -std=gnu11 -c \
    "$ROOT/core-runtime/launcher-3ds/fbneo_launcher.c" -o "$BUILD/fbneo_launcher.o"

COMMON_OBJECTS=()
for source_file in "${COMMON_SOURCES[@]}"; do
    object_file="$BUILD/$(basename "${source_file%.c}").o"
    "$CC" $ARCH $COMMON $INCLUDES -std=gnu11 -c \
        "$SOURCE/src/burner/libretro/libretro-common/$source_file" -o "$object_file"
    COMMON_OBJECTS+=("$object_file")
done

"$CXX" $ARCH -specs=3dsx.specs -Wl,--gc-sections \
    "$BUILD/fbneo_launcher.o" "${COMMON_OBJECTS[@]}" "$CORE" \
    -L"$DEVKITPRO_ROOT/libctru/lib" -lctru -lm -o "$OUTPUT"

"$DEVKITARM_ROOT/bin/arm-none-eabi-strip" --strip-debug "$OUTPUT"
test -s "$OUTPUT"
HEADER=$("$DEVKITARM_ROOT/bin/arm-none-eabi-readelf" -h "$OUTPUT")
printf '%s\n' "$HEADER" | grep -Eq '^ *Class:[[:space:]]+ELF32$'
printf '%s\n' "$HEADER" | grep -Eq '^ *Data:[[:space:]]+2.s complement, little endian$'
printf '%s\n' "$HEADER" | grep -Eq '^ *Machine:[[:space:]]+ARM$'
printf '%s\n' "$HEADER" | grep -Eq '^ *Flags:[[:space:]]+0x05000000, Version5 EABI'
printf '%s\n' "Built self-hosted FBNeo 3DS launcher: $OUTPUT"
