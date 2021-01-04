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
		source ${A_PREBUILT_LIBS_ROOT}/Scripts/Boost/BoostEnvironment.sh
	fi;
fi;


# -----------------------------------
# Functionality

function mBoostEchoEnvironmentIOS_ARM64() {

	mEchoSeparator;
	echo "BOOST_VERSION: ${BOOST_VERSION}";
	echo "BOOST_LIBRARIES: ${BOOST_LIBRARIES[*]}";
	echo "BOOST_DIR_SCRIPTS: ${BOOST_DIR_SCRIPTS}";
	echo "BOOST_DIR_BUILDS: ${BOOST_DIR_BUILDS}";
	echo "BOOST_DIR_DOWNLOADS: ${BOOST_DIR_DOWNLOADS}";
	echo "BOOST_DIR_SOURCES: ${BOOST_DIR_SOURCES}";
	echo "BOOST_LOAD_URL: ${BOOST_LOAD_URL}";
	echo "BOOST_PREFIX_IOS_ARM64: ${BOOST_PREFIX_IOS_ARM64}";
	echo "ICU_PREFIX_IOS: ${ICU_PREFIX_IOS}";
	mEchoSeparator;
}

function mBoostCleanForIOS_ARM64() {

	mCleanDir ${BOOST_DIR_SOURCES_WITH_NAME};
	mCleanDir ${BOOST_PREFIX_IOS_ARM64};
	mEchoSeparator
}

function mBoostConfigureForIOS_ARM64() {

	cat > ${BOOST_DIR_SOURCES_WITH_NAME}/tools/build/src/user-config.jam << EOL
using clang-darwin : arm64
	: xcrun --sdk iphoneos clang++
	: <cxxflags>"-miphoneos-version-min=${A_IPHONE_MIN} -arch arm64 -DBOOST_AC_USE_PTHREADS -DBOOST_SP_USE_PTHREADS ${A_CXXFLAG_STD} -D_LITTLE_ENDIAN -Wall -pedantic -Wno-unused-variable -O3 -g3 -fembed-bitcode"
	  <linkflags>"-arch arm64"
	  <striper>
	;
EOL

	cd ${BOOST_DIR_SOURCES_WITH_NAME};
	./bootstrap.sh \
		--with-icu=${ICU_PREFIX_IOS} \
		--prefix=${BOOST_PREFIX_IOS_ARM64};

	echo "Boost configured.";
	mEchoSeparator;
}

function mBoostBuildForIOS_ARM64() {

	cd ${BOOST_DIR_SOURCES_WITH_NAME};
	mBoostLibraries;
	./b2 \
		${BOOST_BUILD_MODE} \
		toolset=clang-darwin-arm64 \
		target-os=iphone \
		variant=release \
		link=static \
		optimization=speed \
		${VALUE_LIBRARIES} \
		--prefix=${BOOST_PREFIX_IOS_ARM64} \
		--stagedir=${BOOST_PREFIX_IOS_ARM64} \
		--reconfigure boost.locale.iconv=off boost.locale.icu=on \
		-sICU_PATH=${ICU_PREFIX_IOS};

	echo "Boost built successfully.";
	mEchoSeparator;
}


# -----------------------------------
# Run script

mBoostEchoEnvironmentIOS_ARM64;
mBoostCleanForIOS_ARM64;
mBoostGetSources;
mBoostUnzipSources;
mBoostConfigureForIOS_ARM64;
mBoostBuildForIOS_ARM64;

