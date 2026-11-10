#!/usr/bin/env bash
#
# 在 Linux 上从源码构建 librime + RimeBridgeC，并运行候选链路验证程序。
# 只用于开发验证，不生成 iOS 产物；首次运行会下载 Boost 1.89。
#
# 用法：
#   ./ios/scripts/verify-rime-linux.sh [schema]
#
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
JNI="$ROOT/app/src/main/jni"
BASE="$ROOT/ios/.build/linux-verify"
SRC="$BASE/src"
BUILD="$BASE/build"
USER_DIR="$BASE/user"
SCHEMA="${1:-pinyin_simp}"

if [[ ! -f "$JNI/librime/src/rime_api.h" ]]; then
    echo "错误：librime 子模块未初始化，请先执行：" >&2
    echo "  git submodule update --init --recursive" >&2
    exit 1
fi

for tool in cmake g++ python3; do
    if ! command -v "$tool" >/dev/null 2>&1; then
        echo "错误：找不到 $tool" >&2
        exit 1
    fi
done

mkdir -p "$SRC/cmake"
for module in "$JNI"/cmake/*.cmake; do
    cp "$module" "$SRC/cmake/"
done
# OpenccWorkarounds 使用 CMAKE_SOURCE_DIR 定位 opencc 头文件；
# 在验证工程里需要指向 app/src/main/jni。
sed "s|\${CMAKE_SOURCE_DIR}|$JNI|g" \
    "$JNI/cmake/OpenccWorkarounds.cmake" > "$SRC/cmake/OpenccWorkarounds.cmake"

cp "$ROOT/ios/RimeBridge/tests/linux/CMakeLists.txt" "$SRC/CMakeLists.txt"

# Boost.cmake 的相对路径以 CMake 进程工作目录为准；
# 必须让 cwd 与 CMAKE_SOURCE_DIR 一致，否则下载和 add_subdirectory 会错位。
if [[ ! -d "$SRC/boost" && -d "$SRC/boost-1.89.0" ]]; then
    echo "==> 清理上次中断的 Boost 解压目录"
    rm -rf "$SRC/boost-1.89.0"
fi

cd "$SRC"
cmake -S . -B "$BUILD" \
    -DCMAKE_BUILD_TYPE=Release \
    -DJNI_DIR="$JNI" \
    -DBRIDGE_DIR="$ROOT/ios/RimeBridge" \
    -DRIME_TEST_SOURCE="$ROOT/ios/RimeBridge/tests/rime_bridge_test.cpp"

cmake --build "$BUILD" -j"$(nproc)"

rm -rf "$USER_DIR"
echo
echo "==> 运行验证（schema: $SCHEMA）"
"$BUILD/rime_bridge_test" "$ROOT/app/src/main/assets/rime" "$USER_DIR" "$SCHEMA"
