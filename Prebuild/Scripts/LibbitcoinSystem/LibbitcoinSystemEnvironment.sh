#!/usr/bin/env bash


# -----------------------------------
# Functionality

function mLibbitcoinSystemLoadSourcesFromGithub() {

	echo "Loading Libbitcoin sources from ${LIBBITCOIN_SYSTEM_URL_GITHUB}";
	git clone ${LIBBITCOIN_SYSTEM_URL_GITHUB} ${LIBBITCOIN_SYSTEM_DIR_SOURCES_WITH_NAME};
}

function mLibbitcoinSystemGetSources() {

	mLibbitcoinSystemLoadSourcesFromGithub;
	mEchoSeparator;
}
