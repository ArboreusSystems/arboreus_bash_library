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
		source ${A_PREBUILT_LIBS_ROOT}/Scripts/LibbitcoinSystem/LibbitcoinSystemEnvironment.sh
	fi;
fi;


# -----------------------------------
# Run script

${LIBBITCOIN_SYSTEM_DIR_SCRIPTS}/LibbitcoinSystemBuild_iOS_arm64.sh;
${LIBBITCOIN_SYSTEM_DIR_SCRIPTS}/LibbitcoinSystemBuild_iOS_x86_64.sh;

mCreateFat ${LIBBITCOIN_SYSTEM_PREFIX_IOS} \
	${LIBBITCOIN_SYSTEM_PREFIX_IOS_ARM64} \
	${LIBBITCOIN_SYSTEM_PREFIX_IOS_X86_64};