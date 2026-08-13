#!/bin/sh
set -eu

ROOT=$(CDPATH= cd -- "$(dirname "$0")/../.." && pwd)
SOURCE=${FBA_SOURCE:-$ROOT/work/fbalpha2012}
BUILD=${FBA_BUILD:-$ROOT/.core-build/fbalpha2012}
OUTPUT=${FBA_OUTPUT:-$ROOT/core-runtime/dist/fba2012}
PATCH="$ROOT/core-runtime/patches/fba2012-ignore-rom-crc.patch"
EXPECTED_COMMIT=${FBA_COMMIT:-0ce31536bef3162fe7e69ff5f555334ec4913cef}
ARCH_FLAGS='-march=armv6k -mtune=mpcore -mfloat-abi=hard -marm -mfpu=vfp -mtp=soft'
FBA_FLAGS="-DFBA_IGNORE_ROM_CRC=1 -DARM11 -D_3DS $ARCH_FLAGS -Wall -mword-relocations -fomit-frame-pointer -ffast-math"

if [ ! -d "$SOURCE/.git" ]; then
    printf '%s\n' "FBA source checkout not found: $SOURCE" >&2
    exit 1
fi
if [ -z "${DEVKITARM:-}" ] || [ ! -x "$DEVKITARM/bin/arm-none-eabi-g++" ]; then
    printf '%s\n' 'DEVKITARM with arm-none-eabi-g++ is required for platform=ctr.' >&2
    exit 1
fi
if [ "$(git -C "$SOURCE" rev-parse HEAD)" != "$EXPECTED_COMMIT" ]; then
    printf '%s\n' "FBA source must be commit $EXPECTED_COMMIT (set FBA_COMMIT to override)." >&2
    exit 1
fi

rm -rf "$BUILD"
mkdir -p "$BUILD" "$OUTPUT"
git -C "$SOURCE" archive --format=tar HEAD | tar -xf - -C "$BUILD"

git -C "$BUILD" apply --whitespace=error "$PATCH"

make -C "$BUILD/svn-current/trunk" -f makefile.libretro clean \
    platform=ctr target=generic FBA_DEFINES="$FBA_FLAGS" \
    CFLAGS="$ARCH_FLAGS" CXXFLAGS="$ARCH_FLAGS" ASFLAGS="$ARCH_FLAGS"
make -C "$BUILD/svn-current/trunk" -f makefile.libretro -j"${JOBS:-$(getconf _NPROCESSORS_ONLN 2>/dev/null || printf 2)}" \
    platform=ctr target=generic FBA_DEFINES="$FBA_FLAGS" \
    CFLAGS="$ARCH_FLAGS" CXXFLAGS="$ARCH_FLAGS" ASFLAGS="$ARCH_FLAGS"

rm -rf "$OUTPUT"
mkdir -p "$OUTPUT"
cp "$BUILD/svn-current/trunk/fbalpha2012_libretro_ctr.a" "$OUTPUT/runtime.a"
cp "$PATCH" "$OUTPUT/fba2012-ignore-rom-crc.patch"
printf '%s\n' 'FBA 2012 build completed with CRC-ignore support.'
