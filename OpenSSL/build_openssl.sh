#!/usr/bin/env bash
# =============================================================================
#  build_openssl.sh
#
#  Automatically downloads, verifies and builds the LATEST OpenSSL LTS release
#  (Long Term Support) as STATIC LIBRARIES ONLY (libcrypto.a, libssl.a) for:
#
#     iOS            arm64 (devices)
#     iOS Simulator  arm64 (Apple Silicon) [+ optional x86_64]
#     Android        arm64-v8a, armeabi-v7a
#     macOS          arm64
#
#  Output is ONLY plain static archives (.a) + public headers per platform.
#  NO frameworks of any kind are produced (no .framework, no .xcframework),
#  no shared libraries (.so / .dylib), no CMake / pkg-config files.
#  This is enforced by fVerifyStaticOnlyOutput (build fails otherwise).
#
#  Output layout (arch sub-folder ONLY for Android):
#     openssl-dist/ios/{lib,include}
#     openssl-dist/ios-simulator/{lib,include}     (multi-arch via lipo if needed)
#     openssl-dist/macos/{lib,include}
#     openssl-dist/android/<abi>/{lib,include}
#
#  Started WITHOUT parameters the script builds ALL platforms for the latest
#  (highest) supported LTS release. The Android NDK is auto-detected.
#
#  Only LTS releases are allowed:
#    * The newest LTS series that has not reached End-Of-Life is selected from
#      the table __A_LTS_SERIES_TABLE (source of truth: OpenSSL release
#      strategy https://openssl-library.org/policies/releasestrat/).
#    * The newest patch release of that series is resolved automatically from
#      the official git repository tags.
#    * Tarball integrity is always verified (SHA-256), optionally GPG.
#
#  Hardening:
#    * Every hardening flag is probed with the real target compiler.
#    * _FORTIFY_SOURCE=3 is used when the toolchain + libc headers really
#      support it (verified by a code generation probe), otherwise level 2.
#    * Hardening flags are appended as positional arguments to OpenSSL
#      Configure (which APPENDS them to its own CFLAGS/CPPFLAGS, keeping
#      -O3 etc.). The script then VERIFIES that every flag took effect:
#        1) after Configure : each flag must be present in the Makefile
#        2) after make      : each flag must be present on the real compiler
#                             command line of libcrypto and libssl objects
#      Any missing flag aborts the build. Results go to BUILD_INFO.txt.
#
#  Conventions used in this script:
#    * every variable : __A_ prefix, UPPERCASE
#    * every function : 'f' prefix, CamelCase
#
#  Requirements:
#    common  : bash (3.2+ OK), curl, git, perl, make, tar
#    Apple   : macOS host + Xcode command line tools (xcrun, clang, lipo)
#    Android : Android NDK r26+ (r27/r28 recommended), Linux or macOS host
#
#  Usage: ./build_openssl.sh --help
# =============================================================================

set -Eeuo pipefail

# -----------------------------------------------------------------------------
# Constants
# -----------------------------------------------------------------------------
__A_SCRIPT_NAME="${0##*/}"
__A_START_DIR="$(pwd)"

# OpenSSL LTS series -> End-Of-Life date (YYYY-MM-DD), NEWEST FIRST.
# When OpenSSL designates a new LTS series, add it at the top.
__A_LTS_SERIES_TABLE=(
    "3.5:2030-04-08"
    "3.0:2026-09-07"
)

__A_GIT_URL="https://github.com/openssl/openssl.git"
__A_RELEASE_URL_BASE="https://github.com/openssl/openssl/releases/download"

__A_SUPPORTED_PLATFORMS="ios ios-simulator android macos"
__A_SUPPORTED_ANDROID_ABIS="arm64-v8a armeabi-v7a"
__A_SUPPORTED_IOS_SIM_ARCHS="arm64 x86_64"

readonly __A_SCRIPT_NAME __A_START_DIR __A_LTS_SERIES_TABLE __A_GIT_URL \
         __A_RELEASE_URL_BASE __A_SUPPORTED_PLATFORMS __A_SUPPORTED_ANDROID_ABIS \
         __A_SUPPORTED_IOS_SIM_ARCHS

# -----------------------------------------------------------------------------
# User configurable defaults (may be overridden by environment or CLI options)
# -----------------------------------------------------------------------------
__A_PLATFORMS="${__A_PLATFORMS:-ios,ios-simulator,android,macos}"
__A_PLATFORMS_EXPLICIT=0
__A_ALL_MODE=0                                   # 1 = started without parameters
__A_ANDROID_ABIS="${__A_ANDROID_ABIS:-arm64-v8a,armeabi-v7a}"
__A_IOS_SIM_ARCHS="${__A_IOS_SIM_ARCHS:-arm64}"  # add x86_64 for Intel Macs
__A_ANDROID_API="${__A_ANDROID_API:-24}"
__A_ANDROID_NDK="${__A_ANDROID_NDK:-${ANDROID_NDK_ROOT:-${ANDROID_NDK_HOME:-}}}"
__A_IOS_MIN="${__A_IOS_MIN:-13.0}"
__A_MACOS_MIN="${__A_MACOS_MIN:-11.0}"
__A_WORK_DIR="${__A_WORK_DIR:-${__A_START_DIR}/openssl-work}"
__A_OUTPUT_DIR="${__A_OUTPUT_DIR:-${__A_START_DIR}/openssl-dist}"   # -o / --output-dir
__A_OUTPUT_MARKER=".openssl-dist"   # marks a directory as owned by this script
__A_JOBS="${__A_JOBS:-}"
__A_OPENSSL_VERSION="${__A_OPENSSL_VERSION:-}"   # optional pin, must belong to latest LTS
__A_FORTIFY_MAX="${__A_FORTIFY_MAX:-3}"          # highest _FORTIFY_SOURCE level to try (2|3)
__A_VERIFY_GPG="${__A_VERIFY_GPG:-0}"
__A_CLEAN="${__A_CLEAN:-0}"

# -----------------------------------------------------------------------------
# Runtime state
# -----------------------------------------------------------------------------
__A_LTS_SERIES=""
__A_LTS_EOL=""
__A_SRC_DIR=""
__A_TARBALL_SHA256=""
__A_HOST_OS="$(uname -s)"
__A_NDK_BIN=""
__A_BUILT_TARGETS=()
__A_PLATFORM_LIST=()
__A_ABI_LIST=()
__A_SIM_ARCH_LIST=()

# Per-target state (set by the platform functions, consumed by fBuildOpenssl)
__A_CUR_LABEL=""
__A_CUR_CONF_TARGET=""
__A_CUR_PREFIX=""
__A_CUR_BUILD_NAME=""      # build sub-dir: arch sub-folder ONLY for android
__A_CUR_FORTIFY_LEVEL=""
__A_CUR_NM=()
__A_CUR_READELF=""
__A_CUR_CC=()
__A_CUR_ENV=()
__A_CUR_CONF_EXTRA=()
__A_CUR_CFLAGS=()

# -----------------------------------------------------------------------------
# OpenSSL configure options (static only + security oriented), all targets
# -----------------------------------------------------------------------------
__A_CONF_COMMON=(
    --release
    --libdir=lib
    --openssldir=/etc/ssl
    no-shared               # STATIC libraries only (no .so / .dylib)
    no-module               # providers (incl. legacy) linked into libcrypto.a
    no-ssl3                 # no SSLv3 protocol
    no-ssl3-method          # no SSLv3 method API
    no-weak-ssl-ciphers     # no RC4 / weak cipher suites
    no-comp                 # no TLS compression (CRIME)
    no-engine               # deprecated ENGINE API
    no-apps                 # do not build the openssl CLI
    no-tests
    no-docs
    -DOPENSSL_TLS_SECURITY_LEVEL=2
)

# -----------------------------------------------------------------------------
# Hardening / security compiler flags
#   REQUIRED : build aborts if the compiler does not accept them
#   OPTIONAL : dropped (with a warning) if unsupported
#   _FORTIFY_SOURCE is handled separately by fDetectFortifyLevel (3 -> 2).
#
# Note: linker hardening (-z relro, -z now, -z noexecstack, 16 KB pages, ...)
# does not apply to static archives; it must be set when the final app /
# shared library is linked. Recommendations are written to BUILD_INFO.txt.
# -----------------------------------------------------------------------------
__A_HARDEN_CFLAGS_REQUIRED=(
    -fPIC                           # PIC: archives can be linked into PIE / .so (ASLR)
    -fstack-protector-strong        # stack canaries
    -Wformat
    -Wformat-security
    -Werror=format-security         # format string vulnerabilities are errors
)
__A_HARDEN_CFLAGS_OPTIONAL=(
    -fstack-clash-protection        # stack clash protection
    -ftrivial-auto-var-init=zero    # zero-init automatic variables (info leaks)
    -fno-strict-overflow            # no UB-based overflow-check elimination
    -fno-delete-null-pointer-checks # keep NULL checks
    -fno-common
)
__A_HARDEN_CFLAGS_ARM64=(
    -mbranch-protection=standard    # ARMv8.3 PAC + ARMv8.5 BTI (NOP on older CPUs)
)
__A_HARDEN_CFLAGS_X86_64=(
    -fcf-protection=full            # Intel CET (IBT + shadow stack) - x86_64 simulator only
)

# Environment variables which must NOT leak from the caller into Configure/make
__A_ENV_SANITIZE=(
    -u CC -u CXX -u CPP -u CFLAGS -u CXXFLAGS -u CPPFLAGS -u LDFLAGS -u LDLIBS
    -u AR -u RANLIB -u CROSS_COMPILE -u CROSS_TOP -u CROSS_SDK -u OPENSSL_CONF
)

# -----------------------------------------------------------------------------
# Logging
# -----------------------------------------------------------------------------
if [[ -t 2 ]]; then
    __A_C_RED=$'\033[31m'; __A_C_YEL=$'\033[33m'; __A_C_GRN=$'\033[32m'
    __A_C_BLU=$'\033[34m'; __A_C_RST=$'\033[0m'
else
    __A_C_RED=""; __A_C_YEL=""; __A_C_GRN=""; __A_C_BLU=""; __A_C_RST=""
fi

# --------------------------
# @fLog
# @description Print a timestamped, colored log line.
#
# @arg $1 string ANSI color escape sequence (may be empty).
# @arg $2 string Log level label (INFO, OK, WARN, ERROR).
# @arg $@ string Message text.
#
# @stderr Formatted log line.
# @exitcode 0 Always.
fLog() {
    local __A_COLOR="$1" __A_LEVEL="$2"
    shift 2
    printf '%s%s [%-5s]%s %s\n' "${__A_COLOR}" "$(date '+%H:%M:%S')" \
        "${__A_LEVEL}" "${__A_C_RST}" "$*" >&2
}

# --------------------------
# @fLogInfo
# @description Print an informational message.
#
# @arg $@ string Message text.
#
# @stderr Log line with INFO level.
# @exitcode 0 Always.
fLogInfo()  { fLog "${__A_C_BLU}" INFO "$@"; }

# --------------------------
# @fLogOk
# @description Print a success message.
#
# @arg $@ string Message text.
#
# @stderr Log line with OK level.
# @exitcode 0 Always.
fLogOk()    { fLog "${__A_C_GRN}" OK "$@"; }

# --------------------------
# @fLogWarn
# @description Print a warning message.
#
# @arg $@ string Message text.
#
# @stderr Log line with WARN level.
# @exitcode 0 Always.
fLogWarn()  { fLog "${__A_C_YEL}" WARN "$@"; }

# --------------------------
# @fLogError
# @description Print an error message.
#
# @arg $@ string Message text.
#
# @stderr Log line with ERROR level.
# @exitcode 0 Always.
fLogError() { fLog "${__A_C_RED}" ERROR "$@"; }

# --------------------------
# @fDie
# @description Print an error message and terminate the script.
#
# @arg $@ string Error message.
#
# @stderr Log line with ERROR level.
# @exitcode 1 Always (never returns).
fDie()      { fLogError "$@"; exit 1; }

# --------------------------
# @fOnError
# @description ERR trap handler: reports the failing command and line, then exits.
#
# @arg $1 int Line number where the failure happened.
#
# @stderr Error description with the failing command.
# @exitcode * Exit code of the failed command (never returns).
fOnError() {
    local __A_RC=$? __A_LINE="${1:-?}"
    fLogError "Unexpected failure (exit ${__A_RC}) at line ${__A_LINE}: ${BASH_COMMAND}"
    exit "${__A_RC}"
}
trap 'fOnError ${LINENO}' ERR

# -----------------------------------------------------------------------------
# Help / argument parsing
# -----------------------------------------------------------------------------

# --------------------------
# @fUsage
# @description Print command line help.
#
# @noargs
#
# @stdout Usage text.
# @exitcode 0 Always.
fUsage() {
    cat <<EOF
Usage: ${__A_SCRIPT_NAME} [options]

Builds the latest OpenSSL LTS release as STATIC libraries for
iOS (arm64), iOS Simulator (arm64 [+x86_64]), Android (arm64-v8a,
armeabi-v7a) and macOS (arm64).

Without any parameters: ALL platforms, latest (highest) supported LTS,
Android NDK auto-detected (ANDROID_NDK_ROOT, ANDROID_NDK_HOME,
ANDROID_HOME/ndk/*, ANDROID_SDK_ROOT/ndk/*, default SDK locations).

Options:
  --platforms LIST     Comma separated: ios,ios-simulator,android,macos (default: all)
  --android-abis LIST  Comma separated: arm64-v8a,armeabi-v7a (default: both)
  --ios-sim-archs LIST Comma separated: arm64,x86_64        (default: ${__A_IOS_SIM_ARCHS})
  --android-api N      Android minimum API level             (default: ${__A_ANDROID_API})
  --ndk PATH           Android NDK root (default: \$ANDROID_NDK_ROOT / \$ANDROID_NDK_HOME)
  --ios-min VER        iOS deployment target                 (default: ${__A_IOS_MIN})
  --macos-min VER      macOS deployment target               (default: ${__A_MACOS_MIN})
  --version X.Y.Z      Pin a patch release (must belong to the latest LTS series)
  --fortify-max N      Highest _FORTIFY_SOURCE level to try: 2 or 3 (default: ${__A_FORTIFY_MAX})
  -j, --jobs N         Parallel make jobs                    (default: CPU count)
  -w, --work-dir PATH  Temporary build directory             (default: ./openssl-work)
  -o, --output-dir PATH
                       Output directory for static libs + headers
                       (default: ./openssl-dist). Must be empty, not existing,
                       or a previous output of this script.
  --verify-gpg         Also verify the tarball GPG signature (keys must be imported)
  --clean              Remove work directory after a successful build
  -h, --help           Show this help

Options taking a value accept both "--opt VALUE" and "--opt=VALUE".

Examples:
  ${__A_SCRIPT_NAME}                                   # all platforms -> ./openssl-dist
  ${__A_SCRIPT_NAME} -o ~/libs/openssl                 # all platforms -> ~/libs/openssl
  ${__A_SCRIPT_NAME} --output-dir=/opt/deps/openssl --platforms android
  __A_OUTPUT_DIR=/tmp/ossl ${__A_SCRIPT_NAME}           # via environment

Every option can also be given as an environment variable (__A_OUTPUT_DIR, __A_PLATFORMS,
__A_ANDROID_NDK, __A_ANDROID_API, __A_IOS_MIN, __A_FORTIFY_MAX, __A_JOBS, ...).
EOF
}

# --------------------------
# @fRequireValue
# @description Ensure a command line option is followed by a non-empty value.
#
# @arg $1 string Option name.
# @arg $2 string Option value (next command line argument).
#
# @stderr Error message if the value is missing.
# @exitcode 0 If a value is present.
# @exitcode 1 If the value is missing (script terminates).
fRequireValue() {
    [[ $# -ge 2 && -n "$2" && "$2" != --* ]] || fDie "Option '$1' requires a value"
}

# --------------------------
# @fParseArgs
# @description Parse command line options into __A_* configuration variables.
#   Supports "--opt VALUE", "--opt=VALUE" and short aliases (-o, -j, -w).
#
# @arg $@ string Command line arguments.
#
# @set __A_PLATFORMS __A_ANDROID_ABIS __A_IOS_SIM_ARCHS __A_ANDROID_API __A_ANDROID_NDK __A_IOS_MIN
#      __A_MACOS_MIN __A_OPENSSL_VERSION __A_FORTIFY_MAX __A_JOBS __A_WORK_DIR
#      __A_OUTPUT_DIR __A_VERIFY_GPG __A_CLEAN
# @stdout Help text when -h/--help is given.
# @exitcode 0 On success (or after printing help).
# @exitcode 1 On unknown option or missing option value.
fParseArgs() {
    while [[ $# -gt 0 ]]; do
        # "--opt=value" -> "--opt" "value"
        if [[ "$1" == --*=* ]]; then
            set -- "${1%%=*}" "${1#*=}" "${@:2}"
            [[ -n "$2" ]] || fDie "Option '$1' requires a non-empty value"
        fi
        case "$1" in
            --platforms)      fRequireValue "$@"; __A_PLATFORMS="$2"; __A_PLATFORMS_EXPLICIT=1; shift 2 ;;
            --android-abis)   fRequireValue "$@"; __A_ANDROID_ABIS="$2"; shift 2 ;;
            --ios-sim-archs)  fRequireValue "$@"; __A_IOS_SIM_ARCHS="$2"; shift 2 ;;
            --android-api)    fRequireValue "$@"; __A_ANDROID_API="$2"; shift 2 ;;
            --ndk)            fRequireValue "$@"; __A_ANDROID_NDK="$2"; shift 2 ;;
            --ios-min)        fRequireValue "$@"; __A_IOS_MIN="$2"; shift 2 ;;
            --macos-min)      fRequireValue "$@"; __A_MACOS_MIN="$2"; shift 2 ;;
            --version)        fRequireValue "$@"; __A_OPENSSL_VERSION="$2"; shift 2 ;;
            --fortify-max)    fRequireValue "$@"; __A_FORTIFY_MAX="$2"; shift 2 ;;
            -j|--jobs)        fRequireValue "$@"; __A_JOBS="$2"; shift 2 ;;
            -w|--work-dir)    fRequireValue "$@"; __A_WORK_DIR="$2"; shift 2 ;;
            -o|--output-dir)  fRequireValue "$@"; __A_OUTPUT_DIR="$2"; shift 2 ;;
            --verify-gpg)     __A_VERIFY_GPG=1; shift ;;
            --clean)          __A_CLEAN=1; shift ;;
            -h|--help)        fUsage; exit 0 ;;
            *)                fUsage >&2; fDie "Unknown option: $1" ;;
        esac
    done
}

# -----------------------------------------------------------------------------
# Generic helpers
# -----------------------------------------------------------------------------

# --------------------------
# @fToLower
# @description Convert a string to lower case (bash 3.2 compatible).
#
# @arg $1 string Input string.
#
# @stdout Lower-cased string.
# @exitcode 0 Always.
fToLower() { printf '%s' "$1" | tr '[:upper:]' '[:lower:]'; }

# --------------------------
# @fListContains
# @description Check whether a space separated list contains an item.
#
# @arg $1 string Space separated list.
# @arg $2 string Item to look for.
#
# @exitcode 0 If the item is in the list.
# @exitcode 1 If the item is not in the list.
fListContains() {
    case " $1 " in *" $2 "*) return 0 ;; *) return 1 ;; esac
}

# --------------------------
# @fAbsPath
# @description Create a directory (if needed) and return its absolute physical path.
#
# @arg $1 string Directory path (relative or absolute).
#
# @stdout Absolute path of the directory.
# @exitcode 0 On success.
# @exitcode 1 If the directory cannot be created or entered.
fAbsPath() {
    mkdir -p "$1"
    (cd "$1" && pwd -P)
}

# --------------------------
# @fVersionToNumber
# @description Convert a "MAJOR.MINOR.PATCH" version into a comparable integer.
#
# @arg $1 string Version string, e.g. "3.5.4".
#
# @stdout Integer, e.g. 3005004.
# @exitcode 0 Always.
fVersionToNumber() {
    local __A_MAJ __A_MIN __A_PAT
    IFS=. read -r __A_MAJ __A_MIN __A_PAT <<< "$1"
    echo $(( 10#${__A_MAJ:-0} * 1000000 + 10#${__A_MIN:-0} * 1000 + 10#${__A_PAT:-0} ))
}

# --------------------------
# @fSha256
# @description Compute the SHA-256 digest of a file (sha256sum or shasum).
#
# @arg $1 string Path to the file.
#
# @stdout Lower-case hex SHA-256 digest.
# @exitcode 0 On success.
# @exitcode 1 If the file cannot be read.
fSha256() {
    if command -v sha256sum >/dev/null 2>&1; then
        sha256sum "$1" | awk '{print $1}'
    else
        shasum -a 256 "$1" | awk '{print $1}'
    fi
}

# --------------------------
# @fSafeRemove
# @description Recursively remove a path, but only inside the work/output directories.
#
# @arg $1 string Path to remove.
#
# @stderr Error message if the path is outside the allowed directories.
# @exitcode 0 If the path was removed.
# @exitcode 1 If the path is empty, "/" or outside the allowed directories.
fSafeRemove() {
    local __A_TARGET="$1"
    [[ -n "${__A_TARGET}" && "${__A_TARGET}" != "/" ]] || fDie "Refusing to remove '${__A_TARGET}'"
    case "${__A_TARGET}" in
        "${__A_WORK_DIR}"/*|"${__A_OUTPUT_DIR}"/*|"${__A_WORK_DIR}") rm -rf -- "${__A_TARGET}" ;;
        *) fDie "Refusing to remove path outside work/output dir: ${__A_TARGET}" ;;
    esac
}

# --------------------------
# @fFetch
# @description Download a URL over HTTPS only (TLS 1.2+), with retries.
#
# @arg $1 string Source URL.
# @arg $2 string Destination file path.
#
# @stderr curl error messages.
# @exitcode 0 If the download succeeded.
# @exitcode * curl exit code on failure.
fFetch() {
    curl --fail --location --silent --show-error \
         --proto '=https' --tlsv1.2 \
         --retry 3 --retry-delay 3 --connect-timeout 30 \
         --output "$2" "$1"
}

# --------------------------
# @fRunLogged
# @description Run a command, appending its output to a log file; on failure show the log tail and abort.
#
# @arg $1 string Log file path.
# @arg $@ string Command and its arguments.
#
# @stderr Last 40 lines of the log on failure.
# @exitcode 0 If the command succeeded.
# @exitcode 1 If the command failed (script terminates).
fRunLogged() {
    local __A_LOG_FILE="$1"
    shift
    printf '\n$ %s\n' "$*" >> "${__A_LOG_FILE}"
    if ! "$@" >> "${__A_LOG_FILE}" 2>&1; then
        fLogError "Command failed: $*"
        echo "----- last 40 lines of ${__A_LOG_FILE} -----" >&2
        tail -n 40 "${__A_LOG_FILE}" >&2 || true
        fDie "Build failed. Full log: ${__A_LOG_FILE}"
    fi
}

# -----------------------------------------------------------------------------
# Environment / prerequisites
# -----------------------------------------------------------------------------

# --------------------------
# @fExpandPath
# @description Expand a leading "~" (e.g. when the path was quoted in the shell) and make it absolute
#   relative to the directory the script was started from. The path does not have to exist.
#
# @arg $1 string Path given by the user.
#
# @stdout Absolute path (not normalized for "..", not created).
# @exitcode 0 Always.
fExpandPath() {
    local __A_PATH="$1"
    case "${__A_PATH}" in
        "~")   __A_PATH="${HOME}" ;;
        "~/"*) __A_PATH="${HOME}/${__A_PATH#\~/}" ;;
    esac
    [[ "${__A_PATH}" == /* ]] || __A_PATH="${__A_START_DIR}/${__A_PATH}"
    # strip trailing slashes (but keep "/")
    while [[ "${__A_PATH}" == */ && "${__A_PATH}" != "/" ]]; do __A_PATH="${__A_PATH%/}"; done
    echo "${__A_PATH}"
}

# --------------------------
# @fPrepareOutputDir
# @description Validate and create the output directory given by -o/--output-dir (or __A_OUTPUT_DIR).
#   Protects user data: the directory must not exist, be empty, or carry this script's marker
#   file from a previous run. System/home/root directories and overlap with the work dir are refused.
#
# @noargs
#
# @set __A_OUTPUT_DIR (absolute, physical path)
# @stderr Selected output directory, or the reason it was refused.
# @exitcode 0 If the output directory is ready.
# @exitcode 1 If the directory is unsafe, not empty/foreign, or not writable (script terminates).
fPrepareOutputDir() {
    local __A_DIR __A_CONTENT
    [[ -n "${__A_OUTPUT_DIR}" ]] || fDie "Output directory must not be empty"
    __A_DIR="$(fExpandPath "${__A_OUTPUT_DIR}")"

    case "${__A_DIR}" in
        /|/bin|/sbin|/usr|/usr/*|/etc|/etc/*|/System|/System/*|/Library|/Applications|/var|/opt|/tmp|"${HOME}")
            fDie "Refusing to use '${__A_DIR}' as output directory - choose a dedicated sub-directory" ;;
    esac

    if [[ -e "${__A_DIR}" && ! -d "${__A_DIR}" ]]; then
        fDie "Output path exists and is not a directory: ${__A_DIR}"
    fi
    if [[ -d "${__A_DIR}" ]]; then
        __A_CONTENT="$(ls -A "${__A_DIR}" 2>/dev/null || true)"
        if [[ -n "${__A_CONTENT}" && ! -f "${__A_DIR}/${__A_OUTPUT_MARKER}" ]]; then
            fDie "Output directory '${__A_DIR}' is not empty and was not created by this script - use an empty or new directory"
        fi
    fi

    mkdir -p "${__A_DIR}" 2>/dev/null || fDie "Cannot create output directory: ${__A_DIR}"
    [[ -w "${__A_DIR}" ]] || fDie "Output directory is not writable: ${__A_DIR}"
    __A_OUTPUT_DIR="$(cd "${__A_DIR}" && pwd -P)"

    case "${__A_WORK_DIR}/" in
        "${__A_OUTPUT_DIR}/"*) fDie "Work directory must not be inside the output directory" ;;
    esac
    case "${__A_OUTPUT_DIR}/" in
        "${__A_WORK_DIR}/"*) fDie "Output directory must not be inside the work directory" ;;
    esac

    echo "Created by ${__A_SCRIPT_NAME}: OpenSSL static libraries output directory." \
        > "${__A_OUTPUT_DIR}/${__A_OUTPUT_MARKER}"
    fLogInfo "Output directory: ${__A_OUTPUT_DIR}"
}

# --------------------------
# @fDetectJobs
# @description Determine the number of parallel make jobs (CPU count) unless given.
#
# @noargs
#
# @set __A_JOBS
# @exitcode 0 On success.
# @exitcode 1 If a user supplied value is not a number.
fDetectJobs() {
    if [[ -n "${__A_JOBS}" ]]; then
        [[ "${__A_JOBS}" =~ ^[0-9]+$ ]] || fDie "--jobs must be a number"
        return 0
    fi
    if command -v nproc >/dev/null 2>&1; then
        __A_JOBS="$(nproc)"
    elif command -v sysctl >/dev/null 2>&1 && sysctl -n hw.ncpu >/dev/null 2>&1; then
        __A_JOBS="$(sysctl -n hw.ncpu)"
    else
        __A_JOBS=4
    fi
}

# --------------------------
# @fCheckPrerequisites
# @description Verify required host tools and validate numeric options.
#
# @noargs
#
# @stderr Error message for the first missing tool / invalid option.
# @exitcode 0 If all prerequisites are satisfied.
# @exitcode 1 If a tool is missing or an option is invalid.
fCheckPrerequisites() {
    local __A_CMD
    for __A_CMD in curl git perl make tar awk sed grep; do
        command -v "${__A_CMD}" >/dev/null 2>&1 || fDie "Required tool not found: ${__A_CMD}"
    done
    if ! command -v sha256sum >/dev/null 2>&1 && ! command -v shasum >/dev/null 2>&1; then
        fDie "Required tool not found: sha256sum or shasum"
    fi
    if [[ "${__A_VERIFY_GPG}" == "1" ]]; then
        command -v gpg >/dev/null 2>&1 || fDie "--verify-gpg requested but gpg is not installed"
    fi
    [[ "${__A_ANDROID_API}" =~ ^[0-9]+$ ]] || fDie "Invalid Android API level: ${__A_ANDROID_API}"
    [[ "${__A_FORTIFY_MAX}" == "2" || "${__A_FORTIFY_MAX}" == "3" ]] \
        || fDie "--fortify-max must be 2 or 3"
}

# --------------------------
# @fResolvePlatforms
# @description Validate and normalize requested platforms and Android ABIs for this host.
#
# @noargs
#
# @set __A_PLATFORM_LIST __A_ABI_LIST __A_SIM_ARCH_LIST
# @stderr Warnings for platforms skipped on a non-macOS host.
# @exitcode 0 If at least one platform can be built.
# @exitcode 1 On unsupported platform/ABI/arch or if nothing can be built.
fResolvePlatforms() {
    local __A_RAW_LIST=() __A_ITEM __A_LOWER
    IFS=',' read -r -a __A_RAW_LIST <<< "${__A_PLATFORMS}"
    __A_PLATFORM_LIST=()
    for __A_ITEM in ${__A_RAW_LIST[@]+"${__A_RAW_LIST[@]}"}; do
        __A_LOWER="$(fToLower "${__A_ITEM// /}")"
        [[ -n "${__A_LOWER}" ]] || continue
        fListContains "${__A_SUPPORTED_PLATFORMS}" "${__A_LOWER}" \
            || fDie "Unsupported platform '${__A_ITEM}' (supported: ${__A_SUPPORTED_PLATFORMS})"
        fListContains "${__A_PLATFORM_LIST[*]:-}" "${__A_LOWER}" && continue    # skip duplicates
        if [[ "${__A_LOWER}" != "android" && "${__A_HOST_OS}" != "Darwin" ]]; then
            if [[ "${__A_PLATFORMS_EXPLICIT}" == "1" ]]; then
                fDie "Platform '${__A_LOWER}' can only be built on a macOS host with Xcode"
            fi
            fLogWarn "Skipping '${__A_LOWER}': requires a macOS host with Xcode"
            continue
        fi
        __A_PLATFORM_LIST+=("${__A_LOWER}")
    done
    [[ ${#__A_PLATFORM_LIST[@]} -gt 0 ]] || fDie "Nothing to build on this host"

    __A_RAW_LIST=()
    IFS=',' read -r -a __A_RAW_LIST <<< "${__A_ANDROID_ABIS}"
    __A_ABI_LIST=()
    for __A_ITEM in ${__A_RAW_LIST[@]+"${__A_RAW_LIST[@]}"}; do
        __A_ITEM="${__A_ITEM// /}"
        [[ -n "${__A_ITEM}" ]] || continue
        fListContains "${__A_SUPPORTED_ANDROID_ABIS}" "${__A_ITEM}" \
            || fDie "Unsupported Android ABI '${__A_ITEM}' (supported: ${__A_SUPPORTED_ANDROID_ABIS})"
        __A_ABI_LIST+=("${__A_ITEM}")
    done

    __A_RAW_LIST=()
    IFS=',' read -r -a __A_RAW_LIST <<< "${__A_IOS_SIM_ARCHS}"
    __A_SIM_ARCH_LIST=()
    for __A_ITEM in ${__A_RAW_LIST[@]+"${__A_RAW_LIST[@]}"}; do
        __A_ITEM="${__A_ITEM// /}"
        [[ -n "${__A_ITEM}" ]] || continue
        fListContains "${__A_SUPPORTED_IOS_SIM_ARCHS}" "${__A_ITEM}" \
            || fDie "Unsupported iOS Simulator arch '${__A_ITEM}' (supported: ${__A_SUPPORTED_IOS_SIM_ARCHS})"
        __A_SIM_ARCH_LIST+=("${__A_ITEM}")
    done
}

# --------------------------
# @fFindNewestNdkIn
# @description Find the newest NDK (highest version directory name) inside an SDK "ndk" directory.
#
# @arg $1 string Directory containing side-by-side NDKs (e.g. $ANDROID_HOME/ndk).
#
# @stdout Path of the newest valid NDK, or nothing if none was found.
# @exitcode 0 Always.
fFindNewestNdkIn() {
    local __A_DIR="$1" __A_CAND __A_NAME __A_NUM __A_BEST="" __A_BEST_NUM=-1
    [[ -d "${__A_DIR}" ]] || return 0
    for __A_CAND in "${__A_DIR}"/*; do
        [[ -f "${__A_CAND}/source.properties" ]] || continue
        __A_NAME="${__A_CAND##*/}"
        [[ "${__A_NAME}" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || continue
        # NDK build numbers are large: compare major.minor first, then build
        __A_NUM="$(( $(fVersionToNumber "${__A_NAME%.*}.0") * 100000000 + 10#${__A_NAME##*.} ))"
        if [[ "${__A_NUM}" -gt "${__A_BEST_NUM}" ]]; then
            __A_BEST="${__A_CAND}"
            __A_BEST_NUM="${__A_NUM}"
        fi
    done
    [[ -n "${__A_BEST}" ]] && echo "${__A_BEST}"
    return 0
}

# --------------------------
# @fAutoDetectNdk
# @description Locate an Android NDK when none was given (env vars, then SDK side-by-side NDKs).
#
# @noargs
#
# @set __A_ANDROID_NDK
# @stderr Detected NDK path.
# @exitcode 0 If an NDK was found (or was already set).
# @exitcode 1 If no NDK could be found (script terminates).
fAutoDetectNdk() {
    local __A_SDK __A_FOUND=""
    [[ -n "${__A_ANDROID_NDK}" ]] && return 0
    for __A_SDK in "${ANDROID_HOME:-}" "${ANDROID_SDK_ROOT:-}" \
                   "${HOME}/Library/Android/sdk" "${HOME}/Android/Sdk"; do
        [[ -n "${__A_SDK}" ]] || continue
        __A_FOUND="$(fFindNewestNdkIn "${__A_SDK}/ndk")"
        if [[ -z "${__A_FOUND}" && -f "${__A_SDK}/ndk-bundle/source.properties" ]]; then
            __A_FOUND="${__A_SDK}/ndk-bundle"
        fi
        [[ -n "${__A_FOUND}" ]] && break
    done
    [[ -n "${__A_FOUND}" ]] || fDie "Android NDK not found: install it (SDK Manager -> NDK) or use --ndk / ANDROID_NDK_ROOT"
    __A_ANDROID_NDK="${__A_FOUND}"
    fLogInfo "Auto-detected Android NDK: ${__A_ANDROID_NDK}"
}

# --------------------------
# @fPreflightToolchains
# @description Check every required toolchain BEFORE downloading/building, so missing tools fail fast.
#
# @noargs
#
# @stderr Error for the first missing toolchain.
# @exitcode 0 If all toolchains for the selected platforms are available.
# @exitcode 1 If a toolchain/SDK is missing (script terminates).
fPreflightToolchains() {
    local __A_PLATFORM
    for __A_PLATFORM in "${__A_PLATFORM_LIST[@]}"; do
        case "${__A_PLATFORM}" in
            ios)           fCheckApple iphoneos ;;
            ios-simulator) fCheckApple iphonesimulator
                           [[ ${#__A_SIM_ARCH_LIST[@]} -gt 0 ]] || fDie "No iOS Simulator archs selected" ;;
            macos)         fCheckApple macosx ;;
            android)       [[ ${#__A_ABI_LIST[@]} -gt 0 ]] || fDie "No Android ABIs selected"
                           fCheckAndroidNdk ;;
        esac
    done
    fLogOk "Toolchains OK for: ${__A_PLATFORM_LIST[*]}"
}

# --------------------------
# @fCheckApple
# @description Verify the host can build for an Apple SDK (macOS host, xcrun, SDK installed).
#
# @arg $1 string Apple SDK name ("iphoneos" or "macosx").
#
# @stderr Error message if the toolchain or SDK is missing.
# @exitcode 0 If the SDK is available.
# @exitcode 1 If the host/toolchain/SDK is not usable.
fCheckApple() {
    [[ "${__A_HOST_OS}" == "Darwin" ]] || fDie "Apple targets require a macOS host"
    command -v xcrun >/dev/null 2>&1 || fDie "xcrun not found: install Xcode / command line tools"
    xcrun --sdk "$1" --show-sdk-path >/dev/null 2>&1 \
        || fDie "Apple SDK '$1' not found (install Xcode, run 'xcode-select -s')"
}

# --------------------------
# @fCheckAndroidNdk
# @description Validate the Android NDK location (auto-detected if not set), host toolchain and version.
#
# @noargs
#
# @set __A_ANDROID_NDK __A_NDK_BIN
# @stderr NDK information and warnings for old NDK versions.
# @exitcode 0 If the NDK is usable.
# @exitcode 1 If the NDK is missing or invalid.
fCheckAndroidNdk() {
    local __A_HOST_TAG __A_NDK_REV __A_NDK_MAJOR
    fAutoDetectNdk
    [[ -f "${__A_ANDROID_NDK}/source.properties" ]] || fDie "Not a valid NDK: ${__A_ANDROID_NDK}"
    __A_ANDROID_NDK="$(cd "${__A_ANDROID_NDK}" && pwd -P)"

    case "${__A_HOST_OS}" in
        Linux)  __A_HOST_TAG="linux-x86_64" ;;
        Darwin) __A_HOST_TAG="darwin-x86_64" ;;   # universal binaries on Apple Silicon
        *)      fDie "Unsupported host for Android NDK: ${__A_HOST_OS}" ;;
    esac
    __A_NDK_BIN="${__A_ANDROID_NDK}/toolchains/llvm/prebuilt/${__A_HOST_TAG}/bin"
    [[ -x "${__A_NDK_BIN}/clang" ]] || fDie "NDK clang not found in ${__A_NDK_BIN}"

    __A_NDK_REV="$(sed -n 's/^Pkg\.Revision *= *//p' "${__A_ANDROID_NDK}/source.properties" | tr -d '\r')"
    __A_NDK_MAJOR="${__A_NDK_REV%%.*}"
    fLogInfo "Android NDK ${__A_NDK_REV} (${__A_ANDROID_NDK})"
    if [[ "${__A_NDK_MAJOR}" =~ ^[0-9]+$ ]] && [[ "${__A_NDK_MAJOR}" -lt 26 ]]; then
        fLogWarn "NDK r${__A_NDK_MAJOR} is old; r27+ is recommended (newer hardening support)"
    fi
}

# -----------------------------------------------------------------------------
# OpenSSL LTS resolution
# -----------------------------------------------------------------------------

# --------------------------
# @fResolveLtsSeries
# @description Select the newest OpenSSL LTS series from __A_LTS_SERIES_TABLE that is not End-Of-Life.
#
# @noargs
#
# @set __A_LTS_SERIES __A_LTS_EOL
# @stderr Selected LTS series.
# @exitcode 0 If a supported LTS series was found.
# @exitcode 1 If every series in the table is EOL.
fResolveLtsSeries() {
    local __A_TODAY __A_ENTRY __A_SERIES __A_EOL
    __A_TODAY="$(date -u '+%Y-%m-%d')"
    for __A_ENTRY in "${__A_LTS_SERIES_TABLE[@]}"; do
        __A_SERIES="${__A_ENTRY%%:*}"
        __A_EOL="${__A_ENTRY##*:}"
        if [[ "${__A_EOL}" > "${__A_TODAY}" ]]; then
            __A_LTS_SERIES="${__A_SERIES}"
            __A_LTS_EOL="${__A_EOL}"
            fLogInfo "Latest supported OpenSSL LTS series: ${__A_LTS_SERIES} (EOL ${__A_LTS_EOL})"
            return 0
        fi
    done
    fDie "No supported LTS series in __A_LTS_SERIES_TABLE (all EOL) - update the table"
}

# --------------------------
# @fResolveOpensslVersion
# @description Find the newest stable patch release of the LTS series from git tags (or validate a pinned one).
#
# @noargs
#
# @set __A_OPENSSL_VERSION
# @stderr Selected version and notes about newer non-LTS series.
# @exitcode 0 If a valid LTS release was resolved.
# @exitcode 1 If tags cannot be fetched, or the pinned version is invalid / not LTS.
fResolveOpensslVersion() {
    local __A_TAGS_RAW __A_LINE __A_VER __A_SERIES __A_NUM
    local __A_BEST="" __A_BEST_NUM=-1 __A_NEWER_SERIES="" __A_PIN_FOUND=0
    local __A_SEMVER_RE='^[0-9]+\.[0-9]+\.[0-9]+$'
    local __A_LTS_NUM
    __A_LTS_NUM="$(fVersionToNumber "${__A_LTS_SERIES}.0")"

    fLogInfo "Querying release tags from ${__A_GIT_URL} ..."
    __A_TAGS_RAW="$(git ls-remote --tags --refs "${__A_GIT_URL}" 'openssl-*')" \
        || fDie "Unable to query OpenSSL tags (network?)"

    while IFS= read -r __A_LINE; do
        __A_VER="${__A_LINE##*refs/tags/openssl-}"
        [[ "${__A_VER}" =~ ${__A_SEMVER_RE} ]] || continue       # skip alpha/beta/rc
        __A_SERIES="${__A_VER%.*}"
        if [[ "${__A_SERIES}" == "${__A_LTS_SERIES}" ]]; then
            [[ "${__A_VER}" == "${__A_OPENSSL_VERSION}" ]] && __A_PIN_FOUND=1
            __A_NUM="$(fVersionToNumber "${__A_VER}")"
            if [[ "${__A_NUM}" -gt "${__A_BEST_NUM}" ]]; then
                __A_BEST="${__A_VER}"
                __A_BEST_NUM="${__A_NUM}"
            fi
        elif [[ "$(fVersionToNumber "${__A_SERIES}.0")" -gt "${__A_LTS_NUM}" ]]; then
            fListContains "${__A_NEWER_SERIES}" "${__A_SERIES}" || __A_NEWER_SERIES="${__A_NEWER_SERIES} ${__A_SERIES}"
        fi
    done <<< "${__A_TAGS_RAW}"

    [[ -n "${__A_BEST}" ]] || fDie "No stable release found for LTS series ${__A_LTS_SERIES}"

    if [[ -n "${__A_NEWER_SERIES}" ]]; then
        fLogInfo "Newer non-LTS series exist (ignored):${__A_NEWER_SERIES}"
        fLogInfo "If one of them became LTS, add it to __A_LTS_SERIES_TABLE."
    fi

    if [[ -n "${__A_OPENSSL_VERSION}" ]]; then
        [[ "${__A_OPENSSL_VERSION%.*}" == "${__A_LTS_SERIES}" ]] \
            || fDie "Pinned version ${__A_OPENSSL_VERSION} is not in the latest LTS series ${__A_LTS_SERIES}"
        [[ "${__A_PIN_FOUND}" == "1" ]] || fDie "Pinned version ${__A_OPENSSL_VERSION} does not exist"
        [[ "${__A_OPENSSL_VERSION}" == "${__A_BEST}" ]] \
            || fLogWarn "Pinned ${__A_OPENSSL_VERSION} is older than latest LTS patch ${__A_BEST}"
    else
        __A_OPENSSL_VERSION="${__A_BEST}"
    fi
    fLogOk "OpenSSL version to build: ${__A_OPENSSL_VERSION} (LTS ${__A_LTS_SERIES})"
}

# --------------------------
# @fDownloadAndVerifySource
# @description Download the release tarball, verify SHA-256 (and optionally GPG), and extract it.
#
# @noargs
#
# @set __A_SRC_DIR __A_TARBALL_SHA256
# @stderr Download and verification progress.
# @exitcode 0 If the source is downloaded, verified and extracted.
# @exitcode 1 On download failure, checksum/signature mismatch or bad tarball layout.
fDownloadAndVerifySource() {
    local __A_NAME="openssl-${__A_OPENSSL_VERSION}"
    local __A_DL_DIR="${__A_WORK_DIR}/download"
    local __A_TARBALL="${__A_DL_DIR}/${__A_NAME}.tar.gz"
    local __A_URL="${__A_RELEASE_URL_BASE}/${__A_NAME}/${__A_NAME}.tar.gz"
    local __A_EXPECTED __A_ACTUAL __A_EXTRACT_DIR

    mkdir -p "${__A_DL_DIR}"
    if [[ ! -f "${__A_TARBALL}" ]]; then
        fLogInfo "Downloading ${__A_URL}"
        fFetch "${__A_URL}" "${__A_TARBALL}.part" || fDie "Download failed: ${__A_URL}"
        mv -f "${__A_TARBALL}.part" "${__A_TARBALL}"
    else
        fLogInfo "Using cached ${__A_TARBALL}"
    fi

    fFetch "${__A_URL}.sha256" "${__A_TARBALL}.sha256" || fDie "Download failed: ${__A_URL}.sha256"
    __A_EXPECTED="$(awk 'NR==1 {print tolower($1)}' "${__A_TARBALL}.sha256")"
    [[ "${__A_EXPECTED}" =~ ^[0-9a-f]{64}$ ]] || fDie "Malformed SHA-256 file for ${__A_NAME}"
    __A_ACTUAL="$(fSha256 "${__A_TARBALL}")"
    if [[ "${__A_EXPECTED}" != "${__A_ACTUAL}" ]]; then
        rm -f "${__A_TARBALL}"
        fDie "SHA-256 mismatch for ${__A_NAME}.tar.gz (expected ${__A_EXPECTED}, got ${__A_ACTUAL})"
    fi
    __A_TARBALL_SHA256="${__A_ACTUAL}"
    fLogOk "SHA-256 verified: ${__A_ACTUAL}"

    if [[ "${__A_VERIFY_GPG}" == "1" ]]; then
        fFetch "${__A_URL}.asc" "${__A_TARBALL}.asc" || fDie "Download failed: ${__A_URL}.asc"
        gpg --batch --verify "${__A_TARBALL}.asc" "${__A_TARBALL}" >/dev/null 2>&1 \
            || fDie "GPG signature verification FAILED (import OpenSSL release keys first)"
        fLogOk "GPG signature verified"
    fi

    __A_EXTRACT_DIR="${__A_WORK_DIR}/src"
    [[ -d "${__A_EXTRACT_DIR}" ]] && fSafeRemove "${__A_EXTRACT_DIR}"
    mkdir -p "${__A_EXTRACT_DIR}"
    tar -xzf "${__A_TARBALL}" -C "${__A_EXTRACT_DIR}" --no-same-owner
    __A_SRC_DIR="${__A_EXTRACT_DIR}/${__A_NAME}"
    [[ -f "${__A_SRC_DIR}/Configure" ]] || fDie "Unexpected tarball layout: ${__A_SRC_DIR}"
}

# -----------------------------------------------------------------------------
# Hardening flag detection (each flag is probed with the real target compiler)
# -----------------------------------------------------------------------------

# --------------------------
# @fProbeDir
# @description Return (and create) the per-target directory used for compiler probes.
#
# @noargs
#
# @stdout Absolute path of the probe directory.
# @exitcode 0 On success.
fProbeDir() {
    local __A_DIR="${__A_WORK_DIR}/probe/${__A_CUR_LABEL}"
    mkdir -p "${__A_DIR}"
    echo "${__A_DIR}"
}

# --------------------------
# @fTestCompilerFlag
# @description Check that the current target compiler accepts a flag without any warning.
#
# @arg $1 string Compiler flag to test.
#
# @exitcode 0 If the flag is accepted (compiles with -Werror).
# @exitcode 1 If the flag is rejected or produces a warning.
fTestCompilerFlag() {
    local __A_DIR
    __A_DIR="$(fProbeDir)"
    printf 'int main(void) { return 0; }\n' > "${__A_DIR}/flag.c"
    "${__A_CUR_CC[@]}" -O2 -Werror "$1" -c "${__A_DIR}/flag.c" \
        -o "${__A_DIR}/flag.o" >/dev/null 2>&1
}

# --------------------------
# @fAddCompilerFlags
# @description Probe flags and append the supported ones to __A_CUR_CFLAGS.
#
# @arg $1 string Policy: "required" (abort if unsupported) or "optional" (warn and skip).
# @arg $@ string Compiler flags to probe.
#
# @set __A_CUR_CFLAGS
# @stderr Warning for every skipped optional flag.
# @exitcode 0 If all required flags are supported.
# @exitcode 1 If a required flag is not supported (script terminates).
fAddCompilerFlags() {
    local __A_POLICY="$1" __A_FLAG
    shift
    for __A_FLAG in "$@"; do
        if fTestCompilerFlag "${__A_FLAG}"; then
            __A_CUR_CFLAGS+=("${__A_FLAG}")
        elif [[ "${__A_POLICY}" == "required" ]]; then
            fDie "[${__A_CUR_LABEL}] compiler does not support required hardening flag: ${__A_FLAG}"
        else
            fLogWarn "[${__A_CUR_LABEL}] optional hardening flag not supported, skipped: ${__A_FLAG}"
        fi
    done
}

# --------------------------
# @fProbeFortifyLevel
# @description Check that a _FORTIFY_SOURCE level compiles cleanly AND is really effective.
#   Level 3 must make the compiler emit __memcpy_chk for a malloc()'ed buffer of
#   runtime size (needs __builtin_dynamic_object_size support in compiler + libc
#   headers). Level 2 must emit __memcpy_chk for a fixed-size buffer.
#   If libc headers silently ignore the level, no *_chk call appears -> rejected.
#
# @arg $1 int Fortify level to probe (2 or 3).
#
# @exitcode 0 If the level is supported and effective for the current target.
# @exitcode 1 Otherwise.
fProbeFortifyLevel() {
    local __A_LEVEL="$1" __A_DIR __A_ASM
    __A_DIR="$(fProbeDir)"
    cat > "${__A_DIR}/fortify.c" <<'EOF'
#include <stdlib.h>
#include <string.h>
/* dynamic size: object size known only at run time -> needs FORTIFY 3 */
void *probe_dynamic(const void *s, size_t n, size_t m) {
    char *d = (char *)malloc(n);
    if (d != NULL) { memcpy(d, s, m); }
    return d;
}
/* static size: object size known at compile time -> FORTIFY 2 is enough */
void probe_static(char *out, const void *s, size_t m) {
    char d[16];
    memcpy(d, s, m);
    memcpy(out, d, sizeof(d));
}
EOF
    "${__A_CUR_CC[@]}" -O2 -Werror "-D_FORTIFY_SOURCE=${__A_LEVEL}" -S \
        "${__A_DIR}/fortify.c" -o "${__A_DIR}/fortify${__A_LEVEL}.s" >/dev/null 2>&1 || return 1
    __A_ASM="$(cat "${__A_DIR}/fortify${__A_LEVEL}.s")"

    if [[ "${__A_LEVEL}" == "3" ]]; then
        # Extract only the body of probe_dynamic and look for a checked memcpy
        awk '/probe_dynamic:/{f=1} /probe_static:/{f=0} f' <<< "${__A_ASM}" | grep -q 'memcpy_chk'
    else
        grep -q 'memcpy_chk' <<< "${__A_ASM}"
    fi
}

# --------------------------
# @fDetectFortifyLevel
# @description Choose the highest effective _FORTIFY_SOURCE level (3, fallback 2) and add it to CFLAGS.
#
# @noargs
#
# @set __A_CUR_FORTIFY_LEVEL __A_CUR_CFLAGS
# @stderr Selected fortify level and fallback warnings.
# @exitcode 0 If level 3 or 2 is effective.
# @exitcode 1 If even level 2 is not effective (script terminates).
fDetectFortifyLevel() {
    __A_CUR_FORTIFY_LEVEL=""
    if [[ "${__A_FORTIFY_MAX}" == "3" ]]; then
        if fProbeFortifyLevel 3; then
            __A_CUR_FORTIFY_LEVEL=3
        else
            fLogWarn "[${__A_CUR_LABEL}] _FORTIFY_SOURCE=3 not effective with this toolchain/libc, falling back to 2"
        fi
    fi
    if [[ -z "${__A_CUR_FORTIFY_LEVEL}" ]]; then
        fProbeFortifyLevel 2 || fDie "[${__A_CUR_LABEL}] _FORTIFY_SOURCE=2 is not effective with this toolchain"
        __A_CUR_FORTIFY_LEVEL=2
    fi
    __A_CUR_CFLAGS+=("-D_FORTIFY_SOURCE=${__A_CUR_FORTIFY_LEVEL}")
    fLogOk "[${__A_CUR_LABEL}] _FORTIFY_SOURCE=${__A_CUR_FORTIFY_LEVEL} verified effective"
}

# --------------------------
# @fCollectHardeningFlags
# @description Build the full hardening CFLAGS list for the current target.
#
# @arg $1 string Architecture: "arm64", "arm" or "x86_64".
#
# @set __A_CUR_CFLAGS __A_CUR_FORTIFY_LEVEL
# @stderr Final CFLAGS list and warnings for skipped optional flags.
# @exitcode 0 On success.
# @exitcode 1 If a required flag / fortify level 2 is unsupported.
fCollectHardeningFlags() {
    local __A_ARCH="$1"
    __A_CUR_CFLAGS=()
    fAddCompilerFlags required "${__A_HARDEN_CFLAGS_REQUIRED[@]}"
    fDetectFortifyLevel
    fAddCompilerFlags optional "${__A_HARDEN_CFLAGS_OPTIONAL[@]}"
    case "${__A_ARCH}" in
        arm64)  fAddCompilerFlags optional "${__A_HARDEN_CFLAGS_ARM64[@]}" ;;
        x86_64) fAddCompilerFlags optional "${__A_HARDEN_CFLAGS_X86_64[@]}" ;;
    esac
    fLogInfo "[${__A_CUR_LABEL}] CFLAGS: ${__A_CUR_CFLAGS[*]}"
}

# -----------------------------------------------------------------------------
# Verification that hardening flags passed to Configure really took effect
# -----------------------------------------------------------------------------

# --------------------------
# @fFlagInLine
# @description Check whether a flag appears as a whole, space separated token in a line.
#
# @arg $1 string Line of text (e.g. compiler command line).
# @arg $2 string Flag to look for (e.g. "-D_FORTIFY_SOURCE=3").
#
# @exitcode 0 If the flag is present as a whole token.
# @exitcode 1 Otherwise.
fFlagInLine() {
    case " $1 " in *" $2 "*) return 0 ;; *) return 1 ;; esac
}

# --------------------------
# @fVerifyConfiguredFlags
# @description After Configure, ensure every hardening flag landed in the generated Makefile
#   (CFLAGS / CPPFLAGS / CPPDEFINES). Fails fast before the long compile.
#
# @arg $1 string Path to the generated Makefile.
#
# @stderr OK line, or the list of missing flags.
# @exitcode 0 If all flags are present.
# @exitcode 1 If any flag is missing (script terminates).
fVerifyConfiguredFlags() {
    local __A_MAKEFILE="$1" __A_FLAGS_LINES __A_FLAG __A_MISSING=""
    [[ -f "${__A_MAKEFILE}" ]] || fDie "[${__A_CUR_LABEL}] Makefile not generated: ${__A_MAKEFILE}"
    # Variable definitions are matched token-wise; the authoritative check is
    # fVerifyCompileFlags on the real compiler command line after make.
    __A_FLAGS_LINES="$(grep -E '^[A-Z_]*(CFLAGS|CPPFLAGS|CPPDEFINES)[A-Z_]*=' "${__A_MAKEFILE}" | tr '\n' ' ' || true)"
    for __A_FLAG in ${__A_CUR_CFLAGS[@]+"${__A_CUR_CFLAGS[@]}"}; do
        fFlagInLine "${__A_FLAGS_LINES}" "${__A_FLAG}" || __A_MISSING="${__A_MISSING} ${__A_FLAG}"
    done
    [[ -z "${__A_MISSING}" ]] \
        || fDie "[${__A_CUR_LABEL}] Configure dropped hardening flags:${__A_MISSING}"
    fLogOk "[${__A_CUR_LABEL}] all ${#__A_CUR_CFLAGS[@]} hardening flags present in Makefile"
}

# --------------------------
# @fVerifyCompileFlags
# @description After make, take a real compiler command line of a library C object from the build
#   log and ensure every hardening flag was passed to the compiler.
#
# @arg $1 string Path to the build log (make echoes compiler commands).
# @arg $2 string Library name: "libcrypto" or "libssl".
#
# @stderr OK line, or the list of missing flags.
# @exitcode 0 If all flags are on the compiler command line.
# @exitcode 1 If the command line is not found or any flag is missing (script terminates).
fVerifyCompileFlags() {
    local __A_LOG_FILE="$1" __A_LIB="$2" __A_LINE __A_FLAG __A_MISSING=""
    __A_LINE="$(grep -E " -c -o [^ ]*${__A_LIB}-lib-[^ ]*\.o [^ ]*\.c\$" "${__A_LOG_FILE}" | head -n 1 || true)"
    if [[ -z "${__A_LINE}" ]]; then
        __A_LINE="$(grep -E " -c .*${__A_LIB}-lib-" "${__A_LOG_FILE}" | head -n 1 || true)"
    fi
    [[ -n "${__A_LINE}" ]] \
        || fDie "[${__A_CUR_LABEL}] no ${__A_LIB} compiler command found in ${__A_LOG_FILE}"
    for __A_FLAG in ${__A_CUR_CFLAGS[@]+"${__A_CUR_CFLAGS[@]}"}; do
        fFlagInLine "${__A_LINE}" "${__A_FLAG}" || __A_MISSING="${__A_MISSING} ${__A_FLAG}"
    done
    [[ -z "${__A_MISSING}" ]] \
        || fDie "[${__A_CUR_LABEL}] flags missing on ${__A_LIB} compiler command line:${__A_MISSING}"
    fLogOk "[${__A_CUR_LABEL}] ${__A_LIB}: all hardening flags confirmed on compiler command line"
}

# -----------------------------------------------------------------------------
# Generic OpenSSL configure + build + install
# -----------------------------------------------------------------------------

# --------------------------
# @fBuildOpenssl
# @description Configure, compile and install OpenSSL (static) for the current target state (__A_CUR_*).
#
# @noargs
#
# @set __A_BUILT_TARGETS
# @stderr Build progress; log tail on failure.
# @exitcode 0 If libcrypto.a and libssl.a were built and installed.
# @exitcode 1 On configure/compile/install failure or missing/unexpected outputs.
fBuildOpenssl() {
    local __A_BUILD_DIR="${__A_WORK_DIR}/build/${__A_CUR_BUILD_NAME:-${__A_CUR_LABEL}}"
    local __A_LOG_FILE="${__A_WORK_DIR}/logs/${__A_CUR_LABEL}.log"
    local __A_CONF_ARGS=() __A_UNEXPECTED

    [[ -d "${__A_BUILD_DIR}" ]] && fSafeRemove "${__A_BUILD_DIR}"
    [[ -d "${__A_CUR_PREFIX}" ]] && fSafeRemove "${__A_CUR_PREFIX}"
    mkdir -p "${__A_BUILD_DIR}" "${__A_WORK_DIR}/logs"
    : > "${__A_LOG_FILE}"

    __A_CONF_ARGS=("${__A_CUR_CONF_TARGET}" "--prefix=${__A_CUR_PREFIX}" "${__A_CONF_COMMON[@]}")
    __A_CONF_ARGS+=(${__A_CUR_CONF_EXTRA[@]+"${__A_CUR_CONF_EXTRA[@]}"})
    __A_CONF_ARGS+=(${__A_CUR_CFLAGS[@]+"${__A_CUR_CFLAGS[@]}"})

    pushd "${__A_BUILD_DIR}" >/dev/null
    fLogInfo "[${__A_CUR_LABEL}] Configuring (${__A_CUR_CONF_TARGET}) ..."
    fRunLogged "${__A_LOG_FILE}" env "${__A_CUR_ENV[@]}" perl "${__A_SRC_DIR}/Configure" "${__A_CONF_ARGS[@]}"
    fVerifyConfiguredFlags "${__A_BUILD_DIR}/Makefile"
    fLogInfo "[${__A_CUR_LABEL}] Compiling with ${__A_JOBS} jobs (log: ${__A_LOG_FILE}) ..."
    fRunLogged "${__A_LOG_FILE}" env "${__A_CUR_ENV[@]}" make -j"${__A_JOBS}" build_libs
    fVerifyCompileFlags "${__A_LOG_FILE}" libcrypto
    fVerifyCompileFlags "${__A_LOG_FILE}" libssl
    fLogInfo "[${__A_CUR_LABEL}] Installing to ${__A_CUR_PREFIX} ..."
    fRunLogged "${__A_LOG_FILE}" env "${__A_CUR_ENV[@]}" make install_dev
    popd >/dev/null

    [[ -f "${__A_CUR_PREFIX}/lib/libcrypto.a" && -f "${__A_CUR_PREFIX}/lib/libssl.a" ]] \
        || fDie "[${__A_CUR_LABEL}] build finished but static libraries are missing"
    # Keep ONLY the static archives: drop CMake / pkg-config metadata from lib/
    fSafeRemove "${__A_CUR_PREFIX}/lib/cmake"
    fSafeRemove "${__A_CUR_PREFIX}/lib/pkgconfig"
    __A_UNEXPECTED="$(find "${__A_CUR_PREFIX}/lib" -mindepth 1 ! -name 'libcrypto.a' ! -name 'libssl.a' -print 2>/dev/null || true)"
    [[ -z "${__A_UNEXPECTED}" ]] || fDie "[${__A_CUR_LABEL}] unexpected (non static) outputs: ${__A_UNEXPECTED}"

    {
        echo "[${__A_CUR_LABEL}]"
        echo "  configure target : ${__A_CUR_CONF_TARGET}"
        echo "  fortify level    : ${__A_CUR_FORTIFY_LEVEL}"
        echo "  hardening CFLAGS : ${__A_CUR_CFLAGS[*]}"
        echo "  flags verified   : Makefile + libcrypto/libssl compiler command lines"
        echo "  configure args   : ${__A_CONF_ARGS[*]}"
        echo
    } >> "${__A_OUTPUT_DIR}/BUILD_INFO.txt"

    case "${__A_CUR_PREFIX}" in
        "${__A_OUTPUT_DIR}"/*) __A_BUILT_TARGETS+=("${__A_CUR_LABEL} -> ${__A_CUR_PREFIX}") ;;
    esac
    fLogOk "[${__A_CUR_LABEL}] done"
}

# -----------------------------------------------------------------------------
# Post-build hardening verification (static archives)
# -----------------------------------------------------------------------------

# --------------------------
# @fVerifyArchiveHardening
# @description Inspect the produced static archives for stack-protector and fortify (*_chk) references;
#   on ELF targets also check every object carries a non-executable .note.GNU-stack.
#
# @noargs
#
# @stderr OK / WARN lines per archive.
# @exitcode 0 Always (findings are reported as warnings).
fVerifyArchiveHardening() {
    local __A_LIB __A_ARCHIVE __A_SYMS __A_SECTIONS __A_OBJ_COUNT __A_STACK_COUNT
    for __A_LIB in libcrypto libssl; do
        __A_ARCHIVE="${__A_CUR_PREFIX}/lib/${__A_LIB}.a"
        # Capture output first: avoids SIGPIPE false negatives with pipefail
        __A_SYMS="$("${__A_CUR_NM[@]}" -u "${__A_ARCHIVE}" 2>/dev/null || true)"

        if grep -q '__stack_chk_fail' <<< "${__A_SYMS}"; then
            fLogOk "[${__A_CUR_LABEL}] ${__A_LIB}.a: stack protector present"
        else
            fLogWarn "[${__A_CUR_LABEL}] ${__A_LIB}.a: stack protector symbols not found"
        fi
        if grep -Eq '__[a-z0-9_]+_chk$' <<< "${__A_SYMS}"; then
            fLogOk "[${__A_CUR_LABEL}] ${__A_LIB}.a: fortified libc calls present (_FORTIFY_SOURCE=${__A_CUR_FORTIFY_LEVEL})"
        else
            fLogWarn "[${__A_CUR_LABEL}] ${__A_LIB}.a: no fortified (*_chk) libc calls found"
        fi

        if [[ -n "${__A_CUR_READELF}" && -x "${__A_CUR_READELF}" ]]; then
            __A_SECTIONS="$("${__A_CUR_READELF}" -SW "${__A_ARCHIVE}" 2>/dev/null || true)"
            __A_OBJ_COUNT="$(grep -c '^File: ' <<< "${__A_SECTIONS}" || true)"
            __A_STACK_COUNT="$(grep -c '\.note\.GNU-stack' <<< "${__A_SECTIONS}" || true)"
            if [[ "${__A_OBJ_COUNT}" -gt 0 && "${__A_OBJ_COUNT}" == "${__A_STACK_COUNT}" ]]; then
                fLogOk "[${__A_CUR_LABEL}] ${__A_LIB}.a: all ${__A_OBJ_COUNT} objects have .note.GNU-stack (NX stack)"
            else
                fLogWarn "[${__A_CUR_LABEL}] ${__A_LIB}.a: ${__A_STACK_COUNT}/${__A_OBJ_COUNT} objects have .note.GNU-stack - link the app with -Wl,-z,noexecstack"
            fi
        fi
    done
    return 0
}

# -----------------------------------------------------------------------------
# Platforms
# -----------------------------------------------------------------------------

# --------------------------
# @fBuildIos
# @description Build static OpenSSL for iOS arm64 (device).
#
# @noargs
#
# @set __A_CUR_* (per-target state)
# @stderr Build progress.
# @exitcode 0 On success.
# @exitcode 1 On missing SDK or build failure.
fBuildIos() {
    fCheckApple iphoneos
    __A_CUR_LABEL="ios-arm64"
    __A_CUR_BUILD_NAME="ios"
    __A_CUR_CONF_TARGET="ios64-xcrun"
    __A_CUR_PREFIX="${__A_OUTPUT_DIR}/ios"
    __A_CUR_CC=(xcrun --sdk iphoneos clang -arch arm64 "-mios-version-min=${__A_IOS_MIN}")
    __A_CUR_NM=(xcrun --sdk iphoneos nm)
    __A_CUR_READELF=""
    __A_CUR_ENV=("${__A_ENV_SANITIZE[@]}")
    # no-async: ucontext API is unavailable/deprecated on iOS
    __A_CUR_CONF_EXTRA=(no-async enable-ec_nistp_64_gcc_128 "-mios-version-min=${__A_IOS_MIN}")
    fCollectHardeningFlags arm64
    fBuildOpenssl
    fVerifyArchiveHardening
}

# --------------------------
# @fPickConfTarget
# @description Use a preferred OpenSSL Configure target if this OpenSSL release defines it.
#
# @arg $1 string Preferred Configure target (e.g. "iossimulator-arm64-xcrun").
#
# @set __A_CUR_CONF_TARGET (only when the target exists)
# @exitcode 0 If the preferred target exists and was selected.
# @exitcode 1 If the target does not exist in this OpenSSL release.
fPickConfTarget() {
    if grep -q "\"$1\"" "${__A_SRC_DIR}"/Configurations/*.conf 2>/dev/null; then
        __A_CUR_CONF_TARGET="$1"
        return 0
    fi
    return 1
}

# --------------------------
# @fBuildIosSimulatorArch
# @description Build static OpenSSL for one iOS Simulator architecture (iphonesimulator SDK).
#   Single arch: installed directly to <output>/ios-simulator. Multiple archs: staged in
#   <work>/stage/ios-simulator-<arch> and combined by fAssembleSimulatorOutput.
#   Uses the dedicated "iossimulator-<arch>-xcrun" target (with assembler) when available,
#   otherwise the generic "iossimulator-xcrun" target with an explicit -arch (C only).
#
# @arg $1 string Simulator architecture: "arm64" (Apple Silicon) or "x86_64" (Intel).
#
# @set __A_CUR_* (per-target state)
# @stderr Build progress.
# @exitcode 0 On success.
# @exitcode 1 On unsupported arch or build failure.
fBuildIosSimulatorArch() {
    local __A_ARCH="$1"
    fListContains "${__A_SUPPORTED_IOS_SIM_ARCHS}" "${__A_ARCH}" || fDie "Unsupported simulator arch: ${__A_ARCH}"
    __A_CUR_LABEL="ios-simulator-${__A_ARCH}"
    if [[ ${#__A_SIM_ARCH_LIST[@]} -eq 1 ]]; then
        __A_CUR_BUILD_NAME="ios-simulator"
        __A_CUR_PREFIX="${__A_OUTPUT_DIR}/ios-simulator"
    else
        # several archs: stage each one in the WORK dir (flat names), lipo into output later
        __A_CUR_BUILD_NAME="ios-simulator-${__A_ARCH}"
        __A_CUR_PREFIX="${__A_WORK_DIR}/stage/ios-simulator-${__A_ARCH}"
    fi
    __A_CUR_CC=(xcrun --sdk iphonesimulator clang -arch "${__A_ARCH}" "-mios-simulator-version-min=${__A_IOS_MIN}")
    __A_CUR_NM=(xcrun --sdk iphonesimulator nm)
    __A_CUR_READELF=""
    __A_CUR_ENV=("${__A_ENV_SANITIZE[@]}")
    __A_CUR_CONF_EXTRA=(no-async enable-ec_nistp_64_gcc_128 "-mios-simulator-version-min=${__A_IOS_MIN}")
    if ! fPickConfTarget "iossimulator-${__A_ARCH}-xcrun"; then
        __A_CUR_CONF_TARGET="iossimulator-xcrun"
        # "-arch X" is two words; Configure would treat X as a target name,
        # so the arch is given through CC (Configure honours CC from env).
        __A_CUR_ENV+=("CC=xcrun -sdk iphonesimulator clang -arch ${__A_ARCH}")
        fLogWarn "[${__A_CUR_LABEL}] dedicated target not available, using iossimulator-xcrun (no asm)"
    fi
    if [[ "${__A_ARCH}" == "arm64" ]]; then
        fCollectHardeningFlags arm64
    else
        fCollectHardeningFlags x86_64
    fi
    fBuildOpenssl
    fVerifyArchiveHardening
}

# --------------------------
# @fBuildIosSimulator
# @description Build static OpenSSL for every selected iOS Simulator architecture.
#
# @noargs
#
# @stderr Build progress.
# @exitcode 0 If all simulator architectures were built.
# @exitcode 1 On build failure.
fBuildIosSimulator() {
    local __A_ARCH
    for __A_ARCH in "${__A_SIM_ARCH_LIST[@]}"; do
        fBuildIosSimulatorArch "${__A_ARCH}"
    done
}

# --------------------------
# @fBuildMacos
# @description Build static OpenSSL for macOS arm64 (Apple Silicon).
#
# @noargs
#
# @set __A_CUR_* (per-target state)
# @stderr Build progress.
# @exitcode 0 On success.
# @exitcode 1 On missing SDK or build failure.
fBuildMacos() {
    fCheckApple macosx
    __A_CUR_LABEL="macos-arm64"
    __A_CUR_BUILD_NAME="macos"
    __A_CUR_CONF_TARGET="darwin64-arm64-cc"
    __A_CUR_PREFIX="${__A_OUTPUT_DIR}/macos"
    __A_CUR_CC=(xcrun --sdk macosx clang -arch arm64 "-mmacosx-version-min=${__A_MACOS_MIN}")
    __A_CUR_NM=(xcrun --sdk macosx nm)
    __A_CUR_READELF=""
    __A_CUR_ENV=("${__A_ENV_SANITIZE[@]}")
    __A_CUR_CONF_EXTRA=(enable-ec_nistp_64_gcc_128 "-mmacosx-version-min=${__A_MACOS_MIN}")
    fCollectHardeningFlags arm64
    fBuildOpenssl
    fVerifyArchiveHardening
}

# --------------------------
# @fBuildAndroidAbi
# @description Build static OpenSSL for a single Android ABI.
#
# @arg $1 string Android ABI: "arm64-v8a" or "armeabi-v7a".
#
# @set __A_CUR_* (per-target state)
# @stderr Build progress.
# @exitcode 0 On success.
# @exitcode 1 On unsupported ABI or build failure.
fBuildAndroidAbi() {
    local __A_ABI="$1" __A_ARCH __A_TRIPLE
    case "${__A_ABI}" in
        arm64-v8a)   __A_CUR_CONF_TARGET="android-arm64"; __A_TRIPLE="aarch64-linux-android";    __A_ARCH="arm64" ;;
        armeabi-v7a) __A_CUR_CONF_TARGET="android-arm";   __A_TRIPLE="armv7a-linux-androideabi"; __A_ARCH="arm" ;;
        *)           fDie "Unsupported Android ABI: ${__A_ABI}" ;;
    esac
    __A_CUR_LABEL="android-${__A_ABI}"
    __A_CUR_BUILD_NAME="android/${__A_ABI}"
    __A_CUR_PREFIX="${__A_OUTPUT_DIR}/android/${__A_ABI}"
    __A_CUR_CC=("${__A_NDK_BIN}/clang" "--target=${__A_TRIPLE}${__A_ANDROID_API}")
    __A_CUR_NM=("${__A_NDK_BIN}/llvm-nm")
    __A_CUR_READELF="${__A_NDK_BIN}/llvm-readelf"
    __A_CUR_ENV=("${__A_ENV_SANITIZE[@]}" "ANDROID_NDK_ROOT=${__A_ANDROID_NDK}" "PATH=${__A_NDK_BIN}:${PATH}")
    __A_CUR_CONF_EXTRA=("-D__ANDROID_API__=${__A_ANDROID_API}")
    if [[ "${__A_ARCH}" == "arm64" ]]; then
        __A_CUR_CONF_EXTRA+=(enable-ec_nistp_64_gcc_128)
    fi
    fCollectHardeningFlags "${__A_ARCH}"
    fBuildOpenssl
    fVerifyArchiveHardening
}

# --------------------------
# @fBuildAndroid
# @description Build static OpenSSL for every selected Android ABI (NDK validated by preflight).
#
# @noargs
#
# @stderr Build progress.
# @exitcode 0 If all ABIs were built.
# @exitcode 1 On invalid NDK or build failure.
fBuildAndroid() {
    local __A_ABI
    [[ -n "${__A_NDK_BIN}" ]] || fCheckAndroidNdk
    for __A_ABI in "${__A_ABI_LIST[@]}"; do
        fBuildAndroidAbi "${__A_ABI}"
    done
}

# -----------------------------------------------------------------------------
# iOS Simulator multi-arch static archives (plain .a, NO framework)
# -----------------------------------------------------------------------------

# --------------------------
# @fAssembleSimulatorOutput
# @description When several iOS Simulator architectures were built, combine the staged per-arch
#   archives with lipo into plain multi-arch STATIC archives directly in
#   <output>/ios-simulator/lib (no arch sub-folder, no framework).
#
# @noargs
#
# @set __A_BUILT_TARGETS
# @stderr Progress.
# @exitcode 0 On success, or when nothing needs to be combined (single arch / not selected).
# @exitcode 1 If lipo fails.
fAssembleSimulatorOutput() {
    local __A_DEST="${__A_OUTPUT_DIR}/ios-simulator" __A_LIB __A_ARCH __A_INPUTS=()
    fListContains "${__A_PLATFORM_LIST[*]}" "ios-simulator" || return 0
    [[ ${#__A_SIM_ARCH_LIST[@]} -gt 1 ]] || return 0

    [[ -d "${__A_DEST}" ]] && fSafeRemove "${__A_DEST}"
    mkdir -p "${__A_DEST}/lib"
    for __A_LIB in libcrypto libssl; do
        __A_INPUTS=()
        for __A_ARCH in "${__A_SIM_ARCH_LIST[@]}"; do
            __A_INPUTS+=("${__A_WORK_DIR}/stage/ios-simulator-${__A_ARCH}/lib/${__A_LIB}.a")
        done
        xcrun lipo -create "${__A_INPUTS[@]}" -output "${__A_DEST}/lib/${__A_LIB}.a"
    done
    cp -R "${__A_WORK_DIR}/stage/ios-simulator-${__A_SIM_ARCH_LIST[0]}/include" "${__A_DEST}/include"
    __A_BUILT_TARGETS+=("ios-simulator (${__A_SIM_ARCH_LIST[*]}) -> ${__A_DEST}")
    fLogOk "iOS Simulator multi-arch static archives created ($(xcrun lipo -archs "${__A_DEST}/lib/libcrypto.a"))"
}

# --------------------------
# @fVerifyStaticOnlyOutput
# @description Enforce that the whole output directory contains ONLY static archives (.a),
#   public headers, BUILD_INFO.txt and the ownership marker: no frameworks (.framework / .xcframework),
#   no shared libraries (.so / .dylib / .dll) and no other files.
#
# @noargs
#
# @stderr OK line, or the list of offending paths.
# @exitcode 0 If only static libraries + headers are present.
# @exitcode 1 If anything else is found (script terminates).
fVerifyStaticOnlyOutput() {
    local __A_BAD
    __A_BAD="$(find "${__A_OUTPUT_DIR}" \( -name '*.framework' -o -name '*.xcframework' \) -print 2>/dev/null || true)"
    [[ -z "${__A_BAD}" ]] || fDie "Frameworks are not allowed in output:"$'\n'"${__A_BAD}"

    __A_BAD="$(find "${__A_OUTPUT_DIR}" -type f \
        ! -path '*/lib/*.a' \
        ! -path '*/include/*' \
        ! -path "${__A_OUTPUT_DIR}/BUILD_INFO.txt" \
        ! -path "${__A_OUTPUT_DIR}/${__A_OUTPUT_MARKER}" -print 2>/dev/null || true)"
    [[ -z "${__A_BAD}" ]] || fDie "Non static-library files found in output:"$'\n'"${__A_BAD}"

    fLogOk "Output verified: ONLY static libraries (.a) + headers, no frameworks / shared libs"
}

# -----------------------------------------------------------------------------
# Main
# -----------------------------------------------------------------------------

# --------------------------
# @fWriteBuildInfoHeader
# @description Create BUILD_INFO.txt with version, checksum, targets and app link recommendations.
#
# @noargs
#
# @exitcode 0 On success.
# @exitcode 1 If the output directory is not writable.
fWriteBuildInfoHeader() {
    mkdir -p "${__A_OUTPUT_DIR}"
    {
        echo "OpenSSL ${__A_OPENSSL_VERSION} (LTS series ${__A_LTS_SERIES}, EOL ${__A_LTS_EOL})"
        echo "Library type   : STATIC only (libcrypto.a, libssl.a) - no frameworks, no shared libs"
        echo "Source SHA-256 : ${__A_TARBALL_SHA256}"
        echo "Built on       : $(date -u '+%Y-%m-%dT%H:%M:%SZ') ($(uname -sm))"
        echo "Android API    : ${__A_ANDROID_API}"
        echo "iOS min        : ${__A_IOS_MIN}"
        echo "iOS Sim archs  : ${__A_SIM_ARCH_LIST[*]:-}"
        echo "macOS min      : ${__A_MACOS_MIN}"
        echo
        echo "Linker hardening must be applied when linking YOUR app / shared library:"
        echo "  Android : -Wl,-z,relro -Wl,-z,now -Wl,-z,noexecstack -Wl,-z,max-page-size=16384"
        echo "  Apple   : ld64 defaults (PIE, NX, ASLR) are already hardened"
        echo
    } > "${__A_OUTPUT_DIR}/BUILD_INFO.txt"
}

# --------------------------
# @fPrintSummary
# @description Print the list of built targets and the BUILD_INFO location.
#
# @noargs
#
# @stderr Summary lines.
# @exitcode 0 Always.
fPrintSummary() {
    local __A_ITEM
    echo >&2
    fLogOk "OpenSSL ${__A_OPENSSL_VERSION} (LTS ${__A_LTS_SERIES}) static libraries built:"
    for __A_ITEM in "${__A_BUILT_TARGETS[@]}"; do
        printf '        %s\n' "${__A_ITEM}" >&2
    done
    fLogInfo "Build info: ${__A_OUTPUT_DIR}/BUILD_INFO.txt"
}

# --------------------------
# @fMain
# @description Entry point: parse options, preflight toolchains, resolve the latest LTS, download,
#   build all selected platforms. Without parameters: ALL platforms, latest highest LTS.
#
# @arg $@ string Command line arguments (see fUsage); may be empty.
#
# @set __A_ALL_MODE (1 when started without parameters)
#
# @stdout Help text when requested.
# @stderr Progress, warnings and errors.
# @exitcode 0 If every requested platform was built.
# @exitcode 1 On any validation, download, verification or build error.
fMain() {
    local __A_PLATFORM
    if [[ $# -eq 0 ]]; then
        __A_ALL_MODE=1
        __A_PLATFORMS="ios,ios-simulator,android,macos"
        __A_OPENSSL_VERSION=""
        fLogInfo "No parameters: building ALL platforms for the latest (highest) supported OpenSSL LTS"
    fi
    fParseArgs "$@"
    fCheckPrerequisites
    fDetectJobs
    __A_WORK_DIR="$(fAbsPath "$(fExpandPath "${__A_WORK_DIR}")")"
    fPrepareOutputDir
    fResolvePlatforms
    fLogInfo "Platforms: ${__A_PLATFORM_LIST[*]} | jobs: ${__A_JOBS} | static only"
    fPreflightToolchains

    fResolveLtsSeries
    fResolveOpensslVersion
    fDownloadAndVerifySource
    fWriteBuildInfoHeader

    for __A_PLATFORM in "${__A_PLATFORM_LIST[@]}"; do
        case "${__A_PLATFORM}" in
            ios)           fBuildIos ;;
            ios-simulator) fBuildIosSimulator ;;
            android)       fBuildAndroid ;;
            macos)         fBuildMacos ;;
        esac
    done

    fAssembleSimulatorOutput
    fVerifyStaticOnlyOutput

    if [[ "${__A_CLEAN}" == "1" ]]; then
        fLogInfo "Cleaning ${__A_WORK_DIR}"
        fSafeRemove "${__A_WORK_DIR}"
    fi
    fPrintSummary
}

fMain "$@"
