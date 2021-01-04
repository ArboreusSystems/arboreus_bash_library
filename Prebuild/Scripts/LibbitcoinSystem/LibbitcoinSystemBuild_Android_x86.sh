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

export secp256k1_CFLAGS="-I${SECP256K1_PREFIX_ANDROID_X86}/include";
export secp256k1_LIBS="-L${SECP256K1_PREFIX_ANDROID_X86}/lib -lsecp256k1";


# -----------------------------------
# Functionality

function mLibbitcoinSystemEchoEnvironmentForAndroid_X86() {

	mEchoSeparator;
	echo "LIBBITCOIN_VERSION_NAME: ${LIBBITCOIN_SYSTEM_VERSION_NAME}";
	echo "LIBBITCOIN_DIR_SCRIPTS: ${LIBBITCOIN_SYSTEM_DIR_SCRIPTS}";
	echo "LIBBITCOIN_DIR_BUILDS: ${LIBBITCOIN_SYSTEM_DIR_BUILDS}";
	echo "LIBBITCOIN_DIR_DOWNLOADS: ${LIBBITCOIN_SYSTEM_DIR_DOWNLOADS}";
	echo "LIBBITCOIN_DIR_SOURCES: ${LIBBITCOIN_SYSTEM_DIR_SOURCES}";
	echo "LIBBITCOIN_DIR_SOURCES_WITH_NAME: ${LIBBITCOIN_SYSTEM_DIR_SOURCES_WITH_NAME}";
	echo "LIBBITCOIN_URL_GITHUB: ${LIBBITCOIN_SYSTEM_URL_GITHUB}";
	echo "LIBBITCOIN_SYSTEM_PREFIX_ANDROID_X86: ${LIBBITCOIN_SYSTEM_PREFIX_ANDROID_X86}";
	mEchoSeparator;
}

function mLibbitcoinSystemCleanForAndroid_X86() {

	mCleanDir ${LIBBITCOIN_SYSTEM_DIR_SOURCES_WITH_NAME};
	mCleanDir ${LIBBITCOIN_SYSTEM_PREFIX_ANDROID_X86};
	mEchoSeparator
}

function mLibbitcoinSystemConfigureForAndroid_X86() {

	source ${A_DIR_SCRIPTS}/Global/GlobalEnvironment_Android_x86.sh;
	mEchoSeparator;

	echo "Configuring for Android X86 build";
	cd ${LIBBITCOIN_SYSTEM_DIR_SOURCES_WITH_NAME};

	./autogen.sh;
	./configure \
	    --prefix="${LIBBITCOIN_SYSTEM_PREFIX_ANDROID_X86}" \
	    --host="${TARGET}" \
	    --enable-static \
	    --disable-shared \
	    --with-boost=${BOOST_PREFIX_ANDROID_X86} \
		--with-icu=${ICU_PREFIX_ANDROID_X86} \
		--with-tests=no \
		--with-examples=no;

	echo "Libbitcoin configuring finished for Android X86";
	mEchoSeparator;
}

function mLibbitcoinSystemBuildForAndroid_X86() {

	cd ${LIBBITCOIN_SYSTEM_DIR_SOURCES_WITH_NAME};
	make -j8;
	make install;
	echo "Libbitcoin built successfully for Android X86.";
	mEchoSeparator;
}


# -----------------------------------
# Run script

mLibbitcoinSystemEchoEnvironmentForAndroid_X86;
mLibbitcoinSystemCleanForAndroid_X86;
mLibbitcoinSystemGetSources;
mLibbitcoinSystemConfigureForAndroid_X86;
mLibbitcoinSystemBuildForAndroid_X86;
