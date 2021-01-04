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

export secp256k1_CFLAGS="-I${SECP256K1_PREFIX_IOS}/include";
export secp256k1_LIBS="-L${SECP256K1_PREFIX_IOS}/lib -lsecp256k1";


# -----------------------------------
# Functionality

function mLibbitcoinSystemEchoEnvironmentForIOS_ARM64() {

	mEchoSeparator;
	echo "LIBBITCOIN_VERSION_NAME: ${LIBBITCOIN_SYSTEM_VERSION_NAME}";
	echo "LIBBITCOIN_DIR_SCRIPTS: ${LIBBITCOIN_SYSTEM_DIR_SCRIPTS}";
	echo "LIBBITCOIN_DIR_BUILDS: ${LIBBITCOIN_SYSTEM_DIR_BUILDS}";
	echo "LIBBITCOIN_DIR_DOWNLOADS: ${LIBBITCOIN_SYSTEM_DIR_DOWNLOADS}";
	echo "LIBBITCOIN_DIR_SOURCES: ${LIBBITCOIN_SYSTEM_DIR_SOURCES}";
	echo "LIBBITCOIN_DIR_SOURCES_WITH_NAME: ${LIBBITCOIN_SYSTEM_DIR_SOURCES_WITH_NAME}";
	echo "LIBBITCOIN_URL_GITHUB: ${LIBBITCOIN_SYSTEM_URL_GITHUB}";
	echo "LIBBITCOIN_SYSTEM_PREFIX_IOS_ARM64: ${LIBBITCOIN_SYSTEM_PREFIX_IOS_ARM64}";
	mEchoSeparator;
}

function mLibbitcoinSystemCleanForIOS_ARM64() {

	mCleanDir ${LIBBITCOIN_SYSTEM_DIR_SOURCES_WITH_NAME};
	mCleanDir ${LIBBITCOIN_SYSTEM_PREFIX_IOS_ARM64};
	mEchoSeparator
}

function mLibbitcoinSystemConfigureForIOS_ARM64() {

	export ARCH=arm64;
	export PREFIX=${LIBBITCOIN_SYSTEM_PREFIX_IOS_ARM64};
	source ${A_PREBUILT_LIBS_ROOT}/Scripts/Global/GlobalEnvironment_iOS.sh;
	mEchoSeparator;

	echo "Configuring for IOS arm64 build";
	cd ${LIBBITCOIN_SYSTEM_DIR_SOURCES_WITH_NAME};

	./autogen.sh;
	./configure \
		--host=${ARCH} \
		--prefix=${LIBBITCOIN_SYSTEM_PREFIX_IOS_ARM64} \
		--enable-static \
		--disable-shared \
		--with-boost=${BOOST_PREFIX_IOS} \
		--with-icu=${ICU_PREFIX_IOS} \
		--with-tests=no \
		--with-examples=no;

	echo "Libbitcoin configuring finished for iOS arm64";
	mEchoSeparator;
}

function mLibbitcoinSystemBuildForIOS_ARM64() {

	cd ${LIBBITCOIN_SYSTEM_DIR_SOURCES_WITH_NAME};
	make -j8;
	make install;
	echo "Libbitcoin built successfully for iOS arm64.";
	mEchoSeparator;
}


# -----------------------------------
# Run script

mLibbitcoinSystemEchoEnvironmentForIOS_ARM64;
mLibbitcoinSystemCleanForIOS_ARM64;
mLibbitcoinSystemGetSources;
mLibbitcoinSystemConfigureForIOS_ARM64;
mLibbitcoinSystemBuildForIOS_ARM64;
