#!/usr/bin/env bash
#
# build-liberlang.sh
#
# Builds the Erlang/OTP runtime (BEAM) as ONE STATIC LIBRARY (liberlang.a) per
# target. The ONLY output is a static archive plus its C headers: no shared
# libraries (.so / .dylib), no frameworks / xcframeworks, no executables.
# Every OTP NIF and driver is compiled in statically (--enable-static-nifs /
# --enable-static-drivers), and the result is checked at the end.
#
# OpenSSL is NOT merged into liberlang.a. OTP is compiled against your
# PREBUILT STATIC libcrypto.a, but the application must link that libcrypto.a
# itself, next to liberlang.a. The build fails if any OpenSSL symbol ends up
# inside liberlang.a.
#
# Targets:
#   ios                   iOS device, arm64            (macOS host + Xcode)
#   macos                 macOS Apple Silicon, arm64   (macOS host + Xcode)
#   android-arm64-v8a     Android arm64-v8a            (Linux/macOS host + NDK)
#   android-armeabi-v7a   Android armeabi-v7a          (Linux/macOS host + NDK)
#   android               both Android ABIs
#   all                   every target this host can build (the default when
#                         no target is given)
#
# Hardening (all targets, each flag is probed with the target compiler and
# only kept if the compiler accepts it):
#   -D_FORTIFY_SOURCE=3   if the toolchain AND its libc really implement level 3
#                         (checked by compiling a probe, see fDetectFortifyLevel),
#                         otherwise -D_FORTIFY_SOURCE=2
#   -fstack-protector-strong, -fstack-clash-protection,
#   -ftrivial-auto-var-init=zero, -fno-delete-null-pointer-checks,
#   -fno-strict-overflow, -fPIC, -Wformat -Wformat-security
#   -Werror=format-security, -D_LIBCPP_HARDENING_MODE (C++)
#   Android arm64: -mbranch-protection=standard (PAC + BTI)
#   Android:       -Wa,--noexecstack; link: -z relro -z now -z noexecstack,
#                  16 KB page alignment
#   JIT is disabled on every target (--disable-jit): the BEAM runs as an
#   interpreter and never needs writable+executable memory, which iOS code
#   signing forbids. The build fails if JIT code ends up in liberlang.a.
#   OTP applications: megaco, odbc, debugger and observer are disabled.
#   ssh, public_key, ssl, inets and snmp stay enabled when OpenSSL is used
#   (the build fails if configure would skip any of them).
#
# Source integrity: the OTP tarball is verified against a SHA-256 pinned in
# this script (or __A_OTP_SHA256) on EVERY run, also when it is cached. There
# is no way to skip verification and no checksum is fetched from the network.
#
# Prebuilt OpenSSL (static, NOT downloaded). Each directory must contain
# include/openssl/ and lib/libcrypto.a (lib64/ is accepted too). Either give a
# root laid out like the install folder:
#   __A_OPENSSL_ROOT/ios
#   __A_OPENSSL_ROOT/macos
#   __A_OPENSSL_ROOT/android/arm64-v8a
#   __A_OPENSSL_ROOT/android/armeabi-v7a
# or set a directory per target (overrides the root):
#   __A_OPENSSL_DIR_IOS, __A_OPENSSL_DIR_MACOS,
#   __A_OPENSSL_DIR_ANDROID_ARM64_V8A, __A_OPENSSL_DIR_ANDROID_ARMEABI_V7A
# The architecture (and Apple platform) of each libcrypto.a is checked.
#
# Usage:
#   ./build-liberlang.sh --openssl-dir /opt/openssl-static --install-dir /opt/liberlang ios macos
#   ./build-liberlang.sh --openssl-dir /opt/openssl-static android   # NDK from $ANDROID_HOME
#   __A_OPENSSL_ROOT=/opt/openssl-static __A_INSTALL_DIR=/opt/liberlang ./build-liberlang.sh all
#
# Options (each "--opt DIR" may also be written "--opt=DIR"; command-line
# options override the environment):
#   --install-dir DIR               install folder            [./install]
#   --openssl-dir DIR               prebuilt OpenSSL root (layout above)
#   --openssl-dir-ios DIR           prebuilt OpenSSL for ios
#   --openssl-dir-macos DIR         prebuilt OpenSSL for macos
#   --openssl-dir-android-arm64-v8a DIR
#   --openssl-dir-android-armeabi-v7a DIR
#   --ndk DIR                       Android NDK directory
#   --ndk-version VER               NDK version under $ANDROID_HOME/ndk/
#   --jobs N                        parallel make jobs (default: CPU count)
#   --clean                         delete previous install for the chosen targets
#   --print-flags                   only probe toolchains and print hardening flags
#   --no-crypto                     build without OpenSSL (no crypto, ssl, ssh)
#   -h, --help
#
# Android NDK lookup (first match wins):
#   --ndk / __A_ANDROID_NDK_HOME, $ANDROID_NDK_HOME, $ANDROID_NDK_ROOT,
#   $ANDROID_HOME/ndk/<version> (--ndk-version / __A_ANDROID_NDK_VERSION,
#   otherwise the newest installed version), $ANDROID_HOME/ndk-bundle
#
# Environment (defaults in brackets):
#   __A_INSTALL_DIR [./install]  __A_OPENSSL_ROOT, __A_OPENSSL_DIR_* (see above)
#   __A_OTP_SRC                  local OTP source dir or otp_src_*.tar.gz;
#                                when set, nothing is downloaded at all
#                                (a tarball is verified like a download)
#   __A_OTP_VERSION [28.1]       OTP release to build
#   __A_OTP_SHA256               SHA-256 of otp_src_<version>.tar.gz; required
#                                for any version other than the pinned 28.1
#   __A_IOS_MIN_VERSION [13.0]   __A_MACOS_MIN_VERSION [11.0]
#   __A_ANDROID_API [24]
#   __A_ANDROID_NDK_HOME         __A_ANDROID_NDK_VERSION
#   __A_WORK_DIR [./build]
#
# Install layout (static library + headers only):
#   install/ios/lib/liberlang.a
#   install/macos/lib/liberlang.a
#   install/android/arm64-v8a/lib/liberlang.a
#   install/android/armeabi-v7a/lib/liberlang.a
#   each with include/ (erl_nif.h, erl_driver.h, erlang_start.h ...) and
#   hardening.txt (flags used, libraries the app must link)
#
# Embedding: the library contains everything except main() and OpenSSL. Start
# the VM like OTP's own main() does: call sys_init_signal_stack(), then
# erl_start(argc, argv) (both declared in include/erlang_start.h), normally on
# a dedicated thread, with the usual erl arguments (-root, -bindir, -boot...)
# and the environment variables BINDIR, ROOTDIR, EMU, PROGNAME (see the header
# for an example, and for using the built-in DNS resolver via ERL_INETRC).
# Link the app with liberlang.a AND your prebuilt libcrypto.a.
# The Erlang code (.beam files, boot scripts) is not part of the static
# library; ship it with the app from an OTP release of the same version.
#
# Note: CC, CFLAGS, erl_xcomp_* etc. passed to OTP's configure keep their
# standard names because the OTP build system requires them.

set -Eeuo pipefail

# ==========================================================================
# Configuration
# ==========================================================================
__A_OTP_SRC="${__A_OTP_SRC:-}"
__A_OTP_VERSION="${__A_OTP_VERSION:-28.1}"
__A_OTP_SHA256="${__A_OTP_SHA256:-}"
# SHA-256 of otp_src_28.1.tar.gz, verified independently of the release's
# SHA256.txt. Never fetched at runtime.
__A_OTP_PINNED_VERSION="28.1"
__A_OTP_PINNED_SHA256="c7c6fe06a3bf0031187d4cb10d30e11de119b38bdba7cd277898f75d53bdb218"
# Fixed application policy (not overridable from the environment):
# disabled apps, and apps that must be built when OpenSSL is used.
__A_OTP_WITHOUT_APPS="megaco odbc debugger observer"
__A_OTP_REQUIRED_APPS="crypto ssh public_key ssl inets snmp"
__A_IOS_MIN_VERSION="${__A_IOS_MIN_VERSION:-13.0}"
__A_MACOS_MIN_VERSION="${__A_MACOS_MIN_VERSION:-11.0}"
__A_ANDROID_API="${__A_ANDROID_API:-24}"
__A_ANDROID_NDK_HOME="${__A_ANDROID_NDK_HOME:-}"        # resolved by fResolveNdkHome
__A_ANDROID_NDK_VERSION="${__A_ANDROID_NDK_VERSION:-}"
__A_ANDROID_NDK_FROM=""

__A_OPENSSL_ROOT="${__A_OPENSSL_ROOT:-}"
__A_OPENSSL_DIR_IOS="${__A_OPENSSL_DIR_IOS:-}"
__A_OPENSSL_DIR_MACOS="${__A_OPENSSL_DIR_MACOS:-}"
__A_OPENSSL_DIR_ANDROID_ARM64_V8A="${__A_OPENSSL_DIR_ANDROID_ARM64_V8A:-}"
__A_OPENSSL_DIR_ANDROID_ARMEABI_V7A="${__A_OPENSSL_DIR_ANDROID_ARMEABI_V7A:-}"

__A_SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
__A_WORK_DIR="${__A_WORK_DIR:-$__A_SCRIPT_DIR/build}"
__A_INSTALL_DIR="${__A_INSTALL_DIR:-$__A_SCRIPT_DIR/install}"

__A_WITH_CRYPTO=1
__A_CLEAN=0
__A_PRINT_FLAGS_ONLY=0
__A_JOBS=""

__A_ALL_TARGETS="ios macos android-arm64-v8a android-armeabi-v7a"

__A_ERL_TOP=""
__A_BUILD_TRIPLE=""

# State of the target currently being built (set by fSetupToolchain & co.)
__A_CUR_NAME=""; __A_CUR_SUBDIR=""; __A_CUR_KIND=""; __A_CUR_HOST=""; __A_CUR_ARCH=""
__A_CUR_CC=""; __A_CUR_CXX=""; __A_CUR_AR=""; __A_CUR_RANLIB=""; __A_CUR_NM=""; __A_CUR_READELF=""
__A_CUR_SYSROOT=""; __A_CUR_APPLE_PLATFORM=""; __A_CUR_PROBE_DIR=""; __A_CUR_PLATFORM_CFLAGS=""
__A_CUR_CFLAGS=""; __A_CUR_CXXFLAGS=""; __A_CUR_LDFLAGS=""; __A_CUR_HARDEN=""; __A_CUR_FORTIFY_LEVEL=""
__A_CUR_OPENSSL_SRC=""; __A_CUR_OPENSSL_STAGE=""; __A_CUR_OPENSSL_VERSION=""
__A_CUR_OTP_TARGET=""
__A_CUR_CC_ARR=()

if [ -t 2 ]; then
    __A_C_B=$'\033[1m'; __A_C_R=$'\033[31m'; __A_C_Y=$'\033[33m'; __A_C_G=$'\033[32m'; __A_C_0=$'\033[0m'
else
    __A_C_B=""; __A_C_R=""; __A_C_Y=""; __A_C_G=""; __A_C_0=""
fi

# ==========================================================================
# Helpers
# ==========================================================================

# --------------------------
# @fLog
# @description Print a progress message.
# @arg $@ string Message text.
# @stderr The message prefixed with "==>".
# @exitcode 0 Always.
fLog()  { printf '%s==>%s %s\n' "$__A_C_B" "$__A_C_0" "$*" >&2; }

# --------------------------
# @fOk
# @description Print a success message.
# @arg $@ string Message text.
# @stderr The message prefixed with "ok".
# @exitcode 0 Always.
fOk()   { printf '%s  ok%s %s\n' "$__A_C_G" "$__A_C_0" "$*" >&2; }

# --------------------------
# @fWarn
# @description Print a warning message.
# @arg $@ string Message text.
# @stderr The message prefixed with "warn:".
# @exitcode 0 Always.
fWarn() { printf '%swarn:%s %s\n' "$__A_C_Y" "$__A_C_0" "$*" >&2; }

# --------------------------
# @fDie
# @description Print an error message and terminate the script.
# @arg $@ string Message text.
# @stderr The message prefixed with "error:".
# @exitcode 1 Always (script terminates).
fDie()  { printf '%serror:%s %s\n' "$__A_C_R" "$__A_C_0" "$*" >&2; exit 1; }

# --------------------------
# @fOnErr
# @description ERR trap handler: report the command that failed.
# @arg $1 int Exit status of the failed command.
# @arg $2 int Line number.
# @arg $3 string The failed command.
# @stderr Description of the failure.
# @exitcode 0 Always (set -e then terminates the script).
fOnErr() {
    printf '%serror:%s command failed (exit %s) at line %s: %s\n' \
        "$__A_C_R" "$__A_C_0" "$1" "$2" "$3" >&2
}
trap 'fOnErr $? $LINENO "$BASH_COMMAND"' ERR

# --------------------------
# @fNeedCmd
# @description Make sure a required tool is installed.
# @arg $1 string Command name.
# @stderr Error message if the tool is missing.
# @exitcode 0 If the tool is available.
# @exitcode 1 If the tool is missing (script terminates).
fNeedCmd() { command -v "$1" >/dev/null 2>&1 || fDie "required tool not found: $1"; }

# --------------------------
# @fHostOs
# @description Name of the build machine's operating system.
# @noargs
# @stdout Output of uname -s (e.g. Linux, Darwin).
# @exitcode 0 Always.
fHostOs() { uname -s; }

# --------------------------
# @fCpuCount
# @description Number of CPUs of the build machine (default for --jobs).
# @noargs
# @stdout CPU count (4 if it cannot be determined).
# @exitcode 0 Always.
fCpuCount() {
    if command -v nproc >/dev/null 2>&1; then nproc
    elif command -v sysctl >/dev/null 2>&1; then sysctl -n hw.ncpu
    else echo 4; fi
}

# --------------------------
# @fAbsPath
# @description Convert a path (file or directory, existing or not) to an absolute path. Relative paths
#   are resolved against the current directory; if the parent directory does not exist either, the
#   path is returned unchanged.
# @arg $1 string Path (may be relative, may be empty).
# @stdout Absolute path; nothing for an empty argument.
# @exitcode 0 Always.
fAbsPath() {
    [ -n "$1" ] || return 0
    if [ -d "$1" ]; then
        (cd "$1" && pwd)
    elif [ -d "$(dirname "$1")" ]; then
        printf '%s/%s\n' "$(cd "$(dirname "$1")" && pwd)" "$(basename "$1")"
    else
        printf '%s\n' "$1"
    fi
}

# --------------------------
# @fSha256Of
# @description Compute the SHA-256 checksum of a file.
# @arg $1 string File path.
# @stdout Hex SHA-256 digest.
# @exitcode 0 On success.
fSha256Of() {
    if command -v sha256sum >/dev/null 2>&1; then sha256sum "$1" | awk '{print $1}'
    else shasum -a 256 "$1" | awk '{print $1}'; fi
}

# --------------------------
# @fDownload
# @description Download a file over HTTPS (TLS 1.2+, HTTPS-only redirects) unless it is already cached.
#   A cached file is NOT trusted: the caller must always run fVerifyDownload afterwards.
# @arg $1 string URL.
# @arg $2 string Destination file.
# @stderr Progress message.
# @exitcode 0 On success or if the file is cached.
# @exitcode 1 If the download fails (script terminates).
fDownload() {
    local __A_URL="$1" __A_DEST="$2"
    if [ -s "$__A_DEST" ]; then
        fLog "Using cached $(basename "$__A_DEST") (will be verified)"
        return 0
    fi
    fLog "Downloading $__A_URL"
    rm -f "$__A_DEST.part"
    curl -fL --proto '=https' --proto-redir '=https' --tlsv1.2 --retry 3 --retry-delay 2 \
        -o "$__A_DEST.part" "$__A_URL"
    mv "$__A_DEST.part" "$__A_DEST"
}

# --------------------------
# @fVerifyDownload
# @description Verify a file's SHA-256 against a pinned value. Runs on every build, also for cached
#   files. There is no bypass and no checksum is fetched from the network.
# @arg $1 string File path.
# @arg $2 string Expected SHA-256 (64 hex characters).
# @stderr Verification result.
# @exitcode 0 If the checksum matches.
# @exitcode 1 If the checksum is missing, malformed or does not match (file removed, script terminates).
fVerifyDownload() {
    local __A_FILE="$1" __A_EXPECTED="$2" __A_ACTUAL
    case "$__A_EXPECTED" in
        [0-9a-f]*) ;;
        *) fDie "no valid SHA-256 pinned for $(basename "$__A_FILE")" ;;
    esac
    [ "${#__A_EXPECTED}" -eq 64 ] && [ -z "$(printf '%s' "$__A_EXPECTED" | tr -d '0-9a-f')" ] \
        || fDie "malformed SHA-256 for $(basename "$__A_FILE"): $__A_EXPECTED"
    __A_ACTUAL="$(fSha256Of "$__A_FILE")"
    if [ "$__A_ACTUAL" != "$__A_EXPECTED" ]; then
        rm -f "$__A_FILE"
        fDie "SHA-256 mismatch for $(basename "$__A_FILE"): expected $__A_EXPECTED, got $__A_ACTUAL (file removed)"
    fi
    fOk "sha256 verified: $(basename "$__A_FILE")"
}

# ==========================================================================
# Toolchains
# ==========================================================================

# --------------------------
# @fNdkFromAndroidHome
# @description Find an NDK inside the Android SDK given by $ANDROID_HOME: the version from
#   __A_ANDROID_NDK_VERSION, otherwise the newest version in $ANDROID_HOME/ndk/, otherwise
#   the legacy $ANDROID_HOME/ndk-bundle.
# @noargs
# @stdout NDK directory, empty if none was found.
# @stderr Error message if the requested NDK version is not installed.
# @exitcode 0 If the lookup finished (found or not).
# @exitcode 1 If __A_ANDROID_NDK_VERSION is set but not installed (script terminates).
fNdkFromAndroidHome() {
    local __A_SDK="${ANDROID_HOME:-}" __A_VER __A_BEST=""
    [ -n "$__A_SDK" ] && [ -d "$__A_SDK" ] || return 0
    if [ -n "$__A_ANDROID_NDK_VERSION" ]; then
        [ -d "$__A_SDK/ndk/$__A_ANDROID_NDK_VERSION" ] \
            || fDie "NDK $__A_ANDROID_NDK_VERSION is not installed in $__A_SDK/ndk"
        echo "$__A_SDK/ndk/$__A_ANDROID_NDK_VERSION"
        return 0
    fi
    if [ -d "$__A_SDK/ndk" ]; then
        # newest version that contains an LLVM toolchain (numeric sort, portable)
        __A_BEST="$(for __A_VER in "$__A_SDK"/ndk/*; do
                        if [ -d "$__A_VER/toolchains/llvm" ]; then basename "$__A_VER"; fi
                    done | grep -E '^[0-9]+(\.[0-9]+)*$' \
                         | sort -t. -k1,1n -k2,2n -k3,3n -k4,4n | tail -n1 || true)"
    fi
    if [ -n "$__A_BEST" ]; then
        echo "$__A_SDK/ndk/$__A_BEST"
    elif [ -d "$__A_SDK/ndk-bundle/toolchains/llvm" ]; then
        echo "$__A_SDK/ndk-bundle"
    fi
}

# --------------------------
# @fResolveNdkHome
# @description Determine the Android NDK directory from, in this order: --ndk / __A_ANDROID_NDK_HOME,
#   $ANDROID_NDK_HOME, $ANDROID_NDK_ROOT, $ANDROID_HOME (see fNdkFromAndroidHome).
# @noargs
# @set __A_ANDROID_NDK_HOME __A_ANDROID_NDK_FROM
# @exitcode 0 Always (__A_ANDROID_NDK_HOME stays empty if no NDK was found).
# @exitcode 1 If a requested NDK version is not installed (script terminates).
fResolveNdkHome() {
    if [ -n "$__A_ANDROID_NDK_HOME" ]; then
        __A_ANDROID_NDK_FROM="--ndk / __A_ANDROID_NDK_HOME"
    elif [ -n "${ANDROID_NDK_HOME:-}" ]; then
        __A_ANDROID_NDK_HOME="$ANDROID_NDK_HOME"; __A_ANDROID_NDK_FROM="ANDROID_NDK_HOME"
    elif [ -n "${ANDROID_NDK_ROOT:-}" ]; then
        __A_ANDROID_NDK_HOME="$ANDROID_NDK_ROOT"; __A_ANDROID_NDK_FROM="ANDROID_NDK_ROOT"
    else
        __A_ANDROID_NDK_HOME="$(fNdkFromAndroidHome)" || exit 1
        if [ -n "$__A_ANDROID_NDK_HOME" ]; then __A_ANDROID_NDK_FROM="ANDROID_HOME"; fi
    fi
    __A_ANDROID_NDK_HOME="$(fAbsPath "$__A_ANDROID_NDK_HOME")"
}

# --------------------------
# @fNdkToolchainDir
# @description Locate the LLVM toolchain inside the Android NDK.
# @noargs
# @stdout Path of <NDK>/toolchains/llvm/prebuilt/<host-tag>.
# @stderr Error message if the NDK is missing or invalid.
# @exitcode 0 If the toolchain was found.
# @exitcode 1 If the NDK is not set or invalid (script terminates).
fNdkToolchainDir() {
    local __A_TAG __A_DIR
    [ -n "$__A_ANDROID_NDK_HOME" ] \
        || fDie "Android NDK not found: pass --ndk DIR, or set ANDROID_NDK_HOME, or ANDROID_HOME with an NDK installed in \$ANDROID_HOME/ndk/"
    [ -d "$__A_ANDROID_NDK_HOME" ] || fDie "NDK directory does not exist: $__A_ANDROID_NDK_HOME"
    case "$(fHostOs)" in
        Linux)  __A_TAG=linux-x86_64 ;;
        Darwin) __A_TAG=darwin-x86_64 ;;   # the NDK ships universal binaries under this name
        *) fDie "unsupported host for the Android NDK: $(fHostOs)" ;;
    esac
    __A_DIR="$__A_ANDROID_NDK_HOME/toolchains/llvm/prebuilt/$__A_TAG"
    [ -d "$__A_DIR" ] || fDie "NDK LLVM toolchain not found at $__A_DIR (NDK r23+ required, r26+ recommended)"
    echo "$__A_DIR"
}

# --------------------------
# @fSetupToolchain
# @description Select compiler, binutils, sysroot and OpenSSL location for one target.
# @arg $1 string Target name (ios, macos, android-arm64-v8a, android-armeabi-v7a).
# @set __A_CUR_NAME __A_CUR_SUBDIR __A_CUR_KIND __A_CUR_HOST __A_CUR_ARCH __A_CUR_CC __A_CUR_CXX __A_CUR_CC_ARR __A_CUR_AR __A_CUR_RANLIB __A_CUR_NM __A_CUR_READELF __A_CUR_SYSROOT __A_CUR_APPLE_PLATFORM __A_CUR_PLATFORM_CFLAGS __A_CUR_OPENSSL_SRC
# @stderr Error message if the target cannot be built on this host.
# @exitcode 0 If the toolchain is usable.
# @exitcode 1 If the target is unknown or its toolchain is missing (script terminates).
fSetupToolchain() {
    local __A_SDK __A_VER_FLAG __A_TC
    __A_CUR_NAME="$1"
    __A_CUR_PLATFORM_CFLAGS=""
    case "$__A_CUR_NAME" in
        ios|macos)
            [ "$(fHostOs)" = Darwin ] || fDie "$__A_CUR_NAME can only be built on macOS with Xcode"
            fNeedCmd xcrun
            if [ "$__A_CUR_NAME" = ios ]; then
                __A_SDK=iphoneos; __A_CUR_HOST=aarch64-apple-ios
                __A_VER_FLAG="-mios-version-min=$__A_IOS_MIN_VERSION"
                __A_CUR_APPLE_PLATFORM=2          # LC_BUILD_VERSION platform: iOS
                # OTP's own iOS config (xcomp/erl-xcomp-arm64-ios.conf) defines __IOS__.
                # OTP 28 uses it to skip <net/if_arp.h> (not in the iOS SDK), to stub
                # system() and to refuse spawning external programs.
                __A_CUR_PLATFORM_CFLAGS="-D__IOS__=1"
                __A_CUR_OPENSSL_SRC="$__A_OPENSSL_DIR_IOS"
            else
                __A_SDK=macosx; __A_CUR_HOST=aarch64-apple-darwin
                __A_VER_FLAG="-mmacosx-version-min=$__A_MACOS_MIN_VERSION"
                __A_CUR_APPLE_PLATFORM=1          # LC_BUILD_VERSION platform: macOS
                __A_CUR_OPENSSL_SRC="$__A_OPENSSL_DIR_MACOS"
            fi
            __A_CUR_SUBDIR="$__A_CUR_NAME"
            __A_CUR_KIND=apple; __A_CUR_ARCH=arm64
            __A_CUR_SYSROOT="$(xcrun --sdk "$__A_SDK" --show-sdk-path)"
            __A_CUR_CC="$(xcrun --sdk "$__A_SDK" -f clang) -arch arm64 -isysroot $__A_CUR_SYSROOT $__A_VER_FLAG"
            __A_CUR_CXX="$(xcrun --sdk "$__A_SDK" -f clang++) -arch arm64 -isysroot $__A_CUR_SYSROOT $__A_VER_FLAG"
            __A_CUR_AR="$(xcrun --sdk "$__A_SDK" -f ar)"
            __A_CUR_RANLIB="$(xcrun --sdk "$__A_SDK" -f ranlib)"
            __A_CUR_NM="$(xcrun --sdk "$__A_SDK" -f nm)"
            __A_CUR_READELF=""
            ;;
        android-arm64-v8a|android-armeabi-v7a)
            __A_TC="$(fNdkToolchainDir)" || exit 1
            __A_CUR_KIND=android; __A_CUR_APPLE_PLATFORM=""
            if [ "$__A_CUR_NAME" = android-arm64-v8a ]; then
                __A_CUR_SUBDIR=android/arm64-v8a
                __A_CUR_HOST=aarch64-linux-android; __A_CUR_ARCH=arm64
                __A_CUR_CC="$__A_TC/bin/aarch64-linux-android${__A_ANDROID_API}-clang"
                __A_CUR_CXX="$__A_TC/bin/aarch64-linux-android${__A_ANDROID_API}-clang++"
                __A_CUR_OPENSSL_SRC="$__A_OPENSSL_DIR_ANDROID_ARM64_V8A"
            else
                __A_CUR_SUBDIR=android/armeabi-v7a
                __A_CUR_HOST=arm-linux-androideabi; __A_CUR_ARCH=armv7
                __A_CUR_CC="$__A_TC/bin/armv7a-linux-androideabi${__A_ANDROID_API}-clang"
                __A_CUR_CXX="$__A_TC/bin/armv7a-linux-androideabi${__A_ANDROID_API}-clang++"
                __A_CUR_OPENSSL_SRC="$__A_OPENSSL_DIR_ANDROID_ARMEABI_V7A"
            fi
            [ -x "$__A_CUR_CC" ] || fDie "compiler not found: $__A_CUR_CC (is __A_ANDROID_API=$__A_ANDROID_API supported by this NDK?)"
            __A_CUR_SYSROOT="$__A_TC/sysroot"
            __A_CUR_AR="$__A_TC/bin/llvm-ar"; __A_CUR_RANLIB="$__A_TC/bin/llvm-ranlib"
            __A_CUR_NM="$__A_TC/bin/llvm-nm"; __A_CUR_READELF="$__A_TC/bin/llvm-readelf"
            ;;
        *) fDie "unknown target: $__A_CUR_NAME (valid: $__A_ALL_TARGETS android all)" ;;
    esac
    if [ -z "$__A_CUR_OPENSSL_SRC" ] && [ -n "$__A_OPENSSL_ROOT" ]; then
        __A_CUR_OPENSSL_SRC="$__A_OPENSSL_ROOT/$__A_CUR_SUBDIR"
    fi
    # shellcheck disable=SC2206  # intentional word splitting of "compiler + flags"
    __A_CUR_CC_ARR=($__A_CUR_CC)
}

# ==========================================================================
# Compiler probing and hardening flags
# ==========================================================================

# --------------------------
# @fCcAccepts
# @description Check whether the target compiler accepts flags (compile only, warnings are errors).
# @arg $@ string Compiler flags to test.
# @exitcode 0 If the flags are accepted.
# @exitcode 1 If the flags are rejected.
fCcAccepts() {
    printf 'int main(void){return 0;}\n' > "$__A_CUR_PROBE_DIR/p.c"
    "${__A_CUR_CC_ARR[@]}" -Werror "$@" -c "$__A_CUR_PROBE_DIR/p.c" -o "$__A_CUR_PROBE_DIR/p.o" >/dev/null 2>&1
}

# --------------------------
# @fLdAccepts
# @description Check whether the target compiler/linker accepts flags (compile + link).
# @arg $@ string Compiler/linker flags to test.
# @exitcode 0 If the flags are accepted.
# @exitcode 1 If the flags are rejected.
fLdAccepts() {
    printf 'int main(void){return 0;}\n' > "$__A_CUR_PROBE_DIR/p.c"
    "${__A_CUR_CC_ARR[@]}" -Werror "$@" "$__A_CUR_PROBE_DIR/p.c" -o "$__A_CUR_PROBE_DIR/p.out" >/dev/null 2>&1
}

# --------------------------
# @fDetectFortifyLevel
# @description Choose the highest effective _FORTIFY_SOURCE level (3, fallback 2) and add it to CFLAGS.
#   Level 3 needs compiler support (__builtin_dynamic_object_size) AND a libc
#   whose fortify headers use it; many libcs silently treat 3 as 2. The probe
#   copies a string into a malloc'd buffer whose size is only known at runtime:
#   only real level 3 can size it and emits __strcpy_chk. Level 2 is verified
#   with a fixed-size buffer the same way.
# @noargs
# @set __A_CUR_FORTIFY_LEVEL __A_CUR_CFLAGS __A_CUR_HARDEN
# @stderr Selected fortify level and fallback warnings.
# @exitcode 0 If level 3 or 2 is effective.
# @exitcode 1 If even level 2 is not effective (script terminates).
fDetectFortifyLevel() {
    local __A_ASM="$__A_CUR_PROBE_DIR/fortify.s"
    cat > "$__A_CUR_PROBE_DIR/fortify3.c" <<'EOF'
#include <stdlib.h>
#include <string.h>
#if defined(__has_builtin)
#  if !__has_builtin(__builtin_dynamic_object_size)
#    error "compiler lacks __builtin_dynamic_object_size"
#  endif
#endif
char *fortify_probe(const char *s, size_t n) {
    char *b = (char *)malloc(n);
    if (b) strcpy(b, s);
    return b;
}
EOF
    cat > "$__A_CUR_PROBE_DIR/fortify2.c" <<'EOF'
#include <string.h>
char fortify_buf[16];
void fortify_probe(const char *s) { strcpy(fortify_buf, s); }
EOF
    if "${__A_CUR_CC_ARR[@]}" -O2 -U_FORTIFY_SOURCE -D_FORTIFY_SOURCE=3 -Werror \
            -S "$__A_CUR_PROBE_DIR/fortify3.c" -o "$__A_ASM" >"$__A_CUR_PROBE_DIR/fortify3.log" 2>&1 \
       && grep -q '__strcpy_chk' "$__A_ASM"; then
        __A_CUR_FORTIFY_LEVEL=3
    else
        fWarn "$__A_CUR_NAME: _FORTIFY_SOURCE=3 not effective with this compiler/libc -> falling back to 2"
        if "${__A_CUR_CC_ARR[@]}" -O2 -U_FORTIFY_SOURCE -D_FORTIFY_SOURCE=2 -Werror \
                -S "$__A_CUR_PROBE_DIR/fortify2.c" -o "$__A_ASM" >"$__A_CUR_PROBE_DIR/fortify2.log" 2>&1 \
           && grep -q '__strcpy_chk' "$__A_ASM"; then
            __A_CUR_FORTIFY_LEVEL=2
        else
            fDie "$__A_CUR_NAME: even _FORTIFY_SOURCE=2 is not effective with this toolchain (see $__A_CUR_PROBE_DIR/fortify2.log)"
        fi
    fi
    __A_CUR_CFLAGS="$__A_CUR_CFLAGS -D_FORTIFY_SOURCE=$__A_CUR_FORTIFY_LEVEL"
    __A_CUR_HARDEN="$__A_CUR_HARDEN -D_FORTIFY_SOURCE=$__A_CUR_FORTIFY_LEVEL"
    fOk "$__A_CUR_NAME: _FORTIFY_SOURCE=$__A_CUR_FORTIFY_LEVEL"
}

# --------------------------
# @fComputeHardening
# @description Probe every hardening flag with the target toolchain and build the final compiler/linker flags
#   (including platform defines such as -D__IOS__ for iOS).
# @noargs
# @set __A_CUR_PROBE_DIR __A_CUR_HARDEN __A_CUR_CFLAGS __A_CUR_CXXFLAGS __A_CUR_LDFLAGS __A_CUR_FORTIFY_LEVEL
# @stderr Rejected flags and the selected fortify level.
# @exitcode 0 On success.
# @exitcode 1 If the compiler does not run or fortification is not effective (script terminates).
fComputeHardening() {
    local __A_FLAG __A_REJECTED=""
    local __A_CANDS=(
        -fstack-protector-strong
        -fstack-clash-protection
        -ftrivial-auto-var-init=zero
        -fno-delete-null-pointer-checks
        -fno-strict-overflow
        -fPIC
        -Wformat -Wformat-security -Werror=format-security
    )
    __A_CUR_PROBE_DIR="$__A_WORK_DIR/$__A_CUR_SUBDIR/probe"; mkdir -p "$__A_CUR_PROBE_DIR"
    "${__A_CUR_CC_ARR[@]}" --version >/dev/null 2>&1 || fDie "$__A_CUR_NAME: compiler does not run: $__A_CUR_CC"

    if [ "$__A_CUR_KIND" = android ]; then
        __A_CANDS+=("-Wa,--noexecstack")
        # PAC/BTI for Android arm64. Apple arm64 uses the arm64e ABI for pointer
        # authentication instead, so this is not applied there.
        if [ "$__A_CUR_ARCH" = arm64 ]; then __A_CANDS+=(-mbranch-protection=standard); fi
    fi

    __A_CUR_HARDEN=""
    for __A_FLAG in "${__A_CANDS[@]}"; do
        if fCcAccepts "$__A_FLAG"; then __A_CUR_HARDEN="$__A_CUR_HARDEN $__A_FLAG"
        else __A_REJECTED="$__A_REJECTED $__A_FLAG"; fi
    done
    __A_CUR_HARDEN="${__A_CUR_HARDEN# }"
    if [ -n "$__A_REJECTED" ]; then fWarn "$__A_CUR_NAME: compiler rejected:$__A_REJECTED"; fi

    __A_CUR_CFLAGS="-O2 -U_FORTIFY_SOURCE $__A_CUR_HARDEN${__A_CUR_PLATFORM_CFLAGS:+ $__A_CUR_PLATFORM_CFLAGS}"
    fDetectFortifyLevel
    __A_CUR_CXXFLAGS="$__A_CUR_CFLAGS -D_LIBCPP_HARDENING_MODE=_LIBCPP_HARDENING_MODE_FAST"

    __A_CUR_LDFLAGS=""
    if [ "$__A_CUR_KIND" = android ]; then
        for __A_FLAG in -Wl,-z,relro -Wl,-z,now -Wl,-z,noexecstack -Wl,-z,max-page-size=16384; do
            if fLdAccepts "$__A_FLAG"; then __A_CUR_LDFLAGS="$__A_CUR_LDFLAGS $__A_FLAG"
            else fWarn "$__A_CUR_NAME: linker rejected $__A_FLAG"; fi
        done
        __A_CUR_LDFLAGS="${__A_CUR_LDFLAGS# }"
    fi
}

# --------------------------
# @fPrintFlags
# @description Print the toolchain and hardening flags of the current target.
# @noargs
# @stdout Target name, compiler, fortify level, CFLAGS, CXXFLAGS, LDFLAGS, OpenSSL dir.
# @exitcode 0 Always.
fPrintFlags() {
    printf '%s[%s]%s host=%s install=%s\n' "$__A_C_B" "$__A_CUR_NAME" "$__A_C_0" "$__A_CUR_HOST" "$__A_CUR_SUBDIR"
    printf '  CC        = %s\n' "$__A_CUR_CC"
    printf '  FORTIFY   = %s\n' "$__A_CUR_FORTIFY_LEVEL"
    printf '  CFLAGS    = %s\n' "$__A_CUR_CFLAGS"
    printf '  CXXFLAGS  = %s\n' "$__A_CUR_CXXFLAGS"
    printf '  LDFLAGS   = %s\n' "${__A_CUR_LDFLAGS:-(none)}"
    printf '  OPENSSL   = %s\n' "${__A_CUR_OPENSSL_SRC:-(not set)}"
}

# ==========================================================================
# Prebuilt static OpenSSL
# ==========================================================================

# --------------------------
# @fOpensslLibDir
# @description Find the library directory (lib or lib64) of a prebuilt OpenSSL that contains libcrypto.a.
# @arg $1 string OpenSSL prefix directory.
# @stdout Library directory path.
# @exitcode 0 If libcrypto.a was found.
# @exitcode 1 If libcrypto.a was not found.
fOpensslLibDir() {
    local __A_D
    for __A_D in "$1/lib" "$1/lib64"; do
        if [ -f "$__A_D/libcrypto.a" ]; then echo "$__A_D"; return 0; fi
    done
    return 1
}

# --------------------------
# @fMachoPlatforms
# @description Extract the Apple platform IDs from `otool -l` output (LC_BUILD_VERSION "platform N"
#   or "platform NAME", and the older LC_VERSION_MIN_* load commands).
# @arg $1 string File containing `otool -l` output.
# @stdout Unique platform IDs, one per line (1=macOS, 2=iOS, 6=Mac Catalyst, 7=iOS simulator).
# @exitcode 0 Always.
fMachoPlatforms() {
    awk '$1 == "platform" {
             p = $2
             if (p == "MACOS") p = 1; else if (p == "IOS") p = 2
             else if (p == "MACCATALYST") p = 6; else if (p == "IOSSIMULATOR") p = 7
             print p
         }
         $1 == "cmd" && $2 == "LC_VERSION_MIN_MACOSX"   { print 1 }
         $1 == "cmd" && $2 == "LC_VERSION_MIN_IPHONEOS" { print 2 }' "$1" | sort -u
}

# --------------------------
# @fAppleLibPlatforms
# @description Determine the Apple platforms of the arm64 objects in a static library. Fat libraries are
#   thinned to arm64 first. If otool cannot read the whole archive, every member is extracted and read
#   separately. No pipeline is cut short, so this is safe under `set -o pipefail`.
# @arg $1 string Path of the static library.
# @arg $2 string Scratch directory (recreated).
# @stdout Unique platform IDs, one per line; empty if none could be determined.
# @exitcode 0 Always.
fAppleLibPlatforms() {
    local __A_LIB="$1" __A_DIR="$2" __A_INFO __A_O
    local __A_THIN="$2/thin.a" __A_TXT="$2/otool.txt"
    rm -rf "$__A_DIR"; mkdir -p "$__A_DIR/objs"
    __A_INFO="$(xcrun lipo -info "$__A_LIB" 2>/dev/null || true)"
    # "Non-fat file: ..." also contains "fat file", so match the fat wording exactly.
    case "$__A_INFO" in
        "Architectures in the fat file"*)
            xcrun lipo "$__A_LIB" -thin arm64 -output "$__A_THIN" 2>/dev/null || true ;;
    esac
    [ -s "$__A_THIN" ] || cp "$__A_LIB" "$__A_THIN"
    if ! xcrun otool -l "$__A_THIN" > "$__A_TXT" 2> "$__A_DIR/otool.err" \
       || [ -z "$(fMachoPlatforms "$__A_TXT")" ]; then
        : > "$__A_TXT"
        (cd "$__A_DIR/objs" && xcrun ar -x "$__A_THIN") 2>/dev/null || true
        for __A_O in "$__A_DIR"/objs/*.o; do
            [ -f "$__A_O" ] || continue
            xcrun otool -l "$__A_O" >> "$__A_TXT" 2>/dev/null || true
        done
    fi
    fMachoPlatforms "$__A_TXT"
}

# --------------------------
# @fCheckOpensslArch
# @description Verify that a prebuilt libcrypto.a matches the current target's architecture (and, on
#   Apple, that every arm64 object is built for the target platform: iOS device or macOS).
# @arg $1 string Path of libcrypto.a.
# @stderr Error message on mismatch, warning if the Apple platform cannot be determined.
# @exitcode 0 If the library matches.
# @exitcode 1 If it does not match (script terminates).
fCheckOpensslArch() {
    local __A_LIB="$1" __A_ARCHS __A_PLAT __A_MACHINES __A_WANT
    local __A_DIR="$__A_WORK_DIR/$__A_CUR_SUBDIR/openssl-check"
    if [ "$__A_CUR_KIND" = apple ]; then
        __A_ARCHS="$(xcrun lipo -archs "$__A_LIB" 2>/dev/null || true)"
        case " $__A_ARCHS " in
            *" arm64 "*) ;;
            *) fDie "$__A_CUR_NAME: $__A_LIB has architectures '$__A_ARCHS', arm64 required" ;;
        esac
        __A_PLAT="$(fAppleLibPlatforms "$__A_LIB" "$__A_DIR" | tr '\n' ' ')"
        __A_PLAT="${__A_PLAT% }"
        if [ -z "$__A_PLAT" ]; then
            fWarn "$__A_CUR_NAME: could not determine the Apple platform of $__A_LIB (see $__A_DIR/otool.err)"
        elif [ "$__A_PLAT" != "$__A_CUR_APPLE_PLATFORM" ]; then
            fDie "$__A_CUR_NAME: $__A_LIB contains objects for Apple platform(s) '$__A_PLAT', expected only $__A_CUR_APPLE_PLATFORM (1=macOS, 2=iOS, 6=Mac Catalyst, 7=iOS simulator)"
        fi
    else
        mkdir -p "$__A_DIR"
        if [ "$__A_CUR_ARCH" = arm64 ]; then __A_WANT=AArch64; else __A_WANT=ARM; fi
        "$__A_CUR_READELF" -h "$__A_LIB" > "$__A_DIR/readelf.txt" 2>/dev/null || true
        __A_MACHINES="$(awk -F: '/Machine:/ {gsub(/^[ \t]+/, "", $2); print $2}' "$__A_DIR/readelf.txt" | sort -u)"
        [ -n "$__A_MACHINES" ] || fDie "$__A_CUR_NAME: cannot read ELF headers of $__A_LIB"
        [ "$__A_MACHINES" = "$__A_WANT" ] \
            || fDie "$__A_CUR_NAME: $__A_LIB is built for '$(echo "$__A_MACHINES" | tr '\n' ' ')', expected $__A_WANT"
    fi
}

# --------------------------
# @fPrepareOpenssl
# @description Validate the prebuilt static OpenSSL of the current target and stage only its
#   headers and .a files, so OTP's configure can never pick up a shared libcrypto.
# @noargs
# @set __A_CUR_OPENSSL_STAGE __A_CUR_OPENSSL_VERSION
# @stderr OpenSSL version and location, warning if libcrypto.a lacks stack protection.
# @exitcode 0 If the prebuilt OpenSSL is usable.
# @exitcode 1 If it is missing, incomplete or for the wrong architecture (script terminates).
fPrepareOpenssl() {
    local __A_SRC="$__A_CUR_OPENSSL_SRC" __A_LIBDIR __A_SSP __A_HDR
    [ -n "$__A_SRC" ] || fDie "$__A_CUR_NAME: no prebuilt OpenSSL given (set __A_OPENSSL_ROOT or the per-target __A_OPENSSL_DIR_*), or use --no-crypto"
    [ -d "$__A_SRC" ] || fDie "$__A_CUR_NAME: OpenSSL directory does not exist: $__A_SRC"
    __A_HDR="$__A_SRC/include/openssl/opensslv.h"
    [ -f "$__A_HDR" ] || fDie "$__A_CUR_NAME: $__A_HDR not found"
    __A_LIBDIR="$(fOpensslLibDir "$__A_SRC")" || fDie "$__A_CUR_NAME: libcrypto.a not found in $__A_SRC/lib or lib64"

    fCheckOpensslArch "$__A_LIBDIR/libcrypto.a"

    __A_CUR_OPENSSL_VERSION="$(awk '/define[ \t]+OPENSSL_VERSION_TEXT/ {sub(/.*OPENSSL_VERSION_TEXT[ \t]+/, ""); gsub(/"/, ""); print; exit}' "$__A_HDR")"
    if [ -z "$__A_CUR_OPENSSL_VERSION" ]; then
        __A_CUR_OPENSSL_VERSION="$(awk '/define[ \t]+OPENSSL_FULL_VERSION_STR/ {gsub(/"/, "", $3); print $3; exit}' "$__A_HDR")"
    fi

    __A_CUR_OPENSSL_STAGE="$__A_WORK_DIR/$__A_CUR_SUBDIR/openssl"
    rm -rf "$__A_CUR_OPENSSL_STAGE"; mkdir -p "$__A_CUR_OPENSSL_STAGE/lib"
    cp -R "$__A_SRC/include" "$__A_CUR_OPENSSL_STAGE/include"
    cp "$__A_LIBDIR/libcrypto.a" "$__A_CUR_OPENSSL_STAGE/lib/"
    if [ -f "$__A_LIBDIR/libssl.a" ]; then cp "$__A_LIBDIR/libssl.a" "$__A_CUR_OPENSSL_STAGE/lib/"; fi

    # The prebuilt library was not compiled by this script: report what it has.
    __A_SSP="$("$__A_CUR_NM" "$__A_CUR_OPENSSL_STAGE/lib/libcrypto.a" 2>/dev/null | grep -Ec ' U _{0,3}__stack_chk_(fail|guard)$' || true)"
    if [ "$__A_SSP" -eq 0 ]; then
        fWarn "$__A_CUR_NAME: prebuilt libcrypto.a has no stack-protector references (not built with -fstack-protector*)"
    fi
    fOk "$__A_CUR_NAME: using prebuilt OpenSSL ${__A_CUR_OPENSSL_VERSION:-?} from $__A_SRC"
}

# ==========================================================================
# OTP
# ==========================================================================

# --------------------------
# @fExpectedOtpSha256
# @description SHA-256 the OTP tarball must have: __A_OTP_SHA256 if set, otherwise the value pinned
#   in this script for __A_OTP_PINNED_VERSION.
# @noargs
# @stdout Expected SHA-256.
# @stderr Error message if no checksum is pinned for the requested version.
# @exitcode 0 If a checksum is available.
# @exitcode 1 If no checksum is pinned for __A_OTP_VERSION (script terminates).
fExpectedOtpSha256() {
    if [ -n "$__A_OTP_SHA256" ]; then
        echo "$__A_OTP_SHA256"
    elif [ "$__A_OTP_VERSION" = "$__A_OTP_PINNED_VERSION" ]; then
        echo "$__A_OTP_PINNED_SHA256"
    else
        fDie "no SHA-256 pinned for OTP $__A_OTP_VERSION: set __A_OTP_SHA256 (verify it out of band)"
    fi
}

# --------------------------
# @fFetchSources
# @description Provide a verified OTP source tree. A tarball (downloaded, cached or given by __A_OTP_SRC)
#   is checked against the pinned SHA-256 on every run, and an extracted tree is reused only if it was
#   extracted from a tarball with that same checksum. A source directory given by __A_OTP_SRC cannot be
#   verified and is used as is (with a warning).
# @noargs
# @set __A_ERL_TOP
# @stderr Progress and verification messages.
# @exitcode 0 If the source tree is ready.
# @exitcode 1 If the source is invalid, the download fails or the checksum does not match (script terminates).
fFetchSources() {
    local __A_TGZ __A_BASE __A_SHA __A_STAMP
    if [ -n "$__A_OTP_SRC" ] && [ -d "$__A_OTP_SRC" ]; then
        [ -f "$__A_OTP_SRC/otp_build" ] || fDie "__A_OTP_SRC is not an OTP source tree: $__A_OTP_SRC"
        __A_ERL_TOP="$(cd "$__A_OTP_SRC" && pwd)"
        fWarn "using local OTP source tree $__A_ERL_TOP: a directory cannot be checksum-verified"
        return 0
    fi

    __A_SHA="$(fExpectedOtpSha256)" || exit 1
    if [ -n "$__A_OTP_SRC" ]; then
        [ -f "$__A_OTP_SRC" ] || fDie "__A_OTP_SRC does not exist: $__A_OTP_SRC"
        __A_TGZ="$__A_OTP_SRC"
    else
        fNeedCmd curl
        mkdir -p "$__A_WORK_DIR/downloads"
        __A_TGZ="$__A_WORK_DIR/downloads/otp_src_${__A_OTP_VERSION}.tar.gz"
        __A_BASE="https://github.com/erlang/otp/releases/download/OTP-${__A_OTP_VERSION}"
        fDownload "$__A_BASE/otp_src_${__A_OTP_VERSION}.tar.gz" "$__A_TGZ"
    fi
    fVerifyDownload "$__A_TGZ" "$__A_SHA"

    __A_ERL_TOP="$__A_WORK_DIR/otp_src_${__A_SHA}"
    __A_STAMP="$__A_ERL_TOP/.liberlang-source-sha256"
    if [ ! -f "$__A_ERL_TOP/otp_build" ] || [ "$(cat "$__A_STAMP" 2>/dev/null || true)" != "$__A_SHA" ]; then
        fLog "Extracting $(basename "$__A_TGZ")"
        rm -rf "$__A_ERL_TOP"; mkdir -p "$__A_ERL_TOP"
        tar -xzf "$__A_TGZ" -C "$__A_ERL_TOP" --strip-components=1
        printf '%s\n' "$__A_SHA" > "$__A_STAMP"
    fi
}

# --------------------------
# @fAutoconfScript
# @description Locate an autoconf helper script inside the OTP source tree.
# @arg $1 string Script name (config.guess or config.sub).
# @stdout Path of the script.
# @exitcode 0 If found.
# @exitcode 1 If not found (script terminates).
fAutoconfScript() {
    local __A_D
    for __A_D in "$__A_ERL_TOP/make/autoconf" "$__A_ERL_TOP/erts/autoconf"; do
        if [ -x "$__A_D/$1" ]; then echo "$__A_D/$1"; return 0; fi
    done
    fDie "$1 not found in OTP source tree"
}

# --------------------------
# @fBuildBootstrap
# @description Build the OTP bootstrap system (Erlang compiler for the build machine) required for cross compiling. Nothing from it is installed.
# @noargs
# @stderr Progress messages; tail of the log on failure.
# @exitcode 0 If built (or already built).
# @exitcode 1 If configure or make fails (script terminates).
fBuildBootstrap() {
    if [ -f "$__A_ERL_TOP/.liberlang-bootstrap-done" ]; then fOk "bootstrap already built"; return 0; fi
    fLog "Building OTP bootstrap system for the build machine"
    ( cd "$__A_ERL_TOP"
      ./configure --enable-bootstrap-only --without-termcap --without-ssl --without-javac \
          > "$__A_WORK_DIR/bootstrap-configure.log" 2>&1 \
          || { tail -n 40 "$__A_WORK_DIR/bootstrap-configure.log"; exit 1; }
      make -j "$__A_JOBS" > "$__A_WORK_DIR/bootstrap-make.log" 2>&1 \
          || { tail -n 60 "$__A_WORK_DIR/bootstrap-make.log"; exit 1; }
    )
    touch "$__A_ERL_TOP/.liberlang-bootstrap-done"
    fOk "bootstrap built"
}

# --------------------------
# @fCleanOtpTarget
# @description Remove all build output of the current target from the OTP tree (every directory named
#   after the OTP TARGET triple: objects, generated sources, dependency files, static libraries, target
#   Makefiles). Other targets and the bootstrap system are not touched; configure recreates what it needs.
# @noargs
# @stderr Progress message.
# @exitcode 0 On success.
fCleanOtpTarget() {
    [ -n "$__A_CUR_OTP_TARGET" ] || fDie "$__A_CUR_NAME: OTP TARGET unknown, refusing to clean"
    fLog "$__A_CUR_NAME: configuration changed or last build failed: removing previous $__A_CUR_OTP_TARGET build output"
    find "$__A_ERL_TOP" -type d -name "$__A_CUR_OTP_TARGET" -prune -exec rm -rf {} +
}

# --------------------------
# @fOtpAppSkipped
# @description Check whether OTP's configure marked an application as not to be built
#   (lib/<app>/SKIP from configure checks, or lib/SKIP-APPLICATIONS from --without-<app>).
# @arg $1 string Application name.
# @exitcode 0 If the application is skipped.
# @exitcode 1 If the application will be built.
fOtpAppSkipped() {
    [ -f "$__A_ERL_TOP/lib/$1/SKIP" ] && return 0
    [ -f "$__A_ERL_TOP/lib/SKIP-APPLICATIONS" ] && grep -qx "$1" "$__A_ERL_TOP/lib/SKIP-APPLICATIONS"
}

# --------------------------
# @fCheckOtpApps
# @description Enforce the application policy after configure: megaco, odbc, debugger and observer
#   must be disabled; when OpenSSL is used, crypto, ssh, public_key, ssl, inets and snmp must be built.
# @noargs
# @stderr Error message naming the offending application and the reason given by configure.
# @exitcode 0 If the policy is met.
# @exitcode 1 If it is not (script terminates).
fCheckOtpApps() {
    local __A_APP __A_WHY
    for __A_APP in $__A_OTP_WITHOUT_APPS; do
        fOtpAppSkipped "$__A_APP" || fDie "$__A_CUR_NAME: OTP application $__A_APP is not disabled"
    done
    if [ "$__A_WITH_CRYPTO" = 1 ]; then
        for __A_APP in $__A_OTP_REQUIRED_APPS; do
            if fOtpAppSkipped "$__A_APP"; then
                __A_WHY="$(cat "$__A_ERL_TOP/lib/$__A_APP/SKIP" 2>/dev/null || echo "--without-$__A_APP")"
                fDie "$__A_CUR_NAME: OTP application $__A_APP would not be built: $__A_WHY"
            fi
        done
    fi
    fOk "$__A_CUR_NAME: OTP apps disabled: $__A_OTP_WITHOUT_APPS$([ "$__A_WITH_CRYPTO" = 1 ] && printf '; enabled: %s' "$__A_OTP_REQUIRED_APPS")"
}

# --------------------------
# @fBuildOtp
# @description Configure and cross compile OTP for the current target (armeabi-v7a: --disable-year2038,
#   because 32-bit Android has a fixed 32-bit time_t) with static NIFs/drivers (the
#   static crypto NIF's libcrypto.a is passed as LIBS so OTP's build-time beam executable links; on iOS
#   loadable drivers/NIFs are linked as bundles against beam.smp, as OTP does on macOS), no JIT
#   (interpreter only: no writable+executable memory, required by iOS code signing) and the hardening
#   flags. megaco, odbc, debugger and observer are disabled; with OpenSSL, ssh, public_key, ssl, inets
#   and snmp are kept enabled (checked by fCheckOtpApps).
# @noargs
# @set __A_CUR_OTP_TARGET
# @stderr Progress messages, configure notes; tail of the log on failure.
#   If the configuration (compiler, flags, configure arguments) differs from the last successful
#   build of this target, or that build failed, the target's previous build output is removed first.
# @exitcode 0 If OTP was built.
# @exitcode 1 If configure or make fails, the prebuilt OpenSSL is rejected, or the application policy
#   is not met (script terminates).
fBuildOtp() {
    local __A_TDIR="$__A_WORK_DIR/$__A_CUR_SUBDIR" __A_APP __A_FP_FILE __A_OTP_LIBS=""
    local __A_OTP_ARGS=(
        --build="$__A_BUILD_TRIPLE" --host="$__A_CUR_HOST"
        --enable-static-nifs --enable-static-drivers
        --disable-jit
        --enable-builtin-zlib
        --without-termcap --without-javac
    )
    # Variable names below are dictated by OTP's configure.
    local __A_XCOMP=(
        erl_xcomp_sysroot="$__A_CUR_SYSROOT" erl_xcomp_bigendian=no
        erl_xcomp_double_middle_endian=no erl_xcomp_getaddrinfo=yes
        erl_xcomp_posix_memalign=yes erl_xcomp_reliable_fpe=no
    )
    for __A_APP in $__A_OTP_WITHOUT_APPS; do
        __A_OTP_ARGS+=("--without-$__A_APP")
    done
    # 32-bit Android (bionic, LP32) has a 32-bit time_t that cannot be widened:
    # there is no 64-bit time_t / _TIME_BITS=64 option, so autoconf's year-2038
    # check cannot succeed. Explicitly accept the platform's 32-bit time_t for
    # this target only (all 64-bit targets keep the check).
    if [ "$__A_CUR_NAME" = android-armeabi-v7a ]; then
        __A_OTP_ARGS+=(--disable-year2038)
    fi
    if [ "$__A_WITH_CRYPTO" = 1 ]; then
        __A_OTP_ARGS+=(--with-ssl="$__A_CUR_OPENSSL_STAGE" --disable-dynamic-ssl-lib)
        # With --enable-static-nifs OTP does not link the NIFs' external
        # dependencies itself (see `configure --help`: "for the crypto nifs you
        # want to pass LIBS=-lcrypto"). This is only for OTP's own build-time
        # beam executable; liberlang.a still does NOT contain OpenSSL. The full
        # path makes sure the static libcrypto.a is used, never a shared one.
        __A_OTP_LIBS="$__A_CUR_OPENSSL_STAGE/lib/libcrypto.a"
    else
        __A_OTP_ARGS+=(--without-ssl --without-crypto --without-ssh --without-public_key)
    fi

    __A_CUR_OTP_TARGET="$("$(fAutoconfScript config.sub)" "$__A_CUR_HOST")" || exit 1

    # OTP's configure picks the link mode for dynamically loadable drivers/NIFs
    # (runtime_tools' dyntrace, trace_*_drv, ...) from the host OS. "ios" is not
    # "darwin*", so it falls back to GNU/ELF "-shared", which Apple's linker
    # rejects because these modules use VM symbols. Use what OTP does on macOS:
    # Mach-O bundles whose VM symbols are resolved against the beam.smp built
    # just before (-bundle_loader). They are build intermediates only and are
    # never installed. Configure takes these from the environment only when all
    # DED_LD* variables are given. DED_LDFLAGS_CONFTEST is used by configure
    # tests only and must produce a plain executable (it must not be empty,
    # configure would replace it with DED_LDFLAGS). DED_LIBS is empty so
    # libcrypto.a is not added to every module.
    if [ "$__A_CUR_NAME" = ios ]; then
        __A_XCOMP+=(
            DED_LD="$__A_CUR_CC"
            DED_LDFLAGS="-bundle -bundle_loader $__A_ERL_TOP/bin/$__A_CUR_OTP_TARGET/beam.smp"
            DED_LDFLAGS_CONFTEST="-Wl,-dead_strip"
            DED_LD_FLAG_RUNTIME_LIBRARY_PATH="" DED_LIBS=""
        )
    fi

    # OTP's make reuses objects and dependency files regardless of flag changes,
    # so a changed configuration must start from a clean target build.
    __A_FP_FILE="$__A_TDIR/otp-config.fingerprint"
    printf '%s\n' "$(basename "$__A_ERL_TOP")" "$__A_CUR_CC" "$__A_CUR_CXX" "$__A_CUR_CFLAGS" \
        "$__A_CUR_CXXFLAGS" "$__A_CUR_LDFLAGS" "LIBS=$__A_OTP_LIBS" "${__A_OTP_ARGS[@]}" "${__A_XCOMP[@]}" > "$__A_FP_FILE.new"
    if ! cmp -s "$__A_FP_FILE.new" "$__A_FP_FILE"; then
        fCleanOtpTarget
    fi
    rm -f "$__A_FP_FILE"

    fLog "$__A_CUR_NAME: configuring OTP (host=$__A_CUR_HOST)"
    ( cd "$__A_ERL_TOP"
      env CC="$__A_CUR_CC" CXX="$__A_CUR_CXX" AR="$__A_CUR_AR" RANLIB="$__A_CUR_RANLIB" \
          CFLAGS="$__A_CUR_CFLAGS" CXXFLAGS="$__A_CUR_CXXFLAGS" LDFLAGS="$__A_CUR_LDFLAGS" LIBS="$__A_OTP_LIBS" \
          "${__A_XCOMP[@]}" \
          ./configure "${__A_OTP_ARGS[@]}" > "$__A_TDIR/otp-configure.log" 2>&1 \
          || { tail -n 60 "$__A_TDIR/otp-configure.log"; exit 1; }
    )
    grep -iE 'not be (built|installed)|will not|disabled' "$__A_TDIR/otp-configure.log" \
        | sed 's/^/    /' >&2 || true
    if [ "$__A_WITH_CRYPTO" = 1 ] && grep -qiE 'crypto.*(will not|not be)' "$__A_TDIR/otp-configure.log"; then
        fDie "$__A_CUR_NAME: OTP configure rejected the prebuilt OpenSSL, see $__A_TDIR/otp-configure.log"
    fi
    fCheckOtpApps

    fLog "$__A_CUR_NAME: building OTP (TARGET=$__A_CUR_OTP_TARGET, log: $__A_TDIR/otp-make.log)"
    ( cd "$__A_ERL_TOP"
      make -j "$__A_JOBS" > "$__A_TDIR/otp-make.log" 2>&1 \
          || { tail -n 80 "$__A_TDIR/otp-make.log"; exit 1; }
    )
    [ -d "$__A_ERL_TOP/erts/emulator/obj/$__A_CUR_OTP_TARGET" ] \
        || fDie "$__A_CUR_NAME: expected object dir erts/emulator/obj/$__A_CUR_OTP_TARGET not found"
    # Recorded only after a successful build: a failed build is cleaned next time.
    mv "$__A_FP_FILE.new" "$__A_FP_FILE"
    fOk "$__A_CUR_NAME: OTP built"
}

# ==========================================================================
# Packaging and verification
# ==========================================================================

# --------------------------
# @fDefinesMain
# @description Check whether an object file defines main() (such objects are left out of liberlang.a).
# @arg $1 string Object file path.
# @exitcode 0 If the object defines main.
# @exitcode 1 If it does not.
fDefinesMain() {
    "$__A_CUR_NM" -g "$1" 2>/dev/null \
        | awk '$(NF-1)=="T" && ($NF=="main" || $NF=="_main") {f=1} END {exit !f}'
}

# --------------------------
# @fEmulatorLibs
# @description System libraries OTP's configure chose for the emulator (what the app must link), without
#   the libcrypto.a path passed as LIBS (that one is listed separately).
# @noargs
# @stdout LIBS value from erts/emulator/<target>/Makefile, or a hint if not found.
# @exitcode 0 Always.
fEmulatorLibs() {
    local __A_MK="$__A_ERL_TOP/erts/emulator/$__A_CUR_OTP_TARGET/Makefile" __A_LIBS=""
    if [ -f "$__A_MK" ]; then
        __A_LIBS="$(awk -F= '/^LIBS[ \t]*=/ {sub(/^[ \t]+/, "", $2); print $2; exit}' "$__A_MK")"
        # libcrypto.a is listed separately; keep only the system libraries here.
        __A_LIBS="$(printf '%s\n' $__A_LIBS | grep -v '/libcrypto\.a$' | tr '\n' ' ' || true)"
        __A_LIBS="${__A_LIBS% }"
    fi
    echo "${__A_LIBS:-see LIBS in erts/emulator/$__A_CUR_OTP_TARGET/Makefile}"
}

# --------------------------
# @fPackageTarget
# @description Merge the emulator objects, OTP's internal archives and the static NIFs/drivers into one
#   liberlang.a and install it with the C headers. OpenSSL (libcrypto.a) is deliberately NOT merged:
#   the application links it separately. Nothing else is installed.
# @noargs
# @stderr Inputs of the archive and progress messages.
# @exitcode 0 If the static library was created.
# @exitcode 1 If inputs are missing or archiving fails (script terminates).
fPackageTarget() {
    local __A_TDIR="$__A_WORK_DIR/$__A_CUR_SUBDIR" __A_DEST="$__A_INSTALL_DIR/$__A_CUR_SUBDIR"
    local __A_T="$__A_CUR_OTP_TARGET"
    local __A_OPT="$__A_ERL_TOP/erts/emulator/obj/$__A_CUR_OTP_TARGET/opt"
    local __A_OBJDIR="$__A_OPT/emu"
    local __A_OBJS_LIST="$__A_TDIR/objs.txt" __A_LIBS_LIST="$__A_TDIR/libs.txt"
    local __A_OUT="$__A_DEST/lib/liberlang.a" __A_O __A_H
    [ -d "$__A_OBJDIR" ] || __A_OBJDIR="$__A_OPT"

    fLog "$__A_CUR_NAME: packaging liberlang.a"
    rm -rf "$__A_DEST"; mkdir -p "$__A_DEST/lib" "$__A_DEST/include"

    # 1. emulator objects, without the ones defining main() (beam's erl_main.o,
    #    erl_child_setup, ...): the embedding app calls erl_start() instead.
    : > "$__A_OBJS_LIST"
    for __A_O in "$__A_OBJDIR"/*.o; do
        [ -f "$__A_O" ] || continue
        if fDefinesMain "$__A_O"; then
            printf '    skipping %s (defines main)\n' "$(basename "$__A_O")" >&2
        else
            echo "$__A_O" >> "$__A_OBJS_LIST"
        fi
    done
    [ -s "$__A_OBJS_LIST" ] || fDie "$__A_CUR_NAME: no emulator objects found in $__A_OBJDIR"

    # 2. static archives only: emulator support libs and static NIFs/drivers.
    #    OpenSSL is NOT added: the application links libcrypto.a itself.
    {
        find "$__A_ERL_TOP/erts/emulator" -path "*/obj/$__A_T/opt/*" -name '*.a' \
             -not -path "*/opt/jit/*" -not -path "*/opt/emu/*"
        find "$__A_OPT/emu" -maxdepth 1 -name '*.a' 2>/dev/null
        for __A_O in liberts_internal_r.a libethread.a; do
            if [ -f "$__A_ERL_TOP/erts/lib/internal/$__A_T/$__A_O" ]; then
                echo "$__A_ERL_TOP/erts/lib/internal/$__A_T/$__A_O"
            fi
        done
        find "$__A_ERL_TOP/lib" -path "*/priv/lib/$__A_T/*" -name '*.a'
    } | sort -u | grep -Ev '/lib(crypto|ssl)\.a$' > "$__A_LIBS_LIST" || true
    [ -s "$__A_LIBS_LIST" ] || fDie "$__A_CUR_NAME: no OTP static archives found"
    sed "s|^$__A_ERL_TOP/||; s|^$__A_TDIR/||; s/^/    + /" "$__A_LIBS_LIST" >&2

    if [ "$__A_CUR_KIND" = apple ]; then
        # shellcheck disable=SC2046
        xcrun libtool -static -no_warning_for_no_symbols -o "$__A_OUT" \
            $(cat "$__A_OBJS_LIST") $(cat "$__A_LIBS_LIST") 2> "$__A_TDIR/libtool.log" \
            || { cat "$__A_TDIR/libtool.log"; exit 1; }
    else
        { echo "create $__A_OUT"
          while read -r __A_O; do echo "addlib $__A_O"; done < "$__A_LIBS_LIST"
          while read -r __A_O; do echo "addmod $__A_O"; done < "$__A_OBJS_LIST"
          echo "save"; echo "end"; } | "$__A_CUR_AR" -M
        "$__A_CUR_RANLIB" "$__A_OUT"
    fi

    # C headers for NIFs and for starting the VM
    for __A_H in erl_nif.h erl_nif_api_funcs.h erl_drv_nif.h erl_driver.h; do
        cp "$__A_ERL_TOP/erts/emulator/beam/$__A_H" "$__A_DEST/include/"
    done
    cp "$__A_ERL_TOP/erts/include/$__A_T/erl_int_sizes_config.h" "$__A_DEST/include/" 2>/dev/null \
        || fWarn "$__A_CUR_NAME: erl_int_sizes_config.h not found"
    cat > "$__A_DEST/include/erlang_start.h" <<'EOF'
#ifndef ERLANG_START_H
#define ERLANG_START_H
#ifdef __cplusplus
extern "C" {
#endif
/* Start the Erlang VM contained in liberlang.a the way OTP's own main() does
 * (erts/emulator/sys/unix/erl_main.c), normally on a dedicated thread:
 *     sys_init_signal_stack();   before the VM can spawn any thread
 *     erl_start(argc, argv);     does not return while the VM runs
 *
 * Before erl_start, set the environment the `erl` launcher normally sets:
 *     setenv("BINDIR",   "<root>/bin", 1);
 *     setenv("ROOTDIR",  "<root>", 1);
 *     setenv("EMU",      "beam", 1);
 *     setenv("PROGNAME", "erl", 1);
 * and pass e.g. argv = { "beam", "--", "-root", "<root>", "-bindir", "<root>/bin",
 *                        "-boot", "<root>/releases/<ver>/start", "-noshell", ... }
 * where <root> holds the OTP release files (lib/<app>/ebin, boot scripts).
 *
 * Apps cannot start helper programs (iOS forbids it), so use the VM's built-in
 * DNS resolver instead of OTP's external inet_gethost program: point
 * ERL_INETRC to a file containing   {lookup, [file, dns]}.
 *
 * The application must also link the prebuilt libcrypto.a (OpenSSL is not
 * part of liberlang.a). */
void sys_init_signal_stack(void);
void erl_start(int argc, char **argv);
#ifdef __cplusplus
}
#endif
#endif
EOF

    cat > "$__A_DEST/hardening.txt" <<EOF
target            : $__A_CUR_NAME ($__A_CUR_HOST, OTP TARGET=$__A_T)
OTP               : $(if [ -n "$__A_OTP_SRC" ] && [ -d "$__A_OTP_SRC" ]; then echo "local tree $__A_ERL_TOP (unverified)"; else echo "$__A_OTP_VERSION (sha256 $(fExpectedOtpSha256))"; fi)
OpenSSL           : $(if [ "$__A_WITH_CRYPTO" = 1 ]; then echo "NOT included in liberlang.a; compiled against prebuilt static ${__A_CUR_OPENSSL_VERSION:-?} from $__A_CUR_OPENSSL_SRC (hardening of that build is NOT controlled by this script)"; else echo "not used"; fi)
_FORTIFY_SOURCE   : $__A_CUR_FORTIFY_LEVEL
CC                : $__A_CUR_CC
CFLAGS            : $__A_CUR_CFLAGS
CXXFLAGS          : $__A_CUR_CXXFLAGS
LDFLAGS (OTP)     : ${__A_CUR_LDFLAGS:-none}
JIT               : disabled (interpreter only, no writable+executable memory)
$(if [ "$__A_CUR_NAME" = android-armeabi-v7a ]; then echo "time_t            : 32-bit (platform ABI, --disable-year2038): times after 2038-01-19 overflow"; fi)
Disabled OTP apps : $__A_OTP_WITHOUT_APPS
Enabled OTP apps  : $(if [ "$__A_WITH_CRYPTO" = 1 ]; then echo "$__A_OTP_REQUIRED_APPS (and all others)"; else echo "all others (crypto, ssh, public_key, ssl disabled by --no-crypto)"; fi)

Libraries the application must link besides liberlang.a:
  $(if [ "$__A_WITH_CRYPTO" = 1 ]; then echo "$__A_CUR_OPENSSL_SRC/lib*/libcrypto.a  (prebuilt OpenSSL, same build OTP was compiled against)"; fi)
  $(fEmulatorLibs)  (system libraries chosen by OTP's configure)
EOF
    if [ "$__A_CUR_KIND" = android ]; then
        echo "Recommended application link flags: -Wl,-z,relro -Wl,-z,now -Wl,-z,noexecstack -Wl,-z,max-page-size=16384 -pie" >> "$__A_DEST/hardening.txt"
    fi
}

# --------------------------
# @fVerifyTarget
# @description Verify the installed output: a real static archive that defines erl_start, has no main,
#   contains no OpenSSL and no JIT code, and no shared library or framework anywhere in the target's
#   install folder; report hardening symbols.
# @noargs
# @stderr Verification summary and warnings.
# @exitcode 0 If all checks pass.
# @exitcode 1 If any check fails (script terminates).
fVerifyTarget() {
    local __A_DEST="$__A_INSTALL_DIR/$__A_CUR_SUBDIR"
    local __A_LIB="$__A_DEST/lib/liberlang.a"
    local __A_SYMS="$__A_WORK_DIR/$__A_CUR_SUBDIR/liberlang.nm"
    local __A_BAD __A_CHK __A_SSP __A_TYPE
    fLog "$__A_CUR_NAME: verifying"
    [ -s "$__A_LIB" ] || fDie "$__A_CUR_NAME: $__A_LIB missing"
    __A_TYPE="$(file -b "$__A_LIB" 2>/dev/null || true)"
    case "$__A_TYPE" in
        *[Aa]r\ archive*) ;;
        *) fDie "$__A_CUR_NAME: $__A_LIB is not a static archive ($__A_TYPE)" ;;
    esac
    "$__A_CUR_NM" "$__A_LIB" > "$__A_SYMS" 2>/dev/null || true
    grep -Eq ' T _?erl_start$' "$__A_SYMS" || fDie "$__A_CUR_NAME: erl_start is not defined in liberlang.a"
    ! grep -Eq ' T _?main$' "$__A_SYMS" || fDie "$__A_CUR_NAME: liberlang.a defines main()"
    # OpenSSL must not be merged in: it may only be referenced (U), never defined.
    if grep -Eq ' [TDRB] _?(OPENSSL_init_crypto|OpenSSL_version|EVP_DigestInit_ex|CRYPTO_malloc)$' "$__A_SYMS"; then
        fDie "$__A_CUR_NAME: liberlang.a contains OpenSSL code; it must be linked separately"
    fi
    # No JIT: no asmjit / BeamAsm code may be present. (etp_beamasm exists in
    # every build: it is a debugger constant that is 0 without JIT.)
    if grep -Eq ' [TDRB] .*(asmjit|beamasm_init|BeamModuleAssembler|BeamGlobalAssembler)' "$__A_SYMS"; then
        fDie "$__A_CUR_NAME: liberlang.a contains JIT code (expected interpreter-only build)"
    fi
    __A_BAD="$(find "$__A_DEST" \( -name '*.so' -o -name '*.so.*' -o -name '*.dylib' \
                                   -o -name '*.framework' -o -name '*.xcframework' \) | awk 'NR <= 5')"
    [ -z "$__A_BAD" ] || fDie "$__A_CUR_NAME: shared libraries / frameworks found in output: $__A_BAD"

    __A_CHK="$(grep -Ec ' U _{0,3}[a-z0-9_]+_chk$' "$__A_SYMS" || true)"
    __A_SSP="$(grep -Ec ' U _{0,3}__stack_chk_(fail|guard)$' "$__A_SYMS" || true)"
    [ "$__A_SSP" -gt 0 ] || fWarn "$__A_CUR_NAME: no stack-protector references found"
    [ "$__A_CHK" -gt 0 ] || fWarn "$__A_CUR_NAME: no fortified (*_chk) calls found"
    fOk "$__A_CUR_NAME: $(du -h "$__A_LIB" | awk '{print $1}') static archive, fortify=$__A_CUR_FORTIFY_LEVEL, ${__A_CHK} fortified-call refs, ${__A_SSP} stack-protector refs"
    printf '\nverification: static archive, erl_start defined, no main, no OpenSSL, no JIT, no shared libs/frameworks, %s *_chk refs, %s stack_chk refs\n' \
        "$__A_CHK" "$__A_SSP" >> "$__A_DEST/hardening.txt"
}

# ==========================================================================
# Main
# ==========================================================================

# --------------------------
# @fUsage
# @description Print the help text (the header comment of this script).
# @noargs
# @stdout Help text.
# @exitcode 0 Always.
fUsage() {
    awk 'NR > 2 && /^#/ { sub(/^# ?/, ""); print; next } NR > 2 { exit }' "${BASH_SOURCE[0]}"
}

# --------------------------
# @fHostCanBuild
# @description Check whether a target can be built on this host (used by "all").
# @arg $1 string Target name.
# @exitcode 0 If the target can be built here.
# @exitcode 1 If not (Apple target on a non-macOS host, or no Android NDK set).
fHostCanBuild() {
    case "$1" in
        ios|macos) [ "$(fHostOs)" = Darwin ] ;;
        android-*) [ -n "$__A_ANDROID_NDK_HOME" ] ;;
        *) return 1 ;;
    esac
}

# --------------------------
# @fSetOption
# @description Store the value of a command-line option that takes an argument.
# @arg $1 string Option name (e.g. --install-dir).
# @arg $2 string Option value.
# @set __A_INSTALL_DIR __A_OPENSSL_ROOT __A_OPENSSL_DIR_IOS __A_OPENSSL_DIR_MACOS __A_OPENSSL_DIR_ANDROID_ARM64_V8A __A_OPENSSL_DIR_ANDROID_ARMEABI_V7A __A_ANDROID_NDK_HOME __A_ANDROID_NDK_VERSION __A_JOBS
# @stderr Error message if the value is empty.
# @exitcode 0 If the option was stored.
# @exitcode 1 If the value is empty or the option is unknown (script terminates).
fSetOption() {
    [ -n "$2" ] || fDie "option $1 needs a value"
    case "$1" in
        --install-dir)                     __A_INSTALL_DIR="$2" ;;
        --openssl-dir)                     __A_OPENSSL_ROOT="$2" ;;
        --openssl-dir-ios)                 __A_OPENSSL_DIR_IOS="$2" ;;
        --openssl-dir-macos)               __A_OPENSSL_DIR_MACOS="$2" ;;
        --openssl-dir-android-arm64-v8a)   __A_OPENSSL_DIR_ANDROID_ARM64_V8A="$2" ;;
        --openssl-dir-android-armeabi-v7a) __A_OPENSSL_DIR_ANDROID_ARMEABI_V7A="$2" ;;
        --ndk)                             __A_ANDROID_NDK_HOME="$2" ;;
        --ndk-version)                     __A_ANDROID_NDK_VERSION="$2" ;;
        --jobs|-j)                         __A_JOBS="$2" ;;
        *) fDie "unknown option: $1 (see --help)" ;;
    esac
}

# --------------------------
# @fMain
# @description Parse arguments (no target means "all"), validate all toolchains and prebuilt OpenSSL libraries, then build,
#   package and verify liberlang.a for every requested target.
# @arg $@ string Options and target names (see --help).
# @set __A_JOBS __A_CLEAN __A_PRINT_FLAGS_ONLY __A_WITH_CRYPTO __A_BUILD_TRIPLE __A_INSTALL_DIR __A_OPENSSL_ROOT __A_OPENSSL_DIR_*
# @stderr Progress, warnings and the list of produced libraries.
# @exitcode 0 If every target was built and verified.
# @exitcode 1 On any error (script terminates).
fMain() {
    local __A_TARGETS="" __A_TGT __A_ONE __A_TGT_LIST=""
    while [ $# -gt 0 ]; do
        case "$1" in
            --install-dir|--openssl-dir|--openssl-dir-ios|--openssl-dir-macos|\
            --openssl-dir-android-arm64-v8a|--openssl-dir-android-armeabi-v7a|\
            --ndk|--ndk-version|--jobs|-j)
                [ $# -ge 2 ] || fDie "option $1 needs a value"
                fSetOption "$1" "$2"; shift ;;
            --*=*) fSetOption "${1%%=*}" "${1#*=}" ;;
            --clean) __A_CLEAN=1 ;;
            --print-flags) __A_PRINT_FLAGS_ONLY=1 ;;
            --no-crypto) __A_WITH_CRYPTO=0 ;;
            -h|--help) fUsage; exit 0 ;;
            all|android|ios|macos|android-arm64-v8a|android-armeabi-v7a)
                __A_TGT_LIST="$__A_TGT_LIST $1" ;;
            *) fDie "unknown argument: $1 (see --help)" ;;
        esac
        shift
    done
    if [ -z "$__A_TGT_LIST" ]; then
        fLog "no target given: building all targets this host can build"
        __A_TGT_LIST="all"
    fi
    [ -n "$__A_JOBS" ] || __A_JOBS="$(fCpuCount)"
    case "$__A_JOBS" in ''|*[!0-9]*) fDie "--jobs needs a number, got '$__A_JOBS'" ;; esac

    # Targets are expanded after all options are read, so "all" sees --ndk.
    fResolveNdkHome
    for __A_TGT in $__A_TGT_LIST; do
        case "$__A_TGT" in
            all)
                for __A_ONE in $__A_ALL_TARGETS; do
                    if fHostCanBuild "$__A_ONE"; then __A_TARGETS="$__A_TARGETS $__A_ONE"
                    else fWarn "skipping $__A_ONE (not buildable on this host / no NDK)"; fi
                done ;;
            android) __A_TARGETS="$__A_TARGETS android-arm64-v8a android-armeabi-v7a" ;;
            *) __A_TARGETS="$__A_TARGETS $__A_TGT" ;;
        esac
    done
    [ -n "$__A_TARGETS" ] || fDie "none of the requested targets can be built on this host"

    # Paths given on the command line may be relative to the current directory.
    mkdir -p "$__A_WORK_DIR" "$__A_INSTALL_DIR"
    __A_WORK_DIR="$(fAbsPath "$__A_WORK_DIR")"
    __A_INSTALL_DIR="$(fAbsPath "$__A_INSTALL_DIR")"
    __A_OPENSSL_ROOT="$(fAbsPath "$__A_OPENSSL_ROOT")"
    __A_OPENSSL_DIR_IOS="$(fAbsPath "$__A_OPENSSL_DIR_IOS")"
    __A_OPENSSL_DIR_MACOS="$(fAbsPath "$__A_OPENSSL_DIR_MACOS")"
    __A_OPENSSL_DIR_ANDROID_ARM64_V8A="$(fAbsPath "$__A_OPENSSL_DIR_ANDROID_ARM64_V8A")"
    __A_OPENSSL_DIR_ANDROID_ARMEABI_V7A="$(fAbsPath "$__A_OPENSSL_DIR_ANDROID_ARMEABI_V7A")"
    case "$__A_WORK_DIR$__A_INSTALL_DIR" in
        *" "*) fDie "work and install directories must not contain spaces (OTP build limitation)" ;;
    esac
    fLog "install dir: $__A_INSTALL_DIR"
    case "$__A_TARGETS" in
        *android*)
            if [ -n "$__A_ANDROID_NDK_HOME" ]; then
                fLog "Android NDK: $__A_ANDROID_NDK_HOME (from $__A_ANDROID_NDK_FROM)"
            fi ;;
    esac

    if [ "$__A_PRINT_FLAGS_ONLY" = 1 ]; then
        for __A_TGT in $__A_TARGETS; do fSetupToolchain "$__A_TGT"; fComputeHardening; fPrintFlags; done
        exit 0
    fi

    fNeedCmd tar; fNeedCmd make; fNeedCmd perl; fNeedCmd file
    # Fail fast: every toolchain and every prebuilt OpenSSL must be valid
    # before the long OTP build starts.
    for __A_TGT in $__A_TARGETS; do
        fSetupToolchain "$__A_TGT"
        mkdir -p "$__A_WORK_DIR/$__A_CUR_SUBDIR"
        if [ "$__A_WITH_CRYPTO" = 1 ]; then fPrepareOpenssl; fi
        if [ "$__A_CLEAN" = 1 ]; then rm -rf "${__A_INSTALL_DIR:?}/$__A_CUR_SUBDIR"; fi
    done

    fFetchSources
    __A_BUILD_TRIPLE="$("$(fAutoconfScript config.guess)")" || exit 1
    fLog "build machine: $__A_BUILD_TRIPLE, jobs: $__A_JOBS"
    fBuildBootstrap

    for __A_TGT in $__A_TARGETS; do
        printf '\n' >&2
        fLog "${__A_C_B}=== $__A_TGT ===${__A_C_0}"
        fSetupToolchain "$__A_TGT"
        fComputeHardening
        fPrintFlags >&2
        if [ "$__A_WITH_CRYPTO" = 1 ]; then fPrepareOpenssl; fi
        fBuildOtp
        fPackageTarget
        fVerifyTarget
    done

    printf '\n' >&2
    fOk "done. Static libraries:"
    for __A_TGT in $__A_TARGETS; do
        fSetupToolchain "$__A_TGT"
        printf '    %s/%s/lib/liberlang.a\n' "$__A_INSTALL_DIR" "$__A_CUR_SUBDIR" >&2
    done
}

if [ "${BASH_SOURCE[0]}" = "$0" ]; then
    fMain "$@"
fi
