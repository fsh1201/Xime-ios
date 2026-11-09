# 仅在 Linux 上验证 RimeBridgeC + librime 的候选链路。
# 由 ios/scripts/verify-rime-linux.sh 复制到 .build/linux-verify/src 后配置，
# 不参与 iOS / XcodeGen 构建。
cmake_minimum_required(VERSION 3.20)

project(xime_rime_bridge_test LANGUAGES C CXX)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_CXX_EXTENSIONS OFF)
set(BUILD_SHARED_LIBS OFF CACHE BOOL "" FORCE)
set(BUILD_TESTING OFF CACHE BOOL "" FORCE)

set(JNI_DIR "" CACHE PATH "app/src/main/jni")
set(BRIDGE_DIR "" CACHE PATH "ios/RimeBridge")
set(RIME_TEST_SOURCE "" CACHE FILEPATH "rime_bridge_test.cpp")

if(NOT JNI_DIR OR NOT BRIDGE_DIR OR NOT RIME_TEST_SOURCE)
    message(FATAL_ERROR "请通过 verify-rime-linux.sh 运行，或手动传入 JNI_DIR/BRIDGE_DIR/RIME_TEST_SOURCE")
endif()

set(LIBRIME "${JNI_DIR}/librime")
set(CMAKE_MODULE_PATH "${CMAKE_CURRENT_SOURCE_DIR}/cmake" ${CMAKE_MODULE_PATH})

# Boost 会下载/解压到 ${CMAKE_SOURCE_DIR}/boost。
include(Boost)

option(WITH_GFLAGS "Use gflags" OFF)
option(WITH_GTEST "Use googletest" OFF)
set(WITH_UNWIND "none" CACHE STRING "" FORCE)
add_subdirectory(${LIBRIME}/deps/glog glog-build)

set(Glog_FOUND TRUE CACHE BOOL "" FORCE)
set(Glog_INCLUDE_PATH "${LIBRIME}/deps/glog/src" CACHE PATH "" FORCE)
set(Glog_LIBRARY glog CACHE STRING "" FORCE)
set(Glog_STATIC TRUE CACHE BOOL "" FORCE)

option(YAML_CPP_BUILD_TOOLS "" OFF)
option(YAML_CPP_BUILD_TESTS "" OFF)
option(YAML_CPP_INSTALL "" OFF)
add_subdirectory(${LIBRIME}/deps/yaml-cpp yaml-cpp-build)

set(YamlCpp_FOUND TRUE CACHE BOOL "" FORCE)
set(YamlCpp_INCLUDE_PATH "${LIBRIME}/deps/yaml-cpp/include" CACHE PATH "" FORCE)
set(YamlCpp_LIBRARY yaml-cpp CACHE STRING "" FORCE)
set(YamlCpp_STATIC TRUE CACHE BOOL "" FORCE)
set(YamlCpp_NEW_API TRUE CACHE BOOL "" FORCE)

option(SNAPPY_BUILD_TESTS "" OFF)
option(SNAPPY_BUILD_BENCHMARKS "" OFF)
option(SNAPPY_INSTALL "" OFF)
add_subdirectory(${JNI_DIR}/snappy snappy-build)

set(HAVE_SNAPPY TRUE)
option(LEVELDB_BUILD_TESTS "" OFF)
option(LEVELDB_BUILD_BENCHMARKS "" OFF)
option(LEVELDB_INSTALL "" OFF)
add_subdirectory(${LIBRIME}/deps/leveldb leveldb-build)

set(LevelDb_FOUND TRUE CACHE BOOL "" FORCE)
set(LevelDb_INCLUDE_PATH "${LIBRIME}/deps/leveldb/include" CACHE PATH "" FORCE)
set(LevelDb_LIBRARY leveldb CACHE STRING "" FORCE)
set(LevelDb_STATIC TRUE CACHE BOOL "" FORCE)

set(ENABLE_TOOLS OFF CACHE BOOL "" FORCE)
add_subdirectory(${LIBRIME}/deps/marisa-trie marisa-build)

set(Marisa_FOUND TRUE CACHE BOOL "" FORCE)
set(Marisa_INCLUDE_PATH "${LIBRIME}/deps/marisa-trie/include" CACHE PATH "" FORCE)
set(Marisa_LIBRARY marisa CACHE STRING "" FORCE)
set(Marisa_STATIC TRUE CACHE BOOL "" FORCE)
set(LIBMARISA marisa)
option(USE_SYSTEM_MARISA "" ON)

add_subdirectory(${LIBRIME}/deps/opencc opencc-build)
include(OpenccWorkarounds)

set(Opencc_FOUND TRUE CACHE BOOL "" FORCE)
set(Opencc_INCLUDE_PATH "${LIBRIME}/deps/opencc/src" CACHE PATH "" FORCE)
set(Opencc_LIBRARY libopencc CACHE STRING "" FORCE)
set(Opencc_STATIC TRUE CACHE BOOL "" FORCE)

set(X11Keysym "${LIBRIME}/include")
include_directories("${X11Keysym}" "${CMAKE_BINARY_DIR}/include")

# Android 的 FindBoost 只覆盖依赖闭包内的 Boost 库；源码构建时补全所有头文件目录，
# 否则会缺少 boost/vmd/is_empty.hpp。
file(GLOB __boost_include_dirs LIST_DIRECTORIES true
     "${CMAKE_SOURCE_DIR}/boost/libs/*/include")
include_directories(${__boost_include_dirs})

option(BUILD_TEST "" OFF)
option(BUILD_STATIC "" ON)
add_subdirectory(${LIBRIME} librime-build)

add_library(XimeRimeBridge STATIC "${BRIDGE_DIR}/RimeBridgeC.cpp")
target_include_directories(XimeRimeBridge PUBLIC "${BRIDGE_DIR}/include")
target_include_directories(XimeRimeBridge PRIVATE "${LIBRIME}/include" "${LIBRIME}/src")
target_link_libraries(XimeRimeBridge PUBLIC rime-static)

add_executable(rime_bridge_test "${RIME_TEST_SOURCE}")
target_link_libraries(rime_bridge_test PRIVATE XimeRimeBridge)
