#!/usr/bin/env bash


# -----------------------------------
# Functionality

function mSecp256k1LoadSourcesFromGithub() {

	echo "Loading sources from ${SECP256K1_URL_GITHUB}";
	git clone \
		--single-branch \
		--branch ${SECP256K1_VERSION_NAME} \
		${SECP256K1_URL_GITHUB} \
		${SECP256K1_DIR_SOURCES};
}

function mSecp256k1GetSources() {

	mSecp256k1LoadSourcesFromGithub;
	mEchoSeparator;
}

function mSecp256k1Build() {

	cd ${SECP256K1_DIR_SOURCES};
	make -j8;
	make install;
	mEchoSeparator;
}
