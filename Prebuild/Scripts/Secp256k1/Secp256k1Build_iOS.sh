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
		source ${A_PREBUILT_LIBS_ROOT}/Scripts/Global/Global_iOS.sh
		source ${A_PREBUILT_LIBS_ROOT}/Scripts/Secp256k1/Secp256k1Environment.sh
	fi;
fi;


# -----------------------------------
# Run script

mCleanDir ${SECP256K1_PREFIX_IOS};
${SECP256K1_DIR_SCRIPTS}/Secp256k1Build_iOS_arm64.sh;
${SECP256K1_DIR_SCRIPTS}/Secp256k1Build_iOS_x86_64.sh;
mCreateFat ${SECP256K1_PREFIX_IOS} ${SECP256K1_PREFIX_IOS_ARM64} ${SECP256K1_PREFIX_IOS_X86_64};
