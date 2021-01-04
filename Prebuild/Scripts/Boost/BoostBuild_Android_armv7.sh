#!/usr/bin/env bash


NDK="${A_ANDROID_NDK_ROOT}";
TOOLCHAINS="${BOOST_DIR_SOURCES_WITH_NAME}/toolchains/";
LINK_TYPE="static";

${NDK}/build/tools/make_standalone_toolchain.py \
	--arch arm \
	--stl=libc++ \
	--api=${A_ANDROID_API} \
	--install-dir ${TOOLCHAINS}/android-toolchain-arm;

cat > tools/build/src/user-config.jam << 'EOF'
import os ;

local NDK_ROOT = ${A_ANDROID_NDK_ROOT} ;

using clang : armeabi_v7a
:
toolchains/android-toolchain-arm/bin/arm-linux-androideabi-clang++
:
<archiver>toolchains/android-toolchain-arm/bin/arm-linux-androideabi-ar
<compileflags>-fexceptions
<compileflags>-frtti
<compileflags>-fpic
<compileflags>-ffunction-sections
<compileflags>-funwind-tables
<compileflags>-march=armv7-a
<compileflags>-msoft-float
<compileflags>-mfpu=neon
<compileflags>-mthumb
<compileflags>${A_CXXFLAG_STDLIB}
<compileflags>${A_CXXFLAG_STD}
<linkflags>-march=armv7-a
<linkflags>-Wl,--fix-cortex-a8
<linkflags>${A_CXXFLAG_STDLIB}
<linkflags>${A_CXXFLAG_STD}
<compileflags>-Os
<compileflags>-fomit-frame-pointer
<compileflag>-fno-strict-aliasing
<compileflags>-Wa,--noexecstack
<compileflags>-DANDROID
<compileflags>-D__ANDROID__
<compileflags>-DNDEBUG
<compileflags>-O2
<compileflags>-g
<root>toolchains/android-toolchain-arm/sysroot
<architecture>arm
<compileflags>-fvisibility=hidden
<compileflags>-fvisibility-inlines-hidden
<compileflags>-fdata-sections
<cxxflags>${A_CXXFLAG_STDLIB}
<cxxflags>${A_CXXFLAG_STD}
<cxxflags>-D__arm__
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
    --with-icu=${ICU_PREFIX_ANDROID_ARMV7};

mBoostLibraries;

./b2 \
    -j8 \
    --prefix=${BOOST_PREFIX_ANDROID_ARMV7} \
	--stagedir=${BOOST_PREFIX_ANDROID_ARMV7} \
    toolset=clang-armeabi_v7a \
    variant=release \
    target-os=android \
    architecture=arm \
    abi=aapcs \
    binary-format=elf \
    address-model=32 \
    threading=multi \
    link=${LINK_TYPE} \
    ${VALUE_LIBRARIES} \
    install \
	-sICU_PATH=${ICU_PREFIX_ANDROID_ARMV7};

rm -rf ${BOOST_PREFIX_ANDROID_ARMV7}/boost;

mRanlib \
	${A_ANDROID_NDK_ROOT}/toolchains/llvm/prebuilt/darwin-x86_64/bin/arm-linux-androideabi-ranlib \
	${BOOST_PREFIX_ANDROID_ARMV7}/lib;