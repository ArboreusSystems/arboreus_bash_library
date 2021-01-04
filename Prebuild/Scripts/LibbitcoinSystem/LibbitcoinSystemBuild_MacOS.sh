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
		source ${A_PREBUILT_LIBS_ROOT}/Scripts/LibbitcoinSystem/LibbitcoinSystemEnvironment.sh
	fi;
fi;


# -----------------------------------
# Variables

export secp256k1_CFLAGS="-I${SECP256K1_PREFIX_MACOS}/include";
export secp256k1_LIBS="-L${SECP256K1_PREFIX_MACOS}/lib -lsecp256k1";


# -----------------------------------
# Functionality

function mLibbitcoinSystemEchoEnvironmentForMacOS() {

	mEchoSeparator;
	echo "LIBBITCOIN_VERSION_NAME: ${LIBBITCOIN_SYSTEM_VERSION_NAME}";
	echo "LIBBITCOIN_DIR_SCRIPTS: ${LIBBITCOIN_SYSTEM_DIR_SCRIPTS}";
	echo "LIBBITCOIN_DIR_BUILDS: ${LIBBITCOIN_SYSTEM_DIR_BUILDS}";
	echo "LIBBITCOIN_DIR_DOWNLOADS: ${LIBBITCOIN_SYSTEM_DIR_DOWNLOADS}";
	echo "LIBBITCOIN_DIR_SOURCES: ${LIBBITCOIN_SYSTEM_DIR_SOURCES}";
	echo "LIBBITCOIN_DIR_SOURCES_WITH_NAME: ${LIBBITCOIN_SYSTEM_DIR_SOURCES_WITH_NAME}";
	echo "LIBBITCOIN_URL_GITHUB: ${LIBBITCOIN_SYSTEM_URL_GITHUB}";
	echo "LIBBITCOIN_PREFIX_MACOS: ${LIBBITCOIN_SYSTEM_PREFIX_MACOS}";
	mEchoSeparator;
}

function mLibbitcoinSystemCleanForMacOS() {

	mCleanDir ${LIBBITCOIN_SYSTEM_DIR_SOURCES_WITH_NAME};
	mCleanDir ${LIBBITCOIN_SYSTEM_PREFIX_MACOS};
	mEchoSeparator;
}

function mLibbitcoinSystemConfigureForMacOS() {

	cd ${LIBBITCOIN_SYSTEM_DIR_SOURCES_WITH_NAME};
	./autogen.sh;
	CXXFLAGS="${A_CXXFLAG_STD} $CXXFLAGS" \
	./configure \
		--prefix=${LIBBITCOIN_SYSTEM_PREFIX_MACOS} \
		--with-boost=${BOOST_PREFIX_MACOS} \
		--with-icu=${ICU_PREFIX_MACOS} \
		--with-tests=no \
		--with-examples=no;

	echo "Libbitcoin configuring finished for MacOS.";
	mEchoSeparator;
}

function mLibbitcoinSystemBuildForMacOS() {

	cd ${LIBBITCOIN_SYSTEM_DIR_SOURCES_WITH_NAME};
	make -j8;
	make install;
	echo "Libbitcoin built successfully for MacOS."
	mEchoSeparator;
}


# -----------------------------------
# Run script

mLibbitcoinSystemEchoEnvironmentForMacOS;
mLibbitcoinSystemCleanForMacOS;
mLibbitcoinSystemGetSources;
mLibbitcoinSystemConfigureForMacOS;
mLibbitcoinSystemBuildForMacOS;
