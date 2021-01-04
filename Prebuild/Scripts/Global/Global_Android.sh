#!/usr/bin/env bash


# -----------------------------------
# Functionality

function mRanlib() {

	echo "Doing ranlib";

	local CMD_RANLIB=$1;
	local DIR=$2;
	local LIBRARIES=$(ls ${DIR} | grep "\.a");

	for i in ${LIBRARIES}; do
		${CMD_RANLIB} ${DIR}/$i;
		echo "${DIR}/$i";
	done
}