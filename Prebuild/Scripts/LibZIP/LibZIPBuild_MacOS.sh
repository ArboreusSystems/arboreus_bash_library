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
		source ${A_PREBUILT_LIBS_ROOT}/Scripts/LibZIP/LibZIPEnvironment.sh
	fi;
fi;


# -----------------------------------
# Functionality

function mLibZIPEchoEnvironmentForMacOS() {

	mEchoSeparator;
	echo "LIBZIP_DIR_SCRIPTS: ${LIBZIP_DIR_SCRIPTS}";
	echo "LIBZIP_DIR_BUILDS: ${LIBZIP_DIR_BUILDS}";
	echo "LIBZIP_DIR_SOURCES: ${LIBZIP_DIR_SOURCES}";
	echo "LIBZIP_ARCHIVE_URL: ${LIBZIP_ARCHIVE_URL}";
	echo "LIBZIP_PREFIX_MACOS: ${LIBZIP_PREFIX_MACOS}";
	mEchoSeparator
}

function mLibZIPCleanForMacOS() {

	mCleanDir ${LIBZIP_DIR_SOURCES};
	mCleanDir ${LIBZIP_PREFIX_MACOS};
	mEchoSeparator;
}

function mLibZIPConfigureForMacOS() {

	cd ${LIBZIP_DIR_SOURCES}/${LIBZIP_VERSION_NAME};
	cmake -DCMAKE_INSTALL_PREFIX:PATH=${LIBZIP_PREFIX_MACOS} .;
}

function mLibZIPBuildForMacOS() {

	cd ${LIBZIP_DIR_SOURCES}/${LIBZIP_VERSION_NAME};
	make -j${A_CORE_NUMBER};
	make install;
	mEchoSeparator;
}


# -----------------------------------
# Run script

mLibZIPEchoEnvironmentForMacOS;
mLibZIPCleanForMacOS;
mLibZIPGetSources;
mLibZIPUnzipSources;
mLibZIPConfigureForMacOS;
mLibZIPBuildForMacOS;