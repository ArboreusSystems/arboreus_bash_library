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

function mICUEchoEnvironmentForMacOS() {

	mEchoSeparator;
	echo "ICU_VERSION: ${ICU_VERSION}";
	echo "ICU_DIR_SCRIPTS: ${ICU_DIR_SCRIPTS}";
	echo "ICU_DIR_BUILDS: ${ICU_DIR_BUILDS}";
	echo "ICU_DIR_SOURCES: ${ICU_DIR_SOURCES}";
	echo "ICU_DIR_SOURCES_MACOS: ${ICU_DIR_SOURCES_MACOS}";
	echo "ICU_DIR_DOWNLOADS: ${ICU_DIR_DOWNLOADS}";
	echo "ICU_URL_ARCHIVE: ${ICU_URL_ARCHIVE}";
	echo "ICU_PREFIX_MACOS: ${ICU_PREFIX_MACOS}";
	mEchoSeparator
}

function mICUCleanForMacOS() {

	mCleanDir ${ICU_DIR_SOURCES_MACOS};
	mCleanDir ${ICU_PREFIX_MACOS};
	mEchoSeparator
}

function mICUConfigureForMacOS() {

	echo "Configuring ${ICU_VERSION_NAME}";
	cd ${ICU_DIR_SOURCES_MACOS};

	CFLAGS="-Os ${CFLAGS}" CXXFLAGS="${A_CXXFLAG_STD} ${CXXFLAGS}" \
	${ICU_DIR_SOURCES_WITH_VERSION}/icu4c/source/runConfigureICU MacOSX \
		--prefix=${ICU_PREFIX_MACOS} \
		--enable-static=yes \
		--enable-shared=no \
		--enable-tests=no \
		--enable-samples=no;

	mEchoSeparator;
}

function mICUBuildForMacOS() {

	echo "Building ${ICU_VERSION_NAME}";
	cd ${ICU_DIR_SOURCES_MACOS};
	make -j8;
	make install;
	mEchoSeparator;
}


# -----------------------------------
# Run script

mICUEchoEnvironmentForMacOS;
mICUCleanForMacOS;
mICUGetSources;
mICUConfigureForMacOS;
mICUBuildForMacOS;
