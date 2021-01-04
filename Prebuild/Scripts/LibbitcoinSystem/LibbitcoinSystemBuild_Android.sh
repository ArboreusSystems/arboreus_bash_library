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
# Run script

${LIBBITCOIN_SYSTEM_DIR_SCRIPTS}/LibbitcoinSystemBuild_Android_arm64.sh;
${LIBBITCOIN_SYSTEM_DIR_SCRIPTS}/LibbitcoinSystemBuild_Android_armv7.sh;
${LIBBITCOIN_SYSTEM_DIR_SCRIPTS}/LibbitcoinSystemBuild_Android_x86.sh;
${LIBBITCOIN_SYSTEM_DIR_SCRIPTS}/LibbitcoinSystemBuild_Android_x86_64.sh;