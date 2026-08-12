# Project-level configuration.
cmake_minimum_required(VERSION 3.14)
project(echoclip LANGUAGES CXX)

# The name of the executable created for the application. Change this to change
# the on-disk name of your application.
set(BINARY_NAME "echoclip")

# Explicitly opt in to modern CMake behaviors to avoid warnings with recent
# versions of CMake.
cmake_policy(VERSION 3.14...3.25)

# Define build configuration option.
get_property(IS_MULTICONFIG GLOBAL PROPERTY GENERATOR_IS_MULTI_CONFIG)
if(IS_MULTICONFIG)
  set(CMAKE_CONFIGURATION_TYPES "Debug;Profile;Release"
    CACHE STRING "" FORCE)
else()
  if(NOT CMAKE_BUILD_TYPE AND NOT CMAKE_CONFIGURATION_TYPES)
    set(CMAKE_BUILD_TYPE "Debug" CACHE
      STRING "Flutter build mode" FORCE)
    set_property(CACHE CMAKE_BUILD_TYPE PROPERTY STRINGS
      "Debug" "Profile" "Release")
  endif()
endif()
# Define settings for the Profile build mode.
set(CMAKE_EXE_LINKER_FLAGS_PROFILE "${CMAKE_EXE_LINKER_FLAGS_RELEASE}")
set(CMAKE_SHARED_LINKER_FLAGS_PROFILE "${CMAKE_SHARED_LINKER_FLAGS_RELEASE}")
set(CMAKE_C_FLAGS_PROFILE "${CMAKE_C_FLAGS_RELEASE}")
set(CMAKE_CXX_FLAGS_PROFILE "${CMAKE_CXX_FLAGS_RELEASE}")

# Use Unicode for all projects.
add_definitions(-DUNICODE -D_UNICODE)

# Compilation settings that should be applied to most targets.
#
# Be cautious about adding new options here, as plugins use this function by
# default. In most cases, you should add new options to specific targets instead
# of modifying this function.
function(APPLY_STANDARD_SETTINGS TARGET)
  target_compile_features(${TARGET} PUBLIC cxx_std_17)
  target_compile_options(${TARGET} PRIVATE /W4 /WX /wd"4100")
  target_compile_options(${TARGET} PRIVATE /EHsc)
  target_compile_definitions(${TARGET} PRIVATE "_HAS_EXCEPTIONS=0")
  target_compile_definitions(${TARGET} PRIVATE "$<$<CONFIG:Debug>:_DEBUG>")
endfunction()

# Flutter library and tool build rules.
set(FLUTTER_MANAGED_DIR "${CMAKE_CURRENT_SOURCE_DIR}/flutter")
add_subdirectory(${FLUTTER_MANAGED_DIR})

# Application build; see runner/CMakeLists.txt.
add_subdirectory("runner")


# Generated plugin build rules, which manage building the plugins and adding
# them to the application.
include(flutter/generated_plugins.cmake)

# Build the x86-64 Rust recorder bridge as part of every Windows application
# build. Dart loads this DLL dynamically at runtime, so it is installed beside
# echoclip.exe rather than linked into the runner.
get_filename_component(ECHOCLIP_REPO_ROOT
  "${CMAKE_CURRENT_SOURCE_DIR}/../../.." ABSOLUTE)
set(ECHOCLIP_WINDOWS_FFMPEG_EXE
  "${ECHOCLIP_REPO_ROOT}/third_party/ffmpeg/out/windows/x64/ffmpeg.exe")
set(ECHOCLIP_WINDOWS_FFMPEG_NOTICE
  "${ECHOCLIP_REPO_ROOT}/third_party/ffmpeg/WINDOWS_NOTICE.txt")
set(ECHOCLIP_WINDOWS_FFMPEG_LICENSE
  "${ECHOCLIP_REPO_ROOT}/third_party/ffmpeg/src/ffmpeg/COPYING.LGPLv2.1")
set(ECHOCLIP_WINDOWS_LAME_LICENSE
  "${ECHOCLIP_REPO_ROOT}/third_party/ffmpeg/src/lame/COPYING")
foreach(ECHOCLIP_FFMPEG_FILE IN ITEMS
    "${ECHOCLIP_WINDOWS_FFMPEG_EXE}"
    "${ECHOCLIP_WINDOWS_FFMPEG_NOTICE}"
    "${ECHOCLIP_WINDOWS_FFMPEG_LICENSE}"
    "${ECHOCLIP_WINDOWS_LAME_LICENSE}")
  if(NOT EXISTS "${ECHOCLIP_FFMPEG_FILE}")
    message(FATAL_ERROR
      "Required Windows FFmpeg artifact is missing: ${ECHOCLIP_FFMPEG_FILE}. "
      "Run scripts/build_windows_ffmpeg.ps1 before building the app.")
  endif()
endforeach()
find_program(CARGO_EXECUTABLE NAMES cargo cargo.exe
  HINTS "$ENV{USERPROFILE}/.cargo/bin")
if(NOT CARGO_EXECUTABLE)
  message(FATAL_ERROR
    "cargo was not found; install the Rust x86_64-pc-windows-msvc toolchain")
endif()

set(ECHOCLIP_RUST_TARGET "x86_64-pc-windows-msvc")
set(ECHOCLIP_RUST_TARGET_DIR "${CMAKE_BINARY_DIR}/rust-target")
set(ECHOCLIP_WINDOWS_FFI_DLL
  "${ECHOCLIP_RUST_TARGET_DIR}/${ECHOCLIP_RUST_TARGET}/release/echoclip_windows_ffi.dll")
file(GLOB_RECURSE ECHOCLIP_RUST_SOURCES CONFIGURE_DEPENDS
  "${ECHOCLIP_REPO_ROOT}/crates/echoclip_core/src/*.rs"
  "${ECHOCLIP_REPO_ROOT}/crates/echoclip_windows_ffi/src/*.rs")

add_custom_command(
  OUTPUT "${ECHOCLIP_WINDOWS_FFI_DLL}"
  COMMAND "${CMAKE_COMMAND}" -E env
    "CARGO_TARGET_DIR=${ECHOCLIP_RUST_TARGET_DIR}"
    "${CARGO_EXECUTABLE}" build
    --manifest-path "${ECHOCLIP_REPO_ROOT}/Cargo.toml"
    --package echoclip_windows_ffi
    --release
    --target "${ECHOCLIP_RUST_TARGET}"
  WORKING_DIRECTORY "${ECHOCLIP_REPO_ROOT}"
  DEPENDS
    "${ECHOCLIP_REPO_ROOT}/Cargo.toml"
    "${ECHOCLIP_REPO_ROOT}/Cargo.lock"
    "${ECHOCLIP_REPO_ROOT}/crates/echoclip_core/Cargo.toml"
    "${ECHOCLIP_REPO_ROOT}/crates/echoclip_windows_ffi/Cargo.toml"
    ${ECHOCLIP_RUST_SOURCES}
  COMMENT "Building EchoClip Rust recorder bridge (x86-64)"
  VERBATIM)
add_custom_target(echoclip_windows_ffi_build ALL
  DEPENDS "${ECHOCLIP_WINDOWS_FFI_DLL}")
add_dependencies(${BINARY_NAME} echoclip_windows_ffi_build)


# === Installation ===
# Support files are copied into place next to the executable, so that it can
# run in place. This is done instead of making a separate bundle (as on Linux)
# so that building and running from within Visual Studio will work.
set(BUILD_BUNDLE_DIR "$<TARGET_FILE_DIR:${BINARY_NAME}>")
# Make the "install" step default, as it's required to run.
set(CMAKE_VS_INCLUDE_INSTALL_TO_DEFAULT_BUILD 1)
if(CMAKE_INSTALL_PREFIX_INITIALIZED_TO_DEFAULT)
  set(CMAKE_INSTALL_PREFIX "${BUILD_BUNDLE_DIR}" CACHE PATH "..." FORCE)
endif()

set(INSTALL_BUNDLE_DATA_DIR "${CMAKE_INSTALL_PREFIX}/data")
set(INSTALL_BUNDLE_LIB_DIR "${CMAKE_INSTALL_PREFIX}")

install(TARGETS ${BINARY_NAME} RUNTIME DESTINATION "${CMAKE_INSTALL_PREFIX}"
  COMPONENT Runtime)

install(FILES "${FLUTTER_ICU_DATA_FILE}" DESTINATION "${INSTALL_BUNDLE_DATA_DIR}"
  COMPONENT Runtime)

install(FILES "${FLUTTER_LIBRARY}" DESTINATION "${INSTALL_BUNDLE_LIB_DIR}"
  COMPONENT Runtime)

install(FILES "${ECHOCLIP_WINDOWS_FFI_DLL}"
  DESTINATION "${INSTALL_BUNDLE_LIB_DIR}"
  COMPONENT Runtime)

install(FILES "${ECHOCLIP_WINDOWS_FFMPEG_EXE}"
  DESTINATION "${INSTALL_BUNDLE_LIB_DIR}"
  COMPONENT Runtime)
install(FILES "${ECHOCLIP_WINDOWS_FFMPEG_NOTICE}"
  DESTINATION "${CMAKE_INSTALL_PREFIX}/licenses"
  RENAME "FFmpeg-Windows-NOTICE.txt"
  COMPONENT Runtime)
install(FILES "${ECHOCLIP_WINDOWS_FFMPEG_LICENSE}"
  DESTINATION "${CMAKE_INSTALL_PREFIX}/licenses"
  RENAME "FFmpeg-LGPL-2.1.txt"
  COMPONENT Runtime)
install(FILES "${ECHOCLIP_WINDOWS_LAME_LICENSE}"
  DESTINATION "${CMAKE_INSTALL_PREFIX}/licenses"
  RENAME "LAME-LGPL-2.0.txt"
  COMPONENT Runtime)

if(PLUGIN_BUNDLED_LIBRARIES)
  install(FILES "${PLUGIN_BUNDLED_LIBRARIES}"
    DESTINATION "${INSTALL_BUNDLE_LIB_DIR}"
    COMPONENT Runtime)
endif()

# Copy the native assets provided by the build.dart from all packages.
set(NATIVE_ASSETS_DIR "${PROJECT_BUILD_DIR}native_assets/windows/")
install(DIRECTORY "${NATIVE_ASSETS_DIR}"
   DESTINATION "${INSTALL_BUNDLE_LIB_DIR}"
   COMPONENT Runtime)

# Fully re-copy the assets directory on each build to avoid having stale files
# from a previous install.
set(FLUTTER_ASSET_DIR_NAME "flutter_assets")
install(CODE "
  file(REMOVE_RECURSE \"${INSTALL_BUNDLE_DATA_DIR}/${FLUTTER_ASSET_DIR_NAME}\")
  " COMPONENT Runtime)
install(DIRECTORY "${PROJECT_BUILD_DIR}/${FLUTTER_ASSET_DIR_NAME}"
  DESTINATION "${INSTALL_BUNDLE_DATA_DIR}" COMPONENT Runtime)

# Install the AOT library on non-Debug builds only.
install(FILES "${AOT_LIBRARY}" DESTINATION "${INSTALL_BUNDLE_DATA_DIR}"
  CONFIGURATIONS Profile;Release
  COMPONENT Runtime)
