#!/usr/bin/env bash
#
# build_libzip.sh — build libzip as a STATIC library (libzip.a) for iOS,
# macOS and Android. No shared libraries (.so/.dylib), no frameworks,
# no XCFramework.
#
# Usage:
#   ./build_libzip.sh [ios] [macos] [android] [all] [--clean]
#                     [--out-dir <path>] [--install-dir <path>]
#   ./build_libzip.sh check-app <path-to-final-app-binary>
#
#   ios        iOS device (arm64) + iOS simulator (arm64)          [macOS host]
#   macos      macOS (arm64, Apple Silicon only)                   [macOS host]
#   android    Android arm64-v8a + armeabi-v7a                     [macOS/Linux host]
#   all        everything the current host can build (default)
#   --clean    remove previous build/install directories first
#   --out-dir <path>, --out-dir=<path>, -o <path>
#              build output directory (download, src, build, install);
#              overrides __A_OUT_DIR. Relative paths are taken from the
#              current directory. Default: ./libzip-build
#   --install-dir <path>, --install-dir=<path>
#              where the finished libraries go (one subfolder per platform:
#              ios, ios-simulator, macos, android/<abi>); overrides
#              __A_INSTALL_DIR. Default: <out-dir>/install. With a custom
#              install directory, --clean removes only those subfolders.
#   check-app  check the linker hardening of your FINAL app binary
#              (Android .so: RELRO, BIND_NOW, noexecstack, 16 KB pages;
#               iOS/macOS Mach-O: PIE, no executable stack)
#
# Settings (environment variables, with defaults):
#   __A_LIBZIP_VERSION   1.11.4
#   __A_LIBZIP_SHA256    SHA-256 of libzip-<version>.tar.xz. Pinned for
#                        1.11.4; REQUIRED for any other version.
#   __A_BUILD_TYPE       Release
#   __A_OUT_DIR          ./libzip-build  (the --out-dir option overrides it)
#   __A_INSTALL_DIR      <out-dir>/install  (the --install-dir option overrides it)
#   __A_IOS_MIN          13.0
#   __A_MACOS_MIN        11.0
#   __A_ANDROID_API      24
#   __A_ANDROID_ABIS     "arm64-v8a armeabi-v7a"  (x86/x86_64 are not supported)
#   ANDROID_HOME         Android SDK path; the NDK is taken from
#                        $ANDROID_HOME/ndk/<version> (see the top of this script)
#   __A_ANDROID_NDK_VERSION  NDK version folder under $ANDROID_HOME/ndk
#                        (empty: the newest installed NDK)
#   __A_ANDROID_NDK      explicit NDK path; overrides ANDROID_HOME
#   __A_OPENSSL_ROOT     base folder of the prebuilt OpenSSL — top of this script
#   __A_OPENSSL_IOS / __A_OPENSSL_IOS_SIM / __A_OPENSSL_MACOS
#                        per-platform OpenSSL folders (default: under the root)
#   __A_OPENSSL_ANDROID  Android OpenSSL folder; holds one subfolder per ABI
#   __A_OPENSSL_ALLOWED_SERIES  "3.5 4.0"  OpenSSL release series accepted
#   __A_OPENSSL_CHECK    strict = OpenSSL version/hardening problems stop the
#                        build (default); warn = only print warnings
#   __A_JOBS             number of CPU cores
#   __A_HARDENING        1 = compile with security hardening flags (default), 0 = off
#
# Source integrity:
#   The libzip .tar.xz is downloaded over HTTPS only (TLS 1.2+) and its
#   SHA-256 is checked before it is used: after download, on every run for a
#   cached tarball, and the extracted tree is re-created if it was not made
#   from a verified tarball. Archive entries are checked for path traversal.
#   There is no way to skip the check.
#
# Hardening (__A_HARDENING=1). Each flag is test-compiled for every target
# architecture first and dropped if that compiler doesn't accept it.
#   All platforms:
#     -fstack-protector-strong          stack canaries
#     -D_FORTIFY_SOURCE=3 (or 2)        bounds-checked libc calls (memcpy, ...).
#                                       Level 3 also checks buffers whose size
#                                       is only known at run time (malloc'd).
#                                       It is used only when a probe shows the
#                                       platform's C library really enforces it;
#                                       otherwise the build falls back to 2.
#                                       Only takes effect in optimised builds.
#     -ftrivial-auto-var-init=zero      no uninitialised stack variables
#     -fno-strict-overflow              no UB-based removal of overflow checks
#     -fno-delete-null-pointer-checks   keep NULL checks the optimizer could drop
#     -fvisibility=hidden               smaller exported symbol surface
#     -Wformat -Werror=format-security  reject unsafe printf-style calls
#     -fPIC                             position-independent code (for PIE/ASLR)
#   Android:
#     -fstack-clash-protection          stack probing (arm64)
#     -mbranch-protection=standard      PAC + BTI return/jump protection (arm64)
#   iOS / macOS (arm64 only):
#     -fstack-clash-protection          where the Apple compiler accepts it
#
# Prebuilt OpenSSL checks (before anything is downloaded or built):
#   - version series is in __A_OPENSSL_ALLOWED_SERIES (supported releases)
#   - libcrypto.a was compiled with stack protection and FORTIFY
#   - libcrypto.a is for the right architecture (and Apple platform)
#   - Android arm64: BTI/PAC notes (warning only)
#
# App-level linker hardening: libzip.a is a static library and cannot set the
# final binary's linker flags. Your Qt/Xcode/Gradle build must keep PIE,
# RELRO, BIND_NOW, noexecstack and (Android) 16 KB page alignment. Each
# install folder gets a LINKING.txt with the exact flags; check the final
# binary with: ./build_libzip.sh check-app <binary>
#
# Output (static library + headers only):
#   $__A_OUT_DIR/install/ios/                    lib/libzip.a  include/zip.h zipconf.h
#   $__A_OUT_DIR/install/ios-simulator/          (arm64)
#   $__A_OUT_DIR/install/macos/                  (arm64)
#   $__A_OUT_DIR/install/android/arm64-v8a/      (one subfolder per ABI)
#   $__A_OUT_DIR/install/android/armeabi-v7a/
#   plus HARDENING.txt (flags, OpenSSL used) and LINKING.txt in each.
#   Build trees use the same layout under $__A_OUT_DIR/build/.
#
# Dependencies:
#   zlib     the system zlib is used; link your app with -lz
#            (iOS/macOS: libz.tbd; Android: "z").
#   OpenSSL  used for zip encryption (AES) on EVERY platform. You supply a
#            prebuilt STATIC OpenSSL per platform/arch; set the paths at the
#            top of this script. Each iOS/macOS folder must contain:
#              include/openssl/evp.h
#              lib/libcrypto.a          (libssl.a is optional, not needed)
#            Android: the same, inside one subfolder per ABI, e.g.
#              .../Android/arm64-v8a/include/openssl/evp.h
#              .../Android/arm64-v8a/lib/libcrypto.a
#            Link your app with the same libcrypto.a as libzip.a.

set -euo pipefail

# ============================================================================
#  Android NDK — found through the Android SDK in ANDROID_HOME:
#    1. __A_ANDROID_NDK, if set (explicit NDK path, overrides everything)
#    2. $ANDROID_HOME/ndk/<__A_ANDROID_NDK_VERSION>, if a version is set
#    3. the newest NDK in $ANDROID_HOME/ndk/ (or $ANDROID_HOME/ndk-bundle)
#  If ANDROID_HOME is not set, the Android Studio default SDK location is
#  used: $HOME/Library/Android/sdk (macOS) or $HOME/Android/Sdk (Linux).
#  The NDK path must not contain spaces (the NDK does not support them).
#  Example:  export ANDROID_HOME="$HOME/Library/Android/sdk"
# ============================================================================
__A_ANDROID_HOME="${ANDROID_HOME:-}"
__A_ANDROID_NDK_VERSION="${__A_ANDROID_NDK_VERSION:-}"   # e.g. 27.2.12479018
__A_ANDROID_NDK="${__A_ANDROID_NDK:-}"                   # explicit path (optional)
__A_ANDROID_NDK_SOURCE=""                                # how the NDK was found

# ============================================================================
#  OpenSSL paths — EDIT THESE to point at your prebuilt static OpenSSL.
#  iOS/macOS: each folder must contain include/openssl/ and lib/libcrypto.a,
#  built for that platform and architecture.
# ============================================================================
__A_OPENSSL_ROOT="${__A_OPENSSL_ROOT:-$HOME/Tools/OpenSSL/Build}"
__A_OPENSSL_IOS="${__A_OPENSSL_IOS:-${__A_OPENSSL_ROOT}/ios}"
__A_OPENSSL_IOS_SIM="${__A_OPENSSL_IOS_SIM:-${__A_OPENSSL_ROOT}/ios-simulator}"
__A_OPENSSL_MACOS="${__A_OPENSSL_MACOS:-${__A_OPENSSL_ROOT}/macos}"
__A_OPENSSL_ANDROID="${__A_OPENSSL_ANDROID:-${__A_OPENSSL_ROOT}/android}"

# -------------------------
# Settings
__A_LIBZIP_VERSION="${__A_LIBZIP_VERSION:-1.11.4}"
__A_LIBZIP_SHA256="${__A_LIBZIP_SHA256:-}"
__A_BUILD_TYPE="${__A_BUILD_TYPE:-Release}"
__A_OUT_DIR="${__A_OUT_DIR:-$(pwd)/libzip-build}"
__A_IOS_MIN="${__A_IOS_MIN:-13.0}"
__A_MACOS_MIN="${__A_MACOS_MIN:-11.0}"
__A_ANDROID_API="${__A_ANDROID_API:-24}"
__A_ANDROID_ABIS="${__A_ANDROID_ABIS:-arm64-v8a armeabi-v7a}"
__A_JOBS="${__A_JOBS:-$(getconf _NPROCESSORS_ONLN 2>/dev/null || echo 4)}"
__A_HARDENING="${__A_HARDENING:-1}"
# Supported OpenSSL release series as of 2026-11: 3.5 (LTS, to 2030-04-08)
# and 4.0 (to 2027-05-14). 3.0, 3.3, 3.4 and 3.6 are end-of-life.
__A_OPENSSL_ALLOWED_SERIES="${__A_OPENSSL_ALLOWED_SERIES:-3.5 4.0}"
__A_OPENSSL_CHECK="${__A_OPENSSL_CHECK:-strict}"

# Known-good SHA-256 of the official release tarballs (.tar.xz).
# 1.11.4: matches the hash published by openSUSE (pool/libzip) and the MD5
# published by Debian/Ubuntu for the same file.
if [[ -z "${__A_LIBZIP_SHA256}" ]]; then
    case "${__A_LIBZIP_VERSION}" in
        1.11.4) __A_LIBZIP_SHA256="8a247f57d1e3e6f6d11413b12a6f28a9d388de110adc0ec608d893180ed7097b" ;;
    esac
fi

__A_TARBALL_NAME="libzip-${__A_LIBZIP_VERSION}.tar.xz"
__A_SRC_URL="https://github.com/nih-at/libzip/releases/download/v${__A_LIBZIP_VERSION}/${__A_TARBALL_NAME}"
__A_INSTALL_DIR="${__A_INSTALL_DIR:-}"   # empty: <out-dir>/install
# __A_DL_DIR, __A_SRC_DIR, __A_BUILD_ROOT and __A_INSTALL_ROOT are derived
# by fSetOutDir / fSetInstallDir (see Helpers), also after --out-dir and
# --install-dir.

__A_HOST_OS="$(uname -s)"

# -------------------------
# Helpers

# ------------------------------
# @description Print a highlighted progress message.
# @arg $@ string Message text.
# @stdout The formatted message.
# @exitcode 0 Always.
fLog()  { printf '\n\033[1;34m==> %s\033[0m\n' "$*"; }

# ------------------------------
# @description Print a warning message.
# @arg $@ string Warning text.
# @stderr The formatted warning.
# @exitcode 0 Always.
fWarn() { printf '\033[1;33mwarning:\033[0m %s\n' "$*" >&2; }

# ------------------------------
# @description Print an error message and stop the script.
# @arg $@ string Error text.
# @stderr The formatted error.
# @exitcode 1 Always; exits the whole script.
fDie()  { printf '\033[1;31merror:\033[0m %s\n' "$*" >&2; exit 1; }

# ------------------------------
# @description Print the usage text taken from the header comment of this
#  script, then exit.
# @noargs
# @stdout Usage text.
# @exitcode 0 Always; exits the whole script.
fUsage() { sed -n '3,/^set -euo/p' "$0" | sed '$d' | sed 's/^# \{0,1\}//'; exit 0; }

# ------------------------------
# @description Check that a required command is available in PATH.
# @arg $1 string Command name.
# @exitcode 0 If the command is found.
# @exitcode 1 If the command is missing (exits the script via fDie).
fNeed() { command -v "$1" >/dev/null 2>&1 || fDie "'$1' not found in PATH"; }

# ------------------------------
# @description Turn a directory path into a clean absolute path: relative
#  paths are taken from the current directory and trailing slashes removed.
#  The directory is not created here.
# @arg $1 string Directory path.
# @arg $2 string What the directory is for, used in error messages.
# @stdout The absolute path.
# @exitcode 0 If the path is usable.
# @exitcode 1 If the path is empty or "/" (exits the script via fDie).
fAbsDir() {
    local __A_DIR="$1"
    [[ -n "${__A_DIR}" ]] || fDie "$2 must not be empty"
    [[ "${__A_DIR}" == /* ]] || __A_DIR="$(pwd)/${__A_DIR}"
    while [[ "${__A_DIR}" == */ && "${__A_DIR}" != "/" ]]; do
        __A_DIR="${__A_DIR%/}"
    done
    [[ "${__A_DIR}" != "/" ]] || fDie "$2 must not be '/'"
    printf '%s' "${__A_DIR}"
}

# ------------------------------
# @description Set the build output directory and every path derived from it.
#  The install directory follows it (<out>/install) unless a custom one was
#  set with fSetInstallDir, in either order.
# @arg $1 string Output directory path.
# @set __A_OUT_DIR string Absolute output directory.
# @set __A_DL_DIR string Download folder (<out>/download).
# @set __A_SRC_DIR string Extracted source folder (<out>/src/libzip-<version>).
# @set __A_BUILD_ROOT string Build trees (<out>/build).
# @set __A_INSTALL_ROOT string Installed results (custom or <out>/install).
# @exitcode 0 If the path is usable.
# @exitcode 1 If the path is empty or "/" (exits the script via fDie).
fSetOutDir() {
    local __A_DIR
    __A_DIR="$(fAbsDir "$1" "output directory")"
    __A_OUT_DIR="${__A_DIR}"
    __A_DL_DIR="${__A_OUT_DIR}/download"
    __A_SRC_DIR="${__A_OUT_DIR}/src/libzip-${__A_LIBZIP_VERSION}"
    __A_BUILD_ROOT="${__A_OUT_DIR}/build"
    __A_INSTALL_ROOT="${__A_INSTALL_DIR:-${__A_OUT_DIR}/install}"
}

# ------------------------------
# @description Set a custom install directory for the finished libraries.
#  It stays in effect if the output directory is changed afterwards.
# @arg $1 string Install directory path.
# @set __A_INSTALL_DIR string Absolute custom install directory.
# @set __A_INSTALL_ROOT string Same as __A_INSTALL_DIR.
# @exitcode 0 If the path is usable.
# @exitcode 1 If the path is empty or "/" (exits the script via fDie).
fSetInstallDir() {
    local __A_DIR
    __A_DIR="$(fAbsDir "$1" "install directory")"
    __A_INSTALL_DIR="${__A_DIR}"
    __A_INSTALL_ROOT="${__A_INSTALL_DIR}"
}

# ------------------------------
# @description Remove previous install results. The default install folder
#  (<out>/install) is removed whole; a custom install directory may hold
#  other files, so only the subfolders this script creates are removed.
# @noargs
# @stdout What is being removed.
# @exitcode 0 Always.
fCleanInstall() {
    local __A_ABI
    if [[ -z "${__A_INSTALL_DIR}" ]]; then
        printf '    removing %s\n' "${__A_INSTALL_ROOT}"
        rm -rf "${__A_INSTALL_ROOT}"
        return 0
    fi
    printf '    removing libzip subfolders in %s\n' "${__A_INSTALL_ROOT}"
    rm -rf "${__A_INSTALL_ROOT}/ios" "${__A_INSTALL_ROOT}/ios-simulator" \
           "${__A_INSTALL_ROOT}/macos"
    for __A_ABI in arm64-v8a armeabi-v7a; do
        rm -rf "${__A_INSTALL_ROOT}/android/${__A_ABI}"
    done
    rmdir "${__A_INSTALL_ROOT}/android" 2>/dev/null || true
}

[[ -z "${__A_INSTALL_DIR}" ]] || fSetInstallDir "${__A_INSTALL_DIR}"
fSetOutDir "${__A_OUT_DIR}"

# ------------------------------
# @description Report an OpenSSL policy problem according to __A_OPENSSL_CHECK:
#  stop the script in strict mode, otherwise print a warning.
# @arg $@ string Problem description.
# @stderr The error or warning.
# @exitcode 0 In warn mode.
# @exitcode 1 In strict mode (exits the script via fDie).
fPolicyFail() {
    if [[ "${__A_OPENSSL_CHECK}" == "strict" ]]; then
        fDie "$* (set __A_OPENSSL_CHECK=warn to continue anyway)"
    fi
    fWarn "$*"
}

if command -v ninja >/dev/null 2>&1; then
    __A_GENERATOR="Ninja"
else
    __A_GENERATOR="Unix Makefiles"
fi

# Options shared by every target: static lib only (no shared lib, no
# framework bundle), no tools/tests/docs, no optional compressors.
# Crypto: OpenSSL only. CommonCrypto must be OFF, otherwise libzip would
# prefer it over OpenSSL on Apple platforms.
__A_COMMON_ARGS=(
    -DCMAKE_BUILD_TYPE="${__A_BUILD_TYPE}"
    -DCMAKE_POSITION_INDEPENDENT_CODE=ON
    -DBUILD_SHARED_LIBS=OFF
    -DCMAKE_FRAMEWORK=OFF
    -DCMAKE_MACOSX_BUNDLE=OFF
    -DCMAKE_FIND_FRAMEWORK=NEVER
    -DBUILD_TOOLS=OFF
    -DBUILD_REGRESS=OFF
    -DBUILD_OSSFUZZ=OFF
    -DBUILD_EXAMPLES=OFF
    -DBUILD_DOC=OFF
    -DENABLE_BZIP2=OFF
    -DENABLE_LZMA=OFF
    -DENABLE_ZSTD=OFF
    -DENABLE_OPENSSL=ON
    -DENABLE_COMMONCRYPTO=OFF
    -DENABLE_GNUTLS=OFF
    -DENABLE_MBEDTLS=OFF
    -DENABLE_WINDOWS_CRYPTO=OFF
)

# -------------------------
# Toolchains

# ------------------------------
# @description Compare two dotted version strings numerically, e.g.
#  27.2.12479018 vs 26.3.11579264. Non-numeric parts (like -rc1) count as 0.
# @arg $1 string First version.
# @arg $2 string Second version.
# @exitcode 0 If the first version is greater than the second.
# @exitcode 1 Otherwise.
fVersionGreater() {
    local __A_A="$1." __A_B="$2." __A_X __A_Y
    while [[ -n "${__A_A}" || -n "${__A_B}" ]]; do
        __A_X="${__A_A%%.*}"; __A_A="${__A_A#*.}"
        __A_Y="${__A_B%%.*}"; __A_B="${__A_B#*.}"
        __A_X="${__A_X%%[!0-9]*}"; __A_Y="${__A_Y%%[!0-9]*}"
        __A_X="$((10#${__A_X:-0}))"; __A_Y="$((10#${__A_Y:-0}))"
        [[ ${__A_X} -gt ${__A_Y} ]] && return 0
        [[ ${__A_X} -lt ${__A_Y} ]] && return 1
    done
    return 1
}

# ------------------------------
# @description Read an NDK's version from its source.properties
#  (Pkg.Revision), falling back to the folder name.
# @arg $1 string Path to the NDK folder.
# @stdout The version, e.g. 27.2.12479018 or 28.0.12433566-beta1.
# @exitcode 0 Always.
fNdkRevision() {
    local __A_REV=""
    if [[ -f "$1/source.properties" ]]; then
        __A_REV="$(sed -n 's/^Pkg\.Revision[[:space:]]*=[[:space:]]*//p' "$1/source.properties" \
                   | tr -d '\r' | head -n 1)"
    fi
    printf '%s' "${__A_REV:-${1##*/}}"
}

# ------------------------------
# @description Find the newest valid NDK (one that has the CMake toolchain
#  file) inside an SDK's ndk/ folder. Stable releases are preferred; a beta
#  or release candidate is picked only when no stable NDK is installed.
# @arg $1 string Path to the SDK's ndk/ folder.
# @stdout Path to the chosen NDK, or nothing if none is installed.
# @exitcode 0 Always.
fNewestNdk() {
    local __A_DIR __A_V
    local __A_STABLE="" __A_STABLE_V="" __A_PRE="" __A_PRE_V=""
    for __A_DIR in "$1"/*; do
        [[ -f "${__A_DIR}/build/cmake/android.toolchain.cmake" ]] || continue
        __A_V="$(fNdkRevision "${__A_DIR}")"
        if [[ "${__A_V}${__A_DIR##*/}" =~ [A-Za-z] ]]; then
            if [[ -z "${__A_PRE}" ]] || fVersionGreater "${__A_V}" "${__A_PRE_V}"; then
                __A_PRE="${__A_DIR}"; __A_PRE_V="${__A_V}"
            fi
        elif [[ -z "${__A_STABLE}" ]] || fVersionGreater "${__A_V}" "${__A_STABLE_V}"; then
            __A_STABLE="${__A_DIR}"; __A_STABLE_V="${__A_V}"
        fi
    done
    printf '%s' "${__A_STABLE:-${__A_PRE}}"
}

# ------------------------------
# @description Work out the NDK path when __A_ANDROID_NDK is not set: use
#  ANDROID_HOME (or the Android Studio default SDK location) and pick
#  __A_ANDROID_NDK_VERSION or the newest installed NDK.
# @noargs
# @set __A_ANDROID_NDK string Resolved NDK path (unchanged if already set).
# @set __A_ANDROID_NDK_SOURCE string How the NDK was found, for the log.
# @exitcode 0 If an NDK path was determined.
# @exitcode 1 If no SDK or no NDK was found (__A_ANDROID_NDK stays empty).
fResolveNdk() {
    local __A_SDK __A_FOUND
    if [[ -n "${__A_ANDROID_NDK}" ]]; then
        [[ -n "${__A_ANDROID_NDK_SOURCE}" ]] || __A_ANDROID_NDK_SOURCE="__A_ANDROID_NDK"
        return 0
    fi

    if [[ -n "${__A_ANDROID_HOME}" ]]; then
        __A_SDK="${__A_ANDROID_HOME%/}"
        __A_ANDROID_NDK_SOURCE="ANDROID_HOME"
    elif [[ "${__A_HOST_OS}" == "Darwin" ]]; then
        __A_SDK="${HOME}/Library/Android/sdk"
        __A_ANDROID_NDK_SOURCE="default SDK location (ANDROID_HOME not set)"
    else
        __A_SDK="${HOME}/Android/Sdk"
        __A_ANDROID_NDK_SOURCE="default SDK location (ANDROID_HOME not set)"
    fi

    if [[ -n "${__A_ANDROID_NDK_VERSION}" ]]; then
        __A_ANDROID_NDK="${__A_SDK}/ndk/${__A_ANDROID_NDK_VERSION}"
        __A_ANDROID_NDK_SOURCE+=", version ${__A_ANDROID_NDK_VERSION}"
        return 0
    fi

    __A_FOUND="$(fNewestNdk "${__A_SDK}/ndk")"
    if [[ -n "${__A_FOUND}" ]]; then
        __A_ANDROID_NDK="${__A_FOUND}"
        __A_ANDROID_NDK_SOURCE+=", newest installed: $(fNdkRevision "${__A_FOUND}")"
        return 0
    fi
    if [[ -f "${__A_SDK}/ndk-bundle/build/cmake/android.toolchain.cmake" ]]; then
        __A_ANDROID_NDK="${__A_SDK}/ndk-bundle"
        __A_ANDROID_NDK_SOURCE+=", ndk-bundle"
        return 0
    fi

    __A_ANDROID_NDK_SOURCE="no NDK found in '${__A_SDK}/ndk'"
    return 1
}

# ------------------------------
# @description Resolve the NDK (see fResolveNdk) and check that it exists and
#  its path has no whitespace.
# @noargs
# @set __A_ANDROID_NDK string Resolved NDK path.
# @exitcode 0 If the NDK toolchain file exists and the path is safe.
# @exitcode 1 If no NDK is found, it is incomplete, or its path contains
#  whitespace (exits the script via fDie).
fCheckNdk() {
    fResolveNdk || fDie "Android NDK: ${__A_ANDROID_NDK_SOURCE}. Install an NDK with the Android SDK Manager, set ANDROID_HOME to your SDK, or set __A_ANDROID_NDK."
    [[ ! "${__A_ANDROID_NDK}" =~ [[:space:]] ]] \
        || fDie "Android NDK path '${__A_ANDROID_NDK}' contains spaces. Move the SDK/NDK to a path without spaces."
    [[ -f "${__A_ANDROID_NDK}/build/cmake/android.toolchain.cmake" ]] \
        || fDie "Android NDK not found at '${__A_ANDROID_NDK}' (${__A_ANDROID_NDK_SOURCE}). Check ANDROID_HOME, __A_ANDROID_NDK_VERSION or __A_ANDROID_NDK."
}

# ------------------------------
# @description Find a tool in the NDK's prebuilt LLVM toolchain. The host
#  folder is darwin-x86_64 even on Apple Silicon, so it is matched by glob.
# @arg $1 string Tool name, e.g. clang, llvm-nm or llvm-readelf.
# @stdout Full path to the tool.
# @exitcode 0 If the tool is found.
# @exitcode 1 If the tool is missing (exits the script via fDie).
fNdkTool() {
    local __A_MATCHES=( "${__A_ANDROID_NDK}"/toolchains/llvm/prebuilt/*/bin/"$1" )
    [[ -x "${__A_MATCHES[0]}" ]] \
        || fDie "'$1' not found in ${__A_ANDROID_NDK}/toolchains/llvm/prebuilt/*/bin"
    printf '%s' "${__A_MATCHES[0]}"
}

# ------------------------------
# @description Set the compiler command used by the hardening probes to Apple
#  clang for an SDK. Stored as an array so paths with spaces stay intact.
# @arg $1 string SDK name: iphoneos, iphonesimulator or macosx.
# @set __A_CC_CMD array clang path, -isysroot and the SDK path.
# @exitcode 0 If xcrun finds the SDK.
# @exitcode 1 If xcrun fails.
fSetAppleCc() {
    local __A_CLANG __A_SDK
    __A_CLANG="$(xcrun --sdk "$1" -f clang)"
    __A_SDK="$(xcrun --sdk "$1" --show-sdk-path)"
    __A_CC_CMD=( "${__A_CLANG}" -isysroot "${__A_SDK}" )
}

# -------------------------
# OpenSSL

# ------------------------------
# @description Check that a folder holds OpenSSL headers and a static libcrypto.a.
# @arg $1 string Path to the OpenSSL folder (include/ and lib/ inside).
# @arg $2 string Label used in error messages (platform name).
# @exitcode 0 If include/openssl/evp.h and lib/libcrypto.a exist.
# @exitcode 1 If either is missing (exits the script via fDie).
fCheckOpenssl() {
    local __A_DIR="$1" __A_LABEL="$2"
    [[ -f "${__A_DIR}/include/openssl/evp.h" ]] \
        || fDie "${__A_LABEL}: OpenSSL headers not found in '${__A_DIR}/include/openssl'. Edit the OpenSSL paths at the top of this script."
    [[ -f "${__A_DIR}/lib/libcrypto.a" ]] \
        || fDie "${__A_LABEL}: static '${__A_DIR}/lib/libcrypto.a' not found. Edit the OpenSSL paths at the top of this script."
}

# ------------------------------
# @description Read the OpenSSL version from include/openssl/opensslv.h.
#  Only OpenSSL 3.0+ defines OPENSSL_VERSION_MAJOR/MINOR/PATCH.
# @arg $1 string Path to the OpenSSL folder.
# @stdout Version as MAJOR.MINOR.PATCH, or nothing for OpenSSL older than 3.0.
# @exitcode 0 Always.
fOpensslVersion() {
    local __A_H="$1/include/openssl/opensslv.h" __A_PART __A_V="" __A_N
    [[ -f "${__A_H}" ]] || return 0
    for __A_PART in MAJOR MINOR PATCH; do
        __A_N="$(sed -n "s/^#[[:space:]]*define[[:space:]][[:space:]]*OPENSSL_VERSION_${__A_PART}[[:space:]][[:space:]]*\([0-9][0-9]*\).*/\1/p" "${__A_H}" | head -n 1)"
        [[ -n "${__A_N}" ]] || return 0
        __A_V+="${__A_V:+.}${__A_N}"
    done
    printf '%s' "${__A_V}"
}

# ------------------------------
# @description Check that the OpenSSL version belongs to a supported release
#  series listed in __A_OPENSSL_ALLOWED_SERIES.
# @arg $1 string Path to the OpenSSL folder.
# @arg $2 string Label used in messages (platform name).
# @stdout The version found.
# @exitcode 0 If the series is allowed (or in warn mode).
# @exitcode 1 If the version is unknown or not allowed, in strict mode.
fCheckOpensslVersion() {
    local __A_DIR="$1" __A_LABEL="$2" __A_V __A_SERIES __A_S
    __A_V="$(fOpensslVersion "${__A_DIR}")"
    if [[ -z "${__A_V}" ]]; then
        fPolicyFail "${__A_LABEL}: OpenSSL in '${__A_DIR}' is older than 3.0 or its version is unreadable; use a supported release (${__A_OPENSSL_ALLOWED_SERIES})"
        return 0
    fi
    printf '    OpenSSL %s: %s\n' "${__A_LABEL}" "${__A_V}"
    __A_SERIES="${__A_V%.*}"
    for __A_S in ${__A_OPENSSL_ALLOWED_SERIES}; do
        [[ "${__A_SERIES}" == "${__A_S}" ]] && return 0
    done
    fPolicyFail "${__A_LABEL}: OpenSSL ${__A_V} is not in a supported series (${__A_OPENSSL_ALLOWED_SERIES}); rebuild OpenSSL from a supported release"
}

# ------------------------------
# @description Check that libcrypto.a was compiled with stack protection and
#  FORTIFY, by looking for __stack_chk_fail and *_chk references.
# @arg $1 string Path to libcrypto.a.
# @arg $2 string Label used in messages (platform name).
# @arg $@ string nm command (from $3 on).
# @exitcode 0 If both are present (or in warn mode).
# @exitcode 1 If either is missing, in strict mode.
fCheckOpensslHardening() {
    local __A_LIB="$1" __A_LABEL="$2"; shift 2
    local __A_SYMS __A_STACK __A_FORT
    __A_SYMS="$("$@" "${__A_LIB}" 2>/dev/null || true)"
    __A_STACK="$(printf '%s\n' "${__A_SYMS}" | grep -c '__stack_chk_fail' || true)"
    __A_FORT="$(printf '%s\n' "${__A_SYMS}" | grep -v 'stack_chk' \
                | grep -cE '__[a-z0-9_]+_chk([^a-z0-9_]|$)' || true)"
    printf '    OpenSSL %s: %s stack-protector refs, %s FORTIFY refs\n' \
        "${__A_LABEL}" "${__A_STACK}" "${__A_FORT}"
    [[ "${__A_STACK}" -gt 0 ]] \
        || fPolicyFail "${__A_LABEL}: ${__A_LIB} was not built with stack protection (-fstack-protector-strong)"
    [[ "${__A_FORT}" -gt 0 ]] \
        || fPolicyFail "${__A_LABEL}: ${__A_LIB} was not built with FORTIFY (-D_FORTIFY_SOURCE=2/3 and -O2)"
}

# ------------------------------
# @description Check that every object in an ELF static library targets the
#  expected machine.
# @arg $1 string Path to the static library.
# @arg $2 string Label used in messages.
# @arg $3 string Expected machine as printed by readelf (AArch64 or ARM).
# @arg $@ string readelf command (from $4 on).
# @exitcode 0 If all objects match.
# @exitcode 1 If any object is for another machine (exits the script via fDie).
fCheckElfArch() {
    local __A_LIB="$1" __A_LABEL="$2" __A_WANT="$3"; shift 3
    local __A_FOUND
    __A_FOUND="$("$@" -h "${__A_LIB}" 2>/dev/null \
        | sed -n 's/^[[:space:]]*Machine:[[:space:]]*//p' | sort -u | tr '\n' ',' )"
    __A_FOUND="${__A_FOUND%,}"
    [[ "${__A_FOUND}" == "${__A_WANT}" ]] \
        || fDie "${__A_LABEL}: ${__A_LIB} is for '${__A_FOUND:-unknown}', expected '${__A_WANT}'"
}

# ------------------------------
# @description Report how many objects of an arm64 ELF library carry the
#  BTI/PAC property. The linker drops BTI for the whole binary if any object
#  lacks it. Warning only, as most prebuilt OpenSSL builds omit it.
# @arg $1 string Path to the static library.
# @arg $2 string Label used in messages.
# @arg $@ string readelf command (from $3 on).
# @stdout The number of objects with BTI/PAC.
# @exitcode 0 Always.
fCheckBranchProtection() {
    local __A_LIB="$1" __A_LABEL="$2"; shift 2
    local __A_NOTES __A_TOTAL __A_BTI
    __A_NOTES="$("$@" --notes "${__A_LIB}" 2>/dev/null || true)"
    __A_TOTAL="$("$@" -h "${__A_LIB}" 2>/dev/null | grep -c 'Machine:' || true)"
    __A_BTI="$(printf '%s\n' "${__A_NOTES}" | grep -ciE 'aarch64 feature:.*BTI' || true)"
    printf '    OpenSSL %s: %s of %s objects with BTI/PAC\n' "${__A_LABEL}" "${__A_BTI}" "${__A_TOTAL}"
    [[ "${__A_BTI}" -ge "${__A_TOTAL}" && "${__A_TOTAL}" -gt 0 ]] \
        || fWarn "${__A_LABEL}: not all of libcrypto.a has BTI/PAC; build OpenSSL with -mbranch-protection=standard to keep BTI in your app"
}

# ------------------------------
# @description Check the architectures and Apple platform of a Mach-O static
#  library, so device, simulator and macOS libraries are not mixed up.
# @arg $1 string Path to the static library.
# @arg $2 string Label used in messages.
# @arg $3 string Expected platform: ios, iossim or macos.
# @exitcode 0 If arm64 is present and the platform matches.
# @exitcode 1 If arm64 is missing or the platform differs (exits via fDie).
fCheckAppleArch() {
    local __A_LIB="$1" __A_LABEL="$2" __A_WANT="$3" __A_ARCHS __A_PLAT __A_RE
    __A_ARCHS="$(xcrun lipo -archs "${__A_LIB}" 2>/dev/null || true)"
    [[ " ${__A_ARCHS} " == *" arm64 "* ]] \
        || fDie "${__A_LABEL}: ${__A_LIB} has no arm64 slice (found: '${__A_ARCHS:-none}')"
    [[ "${__A_ARCHS}" == "arm64" ]] \
        || fWarn "${__A_LABEL}: ${__A_LIB} also contains '${__A_ARCHS}'; only arm64 is used"

    case "${__A_WANT}" in
        ios)    __A_RE='^(2|IOS)$' ;;
        iossim) __A_RE='^(7|IOSSIMULATOR)$' ;;
        macos)  __A_RE='^(1|MACOS)$' ;;
    esac
    __A_PLAT="$(xcrun otool -l -arch arm64 "${__A_LIB}" 2>/dev/null \
        | awk '/LC_BUILD_VERSION/{f=1} f && $1=="platform"{print $2; f=0}' | sort -u)"
    if [[ -z "${__A_PLAT}" ]]; then
        fWarn "${__A_LABEL}: could not read the Apple platform of ${__A_LIB}"
    elif printf '%s\n' "${__A_PLAT}" | grep -qvE "${__A_RE}"; then
        # At least one object is built for a different Apple platform.
        fDie "${__A_LABEL}: ${__A_LIB} is built for platform '$(printf '%s' "${__A_PLAT}" | tr '\n' ' ')', not ${__A_WANT}"
    fi
}

# ------------------------------
# @description Verify one Apple OpenSSL folder: files, version, architecture,
#  platform and hardening.
# @arg $1 string Path to the OpenSSL folder.
# @arg $2 string Label used in messages.
# @arg $3 string Expected platform: ios, iossim or macos.
# @stdout Version and hardening summary.
# @exitcode 0 If the checks pass (or only warnings).
# @exitcode 1 If a check fails.
fVerifyOpensslApple() {
    local __A_DIR="$1" __A_LABEL="$2"
    fCheckOpenssl "${__A_DIR}" "${__A_LABEL}"
    fCheckOpensslVersion "${__A_DIR}" "${__A_LABEL}"
    fCheckAppleArch "${__A_DIR}/lib/libcrypto.a" "${__A_LABEL}" "$3"
    fCheckOpensslHardening "${__A_DIR}/lib/libcrypto.a" "${__A_LABEL}" xcrun nm -arch arm64
}

# ------------------------------
# @description Verify one Android OpenSSL folder: files, version, machine,
#  hardening and (arm64) BTI/PAC.
# @arg $1 string Android ABI (arm64-v8a or armeabi-v7a).
# @stdout Version and hardening summary.
# @exitcode 0 If the checks pass (or only warnings).
# @exitcode 1 If a check fails.
fVerifyOpensslAndroid() {
    local __A_ABI="$1" __A_DIR __A_LABEL="android/$1" __A_NM __A_READELF __A_MACHINE
    __A_DIR="$(fAndroidOpensslDir "${__A_ABI}")"
    __A_NM="$(fNdkTool llvm-nm)"
    __A_READELF="$(fNdkTool llvm-readelf)"
    case "${__A_ABI}" in
        arm64-v8a)   __A_MACHINE="AArch64" ;;
        armeabi-v7a) __A_MACHINE="ARM" ;;
        *)           fDie "unsupported Android ABI '${__A_ABI}' (only arm64-v8a and armeabi-v7a)" ;;
    esac

    fCheckOpenssl "${__A_DIR}" "${__A_LABEL}"
    fCheckOpensslVersion "${__A_DIR}" "${__A_LABEL}"
    fCheckElfArch "${__A_DIR}/lib/libcrypto.a" "${__A_LABEL}" "${__A_MACHINE}" "${__A_READELF}"
    fCheckOpensslHardening "${__A_DIR}/lib/libcrypto.a" "${__A_LABEL}" "${__A_NM}"
    if [[ "${__A_ABI}" == "arm64-v8a" ]]; then
        fCheckBranchProtection "${__A_DIR}/lib/libcrypto.a" "${__A_LABEL}" "${__A_READELF}"
    fi
}

# ------------------------------
# @description Build the CMake arguments that point find_package(OpenSSL) at a
#  folder. The paths are given explicitly because the iOS and Android
#  toolchains restrict CMake's search to the SDK/NDK sysroot.
# @arg $1 string Path to the OpenSSL folder.
# @set __A_OPENSSL_ARGS array CMake arguments for that OpenSSL folder.
# @exitcode 0 Always.
fSetOpensslArgs() {
    local __A_DIR="$1"
    __A_OPENSSL_ARGS=(
        -DOPENSSL_ROOT_DIR="${__A_DIR}"
        -DOPENSSL_USE_STATIC_LIBS=TRUE
        -DOPENSSL_INCLUDE_DIR="${__A_DIR}/include"
        -DOPENSSL_CRYPTO_LIBRARY="${__A_DIR}/lib/libcrypto.a"
    )
    if [[ -f "${__A_DIR}/lib/libssl.a" ]]; then
        __A_OPENSSL_ARGS+=(-DOPENSSL_SSL_LIBRARY="${__A_DIR}/lib/libssl.a")
    fi
}

# ------------------------------
# @description Resolve the OpenSSL folder for one Android ABI:
#  <__A_OPENSSL_ANDROID>/<abi>. A trailing slash is ignored.
# @arg $1 string Android ABI (arm64-v8a or armeabi-v7a).
# @stdout Path to the OpenSSL folder for that ABI.
# @exitcode 0 Always.
fAndroidOpensslDir() {
    printf '%s/%s' "${__A_OPENSSL_ANDROID%/}" "$1"
}

# -------------------------
# Build

# ------------------------------
# @description Check that an install folder holds a real static libzip.a and no
#  shared library or framework output.
# @arg $1 string Build name, used in error messages.
# @arg $2 string Path to the install folder.
# @exitcode 0 If lib/libzip.a is a static archive and nothing shared exists.
# @exitcode 1 If libzip.a is missing or not an archive, or a .so/.dylib/.tbd/
#  framework is found (exits the script via fDie).
fVerifyStatic() {
    local __A_NAME="$1" __A_IDIR="$2" __A_LIB="$2/lib/libzip.a" __A_BAD

    [[ -f "${__A_LIB}" ]] || fDie "${__A_NAME}: libzip.a was not produced"
    [[ "$(head -c 7 "${__A_LIB}")" == '!<arch>' ]] \
        || fDie "${__A_NAME}: ${__A_LIB} is not a static archive"

    __A_BAD="$(find "${__A_IDIR}" \( -name '*.so' -o -name '*.so.*' -o -name '*.dylib' \
                                   -o -name '*.tbd' -o -name '*.framework' \
                                   -o -name '*.xcframework' \) -print)"
    [[ -z "${__A_BAD}" ]] || fDie "${__A_NAME}: unexpected shared library/framework output:
${__A_BAD}"
}

# ------------------------------
# @description Write LINKING.txt into an install folder with the linker
#  hardening the final app must keep, since a static library cannot set it.
# @arg $1 string Build name; android/* selects the Android text.
# @arg $2 string Path to the install folder.
# @exitcode 0 Always.
fWriteLinkingNotes() {
    local __A_NAME="$1" __A_FILE="$2/LINKING.txt"
    if [[ "${__A_NAME}" == android/* ]]; then
        cat > "${__A_FILE}" <<'EOF'
Link libzip.a into your app's shared library (.so) together with libcrypto.a
and zlib, in this order:  libzip.a  libcrypto.a  -lz

Final .so linker hardening (a static library cannot set these):
  -Wl,-z,relro -Wl,-z,now          RELRO + BIND_NOW (read-only GOT)
  -Wl,-z,noexecstack               non-executable stack
  -Wl,-z,max-page-size=16384       16 KB page alignment (required by
                                   Google Play for apps targeting
                                   Android 15+ / API 35+)
  -Wl,--build-id=sha1              (optional) stable build IDs

CMake / Qt:
  target_link_options(app PRIVATE
      -Wl,-z,relro -Wl,-z,now -Wl,-z,noexecstack -Wl,-z,max-page-size=16384)
  NDK r27: also pass -DANDROID_SUPPORT_FLEXIBLE_PAGE_SIZES=ON
  NDK r28+: 16 KB alignment is the default.

Gradle (externalNativeBuild.cmake.arguments):
  "-DANDROID_SUPPORT_FLEXIBLE_PAGE_SIZES=ON"

Check the final binary:
  ./build_libzip.sh check-app path/to/libyourapp.so
EOF
    else
        cat > "${__A_FILE}" <<'EOF'
Link libzip.a into your app together with libcrypto.a and zlib:
  libzip.a  libcrypto.a  -lz   (Xcode: add libz.tbd)

Final binary linker hardening (a static library cannot set these):
  - PIE: on by default in Xcode and Qt; do not pass -Wl,-no_pie
  - no executable stack: do not pass -Wl,-allow_stack_execute
  - keep "Strip Linked Product" and dead-code stripping (-Wl,-dead_strip)
    for release builds

Check the final binary (the executable inside the .app bundle):
  ./build_libzip.sh check-app path/to/YourApp.app/YourApp
EOF
    fi
}

# ------------------------------
# @description Map a build name to its install subfolder. The iOS device
#  build is installed as "ios" (without -arm64); all others keep their name.
# @arg $1 string Build name (ios-arm64, ios-simulator, macos, android/<abi>).
# @stdout The install subfolder name.
# @exitcode 0 Always.
fInstallSubdir() {
    case "$1" in
        ios-arm64) printf 'ios' ;;
        *)         printf '%s' "$1" ;;
    esac
}

# ------------------------------
# @description Configure, build and install libzip for one platform/arch, then
#  verify OpenSSL was used and the output is static only. Writes
#  HARDENING.txt (flags, OpenSSL used) and LINKING.txt.
# @arg $1 string Build name, also the build subfolder name (ios-arm64,
#  ios-simulator, macos, or android/<abi>); the install subfolder comes
#  from fInstallSubdir.
# @arg $2 string C compiler flags (hardening flags).
# @arg $3 string Path to the OpenSSL folder for this platform.
# @arg $@ string Extra CMake arguments (from $4 on).
# @stdout CMake configure, build and install output.
# @exitcode 0 If the build succeeded.
# @exitcode 1 If OpenSSL is missing or not picked up, the build fails, or the
#  output is not a static library only.
fBuildOne() {
    local __A_NAME="$1" __A_CFLAGS="$2" __A_SSL_DIR="$3"; shift 3
    local __A_BDIR="${__A_BUILD_ROOT}/${__A_NAME}"
    local __A_IDIR
    __A_IDIR="${__A_INSTALL_ROOT}/$(fInstallSubdir "${__A_NAME}")"

    fCheckOpenssl "${__A_SSL_DIR}" "${__A_NAME}"
    fSetOpensslArgs "${__A_SSL_DIR}"

    fLog "Building libzip ${__A_LIBZIP_VERSION} for ${__A_NAME}"
    printf '    C flags: %s\n' "${__A_CFLAGS:-(none)}"
    printf '    OpenSSL: %s\n' "${__A_SSL_DIR}"
    rm -rf "${__A_BDIR}" "${__A_IDIR}"

    cmake -S "${__A_SRC_DIR}" -B "${__A_BDIR}" -G "${__A_GENERATOR}" \
        "${__A_COMMON_ARGS[@]}" \
        "${__A_OPENSSL_ARGS[@]}" \
        -DCMAKE_INSTALL_PREFIX="${__A_IDIR}" \
        -DCMAKE_C_FLAGS="${__A_CFLAGS}" \
        "$@"

    # libzip only warns (and builds without encryption) if OpenSSL isn't
    # usable, so make that a hard error.
    grep -q '^#define HAVE_OPENSSL' "${__A_BDIR}/config.h" 2>/dev/null \
        || fDie "${__A_NAME}: libzip did not pick up OpenSSL from '${__A_SSL_DIR}' (see the CMake output above)"

    cmake --build "${__A_BDIR}" --config "${__A_BUILD_TYPE}" --parallel "${__A_JOBS}"
    cmake --install "${__A_BDIR}" --config "${__A_BUILD_TYPE}"

    fVerifyStatic "${__A_NAME}" "${__A_IDIR}"

    # Record the flags and inputs used, for audits.
    printf 'libzip %s (%s)\nsource sha256: %s\nC flags: %s\nOpenSSL: %s (%s)\n' \
        "${__A_LIBZIP_VERSION}" "${__A_BUILD_TYPE}" "${__A_LIBZIP_SHA256}" "${__A_CFLAGS}" \
        "$(fOpensslVersion "${__A_SSL_DIR}")" "${__A_SSL_DIR}" \
        > "${__A_IDIR}/HARDENING.txt"
    fWriteLinkingNotes "${__A_NAME}" "${__A_IDIR}"
}

# -------------------------
# Hardening
# Candidate flags; each entry is tried as one unit.
__A_HARDEN_COMMON=(
    "-fstack-protector-strong"
    "@FORTIFY@"     # replaced by -D_FORTIFY_SOURCE=3 or =2, see fFortifyLevel
    "-ftrivial-auto-var-init=zero"
    "-fno-strict-overflow"
    "-fno-delete-null-pointer-checks"
    "-fvisibility=hidden"
    "-Wformat -Wformat-security -Werror=format-security"
    "-fPIC"
)
__A_HARDEN_ANDROID=(
    "-fstack-clash-protection"
    "-mbranch-protection=standard"
)
__A_HARDEN_APPLE=(
    "-fstack-clash-protection"
)

# ------------------------------
# @description Find the highest _FORTIFY_SOURCE level the C library really
#  enforces, using the compiler in __A_CC_CMD. Compilers accept
#  -D_FORTIFY_SOURCE=3 everywhere, but only C libraries that support level 3
#  turn it into checks. The probe copies into a malloc'd buffer of run-time
#  size: only level 3 can see that size, so only level 3 makes the compiler
#  call __memcpy_chk instead of memcpy.
# @arg $1 string Space-separated target triples; all must support level 3.
# @stdout 3 if level 3 is enforced for every triple, otherwise 2.
# @exitcode 0 Always.
fFortifyLevel() {
    local __A_TRIPLES="$1" __A_TRIPLE __A_ASM
    local __A_PROBE='#include <stdlib.h>
#include <string.h>
void *fProbe(size_t n, size_t m, const void *s)
{ char *p = malloc(n); if (p) memcpy(p, s, m); return p; }'

    for __A_TRIPLE in ${__A_TRIPLES}; do
        __A_ASM="$(printf '%s\n' "${__A_PROBE}" \
            | "${__A_CC_CMD[@]}" -target "${__A_TRIPLE}" -O2 \
                -U_FORTIFY_SOURCE -D_FORTIFY_SOURCE=3 -x c -S - -o - 2>/dev/null)" \
            || { printf '2'; return 0; }
        [[ "${__A_ASM}" == *__memcpy_chk* ]] || { printf '2'; return 0; }
    done
    printf '3'
}

# ------------------------------
# @description Select the hardening flags the compiler in __A_CC_CMD accepts.
#  Each candidate is test-compiled with -Werror for every triple, so a
#  multi-arch build only gets flags valid on all its architectures. The
#  @FORTIFY@ candidate is replaced by the level found by fFortifyLevel.
# @arg $1 string Space-separated target triples.
# @arg $@ string Candidate flags (from $2 on); each entry is tested as one unit.
# @stdout Accepted flags, space-separated; empty when __A_HARDENING is not 1.
# @exitcode 0 Always.
fHardeningFlags() {
    [[ "${__A_HARDENING}" == "1" ]] || return 0
    local __A_TRIPLES="$1"; shift
    local __A_OUT="" __A_FLAG __A_TRIPLE __A_OK
    local -a __A_FLAG_WORDS
    for __A_FLAG in "$@"; do
        if [[ "${__A_FLAG}" == "@FORTIFY@" ]]; then
            __A_FLAG="-U_FORTIFY_SOURCE -D_FORTIFY_SOURCE=$(fFortifyLevel "${__A_TRIPLES}")"
        fi
        read -r -a __A_FLAG_WORDS <<< "${__A_FLAG}"
        __A_OK=1
        for __A_TRIPLE in ${__A_TRIPLES}; do
            if ! printf 'int f(void){return 0;}\n' \
                | "${__A_CC_CMD[@]}" -target "${__A_TRIPLE}" -O2 -Werror \
                    "${__A_FLAG_WORDS[@]}" -x c -c - -o /dev/null >/dev/null 2>&1; then
                __A_OK=0; break
            fi
        done
        [[ ${__A_OK} -eq 1 ]] && __A_OUT+="${__A_FLAG} "
    done
    printf '%s' "${__A_OUT% }"
}

# -------------------------
# Download

# ------------------------------
# @description Compute the SHA-256 of a file with whichever tool exists.
# @arg $1 string Path to the file.
# @stdout The lowercase hex SHA-256.
# @exitcode 0 If a hash tool is available.
# @exitcode 1 If no SHA-256 tool is found (exits the script via fDie).
fSha256() {
    if command -v shasum >/dev/null 2>&1; then
        shasum -a 256 "$1" | awk '{print $1}'
    elif command -v sha256sum >/dev/null 2>&1; then
        sha256sum "$1" | awk '{print $1}'
    elif command -v openssl >/dev/null 2>&1; then
        openssl dgst -sha256 -r "$1" | awk '{print $1}'
    else
        fDie "no SHA-256 tool found (shasum, sha256sum or openssl)"
    fi
}

# ------------------------------
# @description Check a file against the pinned SHA-256 in __A_LIBZIP_SHA256.
#  A mismatching file is deleted so it is never used.
# @arg $1 string Path to the file.
# @exitcode 0 If the hash matches.
# @exitcode 1 If it differs; the file is deleted (exits the script via fDie).
fVerifySha256() {
    local __A_FILE="$1" __A_ACTUAL
    __A_ACTUAL="$(fSha256 "${__A_FILE}")"
    if [[ "${__A_ACTUAL}" != "${__A_LIBZIP_SHA256}" ]]; then
        rm -f "${__A_FILE}"
        fDie "SHA-256 mismatch for ${__A_TARBALL_NAME}: expected ${__A_LIBZIP_SHA256}, got ${__A_ACTUAL}. The file was deleted."
    fi
    printf '    SHA-256 OK: %s\n' "${__A_ACTUAL}"
}

# ------------------------------
# @description Check that every archive entry stays inside the expected
#  top-level folder (no absolute paths, no ".." components).
# @arg $1 string Path to the .tar.xz archive.
# @exitcode 0 If all entries are safe.
# @exitcode 1 If an entry escapes the folder (exits the script via fDie).
fCheckArchivePaths() {
    local __A_PREFIX="libzip-${__A_LIBZIP_VERSION}/" __A_BAD
    __A_BAD="$(tar -tJf "$1" | awk -v p="${__A_PREFIX}" \
        'index($0, p) != 1 || $0 ~ /(^|\/)\.\.(\/|$)/ { print; exit }')"
    [[ -z "${__A_BAD}" ]] || fDie "unsafe path in ${__A_TARBALL_NAME}: '${__A_BAD}'"
}

# ------------------------------
# @description Download, verify and unpack the libzip source. The tarball is
#  fetched over HTTPS only and its SHA-256 is checked after download and on
#  every run. The source tree is reused only if it was extracted from a
#  tarball with the same verified hash.
# @noargs
# @stdout Download, verification and extraction progress.
# @exitcode 0 If the verified source is ready.
# @exitcode 1 If no checksum is known, the download fails, the checksum does
#  not match or the archive is unsafe or malformed.
fFetchSource() {
    [[ "${__A_LIBZIP_SHA256}" =~ ^[0-9a-f]{64}$ ]] \
        || fDie "no SHA-256 known for libzip ${__A_LIBZIP_VERSION}; set __A_LIBZIP_SHA256 to the hash of ${__A_TARBALL_NAME} from a trusted source"

    local __A_TARBALL="${__A_DL_DIR}/${__A_TARBALL_NAME}"
    local __A_MARKER="${__A_SRC_DIR}/.verified-sha256"
    local __A_TMP

    fNeed curl
    fNeed tar
    mkdir -p "${__A_DL_DIR}" "$(dirname "${__A_SRC_DIR}")"

    if [[ ! -f "${__A_TARBALL}" ]]; then
        fLog "Downloading ${__A_SRC_URL}"
        rm -f "${__A_TARBALL}.part"
        curl --proto '=https' --tlsv1.2 -fL --retry 3 \
            -o "${__A_TARBALL}.part" "${__A_SRC_URL}"
        fVerifySha256 "${__A_TARBALL}.part"
        mv "${__A_TARBALL}.part" "${__A_TARBALL}"
    else
        fLog "Verifying cached ${__A_TARBALL_NAME}"
        fVerifySha256 "${__A_TARBALL}"
    fi

    # Reuse the source tree only if it came from this verified tarball.
    if [[ -f "${__A_SRC_DIR}/CMakeLists.txt" && -f "${__A_MARKER}" \
          && "$(cat "${__A_MARKER}")" == "${__A_LIBZIP_SHA256}" ]]; then
        return 0
    fi

    fLog "Extracting"
    fCheckArchivePaths "${__A_TARBALL}"
    rm -rf "${__A_SRC_DIR}"
    __A_TMP="$(mktemp -d "${__A_OUT_DIR}/src/.extract.XXXXXX")"
    tar -xJf "${__A_TARBALL}" -C "${__A_TMP}" \
        || { rm -rf "${__A_TMP}"; fDie "could not extract ${__A_TARBALL_NAME} (tar needs xz support)"; }
    [[ -f "${__A_TMP}/libzip-${__A_LIBZIP_VERSION}/CMakeLists.txt" ]] \
        || { rm -rf "${__A_TMP}"; fDie "unexpected archive layout"; }
    mv "${__A_TMP}/libzip-${__A_LIBZIP_VERSION}" "${__A_SRC_DIR}"
    rm -rf "${__A_TMP}"
    printf '%s\n' "${__A_LIBZIP_SHA256}" > "${__A_MARKER}"
}

# -------------------------
# iOS

# ------------------------------
# @description Build libzip for iOS device (arm64) and iOS simulator (arm64).
# @noargs
# @stdout Build progress and CMake output.
# @exitcode 0 If both builds succeeded.
# @exitcode 1 If the host is not macOS or a build fails.
fBuildIos() {
    [[ "${__A_HOST_OS}" == "Darwin" ]] || fDie "iOS builds need a macOS host"
    fNeed xcrun

    local __A_DEV_SDK __A_SIM_SDK
    __A_DEV_SDK="$(xcrun --sdk iphoneos --show-sdk-path)"
    __A_SIM_SDK="$(xcrun --sdk iphonesimulator --show-sdk-path)"

    local __A_DEV_FLAGS __A_SIM_FLAGS
    fSetAppleCc iphoneos
    __A_DEV_FLAGS="$(fHardeningFlags "arm64-apple-ios${__A_IOS_MIN}" \
        "${__A_HARDEN_COMMON[@]}" "${__A_HARDEN_APPLE[@]}")"
    fSetAppleCc iphonesimulator
    __A_SIM_FLAGS="$(fHardeningFlags "arm64-apple-ios${__A_IOS_MIN}-simulator" \
        "${__A_HARDEN_COMMON[@]}" "${__A_HARDEN_APPLE[@]}")"

    # zlib is passed explicitly: find_package(ZLIB) is unreliable when
    # cross-compiling for iOS.
    fBuildOne ios-arm64 "${__A_DEV_FLAGS}" "${__A_OPENSSL_IOS}" \
        -DCMAKE_SYSTEM_NAME=iOS \
        -DCMAKE_OSX_SYSROOT="${__A_DEV_SDK}" \
        -DCMAKE_OSX_ARCHITECTURES=arm64 \
        -DCMAKE_OSX_DEPLOYMENT_TARGET="${__A_IOS_MIN}" \
        -DZLIB_INCLUDE_DIR="${__A_DEV_SDK}/usr/include" \
        -DZLIB_LIBRARY="${__A_DEV_SDK}/usr/lib/libz.tbd"

    fBuildOne ios-simulator "${__A_SIM_FLAGS}" "${__A_OPENSSL_IOS_SIM}" \
        -DCMAKE_SYSTEM_NAME=iOS \
        -DCMAKE_OSX_SYSROOT="${__A_SIM_SDK}" \
        -DCMAKE_OSX_ARCHITECTURES=arm64 \
        -DCMAKE_OSX_DEPLOYMENT_TARGET="${__A_IOS_MIN}" \
        -DZLIB_INCLUDE_DIR="${__A_SIM_SDK}/usr/include" \
        -DZLIB_LIBRARY="${__A_SIM_SDK}/usr/lib/libz.tbd"
}

# -------------------------
# macOS

# ------------------------------
# @description Build libzip for macOS (arm64, Apple Silicon).
# @noargs
# @stdout Build progress and CMake output.
# @exitcode 0 If the build succeeded.
# @exitcode 1 If the host is not macOS or the build fails.
fBuildMacos() {
    [[ "${__A_HOST_OS}" == "Darwin" ]] || fDie "macOS builds need a macOS host"
    fNeed xcrun

    local __A_SDK __A_FLAGS
    __A_SDK="$(xcrun --sdk macosx --show-sdk-path)"
    fSetAppleCc macosx
    __A_FLAGS="$(fHardeningFlags "arm64-apple-macos${__A_MACOS_MIN}" \
        "${__A_HARDEN_COMMON[@]}" "${__A_HARDEN_APPLE[@]}")"

    fBuildOne macos "${__A_FLAGS}" "${__A_OPENSSL_MACOS}" \
        -DCMAKE_OSX_SYSROOT="${__A_SDK}" \
        -DCMAKE_OSX_ARCHITECTURES=arm64 \
        -DCMAKE_OSX_DEPLOYMENT_TARGET="${__A_MACOS_MIN}" \
        -DZLIB_INCLUDE_DIR="${__A_SDK}/usr/include" \
        -DZLIB_LIBRARY="${__A_SDK}/usr/lib/libz.tbd"
}

# -------------------------
# Android

# ------------------------------
# @description Build libzip for every Android ABI in __A_ANDROID_ABIS
#  (arm64-v8a, armeabi-v7a) with the NDK found by fCheckNdk.
# @noargs
# @stdout Build progress and CMake output.
# @exitcode 0 If all ABIs built successfully.
# @exitcode 1 If the NDK or its clang is missing, an ABI is unsupported, or
#  a build fails.
fBuildAndroid() {
    fCheckNdk
    local __A_TOOLCHAIN="${__A_ANDROID_NDK}/build/cmake/android.toolchain.cmake"
    fLog "Using NDK ${__A_ANDROID_NDK} (${__A_ANDROID_NDK_SOURCE})"

    local __A_NDK_CC
    __A_NDK_CC="$(fNdkTool clang)"
    __A_CC_CMD=( "${__A_NDK_CC}" )

    local __A_ABI __A_TRIPLE __A_FLAGS
    for __A_ABI in ${__A_ANDROID_ABIS}; do
        case "${__A_ABI}" in
            arm64-v8a)   __A_TRIPLE="aarch64-linux-android${__A_ANDROID_API}" ;;
            armeabi-v7a) __A_TRIPLE="armv7a-linux-androideabi${__A_ANDROID_API}" ;;
            *)           fDie "unsupported Android ABI '${__A_ABI}' (only arm64-v8a and armeabi-v7a)" ;;
        esac
        __A_FLAGS="$(fHardeningFlags "${__A_TRIPLE}" \
            "${__A_HARDEN_COMMON[@]}" "${__A_HARDEN_ANDROID[@]}")"

        fBuildOne "android/${__A_ABI}" "${__A_FLAGS}" \
            "$(fAndroidOpensslDir "${__A_ABI}")" \
            -DCMAKE_TOOLCHAIN_FILE="${__A_TOOLCHAIN}" \
            -DANDROID_ABI="${__A_ABI}" \
            -DANDROID_PLATFORM="android-${__A_ANDROID_API}"
    done
}

# -------------------------
# App check

# ------------------------------
# @description Print one check result line and remember failures.
# @arg $1 string PASS, FAIL or WARN.
# @arg $2 string Description of the check.
# @set __A_APP_FAILED number Set to 1 when the result is FAIL.
# @stdout The result line.
# @exitcode 0 Always.
fAppResult() {
    local __A_COLOR='32'
    [[ "$1" == "FAIL" ]] && { __A_COLOR='31'; __A_APP_FAILED=1; }
    [[ "$1" == "WARN" ]] && __A_COLOR='33'
    printf '  \033[1;%sm%-4s\033[0m  %s\n' "${__A_COLOR}" "$1" "$2"
}

# ------------------------------
# @description Check the linker hardening of a final Android/ELF app binary:
#  PIE/shared, RELRO, BIND_NOW, non-executable stack, 16 KB page alignment
#  and (arm64) BTI/PAC.
# @arg $1 string Path to the ELF binary (.so or executable).
# @arg $@ string readelf command (from $2 on).
# @stdout One PASS/FAIL/WARN line per check.
# @set __A_APP_FAILED number Set to 1 if any check failed.
# @exitcode 0 Always; failures are reported through __A_APP_FAILED.
fCheckAppElf() {
    local __A_BIN="$1"; shift
    local __A_HDR __A_PH __A_DYN __A_STACK __A_MINALIGN __A_ALIGN

    __A_HDR="$("$@" -hW "${__A_BIN}")"
    __A_PH="$("$@" -lW "${__A_BIN}")"
    __A_DYN="$("$@" -dW "${__A_BIN}" 2>/dev/null || true)"

    if printf '%s\n' "${__A_HDR}" | grep -qE 'Type:[[:space:]]+DYN'; then
        fAppResult PASS "position independent (PIE / shared object)"
    else
        fAppResult FAIL "not position independent: link with -fPIE -pie or -shared"
    fi

    if printf '%s\n' "${__A_PH}" | grep -qE '^[[:space:]]*GNU_RELRO'; then
        fAppResult PASS "RELRO (-Wl,-z,relro)"
    else
        fAppResult FAIL "no RELRO: add -Wl,-z,relro"
    fi

    if printf '%s\n' "${__A_DYN}" | grep -qE '\(FLAGS\).*BIND_NOW|\(FLAGS_1\).*[[:space:]]NOW([[:space:]]|$)'; then
        fAppResult PASS "BIND_NOW (-Wl,-z,now)"
    else
        fAppResult FAIL "no BIND_NOW: add -Wl,-z,now"
    fi

    __A_STACK="$(printf '%s\n' "${__A_PH}" | awk '$1=="GNU_STACK"{f=""; for(i=7;i<NF;i++) f=f $i; print f}')"
    if [[ -z "${__A_STACK}" ]]; then
        fAppResult FAIL "no GNU_STACK header: add -Wl,-z,noexecstack"
    elif [[ "${__A_STACK}" == *E* ]]; then
        fAppResult FAIL "executable stack (${__A_STACK}): add -Wl,-z,noexecstack"
    else
        fAppResult PASS "non-executable stack (-Wl,-z,noexecstack)"
    fi

    # Smallest alignment of all LOAD segments (hex converted by bash, which
    # works with every awk).
    __A_MINALIGN=""
    for __A_ALIGN in $(printf '%s\n' "${__A_PH}" | awk '$1=="LOAD"{print $NF}'); do
        __A_ALIGN="$((__A_ALIGN))"
        if [[ -z "${__A_MINALIGN}" || "${__A_ALIGN}" -lt "${__A_MINALIGN}" ]]; then
            __A_MINALIGN="${__A_ALIGN}"
        fi
    done
    if [[ -n "${__A_MINALIGN}" && "${__A_MINALIGN}" -ge 16384 ]]; then
        fAppResult PASS "16 KB page alignment (LOAD align ${__A_MINALIGN})"
    else
        fAppResult FAIL "LOAD segments aligned to ${__A_MINALIGN:-?} bytes, need 16384: add -Wl,-z,max-page-size=16384"
    fi

    if printf '%s\n' "${__A_HDR}" | grep -qE 'Machine:[[:space:]]+AArch64'; then
        if "$@" --notes "${__A_BIN}" 2>/dev/null | grep -qiE 'aarch64 feature:.*BTI'; then
            fAppResult PASS "BTI/PAC branch protection"
        else
            fAppResult WARN "no BTI/PAC: every object (incl. OpenSSL) needs -mbranch-protection=standard"
        fi
    fi
}

# ------------------------------
# @description Check the linker hardening of a final iOS/macOS Mach-O app
#  binary: PIE for executables and no executable stack.
# @arg $1 string Path to the Mach-O binary (executable or dylib).
# @stdout One PASS/FAIL line per check.
# @set __A_APP_FAILED number Set to 1 if any check failed.
# @exitcode 0 Always; failures are reported through __A_APP_FAILED.
fCheckAppMacho() {
    local __A_BIN="$1" __A_HV
    fNeed xcrun
    __A_HV="$(xcrun otool -hv -arch arm64 "${__A_BIN}" 2>/dev/null || xcrun otool -hv "${__A_BIN}")"

    if printf '%s\n' "${__A_HV}" | grep -q 'EXECUTE'; then
        if printf '%s\n' "${__A_HV}" | grep -qw 'PIE'; then
            fAppResult PASS "PIE executable"
        else
            fAppResult FAIL "executable is not PIE: remove -Wl,-no_pie"
        fi
    else
        fAppResult PASS "dynamic library / bundle (always position independent)"
    fi

    if printf '%s\n' "${__A_HV}" | grep -q 'ALLOW_STACK_EXECUTION'; then
        fAppResult FAIL "executable stack allowed: remove -Wl,-allow_stack_execute"
    else
        fAppResult PASS "non-executable stack"
    fi
}

# ------------------------------
# @description Check the linker hardening of a final app binary. ELF files
#  (Android) are read with the NDK's llvm-readelf when available, otherwise
#  readelf/llvm-readelf from PATH; Mach-O files need Xcode's otool.
# @arg $1 string Path to the final app binary.
# @stdout One PASS/FAIL/WARN line per check.
# @exitcode 0 If no check failed.
# @exitcode 1 If the file is missing or unknown, or any check failed.
fCheckApp() {
    local __A_BIN="${1:-}" __A_MAGIC __A_READELF=""
    [[ -n "${__A_BIN}" && -f "${__A_BIN}" ]] || fDie "check-app: file '${__A_BIN}' not found"
    __A_APP_FAILED=0
    __A_MAGIC="$(head -c 4 "${__A_BIN}" | od -An -tx1 | tr -d ' \n')"

    fLog "Checking linker hardening of ${__A_BIN}"
    case "${__A_MAGIC}" in
        7f454c46)
            if fResolveNdk && [[ ! "${__A_ANDROID_NDK}" =~ [[:space:]] ]] \
                && [[ -d "${__A_ANDROID_NDK}/toolchains/llvm/prebuilt" ]]; then
                __A_READELF="$(fNdkTool llvm-readelf)"
            elif command -v llvm-readelf >/dev/null 2>&1; then
                __A_READELF="llvm-readelf"
            elif command -v readelf >/dev/null 2>&1; then
                __A_READELF="readelf"
            else
                fDie "check-app: no readelf found (set ANDROID_HOME or install binutils)"
            fi
            fCheckAppElf "${__A_BIN}" "${__A_READELF}"
            ;;
        cffaedfe|cafebabe|bebafeca)
            fCheckAppMacho "${__A_BIN}"
            ;;
        *)
            fDie "check-app: '${__A_BIN}' is not an ELF or Mach-O binary"
            ;;
    esac

    [[ ${__A_APP_FAILED} -eq 0 ]] || fDie "check-app: linker hardening is incomplete (see FAIL lines above)"
    fLog "All linker hardening checks passed"
}

# -------------------------
# Main

# ------------------------------
# @description Script entry point: parse arguments, verify NDK and OpenSSL
#  (paths, version, architecture, hardening), fetch and verify the source and
#  build the selected platforms. With check-app, only checks a final binary.
# @arg $@ string Platforms and options: ios, macos, android, all, --clean,
#  --out-dir <path> (or --out-dir=<path>, -o <path>), --install-dir <path>
#  (or --install-dir=<path>), --help, or check-app <binary>.
# @stdout Build progress and the list of produced static libraries.
# @exitcode 0 If all selected platforms built successfully.
# @exitcode 1 If an argument is invalid, a tool or path is missing, a check
#  fails, or a build fails.
fMain() {
    local __A_DO_IOS=0 __A_DO_MACOS=0 __A_DO_ANDROID=0 __A_CLEAN=0 __A_ARG __A_ABI
    local __A_ANY_PLATFORM=0

    if [[ "${1:-}" == "check-app" ]]; then
        fCheckApp "${2:-}"
        return 0
    fi

    while [[ $# -gt 0 ]]; do
        __A_ARG="$1"
        case "${__A_ARG}" in
            ios)       __A_DO_IOS=1; __A_ANY_PLATFORM=1 ;;
            macos)     __A_DO_MACOS=1; __A_ANY_PLATFORM=1 ;;
            android)   __A_DO_ANDROID=1; __A_ANY_PLATFORM=1 ;;
            all)       __A_ANY_PLATFORM=1; __A_DO_ANDROID=1
                       if [[ "${__A_HOST_OS}" == "Darwin" ]]; then __A_DO_IOS=1; __A_DO_MACOS=1
                       else fWarn "not on macOS: skipping iOS and macOS"; fi ;;
            --clean)   __A_CLEAN=1 ;;
            -o|--out-dir)
                       [[ $# -ge 2 && -n "$2" && "$2" != -* ]] \
                           || fDie "${__A_ARG} needs a directory path"
                       fSetOutDir "$2"; shift ;;
            --out-dir=*)
                       fSetOutDir "${__A_ARG#--out-dir=}" ;;
            --install-dir)
                       [[ $# -ge 2 && -n "$2" && "$2" != -* ]] \
                           || fDie "${__A_ARG} needs a directory path"
                       fSetInstallDir "$2"; shift ;;
            --install-dir=*)
                       fSetInstallDir "${__A_ARG#--install-dir=}" ;;
            -h|--help) fUsage ;;
            *)         fDie "unknown argument '${__A_ARG}' (try --help)" ;;
        esac
        shift
    done

    # No platform given: build everything this host can build.
    if [[ ${__A_ANY_PLATFORM} -eq 0 ]]; then
        __A_DO_ANDROID=1
        if [[ "${__A_HOST_OS}" == "Darwin" ]]; then __A_DO_IOS=1; __A_DO_MACOS=1
        else fWarn "not on macOS: skipping iOS and macOS"; fi
    fi
    fLog "Output directory: ${__A_OUT_DIR}"
    printf '    Install directory: %s\n' "${__A_INSTALL_ROOT}"

    fNeed cmake
    case "${__A_OPENSSL_CHECK}" in
        strict|warn) ;;
        *) fDie "__A_OPENSSL_CHECK must be 'strict' or 'warn'" ;;
    esac

    # Verify the NDK and every OpenSSL before downloading anything.
    fLog "Verifying prebuilt OpenSSL"
    if [[ ${__A_DO_IOS} -eq 1 ]]; then
        fNeed xcrun
        fVerifyOpensslApple "${__A_OPENSSL_IOS}"     "ios-arm64"     ios
        fVerifyOpensslApple "${__A_OPENSSL_IOS_SIM}" "ios-simulator" iossim
    fi
    if [[ ${__A_DO_MACOS} -eq 1 ]]; then
        fNeed xcrun
        fVerifyOpensslApple "${__A_OPENSSL_MACOS}" "macos" macos
    fi
    if [[ ${__A_DO_ANDROID} -eq 1 ]]; then
        fCheckNdk
        printf '    NDK: %s (%s)\n' "${__A_ANDROID_NDK}" "${__A_ANDROID_NDK_SOURCE}"
        for __A_ABI in ${__A_ANDROID_ABIS}; do
            fVerifyOpensslAndroid "${__A_ABI}"
        done
    fi

    if [[ ${__A_CLEAN} -eq 1 ]]; then
        fLog "Cleaning previous results"
        printf '    removing %s\n' "${__A_BUILD_ROOT}"
        rm -rf "${__A_BUILD_ROOT}"
        fCleanInstall
    fi

    # Remove an XCFramework left over from older versions of this script
    # (only in the default install folder, never in a custom one).
    if [[ -z "${__A_INSTALL_DIR}" ]]; then
        rm -rf "${__A_INSTALL_ROOT}/libzip.xcframework"
    fi

    fFetchSource

    [[ ${__A_DO_IOS}     -eq 1 ]] && fBuildIos
    [[ ${__A_DO_MACOS}   -eq 1 ]] && fBuildMacos
    [[ ${__A_DO_ANDROID} -eq 1 ]] && fBuildAndroid

    fLog "Done. Static libraries in ${__A_INSTALL_ROOT}:"
    find "${__A_INSTALL_ROOT}" -path '*/lib/libzip.a' | sed "s|^${__A_INSTALL_ROOT}/|  |" | sort
    printf '\nLink your app with the flags in each LINKING.txt, then run:\n  %s check-app <your-app-binary>\n' "$0"
}

fMain "$@"
