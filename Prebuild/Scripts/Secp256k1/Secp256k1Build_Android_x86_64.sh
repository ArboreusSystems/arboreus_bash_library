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

function mSecp256k1EchoEnvironmentForAndroid_x86_64() {

	mEchoSeparator;
	echo "SECP256K1_DIR_SCRIPTS: ${SECP256K1_DIR_SCRIPTS}";
	echo "SECP256K1_DIR_BUILDS: ${SECP256K1_DIR_BUILDS}";
	echo "SECP256K1_DIR_SOURCES: ${SECP256K1_DIR_SOURCES}";
	echo "SECP256K1_URL_GITHUB: ${SECP256K1_URL_GITHUB}";
	echo "SECP256K1_PREFIX_ANDROID_X86_64: ${SECP256K1_PREFIX_ANDROID_X86_64}";
	mEchoSeparator
}

function mSecp256k1CleanForAndroid_x86_64() {

	mCleanDir ${SECP256K1_DIR_SOURCES};
	mCleanDir ${SECP256K1_PREFIX_ANDROID_X86_64};
	mEchoSeparator;
}

function mSecp256k1ConfigureForAndroid_x86_64() {

	source ${A_DIR_SCRIPTS}/Global/GlobalEnvironment_Android_x86_64.sh;
	mEchoSeparator;

	echo "Configuring Secp256k1 for Android x86_64.";
	cd ${SECP256K1_DIR_SOURCES};
	./autogen.sh;
	./configure \
		--host=${TARGET} \
		--prefix=${SECP256K1_PREFIX_ANDROID_X86_64} \
		--enable-tests=no \
		--enable-shared=no \
		--enable-static=yes \
		--enable-module-recovery=yes;

	mEchoSeparator;
}


# -----------------------------------
# Run script

mSecp256k1EchoEnvironmentForAndroid_x86_64;
mSecp256k1CleanForAndroid_x86_64;
mSecp256k1GetSources;
mSecp256k1ConfigureForAndroid_x86_64;
mSecp256k1Build;