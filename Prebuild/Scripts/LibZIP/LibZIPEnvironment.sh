#!/usr/bin/env bash


# -----------------------------------
# Functionality

function mLibZIPLoadFromOffsite() {

	if [[ ! -f "${LIBZIP_ARCHIVE_PATH}" ]]; then
		echo "Loading ${LIBZIP_VERSION_NAME} from ${LIBZIP_ARCHIVE_URL}";
		curl --create-dirs -L ${LIBZIP_ARCHIVE_URL} --output ${LIBZIP_ARCHIVE_PATH};
	else
		echo "File ${LIBZIP_ARCHIVE_NAME} already loaded.";
	fi;
}

function mLibZIPGetSources() {

	mLibZIPLoadFromOffsite;
	mEchoSeparator;
}

function mLibZIPUnzipSources() {

	if [[ -f "${LIBZIP_ARCHIVE_PATH}" ]]; then
		echo "Unzipping sources from ${LIBZIP_ARCHIVE_PATH}";
		mkdir -p ${LIBZIP_DIR_SOURCES};
		tar -xzf ${LIBZIP_ARCHIVE_PATH} --directory ${LIBZIP_DIR_SOURCES};
		echo "LibZIP sources unzipped for ${LIBZIP_VERSION_NAME}";
		mEchoSeparator;
	else
		mEchoError "No LibZIP archive for unzip.";
		exit 1;
	fi;
}