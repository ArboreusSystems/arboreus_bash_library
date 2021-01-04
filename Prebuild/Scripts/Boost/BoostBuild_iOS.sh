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
		source ${A_PREBUILT_LIBS_ROOT}/Scripts/Boost/BoostEnvironment.sh
	fi;
fi;


# -----------------------------------
# Run script

${BOOST_DIR_SCRIPTS}/BoostBuild_iOS_arm64.sh;
${BOOST_DIR_SCRIPTS}/BoostBuild_iOS_x86_64.sh;

mCreateFat ${BOOST_PREFIX_IOS} ${BOOST_PREFIX_IOS_ARM64} ${BOOST_PREFIX_IOS_X86_64};