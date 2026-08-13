#!/bin/sh
set -eu

ROOT=$(CDPATH= cd -- "$(dirname "$0")/../.." && pwd)
SCRIPT="$ROOT/core-runtime/scripts/build-fbneo.sh"
WORKFLOW="$ROOT/.github/workflows/build-fbneo.yml"
test -x "$SCRIPT"
grep -q 'libretro/FBNeo' "$WORKFLOW"
grep -q 'platform=ctr' "$SCRIPT"
grep -q 'SUBSET=all' "$SCRIPT"
grep -q 'IOAPI_NO_64' "$SCRIPT"
grep -q 'INCLUDE_CHD_SUPPORT=0' "$SCRIPT"
grep -q -- '-include wchar.h' "$SCRIPT"
grep -q "CFLAGS='-DIOAPI_NO_64'" "$SCRIPT"
grep -q "CXXFLAGS='-include wchar.h'" "$SCRIPT"
grep -q 'fbneo_all_libretro_ctr.a' "$SCRIPT"
grep -q 'LIBRETRO=fbneo' "$SCRIPT"
grep -q 'LOAD_WITHOUT_CORE_INFO=1' "$SCRIPT"
grep -q -- '--strip-debug' "$SCRIPT"
grep -q 'arm-none-eabi-readelf' "$SCRIPT"
grep -q 'Class:' "$SCRIPT"
grep -q '16 \* 1024 \* 1024' "$SCRIPT"
grep -q '2fcb2628fbfd529806e75f3559a9d82758c8a5cc' "$SCRIPT"
grep -q 'f3d2eedbfc58908d2c60cec9ed40e95c653cf261' "$WORKFLOW"
printf '%s\n' 'FBNeo 3DS build contract passed.'
