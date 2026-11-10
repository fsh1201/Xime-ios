#!/usr/bin/env bash
#
# 构建 RimeBridgeC + librime 静态库的 iOS XCFramework。
#
# 这是第二阶段（接入 librime）使用的脚本，最小骨架不需要运行。
# 需要在 macOS + Xcode 上执行；Linux 只能生成工程文件，不能编译 iOS。
#
# 前置条件：
#   1. git submodule update --init --recursive
#   2. 已准备 iOS 版 librime 静态库（arm64 device + arm64/x86_64 simulator）
#   3. cmake、xcodebuild、libtool 可用
#
# 用法：
#   export RIME_LIBS_DEVICE="/path/librime.a;/path/libyaml-cpp.a;..."
#   export RIME_LIBS_SIMULATOR="/path/librime.a;/path/libyaml-cpp.a;..."
#   ./ios/scripts/build-rime-ios.sh
#
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
RIME_ROOT="${RIME_ROOT:-$ROOT/app/src/main/jni/librime}"
IOS_CMAKE_DIR="${IOS_CMAKE_DIR:-$ROOT/ios/.tools/ios-cmake}"
BUILD_ROOT="${BUILD_ROOT:-$ROOT/ios/.build}"
DEPLOYMENT_TARGET="${DEPLOYMENT_TARGET:-16.0}"
OUTPUT="$ROOT/ios/RimeBridge/build/XimeRime.xcframework"
HEADERS="$ROOT/ios/RimeBridge/include"

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

if [[ ! -f "$RIME_ROOT/include/rime_api.h" && ! -f "$RIME_ROOT/src/rime_api.h" ]]; then
    echo "错误：librime 子模块未初始化，请先执行：" >&2
    echo "  git submodule update --init --recursive" >&2
    exit 1
fi

if [[ -z "${RIME_LIBS_DEVICE:-}" || -z "${RIME_LIBS_SIMULATOR:-}" ]]; then
    cat >&2 <<'EOF'
错误：请先提供 iOS 版 librime 静态库列表。

  export RIME_LIBS_DEVICE="/path/to/device/librime.a;/path/to/device/libyaml-cpp.a;..."
  export RIME_LIBS_SIMULATOR="/path/to/sim/librime.a;/path/to/sim/libyaml-cpp.a;..."

librime 依赖 boost、yaml-cpp、leveldb、marisa、opencc、snappy、glog 等，
需要先为 iOS 编译这些依赖。可以参考 ghostflyby/librime-xcframework 的产物，
或者使用 ios-cmake 工具链自行构建。
EOF
    exit 2
fi

if [[ ! -f "$IOS_CMAKE_DIR/ios.toolchain.cmake" ]]; then
    echo "==> 获取 ios-cmake 工具链"
    mkdir -p "$(dirname "$IOS_CMAKE_DIR")"
    git clone --depth 1 https://github.com/leetal/ios-cmake.git "$IOS_CMAKE_DIR"
fi

build_bridge() {
    local platform="$1"
    local libraries="$2"
    local build_dir="$BUILD_ROOT/$platform"

    echo "==> 构建 RimeBridgeC ($platform)"
    cmake \
        -S "$ROOT/ios/RimeBridge" \
        -B "$build_dir" \
        -DCMAKE_TOOLCHAIN_FILE="$IOS_CMAKE_DIR/ios.toolchain.cmake" \
        -DPLATFORM="$platform" \
        -DDEPLOYMENT_TARGET="$DEPLOYMENT_TARGET" \
        -DCMAKE_BUILD_TYPE=Release \
        -DRIME_ROOT="$RIME_ROOT" \
        -DRIME_LIBRARIES="$libraries"
    cmake --build "$build_dir" --config Release
}

build_bridge "OS64" "$RIME_LIBS_DEVICE"
build_bridge "SIMULATORARM64" "$RIME_LIBS_SIMULATOR"

echo "==> 合并静态库"
combine_libraries() {
    local platform="$1"
    local libraries="$2"
    local build_dir="$BUILD_ROOT/$platform"
    local bridge_lib="$build_dir/libXimeRimeBridge.a"
    local output="$build_dir/libXimeRime.a"

    if [[ ! -f "$bridge_lib" ]]; then
        echo "错误：未找到 $bridge_lib" >&2
        exit 1
    fi

    IFS=';' read -r -a lib_array <<< "$libraries"
    libtool -static -o "$output" "$bridge_lib" "${lib_array[@]}" >&2
    echo "$output"
}

DEVICE_LIB="$(combine_libraries "OS64" "$RIME_LIBS_DEVICE")"
SIM_LIB="$(combine_libraries "SIMULATORARM64" "$RIME_LIBS_SIMULATOR")"

echo "==> 生成 XCFramework"
rm -rf "$OUTPUT"
mkdir -p "$(dirname "$OUTPUT")"

# XCFramework 需要 headers 目录；module.modulemap 让 Swift 可以 import RimeBridgeC。
HEADERS_STAGE="$BUILD_ROOT/headers"
rm -rf "$HEADERS_STAGE"
mkdir -p "$HEADERS_STAGE/include"
cp "$HEADERS/RimeBridgeC.h" "$HEADERS_STAGE/include/"
cp "$ROOT/ios/RimeBridge/module.modulemap" "$HEADERS_STAGE/"

xcodebuild -create-xcframework \
    -library "$DEVICE_LIB" -headers "$HEADERS_STAGE" \
    -library "$SIM_LIB" -headers "$HEADERS_STAGE" \
    -output "$OUTPUT"

echo
echo "完成：$OUTPUT"
echo "下一步：在 Xcode 中把 XimeRime.xcframework 加入两个 target，"
echo "Swift 侧会通过 canImport(RimeBridgeC) 自动启用 LibrimeRimeEngine。"
