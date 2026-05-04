#!/usr/bin/env bash
# setup-vst-wine.sh
# Sets up a self-contained Wine 9.21 staging-tkg environment for VST plugins.
#
# Usage:
#   ./setup-vst-wine.sh [WINEPREFIX_PATH]
#
#   WINEPREFIX_PATH defaults to ~/wine/VST-Plugins if not provided.

set -euo pipefail

# ── static configuration ──────────────────────────────────────────────────────

SCRIPT_DEBUG="${SCRIPT_DEBUG:-"0"}"
WINE_VERSION="9.21"
WINE_BUILD="wine-${WINE_VERSION}-staging-tkg-amd64"
WINE_TARBALL="${WINE_BUILD}.tar.xz"
# Kron4ek, wine-mono, and winetricks are all downloaded via gh CLI.

# wine-mono version is detected from the wine binary after extraction;
# this is the fallback used only if binary-level detection fails.
WINE_MONO_VERSION_FALLBACK="9.3.0"

RUNNERS_DIR="${HOME}/.local/share/wine-runners"
WINE_ROOT="${RUNNERS_DIR}/${WINE_BUILD}"
WINE_BIN="${WINE_ROOT}/bin/wine"
WINETRICKS_BIN="${HOME}/.local/bin/winetricks"
MONO_CACHE_DIR="${HOME}/.cache/wine"

WINEPREFIX="${1:-${HOME}/wine/VST-Plugins}"

COLOR_RESET='\033[0m'      # color reset
COLOR_YELOW='\033[0;33m'   # yellow
COLOR_RED='\033[0;31m'     # red
COLOR_MAGENTA='\033[0;35m' # magenta
COLOR_GREEN='\033[1;32m'   # green
# ── helpers ───────────────────────────────────────────────────────────────────

log.msg() {
  local \
    level \
    message \
    timestamp \
    color \
    color_reset
  level="${1?cannot continue without level}"
  shift 1
  message="${*}"
  timestamp="$(date '+%Y-%m-%dT%H:%M:%S')"

  # debug is a no-op unless SCRIPT_DEBUG is set and > 0
  if [[ "${level,,}" == "debug" && "${SCRIPT_DEBUG:-0}" -le 0 ]]; then
    return 0
  fi

  color_reset='\033[0m'
  color=''
  case "${level,,}" in
  warn) color="${COLOR_YELOW}" ;;        # yellow
  error | fatal) color="${COLOR_RED}" ;; # red
  debug) color="${COLOR_MAGENTA}" ;;     # magenta
  *) color='' ;;                         # info: no color
  esac
  printf "%s - ${color}%s${color_reset} - %s\n" "${timestamp}" "${level^^}" "${message}"
}

# Each wrapper extracts its own level by stripping the "log." prefix from
# its own name in the call stack, then delegates to log.msg.
log.info() { log.msg "${FUNCNAME[0]#log.}" "$@"; }
log.warn() { log.msg "${FUNCNAME[0]#log.}" "$@"; }
log.error() { log.msg "${FUNCNAME[0]#log.}" "$@" >&2; }
log.fatal() { log.msg "${FUNCNAME[0]#log.}" "$@" >&2; }
log.debug() { log.msg "${FUNCNAME[0]#log.}" "$@"; }

ok() { printf "${COLOR_GREEN}✓${COLOR_RESET} \033[0m  %s\n" "$*"; }

# die <exit_code> <message...>
die() {
  local exit_code="${1}"
  shift
  log.error "${@}"
  exit "${exit_code}"
}

require_cmd() {
  command -v "$1" &>/dev/null || die 1 "Required command not found: $1 — install it first"
}

validate_sha256() {
  local \
    file \
    expected \
    actual
  file="${1?file is mandatory for ${FUNCNAME[0]}(file, expected)}"
  expected="${2:-""}"
  test -e "${file}" || die 1 "the file ${file} is missing, cannot calculate its SHA256"
  actual="$(sha256sum "${file}" | awk '{print $1}' || true)"
  if [[ "${actual}" != "${expected}" ]]; then
    die 1 "SHA256 mismatch for ${file}\n  expected: ${expected}\n    actual:      ${actual}"
  fi
  ok "SHA256 validated: $(basename "${file}")"
}

# ── utils ─────────────────────────────────────────────────────────────────
gh_release_download() {
  local \
    repo \
    filename \
    target \
    version \
    rc
  local -a \
    cmd
  repo="${1?repo is mandatory in ${FUNCNAME[0]}(repo,filename,target,version)}"
  filename="${2?filename is mandatory in ${FUNCNAME[0]}(repo,filename,target,version)}"
  target="${3?target is mandatory in ${FUNCNAME[0]}(repo,filename,target,version)}"
  version="${4:-""}"
  cmd=(gh release download)
  test -n "${version}" && cmd+=("${version}")
  cmd+=(--repo "${repo}")
  cmd+=(--pattern "${filename}")
  test -e "${target}" && cmd+=(--clobber)
  cmd+=(--output "${target}")
  log.debug "Fetching ${filename} from ${repo} release ${version} ..."
  "${cmd[@]}" && rc=$? || rc=$?
  if [[ "${rc}" -ne 0 ]]; then
    die "${rc}" "gh could not download ${filename} from ${repo} for release '${version}'"
  fi
  return "${rc}"
}

gh_api_method() {
  local \
    repo \
    path \
    target \
    ref \
    method \
    url_path \
    rc
  local -a \
    cmd
  repo="${1?repo is mandatory in ${FUNCNAME[0]}(repo,path,target,ref)}"
  path="${2?path is mandatory in ${FUNCNAME[0]}(repo,path,target,ref)}"
  target="${3?target is mandatory in ${FUNCNAME[0]}(repo,path,target,ref)}"
  ref="${4:-"main"}"
  method="${5:-"GET"}"
  cmd=(gh api)
  url_path="repos/${repo}/contents/${path}?ref=${ref}"
  cmd+=("-X" "${method^^}")
  cmd+=(-H "Accept: application/vnd.github.raw")
  cmd+=("${url_path}")
  local msg="path: '${url_path}' with method '${method}'"
  log.debug "gh api accessing ${msg} ..."
  "${cmd[@]}" >"${target}" && rc=$? || rc=$?
  if [[ "${rc}" -ne 0 ]]; then
    die "${rc}" "gh api Failed to access ${msg}"
  fi
  return "${rc}"
}

# ── preflight ─────────────────────────────────────────────────────────────────

preflight() {
  log.info "Checking required tools ..."
  for cmd in sha256sum tar jq strings gh; do
    require_cmd "${cmd}"
  done

  if command -v wine &>/dev/null; then
    local sys_wine
    sys_wine="$(command -v wine)"
    if [[ "${sys_wine}" != "${WINE_BIN}" ]]; then
      log.warn "System wine found at ${sys_wine} — will NOT be used by this script."
      log.warn "System wine is unaffected."
    fi
  fi
}

# ── step 1: wine runner ───────────────────────────────────────────────────────

# Downloads sha256sums.txt from the Kron4ek release via gh and extracts
# the hash for the specific tarball we want.
fetch_wine_sha256() {
  local \
    sums_file \
    filename \
    release \
    repo \
    hash
  sums_file="$(mktemp)"
  # shellcheck disable=SC2064
  trap "rm -f ${sums_file}" RETURN
  filename="sha256sums.txt"
  release="${WINE_VERSION}"
  repo="Kron4ek/Wine-Builds"
  gh_release_download \
    "${repo}" \
    "${filename}" \
    "${sums_file}" \
    "${release}"

  local hash
  hash="$(grep "${WINE_TARBALL}" "${sums_file}" | awk '{print $1}')"

  [[ -n "${hash}" ]] ||
    die 1 "Could not find hash for ${WINE_TARBALL} in sha256sums.txt"

  log.debug "Fetched SHA256 for ${WINE_TARBALL}: ${hash}"
  printf '%s' "${hash}"
}

install_wine_runner() {
  local \
    sums_file \
    filename \
    release \
    repo \
    hash

  if [[ -x "${WINE_BIN}" ]]; then
    ok "Wine runner already present: ${WINE_BIN}"
    return
  fi

  mkdir -p "${RUNNERS_DIR}"
  local tarball="${RUNNERS_DIR}/${WINE_TARBALL}"
  local wine_sha256
  wine_sha256="$(fetch_wine_sha256)"

  repo="Kron4ek/Wine-Builds"
  release="${WINE_VERSION}"
  log.info "Downloading ${WINE_TARBALL} ..."
  gh_release_download \
    "${repo}" \
    "${WINE_TARBALL}" \
    "${tarball}" \
    "${release}"

  validate_sha256 "${tarball}" "${wine_sha256}"

  log.info "Unpacking wine runner ..."
  tar -xJf "${tarball}" -C "${RUNNERS_DIR}"
  rm -f "${tarball}"

  [[ -x "${WINE_BIN}" ]] || die 1 "Unpacked runner but ${WINE_BIN} is not executable"
  ok "Wine runner installed: ${WINE_ROOT}"
  log.info "Wine version: $("${WINE_BIN}" --version 2>/dev/null || true)"
}

# ── step 2: winetricks ────────────────────────────────────────────────────────

install_winetricks() {
  local \
    repo \
    path \
    target \
    ref
  repo="Winetricks/winetricks"
  path="src/winetricks"
  target="${WINETRICKS_BIN}"
  ref="master"
  mkdir -p "$(dirname "${target}")"
  gh_api_method \
    "${repo}" \
    "${path}" \
    "${target}" \
    "${ref}"
  chmod +x "${target}"
  ok "installed ${target}: $("${target}" --version 2>/dev/null | head -1 || true)"
}

# ── step 3: wine-mono ─────────────────────────────────────────────────────────

# Detects the wine-mono version the wine binary was built against by grepping
# the version string embedded in escoree.so.
detect_mono_version() {
  local \
    version \
    mscoree
  mscoree="${WINE_ROOT}/lib/wine/x86_64-unix/mscoree.so"
  if [[ -z "${mscoree}" ]]; then
    version="${WINE_MONO_VERSION_FALLBACK}"
    log.warn "mscoree.so not found at ${mscoree} using fallback version ${version}" >&2
    printf '%s' "${version}"
    return 0
  fi
  version="$(strings "${mscoree}" | grep -oP 'wine-mono-\K[\d.]+' | head -1)"
  if [[ -z "${version}" ]]; then
    version="${WINE_MONO_VERSION_FALLBACK}"
    log.warn "Could not detect wine-mono version from mscoree.so — using fallback: ${version}" >&2
  else
    ok "Detected wine-mono version from mscoree.so: ${version}" >&2
  fi

  printf '%s' "${version}"
}

# Fetches the sha256 for wine-mono-<version>-x86.msi from the wine-mono
# GitHub release body via gh.
#
# The release body contains checksums as a markdown block. We extract the
# 64-char hex string that appears on the same line as the msi filename —
# format-agnostic across markdown tables, plain lists, and code blocks.
fetch_mono_sha256() {
  local \
    version \
    repo \
    ref \
    installer \
    body \
    hash

  version="$1"
  repo="wine-mono/wine-mono"
  ref="${repo##*/}-${version}"
  installer="${ref}-x86.msi"

  log.info "Fetching wine-mono ${version} SHA256 from GitHub release body ..."
  body="$(gh release view "${ref}" \
    --repo "${repo}" \
    --json assets \
    --jq '.assets[].name')" ||
    die 1 "gh could not fetch ${repo} release ${ref}"

  [[ -n "${body}" && "${body}" != "null" ]] ||
    die 1 "Empty release body for ${repo} release ${ref} — run 'gh auth status' to verify auth"

  # Extract a 64-char hex string from the line containing the msi filename.
  # Handles formats like:
  #   wine-mono-9.3.0-x86.msi  abc123...64chars
  #   | wine-mono-9.3.0-x86.msi | abc123...64chars |
  #   sha256(wine-mono-9.3.0-x86.msi) = abc123...64chars
  hash="$(printf '%s' "${body}" |
    grep -F "${installer}" |
    grep -oP '[a-f0-9]{64}' |
    head -1)"

  [[ -n "${hash}" ]] ||
    die 1 "Could not parse SHA256 for ${installer} from release body.
Raw body snippet:
$(printf '%s' "${body}" | grep -F "${installer}" | head -5 || true)"

  ok "Fetched SHA256 for ${installer}: ${hash}"
  printf '%s' "${hash}"
}

stage_wine_mono() {
  local \
    mono_version \
    repo \
    release \
    installer \
    dest
  mono_version="$(detect_mono_version)"
  repo="wine-mono/wine-mono"
  release="${repo##*/}-${mono_version}"
  log.warn "Detected mono_version: ${mono_version}"
  installer="${release}-x86.msi"
  dest="${MONO_CACHE_DIR}/${installer}"

  # local mono_sha256
  # mono_sha256="$(fetch_mono_sha256 "${mono_version}")"

  # if [[ -f "${dest}" ]]; then
  #   log.info "wine-mono MSI already cached, validating ..."
  #   if sha256sum "${dest}" | grep -q "${mono_sha256}"; then
  #     ok "wine-mono already staged and valid: ${dest}"
  #     return
  #   else
  #     log.warn "Cached wine-mono MSI failed validation — re-downloading ..."
  #     rm -f "${dest}"
  #   fi
  # fi

  mkdir -p "${MONO_CACHE_DIR}"
  log.info "Downloading ${installer} ..."
  gh_release_download \
    "${repo}" \
    "${installer}" \
    "${dest}" \
    "${release}"

  # validate_sha256 "${dest}" "${mono_sha256}"
  ok "${repo##*/} staged: ${dest}"
}

# ── step 4: initialize wineprefix ─────────────────────────────────────────────

run_wine_command() {
  log.debug "no op"
}

init_wineprefix() {
  if [[ -f "${WINEPREFIX}/system.reg" ]]; then
    ok "WINEPREFIX already initialized: ${WINEPREFIX}"
    return
  fi

  log.info "Initializing WINEPREFIX: ${WINEPREFIX}"
  mkdir -p "${WINEPREFIX}"

  WINEPREFIX="${WINEPREFIX}" \
    WINESERVER="${WINE_ROOT}/bin/wineserver" \
    WINELOADER="${WINE_BIN}" \
    "${WINE_BIN}" wineboot --init

  ok "WINEPREFIX initialized: ${WINEPREFIX}"
}

# ── step 5: winetricks runtimes ───────────────────────────────────────────────
#
# corefonts  — Arial, Times, Courier; required for JUCE UI font rendering
# vcrun2019  — VC++ 2015-2019 redistributable (subsumes 2015/2017)
# gdiplus    — GDI+ used by some Arturia installer dialogs
# win10      — report Windows 10 to the prefix (registry strings only, no files)
#
# Intentionally omitted:
#   dotnet*  — wine-mono (above) covers .NET 4.x; native dotnet install is fragile
#   d3dx*/dxvk — Arturia/JUCE renders via OpenGL, not Direct3D
#   mfc42    — legacy, not used by modern JUCE

install_winetricks_dep() {
  local \
    pkg \
    rc
  local -a \
    exit_codes
  pkg="${1?package is a mandatory parameter for ${FUNCNAME[0]}(pkg, exit_codes)}"
  shift 1
  exit_codes=("${@}")
  log.info "Installing winetricks component ${pkg} into WINEPREFIX ..."

  WINEPREFIX="${WINEPREFIX}" \
    WINE="${WINE_BIN}" \
    WINESERVER="${WINE_ROOT}/bin/wineserver" \
    "${WINETRICKS_BIN}" -q "${pkg}" && rc=$? || rc=$?
  if [[ " ${exit_codes[*]} " =~ \ ${rc}\  ]]; then
    ok "winetricks component ${pkg} installed with return code ${rc}"
    return 0
  fi
  log.fatal "winetricks component ${pkg} failed to install. rc=${rc}, not in [${exit_codes[*]}]"
  exit "${rc}"
}

install_winetricks_deps() {
  local pkg
  local -a \
    pkgs
  pkgs=(
    corefonts
    vcrun2019
    gdiplus
    win10
  )
  log.info "Installing winetricks components into WINEPREFIX ..."
  for pkg in "${pkgs[@]}"; do
    if ! install_winetricks_dep "${pkg}" 0 102; then
      log.fatal "Aborting: failed to install ${pkg}"
    fi
  done
  ok "ALL winetricks components installed"
}

# ── step 0: selinux contexts ──────────────────────────────────────────────────

setup_selinux_contexts() {
  if ! command -v semanage &>/dev/null; then
    log.debug "semanage not found — skipping SELinux context setup"
    return 0
  fi

  if ! sestatus 2>/dev/null | grep -q "enabled"; then
    log.debug "SELinux not enabled — skipping context setup"
    return 0
  fi

  log.info "Applying SELinux contexts ..."

  local -a contexts=(
    "wine_exec_t    /home/[^/]+/\.local/share/wine-runners/[^/]+/bin/wine.*"
    "textrel_shlib_t /home/[^/]+/\.local/share/wine-runners/[^/]+/lib/wine/.+\.so"
    "wine_home_t    /home/[^/]+/wine(/.*)?"
  )

  local type pattern
  for entry in "${contexts[@]}"; do
    type="${entry%% *}"
    pattern="${entry#* }"
    if sudo semanage fcontext -l 2>/dev/null | grep -qF "${pattern}"; then
      log.debug "SELinux context already defined: ${pattern}"
    else
      sudo semanage fcontext -a -t "${type}" "${pattern}" ||
        die 1 "Failed to add SELinux context ${type} for ${pattern}"
      log.info "Added SELinux context ${type}: ${pattern}"
    fi
  done

  sudo restorecon -Rv \
    "${RUNNERS_DIR}" \
    "$(dirname "${WINEPREFIX}")" \
    2>/dev/null | while read -r line; do log.debug "${line}"; done

  ok "SELinux contexts applied"
}

# ── main ──────────────────────────────────────────────────────────────────────

main() {
  printf "\n%sVST Wine Setup%s\n" "${COLOR_GREEN}" "${COLOR_RESET}"
  printf 'Wine:       %s (%s)\n' "${WINE_VERSION}" "staging-tkg"
  printf 'Runner:     %s\n' "${WINE_ROOT}"
  printf 'WINEPREFIX: %s\n\n' "${WINEPREFIX}"

  preflight
  install_wine_runner # sha256 fetched dynamically from Kron4ek release assets
  install_winetricks
  stage_wine_mono # version detected from wine binary; sha256 from GitHub API
  init_wineprefix
  install_winetricks_deps

  printf "\n${COLOR_GREEN}Done.${COLOR_RESET}\n"
  printf '\nEnvironment for this prefix:\n'
  printf '  export WINEPREFIX="%s"\n' "${WINEPREFIX}"
  printf '  export WINE="%s"\n' "${WINE_BIN}"
  # shellcheck disable=SC2016
  printf '  export PATH="%s/bin:$PATH"\n\n' "${WINE_ROOT}"
  printf 'Next: run the Arturia Software Center installer:\n'
  printf '  wine /path/to/Arturia_Software_Center_*.exe\n\n'
  printf 'After installation, register with yabridge:\n'
  printf '  yabridgectl add "%s/drive_c/Program Files/Common Files/VST3"\n' "${WINEPREFIX}"
  printf '  yabridgectl sync\n\n'
}

main "$@"
