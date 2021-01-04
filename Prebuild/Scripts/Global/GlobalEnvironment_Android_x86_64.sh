#!/usr/bin/env bash


# -----------------------------------
# Variables

export NDK="${A_ANDROID_NDK_ROOT}";
export TOOLCHAIN="${NDK}/toolchains/llvm/prebuilt/darwin-x86_64";
export TARGET="x86_64-linux-android";
export API="${A_ANDROID_API}";

export AR="${TOOLCHAIN}/bin/${TARGET}-ar";
export AS="${TOOLCHAIN}/bin/${TARGET}-as";
export CC="${TOOLCHAIN}/bin/${TARGET}${API}-clang";
export CXX="${TOOLCHAIN}/bin/${TARGET}${API}-clang++";
export LD="${TOOLCHAIN}/bin/${TARGET}-ld";
export RANLIB="${TOOLCHAIN}/bin/${TARGET}-ranlib";
export STRIP="${TOOLCHAIN}/bin/${TARGET}-strip";
export CFLAGS="-fPIC ${CFLAGS}";
export CXXFLAGS="${A_CXXFLAG_STD} ${A_CXXFLAG_STDLIB} -fPIC ${CXXFLAGS}";

echo "NDK: ${NDK}";
echo "TOOLCHAIN: ${TOOLCHAIN}";
echo "TARGET: ${TARGET}";
echo "API: ${API}";
echo "AR: ${AR}";
echo "AS: ${AS}";
echo "CC: ${CC}";
echo "CXX: ${CXX}";
echo "LD: ${LD}";
echo "RANLIB: ${RANLIB}";
echo "STRIP: ${STRIP}";
echo "CFLAGS: ${CFLAGS}";
echo "CXXFLAGS: ${CXXFLAGS}";