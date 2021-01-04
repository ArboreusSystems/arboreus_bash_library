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
		source ${A_PREBUILT_LIBS_ROOT}/Scripts/Global/Global_Android.sh;
		source ${A_PREBUILT_LIBS_ROOT}/Scripts/Boost/BoostEnvironment.sh
	fi;
fi;


# -----------------------------------
# Functionality

function mBoostCleanForAndroid_ARM64() {

	mEchoSeparator;
	mCleanDir ${BOOST_DIR_SOURCES_WITH_NAME};
	mCleanDir ${BOOST_PREFIX_ANDROID_ARM64};
	mEchoSeparator;
}

function mBoostCleanForAndroid_ARMV7() {

	mEchoSeparator;
	mCleanDir ${BOOST_DIR_SOURCES_WITH_NAME};
	mCleanDir ${BOOST_PREFIX_ANDROID_ARMV7};
	mEchoSeparator;
}

function mBoostCleanForAndroid_X86() {

	mEchoSeparator;
	mCleanDir ${BOOST_DIR_SOURCES_WITH_NAME};
	mCleanDir ${BOOST_PREFIX_ANDROID_X86};
	mEchoSeparator;
}

function mBoostCleanForAndroid_X86_64() {

	mEchoSeparator;
	mCleanDir ${BOOST_DIR_SOURCES_WITH_NAME};
	mCleanDir ${BOOST_PREFIX_ANDROID_X86_64};
	mEchoSeparator;
}


# -----------------------------------
# Run script

mBoostCleanForAndroid_ARM64;
mBoostGetSources;
mBoostUnzipSources;
cd ${BOOST_DIR_SOURCES_WITH_NAME};
source ${BOOST_DIR_SCRIPTS}/BoostBuild_Android_arm64.sh;

mBoostCleanForAndroid_ARMV7;
mBoostGetSources;
mBoostUnzipSources;
cd ${BOOST_DIR_SOURCES_WITH_NAME};
source ${BOOST_DIR_SCRIPTS}/BoostBuild_Android_armv7.sh;

mBoostCleanForAndroid_X86;
mBoostGetSources;
mBoostUnzipSources;
cd ${BOOST_DIR_SOURCES_WITH_NAME};
source ${BOOST_DIR_SCRIPTS}/BoostBuild_Android_x86.sh;

mBoostCleanForAndroid_X86_64;
mBoostGetSources;
mBoostUnzipSources;
cd ${BOOST_DIR_SOURCES_WITH_NAME};
source ${BOOST_DIR_SCRIPTS}/BoostBuild_Android_x86_64.sh;