#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
WORK="${TMPDIR:-/tmp}/vcoven-3dstool-arm64"
CMAKE="$(brew --prefix cmake)/bin/cmake"
OPENSSL="$(brew --prefix openssl@3)"

test "$(uname -m)" = arm64
rm -rf "$WORK"
git clone --depth 1 --branch v1.2.6 https://github.com/dnasdw/3dstool.git "$WORK"

python3 - "$WORK/src/CMakeLists.txt" <<'PY'
from pathlib import Path
import sys
p = Path(sys.argv[1])
s = p.read_text()
s = s.replace(
    "  target_link_libraries(3dstool curl ssl crypto)",
    '  target_link_libraries(3dstool curl "${OPENSSL_STATIC_ROOT}/lib/libssl.a" "${OPENSSL_STATIC_ROOT}/lib/libcrypto.a")',
)
p.write_text(s)
PY

"$CMAKE" -S "$WORK" -B "$WORK/build" \
  -DCMAKE_BUILD_TYPE=MinSizeRel \
  -DCMAKE_OSX_ARCHITECTURES=arm64 \
  -DCMAKE_POLICY_VERSION_MINIMUM=3.5 \
  -DUSE_DEP=OFF \
  -DOPENSSL_STATIC_ROOT="$OPENSSL" \
  -DCMAKE_C_FLAGS="-I$OPENSSL/include" \
  -DCMAKE_CXX_FLAGS="-I$OPENSSL/include"
"$CMAKE" --build "$WORK/build" -j "$(sysctl -n hw.ncpu)"

cp "$WORK/bin/MinSizeRel/3dstool" "$ROOT/Sources/VcovenApp/Resources/Tools/3dstool"
strip -x "$ROOT/Sources/VcovenApp/Resources/Tools/3dstool"
file "$ROOT/Sources/VcovenApp/Resources/Tools/3dstool"
otool -L "$ROOT/Sources/VcovenApp/Resources/Tools/3dstool"
