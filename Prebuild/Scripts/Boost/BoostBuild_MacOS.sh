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
		source ${A_PREBUILT_LIBS_ROOT}/Scripts/Boost/BoostEnvironment.sh
	fi;
fi;

# -----------------------------------
# Variables

VALUE_MACOS_VERSION="10.14";
VALUE_MACOS_MIN_VERSION="10.8";
VALUE_CXXFLAGS="${A_CXXFLAG_STD} -arch x86_64 -fvisibility=hidden -fvisibility-inlines-hidden -stdlib=libc++ -ftemplate-depth=512";
VALUE_LINKFLAGS="${A_CXXFLAG_STD} -stdlib=libc++";
VALUE_LIBRARIES="";


# -----------------------------------
# Functionality

function mBoostEchoEnvironmentMacOS() {

	mEchoSeparator;
	echo "BOOST_VERSION: ${BOOST_VERSION}";
	echo "BOOST_LIBRARIES: ${BOOST_LIBRARIES[*]}";
	echo "BOOST_DIR_SCRIPTS: ${BOOST_DIR_SCRIPTS}";
	echo "BOOST_DIR_BUILDS: ${BOOST_DIR_BUILDS}";
	echo "BOOST_DIR_DOWNLOADS: ${BOOST_DIR_DOWNLOADS}";
	echo "BOOST_DIR_SOURCES: ${BOOST_DIR_SOURCES}";
	echo "BOOST_LOAD_URL: ${BOOST_LOAD_URL}";
	echo "BOOST_PREFIX_MACOS: ${BOOST_PREFIX_MACOS}";
	echo "ICU_PREFIX_MACOS: ${ICU_PREFIX_MACOS}";
	mEchoSeparator;
}

function mBoostCleanForMacOS() {

	mCleanDir ${BOOST_DIR_SOURCES_WITH_NAME};
	mCleanDir ${BOOST_PREFIX_MACOS};
	mEchoSeparator
}

function mBoostConfigureForMacOS() {

	cd ${BOOST_DIR_SOURCES_WITH_NAME};
	./bootstrap.sh \
		macosx-version=${VALUE_MACOS_VERSION} \
		macosx-version-min=${VALUE_MACOS_MIN_VERSION} \
		--with-icu=${ICU_PREFIX_MACOS};

	echo "Boost configured.";
	mEchoSeparator;
}

function mBoostBuildForMacOS() {

	cd ${BOOST_DIR_SOURCES_WITH_NAME};
	mBoostLibraries;
	./b2 \
		${BOOST_BUILD_MODE} \
		toolset=darwin \
		variant=release \
		cxxflags="${VALUE_CXXFLAGS}" \
		linkflags="${VALUE_LINKFLAGS}" \
		optimization=speed \
		${VALUE_LIBRARIES} \
		--reconfigure boost.locale.iconv=off boost.locale.icu=on \
		--prefix=${BOOST_PREFIX_MACOS} \
		--stagedir=${BOOST_PREFIX_MACOS} \
		-sICU_PATH=${ICU_PREFIX_MACOS} \
		-link=static;

	echo "Boost built successfully.";
	mEchoSeparator;
}


# -----------------------------------
# Run script

mBoostEchoEnvironmentMacOS;
mBoostCleanForMacOS;
mBoostGetSources;
mBoostUnzipSources;
mBoostConfigureForMacOS;
mBoostBuildForMacOS;
