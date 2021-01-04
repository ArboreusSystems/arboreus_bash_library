#!/usr/bin/env bash


# -----------------------------------
# Includes

if [[ -z ${A_PREBUILT_LIBS_ROOT+x} ]]; then
	echo "No defined \$ARB_PREBUILT_LIBS_ROOT variable.";
	exit 1;
else
	if [[ ! -d "${A_PREBUILT_LIBS_ROOT}" ]]; then
		echo "The prebuilt libs root path is wrong.";
		exit 1;
	else
		source ${A_PREBUILT_LIBS_ROOT}/Scripts/Global/Global.sh;
		source ${A_PREBUILT_LIBS_ROOT}/Scripts/ICU/ICUEnvironment.sh
	fi;
fi;


# -----------------------------------
# Functionality

function mICUEchoEnvironmentForIOS_x86_64() {

	mEchoSeparator;
	echo "ICU_VERSION: ${ICU_VERSION}";
	echo "ICU_DIR_SCRIPTS: ${ICU_DIR_SCRIPTS}";
	echo "ICU_DIR_BUILDS: ${ICU_DIR_BUILDS}";
	echo "ICU_DIR_SOURCES: ${ICU_DIR_SOURCES}";
	echo "ICU_DIR_SOURCES_MACOS: ${ICU_DIR_SOURCES_MACOS}";
	echo "ICU_DIR_DOWNLOADS: ${ICU_DIR_DOWNLOADS}";
	echo "ICU_URL_ARCHIVE: ${ICU_URL_ARCHIVE}";
	echo "ICU_PREFIX_IOS_X86_64: ${ICU_PREFIX_IOS_X86_64}";
	mEchoSeparator
}

function mICUCleanForIOS_x86_64() {

	mCleanDir ${ICU_DIR_SOURCES_IOS_X86_64};
	mCleanDir ${ICU_PREFIX_IOS_X86_64};
	mEchoSeparator
}

function mICUConfigureForIOS_x86_64() {

	echo "Configuring ${ICU_VERSION_NAME} for iOS_x86_64";
	mkdir -p ${ICU_DIR_SOURCES_IOS_X86_64};
	cd ${ICU_DIR_SOURCES_IOS_X86_64};

	export MACOSX_DEPLOYMENT_TARGET="10.4";
	export SDK=$(xcrun --sdk iphonesimulator --show-sdk-path)

	export VALUE_CC=$(xcrun --find --sdk "${SDK}" clang);
	export VALUE_CXX=$(xcrun --find --sdk "${SDK}" clang++);
	export VALUE_AR=$(xcrun --find --sdk "${SDK}" ar);
	export VALUE_RANLIB=$(xcrun --find --sdk "${SDK}" ranlib);
	export VALUE_SYSROOT=$SDK;
	export TARGET=x86_64-apple-darwin;
	export MIN_IOS_VERSION=11.0;
	export FLAGS_OPT="-O3 -g3 -fembed-bitcode";
	export FLAGS_ARCH="-arch x86_64";
	export FLAGS_HOST="${FLAGS_ARCH} -mios-simulator-version-min=${MIN_IOS_VERSION} -isysroot $VALUE_SYSROOT"

	${ICU_DIR_SOURCES_WITH_VERSION}/icu4c/source/configure \
		--prefix=${ICU_PREFIX_IOS_X86_64} \
		--host=$TARGET \
		--enable-static=yes \
		--enable-shared=no \
		--enable-tests=no \
		--enable-samples=no \
		--with-data-packaging=archive \
		--with-cross-build=${ICU_DIR_SOURCES_MACOS} \
		CFLAGS="$FLAGS_HOST $FLAGS_OPT " \
		CXXFLAGS="$A_CXXFLAG_STD $FLAGS_HOST $FLAGS_OPT" \
		LDFLAGS="$FLAGS_HOST" \
		CC=$VALUE_CC \
		CXX=$VALUE_CXX \
		AR=$VALUE_AR \
		RANLIB=$VALUE_RANLIB;

	mEchoSeparator;
}

function mICUBuildForIOS_x86_64() {

	echo "Building ${ICU_VERSION_NAME} for iOS_x86_64";
	cd ${ICU_DIR_SOURCES_IOS_X86_64};
	make -j8;
	make install;
	mEchoSeparator;
}


# -----------------------------------
# Run script

mICUEchoEnvironmentForIOS_x86_64;
mICUCleanForIOS_x86_64;
mICUGetSources;
mICUConfigureForIOS_x86_64;
mICUBuildForIOS_x86_64;
