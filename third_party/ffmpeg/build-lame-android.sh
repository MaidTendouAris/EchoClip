#!/usr/bin/env bash
set -euo pipefail

to_unix_path() {
  if command -v cygpath >/dev/null 2>&1; then
    cygpath -u "$1"
  else
    printf '%s\n' "$1"
  fi
}

host_tag() {
  case "$(uname -s)" in
    MINGW*|MSYS*|CYGWIN*) printf 'windows-x86_64\n' ;;
    Darwin*) printf 'darwin-x86_64\n' ;;
    *) printf 'linux-x86_64\n' ;;
  esac
}

if [[ "${ABI:-arm64-v8a}" != "arm64-v8a" ]]; then
  echo "Only arm64-v8a is supported for now." >&2
  exit 1
fi

ANDROID_API="${ANDROID_API:-26}"
JOBS="${JOBS:-4}"
NDK_ROOT="$(to_unix_path "${NDK_ROOT:?NDK_ROOT is required}")"
LAME_SOURCE="$(to_unix_path "${LAME_SOURCE:?LAME_SOURCE is required}")"
LAME_PREFIX="$(to_unix_path "${LAME_PREFIX:?LAME_PREFIX is required}")"
TOOLCHAIN="$NDK_ROOT/toolchains/llvm/prebuilt/$(host_tag)"

export CC="$TOOLCHAIN/bin/aarch64-linux-android${ANDROID_API}-clang"
export AR="$TOOLCHAIN/bin/llvm-ar"
export RANLIB="$TOOLCHAIN/bin/llvm-ranlib"
export STRIP="$TOOLCHAIN/bin/llvm-strip"
export CFLAGS="-fPIC -O2"

if [[ ! -x "$CC" ]]; then
  echo "Android clang was not found: $CC" >&2
  exit 1
fi

mkdir -p "$LAME_PREFIX"
cd "$LAME_SOURCE"

make distclean >/dev/null 2>&1 || true

./configure \
  --host=aarch64-linux-android \
  --prefix="$LAME_PREFIX" \
  --disable-shared \
  --enable-static \
  --disable-frontend \
  --disable-analyzer-hooks \
  --disable-decoder

make -j"$JOBS"
make install
