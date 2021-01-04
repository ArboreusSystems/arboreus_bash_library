#!/usr/bin/env bash


# -----------------------------------
# Functionality

function mBoostLoadFromArchive() {

	if [[ ! -f "${BOOST_ARCHIVE_PATH}" ]]; then
		echo "Loading ${BOOST_VERSION_NAME} from ${BOOST_LOAD_URL}";
		curl --create-dirs -L ${BOOST_LOAD_URL} --output ${BOOST_ARCHIVE_PATH};
	else
		echo "File ${BOOST_ARCHIVE_NAME} already loaded.";
	fi;
}

function mBoostGetSources() {

	mBoostLoadFromArchive;
	mEchoSeparator;
}

function mBoostUnzipSources() {

	if [[ -f "${BOOST_ARCHIVE_PATH}" ]]; then
		echo "Unzipping sources from ${BOOST_ARCHIVE_PATH}";
		mkdir -p ${BOOST_DIR_BUILDS};
		tar -xzf ${BOOST_ARCHIVE_PATH} --directory ${BOOST_DIR_SOURCES};
		echo "Boost sources unzipped for ${BOOST_VERSION_NAME}";
		mEchoSeparator;
	else
		mEchoError "No Boost archive for unzip.";
		exit 1;
	fi;
}

function mBoostLibraries() {

	for i in "${BOOST_LIBRARIES[@]}"
	do
		VALUE_LIBRARIES="--with-$i ${VALUE_LIBRARIES}";
	done;
}
