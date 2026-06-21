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
FFMPEG_SOURCE="$(to_unix_path "${FFMPEG_SOURCE:?FFMPEG_SOURCE is required}")"
LAME_PREFIX="$(to_unix_path "${LAME_PREFIX:?LAME_PREFIX is required}")"
FFMPEG_OUT="$(to_unix_path "${FFMPEG_OUT:?FFMPEG_OUT is required}")"
TOOLCHAIN="$NDK_ROOT/toolchains/llvm/prebuilt/$(host_tag)"

CC="$TOOLCHAIN/bin/aarch64-linux-android${ANDROID_API}-clang"
CXX="$TOOLCHAIN/bin/aarch64-linux-android${ANDROID_API}-clang++"
AR="$TOOLCHAIN/bin/llvm-ar"
RANLIB="$TOOLCHAIN/bin/llvm-ranlib"
STRIP="$TOOLCHAIN/bin/llvm-strip"
NM="$TOOLCHAIN/bin/llvm-nm"

if [[ ! -x "$CC" ]]; then
  echo "Android clang was not found: $CC" >&2
  exit 1
fi
if [[ ! -f "$LAME_PREFIX/lib/libmp3lame.a" ]]; then
  echo "libmp3lame.a was not found: $LAME_PREFIX/lib/libmp3lame.a" >&2
  exit 1
fi

mkdir -p "$FFMPEG_OUT"
cd "$FFMPEG_SOURCE"

make distclean >/dev/null 2>&1 || true

./configure \
  --prefix="$FFMPEG_OUT/prefix" \
  --target-os=android \
  --arch=aarch64 \
  --cpu=armv8-a \
  --enable-cross-compile \
  --cc="$CC" \
  --cxx="$CXX" \
  --ar="$AR" \
  --ranlib="$RANLIB" \
  --strip="$STRIP" \
  --nm="$NM" \
  --pkg-config=false \
  --disable-autodetect \
  --disable-doc \
  --disable-debug \
  --disable-network \
  --disable-avdevice \
  --disable-swscale \
  --disable-ffplay \
  --disable-ffprobe \
  --enable-ffmpeg \
  --enable-small \
  --enable-pic \
  --enable-avcodec \
  --enable-avformat \
  --enable-avfilter \
  --enable-swresample \
  --enable-libmp3lame \
  --disable-encoders \
  --enable-encoder=libmp3lame \
  --enable-encoder=aac \
  --enable-encoder=flac \
  --enable-encoder=pcm_s16le \
  --enable-encoder=pcm_s24le \
  --disable-decoders \
  --enable-decoder=mp3 \
  --enable-decoder=aac \
  --enable-decoder=flac \
  --enable-decoder=pcm_s16le \
  --enable-decoder=pcm_s24le \
  --disable-muxers \
  --enable-muxer=mp3 \
  --enable-muxer=wav \
  --enable-muxer=adts \
  --enable-muxer=flac \
  --enable-muxer=mp4 \
  --enable-muxer=ipod \
  --disable-demuxers \
  --enable-demuxer=pcm_s16le \
  --enable-demuxer=pcm_s24le \
  --enable-demuxer=wav \
  --enable-demuxer=mp3 \
  --enable-demuxer=aac \
  --enable-demuxer=flac \
  --enable-demuxer=mov \
  --disable-parsers \
  --enable-parser=mpegaudio \
  --enable-parser=aac \
  --enable-parser=flac \
  --disable-protocols \
  --enable-protocol=file \
  --enable-protocol=pipe \
  --disable-filters \
  --enable-filter=aresample \
  --enable-filter=volume \
  --enable-filter=loudnorm \
  --enable-filter=acompressor \
  --enable-filter=alimiter \
  --enable-filter=highpass \
  --enable-filter=lowpass \
  --enable-filter=atempo \
  --extra-cflags="-I$LAME_PREFIX/include -fPIC -O2" \
  --extra-ldflags="-L$LAME_PREFIX/lib"

make -j"$JOBS" ffmpeg
cp ffmpeg "$FFMPEG_OUT/libffmpeg.so"
"$STRIP" "$FFMPEG_OUT/libffmpeg.so" || true
