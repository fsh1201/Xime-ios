cmake_minimum_required(VERSION 3.20)

project(XimeRimeBridge LANGUAGES C CXX)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_CXX_EXTENSIONS OFF)

add_library(XimeRimeBridge STATIC RimeBridgeC.cpp)

target_include_directories(XimeRimeBridge PUBLIC
    ${CMAKE_CURRENT_SOURCE_DIR}/include
)

if(NOT RIME_ROOT)
    set(RIME_ROOT "${CMAKE_CURRENT_SOURCE_DIR}/../../app/src/main/jni/librime")
endif()

target_include_directories(XimeRimeBridge PRIVATE
    ${RIME_ROOT}/include
    ${RIME_ROOT}/src
)

# RIME_LIBRARIES 由构建脚本传入，例如：
#   -DRIME_LIBRARIES="/path/to/librime.a;/path/to/yaml-cpp.a;..."
# 或者链接已生成的 XCFramework slice。
if(RIME_LIBRARIES)
    target_link_libraries(XimeRimeBridge PUBLIC ${RIME_LIBRARIES})
endif()

set_target_properties(XimeRimeBridge PROPERTIES
    PUBLIC_HEADER "${CMAKE_CURRENT_SOURCE_DIR}/include/RimeBridgeC.h"
)
