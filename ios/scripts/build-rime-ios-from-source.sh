#!/usr/bin/env bash
#
# 在 macOS 上从源码交叉编译 librime + 依赖，生成 iOS device (arm64) 的
# ios/RimeBridge/build/XimeRime.xcframework。
#
# 前置：
#   git submodule update --init --recursive \
#     app/src/main/jni/librime app/src/main/jni/snappy app/src/main/assets/rime
#
# 输出只包含真机 slice；模拟器构建需要另外编译 SIMULATORARM64。
#
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
JNI="$ROOT/app/src/main/jni"
BASE="$ROOT/ios/.build/rime-ios"
SRC="$BASE/src"
BUILD="$BASE/build"
TOOLCHAIN_DIR="$ROOT/ios/.tools/ios-cmake"
TOOLCHAIN="$TOOLCHAIN_DIR/ios.toolchain.cmake"
BRIDGE="$ROOT/ios/RimeBridge"
DEPLOYMENT_TARGET="${DEPLOYMENT_TARGET:-16.0}"
OUTPUT="$BRIDGE/build/XimeRime.xcframework"

if [[ "$(uname -s)" != "Darwin" ]]; then
    echo "错误：iOS 产物必须在 macOS + Xcode 上构建。" >&2
    exit 1
fi

for tool in cmake xcodebuild libtool git; do
    if ! command -v "$tool" >/dev/null 2>&1; then
        echo "错误：找不到 $tool" >&2
        exit 1
    fi
done

if [[ ! -f "$JNI/librime/src/rime_api.h" ]]; then
    echo "错误：librime 子模块未初始化。" >&2
    exit 1
fi
if [[ ! -d "$JNI/snappy" ]]; then
    echo "错误：snappy 子模块未初始化。" >&2
    exit 1
fi

if [[ ! -f "$TOOLCHAIN" ]]; then
    echo "==> 获取 ios-cmake 工具链"
    mkdir -p "$(dirname "$TOOLCHAIN_DIR")"
    git clone --depth 1 https://github.com/leetal/ios-cmake.git "$TOOLCHAIN_DIR"
fi

echo "==> 准备构建目录"
mkdir -p "$SRC/cmake" "$BUILD"
for module in "$JNI"/cmake/*.cmake; do
    cp "$module" "$SRC/cmake/"
done
# OpenccWorkarounds 的 CMAKE_SOURCE_DIR 需要指向 app/src/main/jni。
sed "s|\${CMAKE_SOURCE_DIR}|$JNI|g" \
    "$JNI/cmake/OpenccWorkarounds.cmake" > "$SRC/cmake/OpenccWorkarounds.cmake"
cp "$ROOT/ios/RimeBridge/ios/CMakeLists.txt" "$SRC/CMakeLists.txt"

# 交叉编译时不能运行 iOS 版 opencc_dict；rime 数据里已有预生成的 .ocd2。
OPENCC_CMAKE="$JNI/librime/deps/opencc/CMakeLists.txt"
if [[ -f "$OPENCC_CMAKE.xime.bak" ]]; then
    mv -f "$OPENCC_CMAKE.xime.bak" "$OPENCC_CMAKE"
fi
if grep -q '^add_subdirectory(data)$' "$OPENCC_CMAKE"; then
    echo "==> 跳过 OpenCC 词典生成（使用 assets 中预生成的 ocd2）"
    cp "$OPENCC_CMAKE" "$OPENCC_CMAKE.xime.bak"
    sed -i '' 's|^add_subdirectory(data)$|# XIME_SKIP_OPENCC_DATA\n# add_subdirectory(data)|' "$OPENCC_CMAKE"
    trap 'mv -f "$OPENCC_CMAKE.xime.bak" "$OPENCC_CMAKE"' EXIT
fi

# Boost.cmake 的相对路径以 CMake 进程工作目录为准。
if [[ ! -d "$SRC/boost" && -d "$SRC/boost-1.89.0" ]]; then
    echo "==> 清理上次中断的 Boost 解压目录"
    rm -rf "$SRC/boost-1.89.0"
fi

cd "$SRC"
echo "==> 配置 iOS arm64"
cmake -S . -B "$BUILD" \
    -DCMAKE_TOOLCHAIN_FILE="$TOOLCHAIN" \
    -DPLATFORM=OS64 \
    -DARCHS=arm64 \
    -DDEPLOYMENT_TARGET="$DEPLOYMENT_TARGET" \
    -DENABLE_BITCODE=OFF \
    -DCMAKE_BUILD_TYPE=Release \
    -DJNI_DIR="$JNI" \
    -DBRIDGE_DIR="$BRIDGE"

echo "==> 编译"
cmake --build "$BUILD" -j"$(sysctl -n hw.ncpu)"

echo "==> 合并静态库"
PACKAGE="$BASE/package"
rm -rf "$PACKAGE"
mkdir -p "$PACKAGE/headers/include"

LIBS=()
while IFS= read -r lib; do
    LIBS+=("$lib")
done < <(find "$BUILD" -name '*.a' \
    ! -name '*gtest*' ! -name '*gmock*' ! -name '*benchmark*' \
    ! -name 'libXimeRime.a' | sort)

if [[ ${#LIBS[@]} -eq 0 ]]; then
    echo "错误：没有找到任何静态库。" >&2
    exit 1
fi

libtool -static -o "$PACKAGE/libXimeRime.a" "${LIBS[@]}"

cp "$BRIDGE/include/RimeBridgeC.h" "$PACKAGE/headers/include/"
cp "$BRIDGE/module.modulemap" "$PACKAGE/headers/"

echo "==> 生成 XCFramework"
rm -rf "$OUTPUT"
mkdir -p "$(dirname "$OUTPUT")"
xcodebuild -create-xcframework \
    -library "$PACKAGE/libXimeRime.a" \
    -headers "$PACKAGE/headers" \
    -output "$OUTPUT"

echo
echo "完成：$OUTPUT"
echo "下一步：./ios/scripts/enable-rime.sh && cd ios && xcodegen generate"
