#!/usr/bin/env bash


NDK="${A_ANDROID_NDK_ROOT}";
TOOLCHAINS="${BOOST_DIR_SOURCES_WITH_NAME}/toolchains/";
LINK_TYPE="static";

${NDK}/build/tools/make_standalone_toolchain.py \
	--arch arm64 \
	--stl=libc++ \
	--install-dir ${TOOLCHAINS}/android-toolchain-arm64;

cat > tools/build/src/user-config.jam << 'EOF'
import os ;

local NDK_ROOT = ${A_ANDROID_NDK_ROOT} ;
local ANDROID_TOOLCHAIN_ARM64 = android-toolchain-arm64 ;

using clang : arm64_v8a
:
toolchains/android-toolchain-arm64/bin/aarch64-linux-android-clang++
:
<archiver>toolchains/android-toolchain-arm64/bin/aarch64-linux-android-ar
<compileflags>-fexceptions
<compileflags>-frtti
<compileflags>-fpic
<compileflags>-ffunction-sections
<compileflags>-funwind-tables
<compileflags>-fstack-protector
<compileflags>-march=armv8-a
<compileflags>-mtune=cortex-a53
<compileflags>${A_CXXFLAG_STDLIB}
<compileflags>${A_CXXFLAG_STD}
<linkflags>-march=armv8-a
<linkflags>${A_CXXFLAG_STDLIB}
<linkflags>${A_CXXFLAG_STD}
<compileflags>-Os
<compileflags>-fno-short-enums
<compileflags>-fomit-frame-pointer
<compileflags>-fno-strict-aliasing
<compileflags>-DANDROID
<compileflags>-D__ANDROID__
<compileflags>-DNDEBUG
<compileflags>-O2
<compileflags>-g
<root>toolchains/android-toolchain-arm64/sysroot
<architecture>arm
<compileflags>-fvisibility=hidden
<compileflags>-fvisibility-inlines-hidden
<compileflags>-fdata-sections
<cxxflags>${A_CXXFLAG_STDLIB}
<cxxflags>${A_CXXFLAG_STD}
<cxxflags>-D_REENTRANT
<cxxflags>-D_GLIBCXX__PTHREADS
<compileflags>-Wno-long-long
<compileflags>-Wno-missing-field-initializers
<compileflags>-Wno-unused-variable
;

EOF

rm -f user-config.jam;
ln -s tools/build/src/user-config.jam;

./bootstrap.sh \
    --with-icu=${ICU_PREFIX_ANDROID_ARM64};

mBoostLibraries;

./b2 \
    -j8 \
    --prefix=${BOOST_PREFIX_ANDROID_ARM64} \
	--stagedir=${BOOST_PREFIX_ANDROID_ARM64} \
    toolset=clang-arm64_v8a \
    variant=release \
    target-os=android \
    architecture=arm \
    abi=aapcs \
    binary-format=elf \
    address-model=64 \
    threading=multi \
    link=${LINK_TYPE} \
    ${VALUE_LIBRARIES} \
    install \
	-sICU_PATH=${ICU_PREFIX_ANDROID_ARM64};

rm -rf ${BOOST_PREFIX_ANDROID_ARM64}/boost;

mRanlib \
	${A_ANDROID_NDK_ROOT}/toolchains/llvm/prebuilt/darwin-x86_64/bin/aarch64-linux-android-ranlib \
	${BOOST_PREFIX_ANDROID_ARM64}/lib;