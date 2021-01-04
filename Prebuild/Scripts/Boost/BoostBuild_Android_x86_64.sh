#!/usr/bin/env bash

NDK="${A_ANDROID_NDK_ROOT}";
TOOLCHAINS="${BOOST_DIR_SOURCES_WITH_NAME}/toolchains/";
LINK_TYPE="static";

${NDK}/build/tools/make_standalone_toolchain.py \
	--arch x86_64 \
	--stl=libc++ \
	--install-dir $TOOLCHAINS/android-toolchain-x86_64;

cat > tools/build/src/user-config.jam << 'EOF'
import os ;

local NDK_ROOT = ${A_ANDROID_NDK_ROOT} ;
local ANDROID_TOOLCHAIN_x86_64 = android-toolchain-x86_64 ;

using clang : x86_64
:
toolchains/android-toolchain-x86_64/bin/x86_64-linux-android-clang++
:
<archiver>toolchains/android-toolchain-x86_64/bin/x86_64-linux-android-ar
<compileflags>-fexceptions
<compileflags>-frtti
<compileflags>-fpic
<compileflags>-ffunction-sections
<compileflags>-funwind-tables
<compileflags>-Wno-missing-field-initializers
<compileflags>-no-canonical-prefixes
<compileflags>${A_CXXFLAG_STDLIB}
<compileflags>${A_CXXFLAG_STD}
<linkflags>-no-canonical-prefixes
<linkflags>${A_CXXFLAG_STDLIB}
<linkflags>${A_CXXFLAG_STD}
<compileflags>-Os
<compileflags>-fomit-frame-pointer
<compileflags>-fno-strict-aliasing
<compileflags>-Wa,--noexecstack
<compileflags>-DANDROID
<compileflags>-D__ANDROID__
<compileflags>-DNDEBUG
<compileflags>-O2
<compileflags>-g
<root>toolchains/android-toolchain-x86_64/sysroot
<architecture>x86_64
<compileflags>-fvisibility=hidden
<compileflags>-fvisibility-inlines-hidden
<compileflags>-fdata-sections
<cxxflags>-D_REENTRANT
<cxxflags>-D_GLIBCXX__PTHREADS
<cxxflags>${A_CXXFLAG_STDLIB}
<cxxflags>${A_CXXFLAG_STD}
<compileflags>-Wno-long-long
<compileflags>-Wno-missing-field-initializers
<compileflags>-Wno-unused-variable
;

EOF

rm -f user-config.jam;
ln -s tools/build/src/user-config.jam;

./bootstrap.sh \
	--with-icu=${ICU_PREFIX_ANDROID_X86_64};

mBoostLibraries;

./b2 \
	-j8 \
    --prefix=${BOOST_PREFIX_ANDROID_X86_64} \
	--stagedir=${BOOST_PREFIX_ANDROID_X86_64} \
	toolset=clang-x86_64 \
	variant=release \
	target-os=android \
	architecture=x86 \
	abi=x32 \
	binary-format=elf \
	address-model=64 \
	threading=multi \
	link=${LINK_TYPE} \
	${VALUE_LIBRARIES} \
	install \
	-sICU_PATH=${ICU_PREFIX_ANDROID_X86_64};

rm -rf ${BOOST_PREFIX_ANDROID_X86_64}/boost;

mRanlib \
	${A_ANDROID_NDK_ROOT}/toolchains/llvm/prebuilt/darwin-x86_64/bin/x86_64-linux-android-ranlib \
	${BOOST_PREFIX_ANDROID_X86_64}/lib;
