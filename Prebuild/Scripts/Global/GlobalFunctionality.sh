#!/usr/bin/env bash


# -----------------------------------
# Functionality

function mCleanDir() {

	if [[ -d "$1" ]]; then
		rm -rf $1;
		mkdir -p $1;
		echo "Directory cleaned in $1";
	else
		mkdir -p $1;
		echo "Nothing to be cleaned in $1.";
	fi;
}

function mEchoSeparator() {

	echo ">>> ----------------------------------";
}

function mEchoError() {

	echo_separator;
	echo "ERROR! $1";
	echo_separator;
}
