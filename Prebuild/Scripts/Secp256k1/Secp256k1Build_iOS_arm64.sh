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
		source ${A_PREBUILT_LIBS_ROOT}/Scripts/Secp256k1/Secp256k1Environment.sh
	fi;
fi;


# -----------------------------------
# Functionality

function mSecp256k1EchoEnvironmentForIOS_ARM64() {

	mEchoSeparator;
	echo "SECP256K1_DIR_SCRIPTS: ${SECP256K1_DIR_SCRIPTS}";
	echo "SECP256K1_DIR_BUILDS: ${SECP256K1_DIR_BUILDS}";
	echo "SECP256K1_DIR_SOURCES: ${SECP256K1_DIR_SOURCES}";
	echo "SECP256K1_URL_GITHUB: ${SECP256K1_URL_GITHUB}";
	echo "SECP256K1_PREFIX_IOS_ARM64: ${SECP256K1_PREFIX_IOS_ARM64}";
	mEchoSeparator
}

function mSecp256k1CleanForIOS_ARM64() {

	mCleanDir ${SECP256K1_DIR_SOURCES};
	mCleanDir ${SECP256K1_PREFIX_IOS_ARM64};
	mEchoSeparator;
}

function mSecp256k1ConfigureForIOS_ARM64() {

	export ARCH=arm64;
	export PREFIX=${SECP256K1_PREFIX_IOS_ARM64};
	source ${A_PREBUILT_LIBS_ROOT}/Scripts/Global/GlobalEnvironment_iOS.sh;
	mEchoSeparator;

	echo "Configuring for IOS_ARM64 build";
	cd ${SECP256K1_DIR_SOURCES};
	./autogen.sh;
	./configure \
		--host=${ARCH} \
		--prefix=${SECP256K1_PREFIX_IOS_ARM64} \
		--enable-tests=no \
		--enable-shared=no \
		--enable-static=yes \
		--enable-module-recovery=yes;

	mEchoSeparator;
}


# -----------------------------------
# Run script

mSecp256k1EchoEnvironmentForIOS_ARM64;
mSecp256k1CleanForIOS_ARM64;
mSecp256k1GetSources;
mSecp256k1ConfigureForIOS_ARM64;
mSecp256k1Build;