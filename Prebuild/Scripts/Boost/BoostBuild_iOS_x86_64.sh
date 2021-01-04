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

function mBoostEchoEnvironmentIOS_x86_64() {

	mEchoSeparator;
	echo "BOOST_VERSION: ${BOOST_VERSION}";
	echo "BOOST_LIBRARIES: ${BOOST_LIBRARIES[*]}";
	echo "BOOST_DIR_SCRIPTS: ${BOOST_DIR_SCRIPTS}";
	echo "BOOST_DIR_BUILDS: ${BOOST_DIR_BUILDS}";
	echo "BOOST_DIR_DOWNLOADS: ${BOOST_DIR_DOWNLOADS}";
	echo "BOOST_DIR_SOURCES: ${BOOST_DIR_SOURCES}";
	echo "BOOST_LOAD_URL: ${BOOST_LOAD_URL}";
	echo "BOOST_PREFIX_IOS_X86_64: ${BOOST_PREFIX_IOS_X86_64}";
	echo "ICU_PREFIX_IOS: ${ICU_PREFIX_IOS}";
	mEchoSeparator;
}

function mBoostCleanForIOS_x86_64() {

	mCleanDir ${BOOST_DIR_SOURCES_WITH_NAME};
	mCleanDir ${BOOST_PREFIX_IOS_X86_64};
	mEchoSeparator
}

function mBoostConfigureForIOS_x86_64() {

	cat > ${BOOST_DIR_SOURCES_WITH_NAME}/tools/build/src/user-config.jam << EOL
using clang-darwin : x86_64
	: xcrun --sdk iphonesimulator clang++
	: <cxxflags>"-mios-simulator-version-min=${A_IPHONE_MIN} -arch x86_64 -DBOOST_AC_USE_PTHREADS -DBOOST_SP_USE_PTHREADS ${A_CXXFLAG_STD} -Wall -pedantic -Wno-unused-variable -O3 -g3 -fembed-bitcode"
	  <linkflags>"-arch x86_64"
	  <striper>
	;
EOL

	cd ${BOOST_DIR_SOURCES_WITH_NAME};
	./bootstrap.sh \
		--with-icu=${ICU_PREFIX_IOS} \
		--prefix=${BOOST_PREFIX_IOS_X86_64};

	echo "Boost configured.";
	mEchoSeparator;
}

function mBoostBuildForIOS_x86_64() {

	cd ${BOOST_DIR_SOURCES_WITH_NAME};
	mBoostLibraries;
	./b2 \
		${BOOST_BUILD_MODE} \
		toolset=clang-darwin-x86_64 \
		target-os=iphone \
		variant=release \
		link=static \
		optimization=speed \
		${VALUE_LIBRARIES} \
		--prefix=${BOOST_PREFIX_IOS_X86_64} \
		--stagedir=${BOOST_PREFIX_IOS_X86_64} \
		--reconfigure boost.locale.iconv=off boost.locale.icu=on \
		-sICU_PATH=${ICU_PREFIX_IOS};

	echo "Boost built successfully.";
	mEchoSeparator;
}


# -----------------------------------
# Run script

mBoostEchoEnvironmentIOS_x86_64;
mBoostCleanForIOS_x86_64;
mBoostGetSources;
mBoostUnzipSources;
mBoostConfigureForIOS_x86_64;
mBoostBuildForIOS_x86_64;

