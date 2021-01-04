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
	fi;
fi;


# -----------------------------------
# Run script

${SECP256K1_DIR_SCRIPTS}/Secp256k1Build_Android_arm64.sh;
${SECP256K1_DIR_SCRIPTS}/Secp256k1Build_Android_armv7.sh;
${SECP256K1_DIR_SCRIPTS}/Secp256k1Build_Android_x86.sh;
${SECP256K1_DIR_SCRIPTS}/Secp256k1Build_Android_x86_64.sh;
