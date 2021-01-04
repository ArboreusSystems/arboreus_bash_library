#!/usr/bin/env bash


# -----------------------------------
# Includes

source ${A_PREBUILT_LIBS_ROOT}/Scripts/Global/GlobalFunctionality.sh;


# -----------------------------------
# Global Variables

A_DIR_SCRIPTS="${A_PREBUILT_LIBS_ROOT}/Scripts";
A_DIR_DOWNLOADS="${A_PREBUILT_LIBS_ROOT}/Downloads";
A_DIR_BUILDS="${A_PREBUILT_LIBS_ROOT}/Builds";
A_DIR_SOURCES="${A_PREBUILT_LIBS_ROOT}/Sources";
A_DIR_EXTENSIONS="${A_PREBUILT_LIBS_ROOT}/Extensions";
A_DIR_HANDLERS="${A_PREBUILT_LIBS_ROOT}/Handlers";


# -----------------------------------
# Compiler Variables

A_CXXFLAG_STD="-std=c++11";
A_CXXFLAG_STDLIB="-stdlib=libc++";
A_IPHONE_MIN="11.0";
A_ANDROID_NDK_ROOT="/Users/alexandr/Tools/android/sdk/ndk/21.3.6528147";
A_ANDROID_API="21";
A_CORE_NUMBER=$(getconf _NPROCESSORS_ONLN);


# -----------------------------------
# Secp256k1 variables

SECP256K1_VERSION_NAME="version6";
SECP256K1_DIR_SCRIPTS="${A_DIR_SCRIPTS}/Secp256k1";
SECP256K1_DIR_BUILDS="${A_DIR_BUILDS}/Secp256k1";
SECP256K1_DIR_SOURCES="${A_DIR_SOURCES}/Secp256k1/${SECP256K1_VERSION_NAME}";
SECP256K1_URL_GITHUB="https://github.com/libbitcoin/secp256k1.git";

SECP256K1_PREFIX_MACOS="${SECP256K1_DIR_BUILDS}/macos";

SECP256K1_PREFIX_IOS="${SECP256K1_DIR_BUILDS}/ios";
SECP256K1_PREFIX_IOS_ARM64="${SECP256K1_PREFIX_IOS}/arm64";
SECP256K1_PREFIX_IOS_X86_64="${SECP256K1_PREFIX_IOS}/x86_64";

SECP256K1_PREFIX_ANDROID="${SECP256K1_DIR_BUILDS}/android";
SECP256K1_PREFIX_ANDROID_ARM64="${SECP256K1_PREFIX_ANDROID}/arm64";
SECP256K1_PREFIX_ANDROID_ARMV7="${SECP256K1_PREFIX_ANDROID}/armv7";
SECP256K1_PREFIX_ANDROID_X86="${SECP256K1_PREFIX_ANDROID}/x86";
SECP256K1_PREFIX_ANDROID_X86_64="${SECP256K1_PREFIX_ANDROID}/x86_64";


# -----------------------------------
# ICU variables

ICU_VERSION="55.2";
ICU_VERSION_STRING="55-2";
ICU_VERSION_NAME="icu-release-${ICU_VERSION_STRING}";
ICU_DIR_SCRIPTS="${A_DIR_SCRIPTS}/ICU";
ICU_DIR_BUILDS="${A_DIR_BUILDS}/ICU";
ICU_DIR_SOURCES="${A_DIR_SOURCES}/ICU";
ICU_DIR_SOURCES_WITH_VERSION="${ICU_DIR_SOURCES}/${ICU_VERSION_NAME}";
ICU_DIR_SOURCES_MACOS="${ICU_DIR_SOURCES}/${ICU_VERSION_NAME}_macos";
ICU_DIR_SOURCES_IOS_ARM64="${ICU_DIR_SOURCES}/${ICU_VERSION_NAME}_ios_arm64";
ICU_DIR_SOURCES_IOS_X86_64="${ICU_DIR_SOURCES}/${ICU_VERSION_NAME}_ios_x86_64";
ICU_DIR_SOURCES_ANDROID_ARM64="${ICU_DIR_SOURCES}/${ICU_VERSION_NAME}_android_arm64";
ICU_DIR_SOURCES_ANDROID_ARMV7="${ICU_DIR_SOURCES}/${ICU_VERSION_NAME}_android_armv7";
ICU_DIR_SOURCES_ANDROID_X86="${ICU_DIR_SOURCES}/${ICU_VERSION_NAME}_android_x86";
ICU_DIR_SOURCES_ANDROID_X86_64="${ICU_DIR_SOURCES}/${ICU_VERSION_NAME}_android_x86_64";
ICU_DIR_DOWNLOADS="${A_DIR_DOWNLOADS}/ICU";
ICU_ARCHIVE_NAME="release-${ICU_VERSION_STRING}.tar.gz";
ICU_ARCHIVE_PATH="${ICU_DIR_DOWNLOADS}/${ICU_ARCHIVE_NAME}";
ICU_URL_ARCHIVE="https://github.com/unicode-org/icu/archive/${ICU_ARCHIVE_NAME}";
ICU_URL_GITHUB="https://github.com/unicode-org/icu.git";

ICU_PREFIX_MACOS="${ICU_DIR_BUILDS}/macos";

ICU_PREFIX_IOS="${ICU_DIR_BUILDS}/ios";
ICU_PREFIX_IOS_ARM64="${ICU_PREFIX_IOS}/arm64";
ICU_PREFIX_IOS_X86_64="${ICU_PREFIX_IOS}/x86_64";

ICU_PREFIX_ANDROID="${ICU_DIR_BUILDS}/android";
ICU_PREFIX_ANDROID_ARM64="${ICU_PREFIX_ANDROID}/arm64";
ICU_PREFIX_ANDROID_ARMV7="${ICU_PREFIX_ANDROID}/armv7";
ICU_PREFIX_ANDROID_X86="${ICU_PREFIX_ANDROID}/x86";
ICU_PREFIX_ANDROID_X86_64="${ICU_PREFIX_ANDROID}/x86_64";


# -----------------------------------
# Boost variables

BOOST_VERSION="1.62.0";
BOOST_VERSION_STRING="1_62_0";
BOOST_VERSION_NAME="boost_${BOOST_VERSION_STRING}"
BOOST_DIR_SCRIPTS="${A_DIR_SCRIPTS}/Boost";
BOOST_DIR_BUILDS="${A_DIR_BUILDS}/Boost";
BOOST_DIR_DOWNLOADS="${A_DIR_DOWNLOADS}/Boost";
BOOST_DIR_SOURCES="${A_DIR_SOURCES}/Boost";
BOOST_DIR_SOURCES_WITH_NAME="${BOOST_DIR_SOURCES}/${BOOST_VERSION_NAME}";
BOOST_ARCHIVE_NAME="${BOOST_VERSION_NAME}.tar.bz2";
BOOST_ARCHIVE_PATH="${BOOST_DIR_DOWNLOADS}/${BOOST_ARCHIVE_NAME}";
BOOST_LOAD_URL="http://sourceforge.net/projects/boost/files/boost/${BOOST_VERSION}/${BOOST_ARCHIVE_NAME}/download";
BOOST_BUILD_MODE="install";
#BOOST_BUILD_MODE="stage";
#BOOST_LIBRARIES=("log");
BOOST_LIBRARIES=( \
	"atomic" "chrono" "date_time" "filesystem" "iostreams" "locale" \
	"log" "program_options" "regex" "system" "test" "thread" \
);

BOOST_PREFIX_MACOS="${BOOST_DIR_BUILDS}/macos";

BOOST_PREFIX_IOS="${BOOST_DIR_BUILDS}/ios";
BOOST_PREFIX_IOS_ARM64="${BOOST_PREFIX_IOS}/arm64";
BOOST_PREFIX_IOS_X86_64="${BOOST_PREFIX_IOS}/x86_64";

BOOST_PREFIX_ANDROID="${BOOST_DIR_BUILDS}/android";
BOOST_PREFIX_ANDROID_ARM64="${BOOST_PREFIX_ANDROID}/arm64";
BOOST_PREFIX_ANDROID_ARMV7="${BOOST_PREFIX_ANDROID}/armv7";
BOOST_PREFIX_ANDROID_X86="${BOOST_PREFIX_ANDROID}/x86";
BOOST_PREFIX_ANDROID_X86_64="${BOOST_PREFIX_ANDROID}/x86_64";


# -----------------------------------
# Libbitcoin variables

LIBBITCOIN_SYSTEM_VERSION_NAME="GithubCurrentSources";
LIBBITCOIN_SYSTEM_DIR_SCRIPTS="${A_DIR_SCRIPTS}/LibbitcoinSystem";
LIBBITCOIN_SYSTEM_DIR_BUILDS="${A_DIR_BUILDS}/LibbitcoinSystem";
LIBBITCOIN_SYSTEM_DIR_DOWNLOADS="${A_DIR_DOWNLOADS}/LibbitcoinSystem";
LIBBITCOIN_SYSTEM_DIR_SOURCES="${A_DIR_SOURCES}/LibbitcoinSystem";
LIBBITCOIN_SYSTEM_DIR_SOURCES_WITH_NAME="${LIBBITCOIN_SYSTEM_DIR_SOURCES}/${LIBBITCOIN_SYSTEM_VERSION_NAME}";
LIBBITCOIN_SYSTEM_URL_GITHUB="https://github.com/libbitcoin/libbitcoin-system.git";

LIBBITCOIN_SYSTEM_PREFIX_MACOS="${LIBBITCOIN_SYSTEM_DIR_BUILDS}/macos";

LIBBITCOIN_SYSTEM_PREFIX_IOS="${LIBBITCOIN_SYSTEM_DIR_BUILDS}/ios";
LIBBITCOIN_SYSTEM_PREFIX_IOS_ARM64="${LIBBITCOIN_SYSTEM_PREFIX_IOS}/arm64";
LIBBITCOIN_SYSTEM_PREFIX_IOS_X86_64="${LIBBITCOIN_SYSTEM_PREFIX_IOS}/x86_64";

LIBBITCOIN_SYSTEM_PREFIX_ANDROID="${LIBBITCOIN_SYSTEM_DIR_BUILDS}/android";
LIBBITCOIN_SYSTEM_PREFIX_ANDROID_ARM64="${LIBBITCOIN_SYSTEM_PREFIX_ANDROID}/arm64";
LIBBITCOIN_SYSTEM_PREFIX_ANDROID_ARMV7="${LIBBITCOIN_SYSTEM_PREFIX_ANDROID}/armv7";
LIBBITCOIN_SYSTEM_PREFIX_ANDROID_X86="${LIBBITCOIN_SYSTEM_PREFIX_ANDROID}/x86";
LIBBITCOIN_SYSTEM_PREFIX_ANDROID_X86_64="${LIBBITCOIN_SYSTEM_PREFIX_ANDROID}/x86_64";