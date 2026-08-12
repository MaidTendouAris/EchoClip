#!/usr/bin/env bash
set -euo pipefail

to_unix_path() {
  cygpath -u "$1"
}

JOBS="${JOBS:-4}"
FFMPEG_SOURCE="$(to_unix_path "${FFMPEG_SOURCE:?FFMPEG_SOURCE is required}")"
LAME_SOURCE="$(to_unix_path "${LAME_SOURCE:?LAME_SOURCE is required}")"
BUILD_ROOT="$(to_unix_path "${BUILD_ROOT:?BUILD_ROOT is required}")"
LAME_PREFIX="$(to_unix_path "${LAME_PREFIX:?LAME_PREFIX is required}")"
FFMPEG_OUT="$(to_unix_path "${FFMPEG_OUT:?FFMPEG_OUT is required}")"

export PATH="/ucrt64/bin:/usr/bin:$PATH"
export CC=gcc
export CXX=g++
export AR=ar
export RANLIB=ranlib
export STRIP=strip
export NM=nm

for tool in "$CC" "$CXX" "$AR" "$RANLIB" "$STRIP" make nasm; do
  if ! command -v "$tool" >/dev/null 2>&1; then
    echo "Required Windows build tool was not found: $tool" >&2
    exit 1
  fi
done

mkdir -p "$BUILD_ROOT/lame" "$BUILD_ROOT/ffmpeg" "$LAME_PREFIX" "$FFMPEG_OUT"

if [[ ! -f "$LAME_PREFIX/lib/libmp3lame.a" ]]; then
  cd "$BUILD_ROOT/lame"
  "$LAME_SOURCE/configure" \
    --host=x86_64-w64-mingw32 \
    --prefix="$LAME_PREFIX" \
    --disable-shared \
    --enable-static \
    --disable-frontend \
    --disable-analyzer-hooks \
    --disable-decoder \
    CFLAGS="-O2"
  make -j"$JOBS"
  make install
fi

cd "$BUILD_ROOT/ffmpeg"
"$FFMPEG_SOURCE/configure" \
  --prefix="$FFMPEG_OUT/prefix" \
  --target-os=mingw32 \
  --arch=x86_64 \
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
  --disable-shared \
  --enable-static \
  --enable-w32threads \
  --disable-pthreads \
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
  --extra-cflags="-I$LAME_PREFIX/include -O2" \
  --extra-ldflags="-L$LAME_PREFIX/lib -static -static-libgcc"

make -j"$JOBS"
cp -f ffmpeg.exe "$FFMPEG_OUT/ffmpeg.exe"
"$STRIP" "$FFMPEG_OUT/ffmpeg.exe"
"$FFMPEG_OUT/ffmpeg.exe" -version
