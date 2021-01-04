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

function mICUEchoEnvironmentForAndroid_X86() {

	mEchoSeparator;
	echo "ICU_VERSION: ${ICU_VERSION}";
	echo "ICU_DIR_SCRIPTS: ${ICU_DIR_SCRIPTS}";
	echo "ICU_DIR_BUILDS: ${ICU_DIR_BUILDS}";
	echo "ICU_DIR_SOURCES: ${ICU_DIR_SOURCES}";
	echo "ICU_DIR_SOURCES_MACOS: ${ICU_DIR_SOURCES_MACOS}";
	echo "ICU_DIR_DOWNLOADS: ${ICU_DIR_DOWNLOADS}";
	echo "ICU_URL_ARCHIVE: ${ICU_URL_ARCHIVE}";
	echo "ICU_PREFIX_ANDROID_X86: ${ICU_PREFIX_ANDROID_X86}";
	mEchoSeparator
}

function mICUCleanForAndroid_X86() {

	mCleanDir ${ICU_DIR_SOURCES_ANDROID_X86};
	mCleanDir ${ICU_PREFIX_ANDROID_X86};
	mEchoSeparator
}

function mICUConfigureForAndroid_X86() {

	echo "Configuring ${ICU_VERSION_NAME} for Android X86";
	mkdir -p ${ICU_DIR_SOURCES_ANDROID_X86};
	cd ${ICU_DIR_SOURCES_ANDROID_X86};
	source ${A_DIR_SCRIPTS}/Global/GlobalEnvironment_Android_x86.sh;

	echo "Configuring ${ICU_VERSION_NAME} for Android X86";
	${ICU_DIR_SOURCES_WITH_VERSION}/icu4c/source/configure \
		--prefix=${ICU_PREFIX_ANDROID_X86} \
		--host=${TARGET} \
		--enable-static=yes \
		--enable-shared=yes \
		--enable-tests=no \
		--enable-samples=no \
		--with-data-packaging=archive \
		--with-cross-build=${ICU_DIR_SOURCES_MACOS};

	mEchoSeparator;
}

function mICUBuildForAndroid_X86() {

	echo "Building ${ICU_VERSION_NAME} for Android X86";
	cd ${ICU_DIR_SOURCES_ANDROID_X86};
	make -j8;
	make install;
	mEchoSeparator;
}


# -----------------------------------
# Run script

mICUEchoEnvironmentForAndroid_X86;
mICUCleanForAndroid_X86;
mICUGetSources;
mICUConfigureForAndroid_X86;
mICUBuildForAndroid_X86;
