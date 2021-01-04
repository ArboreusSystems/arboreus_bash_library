#!/usr/bin/env bash

# -----------------------------------
# Functionality

function mICULoadSourcesFromGithub() {

	echo "Loading ICU sources from ${ICU_URL_GITHUB}";
	git clone ${ICU_URL_GITHUB} ${ICU_DIR_SOURCES};
	mEchoSeparator;
}

function mICULoadSourcesFromArchive() {

	if [[ ! -f "${ICU_ARCHIVE_PATH}" ]]; then
		echo "Loading ICU archive from ${ICU_ARCHIVE_PATH}";
		curl --create-dirs -L ${ICU_URL_ARCHIVE} --output ${ICU_ARCHIVE_PATH};
	else
		echo "ICU archive already downloaded in ${ICU_ARCHIVE_PATH}";
	fi;

	if [[ -f "${ICU_ARCHIVE_PATH}" ]]; then
		if [[ ! -d "${ICU_DIR_SOURCES_WITH_VERSION}/icu4c" ]]; then
			echo "Extracting ICU archive to ${ICU_DIR_SOURCES}";
			mkdir -p ${ICU_DIR_SOURCES};
			tar -zxf ${ICU_ARCHIVE_PATH} --directory ${ICU_DIR_SOURCES};
		else
			echo "ICU archive already extracted";
		fi;
	else
		mEchoError "No ICU archive file.";
		exit 1;
	fi;
}

function mICUGetSources() {

	mICULoadSourcesFromArchive;
	mEchoSeparator;
}
