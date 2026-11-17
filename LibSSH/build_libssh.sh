#!/usr/bin/env bash
# =============================================================================
#  build_libssh.sh
#
#  Builds libssh as a STATIC library (libssh.a) with the OpenSSL crypto
#  backend against a PREBUILT STATIC OpenSSL (libssl.a / libcrypto.a).
#  Shared libraries are never built, searched for or accepted.
#  Targets:
#     iOS      : arm64
#     macOS    : arm64
#     Android  : arm64-v8a, armeabi-v7a
#
#  Usage:
#     ./build_libssh.sh --openssl-dir <dir> [--install-dir <dir>] [targets...]
#
#     targets : ios macos android   (default: all available on this host)
#
#  Options:
#     -o, --openssl-dir <dir>   root of the prebuilt static OpenSSL (required)
#     -i, --install-dir <dir>   install root (default: ./install)
#     -h, --help                show this help
#
#  Expected prebuilt OpenSSL layout (same as the install layout):
#     <openssl-dir>/ios/{include,lib}
#     <openssl-dir>/macos/{include,lib}
#     <openssl-dir>/android/arm64-v8a/{include,lib}
#     <openssl-dir>/android/armeabi-v7a/{include,lib}
#  lib/ must contain the static archives libssl.a and libcrypto.a.
#
#  Install layout (only Android has per-arch subfolders):
#     <install-dir>/ios/{include,lib/libssh.a}
#     <install-dir>/macos/{include,lib/libssh.a}
#     <install-dir>/android/arm64-v8a/{include,lib/libssh.a}
#     <install-dir>/android/armeabi-v7a/{include,lib/libssh.a}
#
#  Linking: the final application must link libssh.a, libssl.a and
#  libcrypto.a (in that order); on Android also -ldl. Recommended hardening
#  LDFLAGS for the final link are printed at the end of each target build.
#
#  Requirements:
#     all     : bash, curl, tar, cmake (+ ninja or make)
#     android : ANDROID_HOME pointing to the Android SDK with an NDK installed
#     ios/mac : macOS host with Xcode + command line tools
#
#  Environment overrides (command line options take precedence):
#     __A_OPENSSL_DIR, __A_INSTALL_DIR, __A_LIBSSH_VERSION, __A_LIBSSH_SHA256,
#     __A_ANDROID_API, __A_IOS_MIN, __A_MACOS_MIN, __A_NDK_VERSION,
#     __A_BUILD_TYPE, __A_WORK_DIR, __A_JOBS,
#     __A_WITH_SERVER, __A_WITH_SFTP, __A_WITH_EXEC
#
#  Source integrity: the libssh tarball is ALWAYS verified against a pinned
#  SHA-256. A custom __A_LIBSSH_VERSION requires a matching __A_LIBSSH_SHA256.
#
#  Attack surface: libssh is built client-only by default (no SSH server,
#  no SFTP, no command execution from config/ProxyCommand, no pcap/debug).
#  Set __A_WITH_SERVER / __A_WITH_SFTP / __A_WITH_EXEC to ON only if needed.
# =============================================================================
set -Eeuo pipefail
umask 022

# ----------------------------------------------------------------------------
#  Configuration
# ----------------------------------------------------------------------------
# Pinned release: SHA-256 of https://www.libssh.org/files/0.12/libssh-0.12.2.tar.xz
__A_LIBSSH_PINNED_VERSION="0.12.2"
__A_LIBSSH_PINNED_SHA256="49560f677d96e3706a904ac2de1116e25f3680937d51e5c92198fcba4a1c1e9f"

: "${__A_LIBSSH_VERSION:=${__A_LIBSSH_PINNED_VERSION}}"
: "${__A_LIBSSH_SHA256:=}"
if [[ -z "${__A_LIBSSH_SHA256}" && "${__A_LIBSSH_VERSION}" == "${__A_LIBSSH_PINNED_VERSION}" ]]; then
    __A_LIBSSH_SHA256="${__A_LIBSSH_PINNED_SHA256}"
fi

# Optional libssh features (ON/OFF). Client-only build by default.
: "${__A_WITH_SERVER:=OFF}"         # SSH server (ssh_bind, server-side parsers)
: "${__A_WITH_SFTP:=OFF}"           # SFTP client (and SFTP server if __A_WITH_SERVER=ON)
: "${__A_WITH_EXEC:=OFF}"           # ProxyCommand / Match exec / ProxyJump via exec

: "${__A_ANDROID_API:=24}"
: "${__A_IOS_MIN:=13.0}"
: "${__A_MACOS_MIN:=11.0}"
: "${__A_NDK_VERSION:=}"            # e.g. 27.2.12479018; empty = newest installed
: "${__A_BUILD_TYPE:=Release}"

__A_ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
: "${__A_WORK_DIR:=${__A_ROOT_DIR}/_build}"
: "${__A_INSTALL_DIR:=${__A_ROOT_DIR}/install}"
: "${__A_OPENSSL_DIR:=}"
: "${__A_JOBS:=}"

__A_DL_DIR="${__A_WORK_DIR}/downloads"
__A_SRC_DIR="${__A_WORK_DIR}/src"
__A_LIBSSH_SRC="${__A_SRC_DIR}/libssh-${__A_LIBSSH_VERSION}"
__A_LIBSSH_URL="https://www.libssh.org/files/${__A_LIBSSH_VERSION%.*}/libssh-${__A_LIBSSH_VERSION}.tar.xz"

__A_ANDROID_ABIS=(arm64-v8a armeabi-v7a)
__A_HOST_OS="$(uname -s)"
__A_TARGETS=()
__A_GENERATOR=""
__A_NDK_DIR=""
__A_NDK_TOOLCHAIN=""

# Per-target state (reset for every target).
__A_CC_PROBE=()                # compiler command used for flag probing
__A_CUR_CFLAGS=""              # hardening CFLAGS for the current target
__A_CUR_FORTIFY_LEVEL=""       # selected _FORTIFY_SOURCE level
__A_OSSL_ROOT=""               # prebuilt OpenSSL root for the current target
__A_OSSL_SSL_LIB=""            # <root>/lib/libssl.a
__A_OSSL_CRYPTO_LIB=""         # <root>/lib/libcrypto.a

# Hardening flags common to every target. Each entry is probed against the
# target compiler and dropped when unsupported.
# _FORTIFY_SOURCE is handled separately by fDetectFortifyLevel (3 -> 2).
# -fPIC is kept so the static archives can be linked into Android JNI .so
# files and position-independent executables.
__A_HARDEN_CFLAGS=(
    "-fstack-protector-strong"
    "-fstack-clash-protection"
    "-fPIC"
    "-fno-common"
    "-fno-strict-overflow"
    "-fno-delete-null-pointer-checks"
    "-ftrivial-auto-var-init=zero"
    "-Wformat"
    "-Wformat-security"
    "-Werror=format-security"
)
# Portability shims: "header|macro|replacement". When <header> does not
# define <macro> for the target, -D<macro>=<replacement> is added.
# S_IWRITE: legacy BSD/glibc alias of S_IWUSR, used by libssh misc.c but
# missing from Android bionic.
__A_COMPAT_MACROS=(
    "sys/stat.h|S_IWRITE|S_IWUSR"
)
# Extra flags for AArch64 targets (PAC/BTI).
__A_HARDEN_CFLAGS_ARM64=(
    "-mbranch-protection=standard"
)

# A static archive has no link step, so linker hardening applies to the
# final application. These are printed as recommendations per target.
# ELF (Android): 16 KB page alignment is required on Android 15+ for arm64.
__A_FINAL_LDFLAGS_ANDROID="-Wl,-z,relro -Wl,-z,now -Wl,-z,noexecstack -Wl,--build-id=sha1"
__A_FINAL_LDFLAGS_ANDROID_ARM64="-Wl,-z,max-page-size=16384"
# Mach-O: PIE, NX and ASLR are on by default with the Apple toolchain.
__A_FINAL_LDFLAGS_APPLE="-Wl,-dead_strip"

# ----------------------------------------------------------------------------
#  Helpers
# ----------------------------------------------------------------------------

# --------------------------
# @fLog
# @description Print an informational message with the script prefix.
# @arg $@ string Message text.
# @stdout Formatted message.
# @exitcode 0 Always.
fLog() {
    printf '\033[1;32m[libssh]\033[0m %s\n' "$*"
}

# --------------------------
# @fWarn
# @description Print a warning message with the script prefix.
# @arg $@ string Warning text.
# @stderr Formatted warning.
# @exitcode 0 Always.
fWarn() {
    printf '\033[1;33m[libssh] WARNING:\033[0m %s\n' "$*" >&2
}

# --------------------------
# @fDie
# @description Print an error message and terminate the script.
# @arg $@ string Error text.
# @stderr Formatted error.
# @exitcode 1 Always (script terminates).
fDie() {
    printf '\033[1;31m[libssh] ERROR:\033[0m %s\n' "$*" >&2
    exit 1
}

# --------------------------
# @fOnError
# @description ERR trap handler: report the failed command and its line, then terminate.
# @noargs
# @stderr Failed command, line number and exit code.
# @exitcode * Exit code of the failed command (script terminates).
fOnError() {
    local __A_RC=$?
    printf '\033[1;31m[libssh] ERROR:\033[0m command failed (rc=%d) at line %s: %s\n' \
        "${__A_RC}" "${BASH_LINENO[0]}" "${BASH_COMMAND}" >&2
    exit "${__A_RC}"
}
trap fOnError ERR

# --------------------------
# @fUsage
# @description Print usage help extracted from the script header.
# @noargs
# @stdout Usage text.
# @exitcode 0 Always.
fUsage() {
    sed -n '3,/^#  Environment overrides/{s/^# \{0,2\}//;p}' "${BASH_SOURCE[0]}"
}

# --------------------------
# @fAbsPath
# @description Convert a path to an absolute path (without resolving symlinks) and strip a trailing slash.
# @arg $1 string Path, absolute or relative to the current directory.
# @stdout Absolute path.
# @exitcode 0 Always.
fAbsPath() {
    local __A_PATH="$1"
    [[ "${__A_PATH}" == /* ]] || __A_PATH="${PWD}/${__A_PATH}"
    printf '%s' "${__A_PATH%/}"
}

# --------------------------
# @fDetectJobs
# @description Detect the number of parallel build jobs unless already set.
# @noargs
# @set __A_JOBS
# @exitcode 0 Always.
fDetectJobs() {
    if [[ -z "${__A_JOBS}" ]]; then
        __A_JOBS="$(getconf _NPROCESSORS_ONLN 2>/dev/null || echo 4)"
    fi
}

# --------------------------
# @fRequireTool
# @description Ensure that every listed command is available in PATH.
# @arg $@ string Command names.
# @stderr Error for the first missing command.
# @exitcode 0 If all commands are found.
# @exitcode 1 If a command is missing (script terminates).
fRequireTool() {
    local __A_TOOL
    for __A_TOOL in "$@"; do
        command -v "${__A_TOOL}" >/dev/null 2>&1 || fDie "required tool not found: ${__A_TOOL}"
    done
}

# --------------------------
# @fDetectGenerator
# @description Select the CMake generator: Ninja if available, otherwise Unix Makefiles.
# @noargs
# @set __A_GENERATOR
# @exitcode 0 If a generator is found.
# @exitcode 1 If neither ninja nor make is available (script terminates).
fDetectGenerator() {
    if command -v ninja >/dev/null 2>&1; then
        __A_GENERATOR="Ninja"
    elif command -v make >/dev/null 2>&1; then
        __A_GENERATOR="Unix Makefiles"
    else
        fDie "neither ninja nor make found"
    fi
}

# --------------------------
# @fSha256
# @description Compute the SHA-256 checksum of a file (sha256sum or shasum).
# @arg $1 string File path.
# @stdout Lowercase hex digest.
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
# @fIsStaticArchive
# @description Check that a file is a static library archive (ar format, "!<arch>" magic).
# @arg $1 string File path.
# @exitcode 0 If the file is an ar archive.
# @exitcode 1 If the file is missing or not an ar archive (e.g. shared library or linker script).
fIsStaticArchive() {
    local __A_FILE="$1" __A_MAGIC
    [[ -f "${__A_FILE}" ]] || return 1
    __A_MAGIC="$(head -c 8 "${__A_FILE}" 2>/dev/null || true)"
    [[ "${__A_MAGIC}" == '!<arch>' ]]
}

# --------------------------
# @fDownload
# @description Download a file over HTTPS (TLS 1.2+) if not cached and verify its SHA-256; unverified files are never used.
# @arg $1 string Source URL.
# @arg $2 string Destination file path.
# @arg $3 string Expected SHA-256 (64 hex chars, mandatory).
# @stdout Progress messages.
# @stderr Error on missing checksum or mismatch.
# @exitcode 0 If the file is present and verified.
# @exitcode 1 On missing checksum, download failure or checksum mismatch (script terminates).
fDownload() {
    local __A_URL="$1" __A_DEST="$2" __A_SHA="$3" __A_ACTUAL
    [[ "${__A_SHA}" =~ ^[0-9a-f]{64}$ ]] \
        || fDie "no valid SHA-256 pinned for $(basename "${__A_DEST}") (refusing unverified source)"

    if [[ -f "${__A_DEST}" ]]; then
        # Re-verify cached archives every run.
        __A_ACTUAL="$(fSha256 "${__A_DEST}")"
        if [[ "${__A_ACTUAL}" != "${__A_SHA}" ]]; then
            fWarn "cached $(basename "${__A_DEST}") does not match pinned checksum, re-downloading"
            rm -f "${__A_DEST}"
        fi
    fi

    if [[ ! -f "${__A_DEST}" ]]; then
        fLog "Downloading ${__A_URL}"
        rm -f "${__A_DEST}.part"
        curl --fail --location --proto '=https' --proto-redir '=https' --tlsv1.2 --retry 3 \
             --silent --show-error -o "${__A_DEST}.part" "${__A_URL}"
        __A_ACTUAL="$(fSha256 "${__A_DEST}.part")"
        if [[ "${__A_ACTUAL}" != "${__A_SHA}" ]]; then
            rm -f "${__A_DEST}.part"
            fDie "checksum mismatch for $(basename "${__A_DEST}"): expected ${__A_SHA}, got ${__A_ACTUAL}"
        fi
        mv "${__A_DEST}.part" "${__A_DEST}"
    fi
    fLog "Checksum OK: $(basename "${__A_DEST}") (sha256=${__A_SHA})"
}

# --------------------------
# @fPrepareSources
# @description Download the libssh release tarball and extract a fresh source tree.
# @noargs
# @stdout Progress messages.
# @exitcode 0 On success.
# @exitcode 1 On download, checksum or extraction failure (script terminates).
fPrepareSources() {
    local __A_SSH_TAR="${__A_DL_DIR}/libssh-${__A_LIBSSH_VERSION}.tar.xz"
    mkdir -p "${__A_DL_DIR}" "${__A_SRC_DIR}"

    fDownload "${__A_LIBSSH_URL}" "${__A_SSH_TAR}" "${__A_LIBSSH_SHA256}"

    rm -rf "${__A_LIBSSH_SRC}"
    tar -xf "${__A_SSH_TAR}" -C "${__A_SRC_DIR}"
    [[ -d "${__A_LIBSSH_SRC}" ]] || fDie "unexpected archive layout: ${__A_SSH_TAR}"
}

# ----------------------------------------------------------------------------
#  Compiler hardening
# ----------------------------------------------------------------------------

# --------------------------
# @fFilterFlags
# @description Probe each flag with the target compiler (-Werror) and append the supported ones to CFLAGS.
# @arg $@ string Compiler flags; a multi-word entry is probed as one unit.
# @set __A_CUR_CFLAGS
# @stderr Warning for every unsupported flag.
# @exitcode 0 Always.
fFilterFlags() {
    local __A_PROBE_DIR="${__A_WORK_DIR}/probe"
    local __A_PROBE="${__A_PROBE_DIR}/probe.c"
    local __A_FLAG
    mkdir -p "${__A_PROBE_DIR}"
    printf '#include <string.h>\nint main(void){char b[8];memset(b,0,sizeof b);return b[0];}\n' > "${__A_PROBE}"

    for __A_FLAG in "$@"; do
        # shellcheck disable=SC2086  # intentional splitting for multi-word entries
        if "${__A_CC_PROBE[@]}" -O2 -Werror ${__A_FLAG} \
               -c "${__A_PROBE}" -o "${__A_PROBE}.o" >/dev/null 2>&1; then
            __A_CUR_CFLAGS="${__A_CUR_CFLAGS:+${__A_CUR_CFLAGS} }${__A_FLAG}"
        else
            fWarn "compiler does not support '${__A_FLAG}', skipping"
        fi
    done
}

# --------------------------
# @fDetectFortifyLevel
# @description Choose the highest effective _FORTIFY_SOURCE level (3, fallback 2) and add it to CFLAGS.
# @noargs
# @set __A_CUR_FORTIFY_LEVEL __A_CUR_CFLAGS
# @stderr Selected fortify level and fallback warnings.
# @exitcode 0 If level 3 or 2 is effective.
# @exitcode 1 If even level 2 is not effective (script terminates).
fDetectFortifyLevel() {
    local __A_PROBE_DIR="${__A_WORK_DIR}/probe"
    local __A_PROBE="${__A_PROBE_DIR}/fortify.c"
    local __A_LEVEL
    mkdir -p "${__A_PROBE_DIR}"
    # Level 3 needs __builtin_dynamic_object_size; libc headers that do not
    # support the requested level emit a warning, which -Werror turns into
    # a failure.
    cat > "${__A_PROBE}" <<'EOF'
#include <string.h>
#include <stdio.h>
#if __A_FORTIFY_LEVEL >= 3
#  if !defined(__has_builtin)
#    error "__has_builtin not available"
#  elif !__has_builtin(__builtin_dynamic_object_size)
#    error "__builtin_dynamic_object_size not available"
#  endif
#endif
int main(int argc, char **argv) {
    char b[16];
    (void)argc;
    strncpy(b, argv[0], sizeof(b) - 1);
    b[sizeof(b) - 1] = '\0';
    printf("%s", b);
    return (int)strlen(b);
}
EOF
    __A_CUR_FORTIFY_LEVEL=""
    for __A_LEVEL in 3 2; do
        if "${__A_CC_PROBE[@]}" -O2 -Werror "-D__A_FORTIFY_LEVEL=${__A_LEVEL}" \
               -U_FORTIFY_SOURCE "-D_FORTIFY_SOURCE=${__A_LEVEL}" \
               -c "${__A_PROBE}" -o "${__A_PROBE}.o" >/dev/null 2>&1; then
            __A_CUR_FORTIFY_LEVEL="${__A_LEVEL}"
            break
        fi
        fWarn "_FORTIFY_SOURCE=${__A_LEVEL} is not effective for this target"
    done

    [[ -n "${__A_CUR_FORTIFY_LEVEL}" ]] \
        || fDie "_FORTIFY_SOURCE=2 is not effective for this target"

    __A_CUR_CFLAGS="${__A_CUR_CFLAGS:+${__A_CUR_CFLAGS} }-U_FORTIFY_SOURCE -D_FORTIFY_SOURCE=${__A_CUR_FORTIFY_LEVEL}"
    fLog "Selected _FORTIFY_SOURCE=${__A_CUR_FORTIFY_LEVEL}" >&2
}

# --------------------------
# @fHardeningCflags
# @description Build the full hardening CFLAGS for the compiler in __A_CC_PROBE.
# @arg $1 int 1 for AArch64 targets (adds branch protection), 0 otherwise.
# @set __A_CUR_CFLAGS __A_CUR_FORTIFY_LEVEL
# @stderr Unsupported-flag warnings and selected fortify level.
# @exitcode 0 On success.
# @exitcode 1 If no effective _FORTIFY_SOURCE level exists (script terminates).
fHardeningCflags() {
    local __A_IS_ARM64="$1"
    __A_CUR_CFLAGS=""
    if [[ "${__A_IS_ARM64}" == "1" ]]; then
        fFilterFlags "${__A_HARDEN_CFLAGS[@]}" "${__A_HARDEN_CFLAGS_ARM64[@]}"
    else
        fFilterFlags "${__A_HARDEN_CFLAGS[@]}"
    fi
    fDetectFortifyLevel
}

# --------------------------
# @fAddCompatDefines
# @description Probe the target C library for each macro in __A_COMPAT_MACROS and define missing ones as their portable equivalent.
# @noargs
# @set __A_CUR_CFLAGS
# @stderr Notice for every compatibility define added.
# @exitcode 0 If every missing macro could be mapped.
# @exitcode 1 If a replacement macro is missing too (script terminates).
fAddCompatDefines() {
    local __A_PROBE_DIR="${__A_WORK_DIR}/probe"
    local __A_PROBE="${__A_PROBE_DIR}/compat.c"
    local __A_ENTRY __A_HEADER __A_MACRO __A_REPLACEMENT
    mkdir -p "${__A_PROBE_DIR}"

    for __A_ENTRY in "${__A_COMPAT_MACROS[@]}"; do
        IFS='|' read -r __A_HEADER __A_MACRO __A_REPLACEMENT <<< "${__A_ENTRY}"
        printf '#include <%s>\n#ifndef %s\n#error "%s missing"\n#endif\nint main(void){return 0;}\n' \
            "${__A_HEADER}" "${__A_MACRO}" "${__A_MACRO}" > "${__A_PROBE}"
        # shellcheck disable=SC2086  # CFLAGS is a flag list
        if "${__A_CC_PROBE[@]}" ${__A_CUR_CFLAGS} -Werror \
               -c "${__A_PROBE}" -o "${__A_PROBE}.o" >/dev/null 2>&1; then
            continue
        fi
        printf '#include <%s>\n#ifndef %s\n#error "%s missing"\n#endif\nint main(void){return 0;}\n' \
            "${__A_HEADER}" "${__A_REPLACEMENT}" "${__A_REPLACEMENT}" > "${__A_PROBE}"
        # shellcheck disable=SC2086
        "${__A_CC_PROBE[@]}" ${__A_CUR_CFLAGS} -Werror \
            -c "${__A_PROBE}" -o "${__A_PROBE}.o" >/dev/null 2>&1 \
            || fDie "neither ${__A_MACRO} nor ${__A_REPLACEMENT} is defined in <${__A_HEADER}> for this target"
        __A_CUR_CFLAGS="${__A_CUR_CFLAGS} -D${__A_MACRO}=${__A_REPLACEMENT}"
        fLog "Compat: <${__A_HEADER}> lacks ${__A_MACRO}, adding -D${__A_MACRO}=${__A_REPLACEMENT}" >&2
    done
}

# ----------------------------------------------------------------------------
#  Prebuilt static OpenSSL
# ----------------------------------------------------------------------------

# --------------------------
# @fFindStaticLib
# @description Find the static archive lib<name>.a in a directory; shared libraries are never accepted.
# @arg $1 string Library directory.
# @arg $2 string Library name without "lib" prefix and extension (e.g. ssl).
# @stdout Full path to lib<name>.a.
# @exitcode 0 If lib<name>.a exists and is a valid ar archive.
# @exitcode 1 If lib<name>.a is missing or not a static archive.
fFindStaticLib() {
    local __A_DIR="$1" __A_NAME="$2"
    local __A_LIB="${__A_DIR}/lib${__A_NAME}.a"
    fIsStaticArchive "${__A_LIB}" || return 1
    printf '%s' "${__A_LIB}"
}

# --------------------------
# @fResolveOpenSSL
# @description Locate and validate the prebuilt static OpenSSL for one target inside __A_OPENSSL_DIR.
# @arg $1 string Target sub-path: ios, macos, android/arm64-v8a or android/armeabi-v7a.
# @set __A_OSSL_ROOT __A_OSSL_SSL_LIB __A_OSSL_CRYPTO_LIB
# @stdout Detected OpenSSL version.
# @exitcode 0 If headers and static archives are found.
# @exitcode 1 If the folder, ssl.h, libssl.a or libcrypto.a is missing or invalid (script terminates).
fResolveOpenSSL() {
    local __A_SUB="$1" __A_VER __A_HDR
    __A_OSSL_ROOT="${__A_OPENSSL_DIR}/${__A_SUB}"
    __A_HDR="${__A_OSSL_ROOT}/include/openssl/opensslv.h"

    [[ -d "${__A_OSSL_ROOT}" ]] \
        || fDie "prebuilt OpenSSL for '${__A_SUB}' not found: ${__A_OSSL_ROOT}"
    [[ -f "${__A_OSSL_ROOT}/include/openssl/ssl.h" ]] \
        || fDie "missing ${__A_OSSL_ROOT}/include/openssl/ssl.h"
    __A_OSSL_SSL_LIB="$(fFindStaticLib "${__A_OSSL_ROOT}/lib" ssl)" \
        || fDie "static libssl.a not found or invalid in ${__A_OSSL_ROOT}/lib"
    __A_OSSL_CRYPTO_LIB="$(fFindStaticLib "${__A_OSSL_ROOT}/lib" crypto)" \
        || fDie "static libcrypto.a not found or invalid in ${__A_OSSL_ROOT}/lib"

    __A_VER="$(grep -hE '^#[[:space:]]*define[[:space:]]+OPENSSL_VERSION_(TEXT|STR)[[:space:]]' \
                   "${__A_HDR}" 2>/dev/null | sed -E 's/.*"(.*)".*/\1/' | head -n 1 || true)"
    fLog "OpenSSL (${__A_SUB}): ${__A_VER:-unknown version}, static"
}

# --------------------------
# @fValidateOpenSSL
# @description Check that a prebuilt static OpenSSL exists for every requested target before building.
# @arg $@ string Targets: ios, macos, android.
# @stdout Detected OpenSSL versions.
# @exitcode 0 If every target has a valid prebuilt static OpenSSL.
# @exitcode 1 If the folder is unset/missing or a target is incomplete (script terminates).
fValidateOpenSSL() {
    local __A_TARGET __A_ABI
    [[ -n "${__A_OPENSSL_DIR}" ]] \
        || fDie "prebuilt OpenSSL folder not set (use --openssl-dir <dir> or __A_OPENSSL_DIR)"
    [[ -d "${__A_OPENSSL_DIR}" ]] \
        || fDie "OpenSSL folder does not exist: ${__A_OPENSSL_DIR}"
    for __A_TARGET in "$@"; do
        if [[ "${__A_TARGET}" == "android" ]]; then
            for __A_ABI in "${__A_ANDROID_ABIS[@]}"; do
                fResolveOpenSSL "android/${__A_ABI}"
            done
        else
            fResolveOpenSSL "${__A_TARGET}"
        fi
    done
}

# ----------------------------------------------------------------------------
#  libssh builder
# ----------------------------------------------------------------------------

# --------------------------
# @fBuildLibssh
# @description Configure, build and install static libssh with CMake against the OpenSSL resolved by fResolveOpenSSL.
# @arg $1 string Build directory (recreated).
# @arg $2 string Install prefix (recreated).
# @arg $3 string Hardening CFLAGS.
# @arg $@ string Extra platform-specific CMake arguments.
# @stdout CMake and compiler output.
# @exitcode 0 On success.
# @exitcode 1 On configure, build or install failure (script terminates).
fBuildLibssh() {
    local __A_BUILD="$1" __A_PREFIX="$2" __A_CFLAGS="$3"
    shift 3

    fLog "libssh ${__A_LIBSSH_VERSION} (static) -> ${__A_PREFIX}"
    rm -rf "${__A_BUILD}" "${__A_PREFIX}"
    cmake -S "${__A_LIBSSH_SRC}" -B "${__A_BUILD}" -G "${__A_GENERATOR}" \
        -DCMAKE_BUILD_TYPE="${__A_BUILD_TYPE}" \
        -DCMAKE_INSTALL_PREFIX="${__A_PREFIX}" \
        -DCMAKE_INSTALL_LIBDIR=lib \
        -DCMAKE_INSTALL_INCLUDEDIR=include \
        -DCMAKE_POSITION_INDEPENDENT_CODE=ON \
        -DCMAKE_C_FLAGS="${__A_CFLAGS}" \
        -DCMAKE_FIND_ROOT_PATH="${__A_OSSL_ROOT}" \
        -DCMAKE_PREFIX_PATH="${__A_OSSL_ROOT}" \
        -DCMAKE_FIND_LIBRARY_SUFFIXES=".a" \
        -DBUILD_SHARED_LIBS=OFF \
        -DBUILD_STATIC_LIB=OFF \
        -DOPENSSL_ROOT_DIR="${__A_OSSL_ROOT}" \
        -DOPENSSL_USE_STATIC_LIBS=TRUE \
        -DOPENSSL_INCLUDE_DIR="${__A_OSSL_ROOT}/include" \
        -DOPENSSL_CRYPTO_LIBRARY="${__A_OSSL_CRYPTO_LIB}" \
        -DOPENSSL_SSL_LIBRARY="${__A_OSSL_SSL_LIB}" \
        -DWITH_GCRYPT=OFF \
        -DWITH_MBEDTLS=OFF \
        -DWITH_GSSAPI=OFF \
        -DWITH_ZLIB=OFF \
        -DWITH_SERVER="${__A_WITH_SERVER}" \
        -DWITH_SFTP="${__A_WITH_SFTP}" \
        -DWITH_EXEC="${__A_WITH_EXEC}" \
        -DWITH_PCAP=OFF \
        -DWITH_DEBUG_CALLTRACE=OFF \
        -DWITH_DEBUG_CRYPTO=OFF \
        -DWITH_DEBUG_PACKET=OFF \
        -DWITH_INSECURE_NONE=OFF \
        -DWITH_BLOWFISH_CIPHER=OFF \
        -DWITH_PKCS11_URI=OFF \
        -DWITH_FIDO2=OFF \
        -DFUZZ_TESTING=OFF \
        -DWITH_EXAMPLES=OFF \
        -DWITH_BENCHMARKS=OFF \
        -DWITH_SYMBOL_VERSIONING=OFF \
        -DUNIT_TESTING=OFF \
        -DCLIENT_TESTING=OFF \
        -DSERVER_TESTING=OFF \
        "$@"
    if ! cmake --build "${__A_BUILD}" --parallel "${__A_JOBS}" 2>&1 | tee "${__A_BUILD}/build.log"; then
        fReportBuildFailure "${__A_BUILD}"
    fi
    cmake --install "${__A_BUILD}"
    fVerifyStaticInstall "${__A_PREFIX}"
}

# --------------------------
# @fReportBuildFailure
# @description Re-run a failed build serially and verbosely so the real compiler error is not lost in parallel output, print it and terminate.
# @arg $1 string Build directory of the failed build.
# @stdout Serial rebuild progress.
# @stderr First compiler errors with context, failing compiler command and log paths.
# @exitcode 1 Always (script terminates).
fReportBuildFailure() {
    local __A_BUILD="$1"
    local __A_LOG="${__A_BUILD}/build-serial.log"

    fWarn "parallel build failed, re-running serially to isolate the error (log: ${__A_LOG})"
    if cmake --build "${__A_BUILD}" --parallel 1 --verbose > "${__A_LOG}" 2>&1; then
        fDie "serial rebuild succeeded; the parallel failure may be a race. Full log: ${__A_BUILD}/build.log"
    fi

    printf '\n\033[1;31m========== first compiler errors ==========\033[0m\n' >&2
    grep -nE -B4 -A6 '(error:|fatal error:|undefined reference|Undefined symbols|ld: )' "${__A_LOG}" \
        | head -n 80 >&2 || tail -n 60 "${__A_LOG}" >&2
    printf '\033[1;31m========== failing compiler command ==========\033[0m\n' >&2
    grep -E '(clang|cc|gcc)[^ ]* .* -c ' "${__A_LOG}" | tail -n 1 >&2 || true
    printf '\033[1;31m===========================================\033[0m\n\n' >&2

    fDie "libssh build failed. Full logs: ${__A_BUILD}/build.log and ${__A_LOG}"
}

# --------------------------
# @fVerifyStaticInstall
# @description Ensure an install prefix contains a valid static libssh.a and no shared libraries.
# @arg $1 string Install prefix.
# @stdout Confirmation message.
# @stderr Error describing the offending files.
# @exitcode 0 If only static archives were installed.
# @exitcode 1 If libssh.a is missing/invalid or any .so/.dylib is present (script terminates).
fVerifyStaticInstall() {
    local __A_PREFIX="$1" __A_SHARED_FOUND
    fIsStaticArchive "${__A_PREFIX}/lib/libssh.a" \
        || fDie "static libssh.a missing or invalid in ${__A_PREFIX}/lib"
    __A_SHARED_FOUND="$(find "${__A_PREFIX}" \( -name '*.so' -o -name '*.so.*' -o -name '*.dylib' \) -print)"
    [[ -z "${__A_SHARED_FOUND}" ]] \
        || fDie "shared libraries found in ${__A_PREFIX}: ${__A_SHARED_FOUND}"
    fLog "Verified static-only install: ${__A_PREFIX}/lib/libssh.a"
}

# ----------------------------------------------------------------------------
#  Android
# ----------------------------------------------------------------------------

# --------------------------
# @fFindAndroidNdk
# @description Locate the Android NDK under ANDROID_HOME (ndk/<__A_NDK_VERSION>, newest ndk/*, or ndk-bundle) and its LLVM toolchain.
# @noargs
# @set __A_NDK_DIR __A_NDK_TOOLCHAIN
# @stdout Selected NDK path.
# @exitcode 0 If a valid NDK is found.
# @exitcode 1 If ANDROID_HOME is unset/invalid or no usable NDK exists (script terminates).
fFindAndroidNdk() {
    local __A_HOST_TAG
    [[ -n "${ANDROID_HOME:-}" ]] || fDie "ANDROID_HOME is not set"
    [[ -d "${ANDROID_HOME}" ]]   || fDie "ANDROID_HOME does not exist: ${ANDROID_HOME}"

    if [[ -n "${__A_NDK_VERSION}" ]]; then
        __A_NDK_DIR="${ANDROID_HOME}/ndk/${__A_NDK_VERSION}"
    elif [[ -d "${ANDROID_HOME}/ndk" ]]; then
        __A_NDK_DIR="$(find "${ANDROID_HOME}/ndk" -mindepth 1 -maxdepth 1 -type d | sort -V | tail -n 1)"
    elif [[ -d "${ANDROID_HOME}/ndk-bundle" ]]; then
        __A_NDK_DIR="${ANDROID_HOME}/ndk-bundle"
    fi
    [[ -n "${__A_NDK_DIR}" && -d "${__A_NDK_DIR}" ]] \
        || fDie "Android NDK not found under ${ANDROID_HOME} (ndk/<version> or ndk-bundle)"
    [[ -f "${__A_NDK_DIR}/build/cmake/android.toolchain.cmake" ]] \
        || fDie "invalid NDK (no android.toolchain.cmake): ${__A_NDK_DIR}"

    case "${__A_HOST_OS}" in
        Linux)  __A_HOST_TAG="linux-x86_64" ;;
        Darwin) __A_HOST_TAG="darwin-x86_64" ;;   # universal binaries on Apple Silicon too
        *)      fDie "unsupported host for Android NDK: ${__A_HOST_OS}" ;;
    esac
    __A_NDK_TOOLCHAIN="${__A_NDK_DIR}/toolchains/llvm/prebuilt/${__A_HOST_TAG}"
    [[ -x "${__A_NDK_TOOLCHAIN}/bin/clang" ]] || fDie "NDK clang not found in ${__A_NDK_TOOLCHAIN}"
    fLog "Using Android NDK: ${__A_NDK_DIR}"
}

# --------------------------
# @fBuildAndroidAbi
# @description Build static libssh for one Android ABI into <install-dir>/android/<abi>.
# @arg $1 string Android ABI: arm64-v8a or armeabi-v7a.
# @set __A_CC_PROBE __A_CUR_CFLAGS __A_CUR_FORTIFY_LEVEL
# @stdout Build progress and recommended final-link LDFLAGS.
# @stderr Hardening probe warnings.
# @exitcode 0 On success.
# @exitcode 1 On unsupported ABI or build failure (script terminates).
fBuildAndroidAbi() {
    local __A_ABI="$1"
    local __A_PREFIX="${__A_INSTALL_DIR}/android/${__A_ABI}"
    local __A_TRIPLE __A_IS_ARM64 __A_FINAL_LDFLAGS

    case "${__A_ABI}" in
        arm64-v8a)
            __A_TRIPLE="aarch64-linux-android"
            __A_IS_ARM64=1
            __A_FINAL_LDFLAGS="${__A_FINAL_LDFLAGS_ANDROID} ${__A_FINAL_LDFLAGS_ANDROID_ARM64}"
            ;;
        armeabi-v7a)
            __A_TRIPLE="armv7a-linux-androideabi"
            __A_IS_ARM64=0
            __A_FINAL_LDFLAGS="${__A_FINAL_LDFLAGS_ANDROID}"
            ;;
        *) fDie "unsupported Android ABI: ${__A_ABI}" ;;
    esac

    fLog "=== Android ${__A_ABI} (API ${__A_ANDROID_API}) ==="
    fResolveOpenSSL "android/${__A_ABI}"

    __A_CC_PROBE=("${__A_NDK_TOOLCHAIN}/bin/clang" "--target=${__A_TRIPLE}${__A_ANDROID_API}")
    fHardeningCflags "${__A_IS_ARM64}"
    fAddCompatDefines
    fLog "CFLAGS : ${__A_CUR_CFLAGS}"

    fBuildLibssh "${__A_WORK_DIR}/libssh-android-${__A_ABI}" "${__A_PREFIX}" \
        "${__A_CUR_CFLAGS}" \
        -DCMAKE_TOOLCHAIN_FILE="${__A_NDK_DIR}/build/cmake/android.toolchain.cmake" \
        -DANDROID_ABI="${__A_ABI}" \
        -DANDROID_PLATFORM="android-${__A_ANDROID_API}"

    fLog "Final link (app): libssh.a libssl.a libcrypto.a -ldl ${__A_FINAL_LDFLAGS}"
}

# --------------------------
# @fBuildAndroid
# @description Build static libssh for every ABI listed in __A_ANDROID_ABIS.
# @noargs
# @stdout Build progress.
# @exitcode 0 On success.
# @exitcode 1 On any ABI build failure (script terminates).
fBuildAndroid() {
    local __A_ABI
    for __A_ABI in "${__A_ANDROID_ABIS[@]}"; do
        fBuildAndroidAbi "${__A_ABI}"
    done
}

# ----------------------------------------------------------------------------
#  iOS (arm64)
# ----------------------------------------------------------------------------

# --------------------------
# @fBuildIos
# @description Build static libssh for iOS arm64 into <install-dir>/ios.
# @noargs
# @set __A_CC_PROBE __A_CUR_CFLAGS __A_CUR_FORTIFY_LEVEL
# @stdout Build progress and recommended final-link LDFLAGS.
# @stderr Hardening probe warnings.
# @exitcode 0 On success.
# @exitcode 1 On SDK lookup or build failure (script terminates).
fBuildIos() {
    local __A_PREFIX="${__A_INSTALL_DIR}/ios"
    local __A_SDK

    fLog "=== iOS arm64 (min ${__A_IOS_MIN}) ==="
    fResolveOpenSSL "ios"

    __A_SDK="$(xcrun --sdk iphoneos --show-sdk-path)"
    __A_CC_PROBE=(xcrun --sdk iphoneos clang -arch arm64 -isysroot "${__A_SDK}" "-mios-version-min=${__A_IOS_MIN}")
    fHardeningCflags 1
    fAddCompatDefines
    fLog "CFLAGS : ${__A_CUR_CFLAGS}"

    fBuildLibssh "${__A_WORK_DIR}/libssh-ios" "${__A_PREFIX}" \
        "${__A_CUR_CFLAGS}" \
        -DCMAKE_SYSTEM_NAME=iOS \
        -DCMAKE_OSX_SYSROOT=iphoneos \
        -DCMAKE_OSX_ARCHITECTURES=arm64 \
        -DCMAKE_OSX_DEPLOYMENT_TARGET="${__A_IOS_MIN}"

    fLog "Final link (app): libssh.a libssl.a libcrypto.a ${__A_FINAL_LDFLAGS_APPLE}"
}

# ----------------------------------------------------------------------------
#  macOS (arm64)
# ----------------------------------------------------------------------------

# --------------------------
# @fBuildMacos
# @description Build static libssh for macOS arm64 into <install-dir>/macos.
# @noargs
# @set __A_CC_PROBE __A_CUR_CFLAGS __A_CUR_FORTIFY_LEVEL
# @stdout Build progress and recommended final-link LDFLAGS.
# @stderr Hardening probe warnings.
# @exitcode 0 On success.
# @exitcode 1 On SDK lookup or build failure (script terminates).
fBuildMacos() {
    local __A_PREFIX="${__A_INSTALL_DIR}/macos"
    local __A_SDK

    fLog "=== macOS arm64 (min ${__A_MACOS_MIN}) ==="
    fResolveOpenSSL "macos"

    __A_SDK="$(xcrun --sdk macosx --show-sdk-path)"
    __A_CC_PROBE=(xcrun --sdk macosx clang -arch arm64 -isysroot "${__A_SDK}" "-mmacosx-version-min=${__A_MACOS_MIN}")
    fHardeningCflags 1
    fAddCompatDefines
    fLog "CFLAGS : ${__A_CUR_CFLAGS}"

    fBuildLibssh "${__A_WORK_DIR}/libssh-macos" "${__A_PREFIX}" \
        "${__A_CUR_CFLAGS}" \
        -DCMAKE_OSX_SYSROOT=macosx \
        -DCMAKE_OSX_ARCHITECTURES=arm64 \
        -DCMAKE_OSX_DEPLOYMENT_TARGET="${__A_MACOS_MIN}"

    fLog "Final link (app): libssh.a libssl.a libcrypto.a ${__A_FINAL_LDFLAGS_APPLE}"
}

# ----------------------------------------------------------------------------
#  Main
# ----------------------------------------------------------------------------

# --------------------------
# @fParseArgs
# @description Parse command line options and targets; normalise directories to absolute paths.
# @arg $@ string Command line: [-o|--openssl-dir DIR] [-i|--install-dir DIR] [-h|--help] [ios] [macos] [android].
# @set __A_TARGETS __A_OPENSSL_DIR __A_INSTALL_DIR
# @stdout Usage text for --help.
# @exitcode 0 On success or after --help (script exits).
# @exitcode 1 On unknown argument or missing option value (script terminates).
fParseArgs() {
    __A_TARGETS=()
    while [[ $# -gt 0 ]]; do
        case "$1" in
            ios|macos|android)
                __A_TARGETS+=("$1") ;;
            -o|--openssl-dir)
                [[ $# -ge 2 && -n "$2" ]] || fDie "$1 requires a directory"
                __A_OPENSSL_DIR="$2"; shift ;;
            --openssl-dir=*)
                __A_OPENSSL_DIR="${1#*=}" ;;
            -i|--install-dir)
                [[ $# -ge 2 && -n "$2" ]] || fDie "$1 requires a directory"
                __A_INSTALL_DIR="$2"; shift ;;
            --install-dir=*)
                __A_INSTALL_DIR="${1#*=}" ;;
            -h|--help)
                fUsage; exit 0 ;;
            *)
                fDie "unknown argument: $1 (see --help)" ;;
        esac
        shift
    done

    [[ -n "${__A_INSTALL_DIR}" ]] || fDie "install directory must not be empty"
    __A_INSTALL_DIR="$(fAbsPath "${__A_INSTALL_DIR}")"
    [[ -z "${__A_OPENSSL_DIR}" ]] || __A_OPENSSL_DIR="$(fAbsPath "${__A_OPENSSL_DIR}")"
}

# --------------------------
# @fMain
# @description Entry point: parse arguments, validate host/tools/OpenSSL/NDK, fetch libssh and build all requested targets.
# @arg $@ string Command line arguments (see fParseArgs).
# @stdout Build progress and list of produced static libraries.
# @stderr Warnings and errors.
# @exitcode 0 If all requested targets were built.
# @exitcode 1 On any validation or build failure (script terminates).
fMain() {
    local __A_TARGET __A_TOGGLE

    fParseArgs "$@"

    if [[ ${#__A_TARGETS[@]} -eq 0 ]]; then
        if [[ "${__A_HOST_OS}" == "Darwin" ]]; then
            __A_TARGETS=(ios macos android)
        else
            fWarn "host is ${__A_HOST_OS}: iOS/macOS builds require macOS, building Android only"
            __A_TARGETS=(android)
        fi
    fi

    for __A_TARGET in "${__A_TARGETS[@]}"; do
        if [[ "${__A_TARGET}" != "android" && "${__A_HOST_OS}" != "Darwin" ]]; then
            fDie "${__A_TARGET} build requires a macOS host with Xcode"
        fi
    done

    for __A_TOGGLE in __A_WITH_SERVER __A_WITH_SFTP __A_WITH_EXEC; do
        case "${!__A_TOGGLE}" in
            ON|OFF) ;;
            *) fDie "${__A_TOGGLE} must be ON or OFF (got '${!__A_TOGGLE}')" ;;
        esac
    done
    [[ "${__A_LIBSSH_SHA256}" =~ ^[0-9a-f]{64}$ ]] \
        || fDie "__A_LIBSSH_SHA256 must be set to the SHA-256 of libssh-${__A_LIBSSH_VERSION}.tar.xz (only ${__A_LIBSSH_PINNED_VERSION} is pinned by default)"

    fRequireTool curl tar cmake awk sed grep head find
    [[ "${__A_HOST_OS}" == "Darwin" ]] && fRequireTool xcrun
    fDetectJobs
    fDetectGenerator

    fLog "libssh ${__A_LIBSSH_VERSION} (static only)"
    fLog "targets    : ${__A_TARGETS[*]}"
    fLog "openssl dir: ${__A_OPENSSL_DIR:-<not set>}"
    fLog "install dir: ${__A_INSTALL_DIR}"
    fLog "features   : server=${__A_WITH_SERVER} sftp=${__A_WITH_SFTP} exec=${__A_WITH_EXEC}"
    fLog "jobs: ${__A_JOBS}  generator: ${__A_GENERATOR}"

    # Validate inputs and toolchains before downloading anything.
    fValidateOpenSSL "${__A_TARGETS[@]}"
    for __A_TARGET in "${__A_TARGETS[@]}"; do
        if [[ "${__A_TARGET}" == "android" ]]; then
            fFindAndroidNdk
        fi
    done

    fPrepareSources

    for __A_TARGET in "${__A_TARGETS[@]}"; do
        case "${__A_TARGET}" in
            ios)     fBuildIos ;;
            macos)   fBuildMacos ;;
            android) fBuildAndroid ;;
        esac
    done

    fLog "Done. Static libraries in ${__A_INSTALL_DIR}:"
    find "${__A_INSTALL_DIR}" -name '*.a' | sed "s|^${__A_INSTALL_DIR}/|  |" | sort
}

fMain "$@"
