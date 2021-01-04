#!/usr/bin/env bash


# -----------------------------------
# Functionality

function mCreateFat() {

	echo "Creating fat library";

	local DIR_TARGET=$1;
	local DIR_ARM64=$2;
	local DIR_X86_64=$3;

	rm -rf ${DIR_TARGET}/include;
	mv ${DIR_ARM64}/include ${DIR_TARGET};
	mkdir -p ${DIR_TARGET}/lib;

	local LIBRARIES=$(ls ${DIR_ARM64}/lib | grep "\.a");
	for i in ${LIBRARIES}; do
		lipo \
			-create ${DIR_ARM64}/lib/$i ${DIR_X86_64}/lib/$i \
			-output ${DIR_TARGET}/lib/$i;
		lipo -info ${DIR_TARGET}/lib/$i;
	done

	rm -rf ${DIR_ARM64};
	rm -rf ${DIR_X86_64};
}