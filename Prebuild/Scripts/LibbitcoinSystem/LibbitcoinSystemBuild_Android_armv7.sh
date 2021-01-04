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

export secp256k1_CFLAGS="-I${SECP256K1_PREFIX_ANDROID_ARMV7}/include";
export secp256k1_LIBS="-L${SECP256K1_PREFIX_ANDROID_ARMV7}/lib -lsecp256k1";


# -----------------------------------
# Functionality

function mLibbitcoinSystemEchoEnvironmentForAndroid_ARMV7() {

	mEchoSeparator;
	echo "LIBBITCOIN_VERSION_NAME: ${LIBBITCOIN_SYSTEM_VERSION_NAME}";
	echo "LIBBITCOIN_DIR_SCRIPTS: ${LIBBITCOIN_SYSTEM_DIR_SCRIPTS}";
	echo "LIBBITCOIN_DIR_BUILDS: ${LIBBITCOIN_SYSTEM_DIR_BUILDS}";
	echo "LIBBITCOIN_DIR_DOWNLOADS: ${LIBBITCOIN_SYSTEM_DIR_DOWNLOADS}";
	echo "LIBBITCOIN_DIR_SOURCES: ${LIBBITCOIN_SYSTEM_DIR_SOURCES}";
	echo "LIBBITCOIN_DIR_SOURCES_WITH_NAME: ${LIBBITCOIN_SYSTEM_DIR_SOURCES_WITH_NAME}";
	echo "LIBBITCOIN_URL_GITHUB: ${LIBBITCOIN_SYSTEM_URL_GITHUB}";
	echo "LIBBITCOIN_SYSTEM_PREFIX_ANDROID_ARMV7: ${LIBBITCOIN_SYSTEM_PREFIX_ANDROID_ARMV7}";
	mEchoSeparator;
}

function mLibbitcoinSystemCleanForAndroid_ARMV7() {

	mCleanDir ${LIBBITCOIN_SYSTEM_DIR_SOURCES_WITH_NAME};
	mCleanDir ${LIBBITCOIN_SYSTEM_PREFIX_ANDROID_ARMV7};
	mEchoSeparator
}

function mLibbitcoinSystemConfigureForAndroid_ARMV7() {

	source ${A_DIR_SCRIPTS}/Global/GlobalEnvironment_Android_armv7.sh;
	mEchoSeparator;

	echo "Configuring for Android armv7 build";
	cd ${LIBBITCOIN_SYSTEM_DIR_SOURCES_WITH_NAME};

	./autogen.sh;
	./configure \
	    --prefix="${LIBBITCOIN_SYSTEM_PREFIX_ANDROID_ARMV7}" \
	    --host="${TARGET}" \
	    --enable-static \
	    --disable-shared \
	    --with-boost=${BOOST_PREFIX_ANDROID_ARMV7} \
		--with-icu=${ICU_PREFIX_ANDROID_ARMV7} \
		--with-tests=no \
		--with-examples=no;

	echo "Libbitcoin configuring finished for Android armv7";
	mEchoSeparator;
}

function mLibbitcoinSystemBuildForAndroid_ARMV7() {

	cd ${LIBBITCOIN_SYSTEM_DIR_SOURCES_WITH_NAME};
	make -j8;
	make install;
	echo "Libbitcoin built successfully for Android armv7.";
	mEchoSeparator;
}


# -----------------------------------
# Run script

mLibbitcoinSystemEchoEnvironmentForAndroid_ARMV7;
mLibbitcoinSystemCleanForAndroid_ARMV7;
mLibbitcoinSystemGetSources;
mLibbitcoinSystemConfigureForAndroid_ARMV7;
mLibbitcoinSystemBuildForAndroid_ARMV7;
