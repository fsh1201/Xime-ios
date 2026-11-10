#!/usr/bin/env bash
#
# 在 macOS 上原生编译 librime，并预生成 Rime 词典到
# app/src/main/assets/rime/build，供键盘扩展直接加载。
#
# 这样可以避免在键盘扩展里做全量部署（部署峰值内存约 200MB）。
#
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
JNI="$ROOT/app/src/main/jni"
BASE="$ROOT/ios/.build/rime-native"
SRC="$BASE/src"
BUILD="$BASE/build"
RIME_DATA="$ROOT/app/src/main/assets/rime"
BRIDGE="$ROOT/ios/RimeBridge"

if [[ "$(uname -s)" != "Darwin" ]]; then
    echo "错误：预生成词典需要在 macOS 上运行。" >&2
    exit 1
fi
if [[ ! -f "$JNI/librime/src/rime_api.h" ]]; then
    echo "错误：librime 子模块未初始化。" >&2
    exit 1
fi

echo "==> 准备原生构建目录"
mkdir -p "$SRC/cmake" "$BUILD"
for module in "$JNI"/cmake/*.cmake; do
    cp "$module" "$SRC/cmake/"
done
sed "s|\${CMAKE_SOURCE_DIR}|$JNI|g" \
    "$JNI/cmake/OpenccWorkarounds.cmake" > "$SRC/cmake/OpenccWorkarounds.cmake"
cp "$ROOT/ios/RimeBridge/ios/CMakeLists.txt" "$SRC/CMakeLists.txt"

OPENCC_CMAKE="$JNI/librime/deps/opencc/CMakeLists.txt"
if [[ -f "$OPENCC_CMAKE.xime.bak" ]]; then
    mv -f "$OPENCC_CMAKE.xime.bak" "$OPENCC_CMAKE"
fi
if grep -q '^add_subdirectory(data)$' "$OPENCC_CMAKE"; then
    echo "==> 跳过 OpenCC 词典生成（使用 rime assets 中预生成的 ocd2）"
    cp "$OPENCC_CMAKE" "$OPENCC_CMAKE.xime.bak"
    sed -i '' 's|^add_subdirectory(data)$|# XIME_SKIP_OPENCC_DATA\n# add_subdirectory(data)|' "$OPENCC_CMAKE"
    trap 'mv -f "$OPENCC_CMAKE.xime.bak" "$OPENCC_CMAKE"' EXIT
fi

if [[ ! -d "$SRC/boost" && -d "$SRC/boost-1.89.0" ]]; then
    rm -rf "$SRC/boost-1.89.0"
fi

cd "$SRC"
echo "==> 配置原生构建"
cmake -S . -B "$BUILD" \
    -DCMAKE_BUILD_TYPE=Release \
    -DJNI_DIR="$JNI" \
    -DBRIDGE_DIR="$BRIDGE" \
    -DBUILD_PREDEPLOY_TOOL=ON

echo "==> 编译 rime_predeploy"
cmake --build "$BUILD" --target rime_predeploy -j"$(sysctl -n hw.ncpu)"

echo "==> 预生成词典"
rm -rf "$BASE/user" "$RIME_DATA/build"
"$BUILD/rime_predeploy" "$RIME_DATA" "$BASE/user"

if [[ ! -d "$BASE/user/build" ]]; then
    echo "错误：没有生成 $BASE/user/build" >&2
    exit 1
fi

cp -a "$BASE/user/build" "$RIME_DATA/build"

if [[ ! -d "$RIME_DATA/build" ]]; then
    echo "错误：没有生成 $RIME_DATA/build" >&2
    exit 1
fi

echo "完成：$RIME_DATA/build"
du -sh "$RIME_DATA/build"
