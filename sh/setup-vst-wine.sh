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
  local level="${1}"
  shift
  local message="$*"
  local timestamp
  timestamp="$(date '+%Y-%m-%dT%H:%M:%S')"

  # debug is a no-op unless SCRIPT_DEBUG is set and > 0
  if [[ "${level,,}" == "debug" && "${SCRIPT_DEBUG:-0}" -le 0 ]]; then
    return 0
  fi

  local color_reset='\033[0m'
  local color
  case "${level,,}" in
  warn) color="${COLOR_YELOW}" ;;        # yellow
  error | fatal) color="${COLOR_RED}" ;; # red
  debug) color="${COLOR_MAGENTA}" ;;     # magenta
  *) color='' ;;                         # info: no color
  esac

  printf "%s - ${color}%s${color_reset} - %s\n" \
    "${timestamp}" "${level^^}" "${message}"
}

# Each wrapper extracts its own level by stripping the "log." prefix from
# its own name in the call stack, then delegates to log.msg.
log.info() { log.msg "${FUNCNAME[0]#log.}" "$@"; }
log.warn() { log.msg "${FUNCNAME[0]#log.}" "$@"; }
log.error() { log.msg "${FUNCNAME[0]#log.}" "$@" >&2; }
log.debug() { log.msg "${FUNCNAME[0]#log.}" "$@"; }

ok() { printf "${COLOR_GREEN}✓${COLOR_RESET} \033[0m  %s\n" "$*"; }

# die <exit_code> <message...>
die() {
  local exit_code="${1}"
  shift
  log.error "$@"
  exit "${exit_code}"
}

require_cmd() {
  command -v "$1" &>/dev/null || die 1 "Required command not found: $1 — install it first"
}

validate_sha256() {
  local file="$1" expected="$2"
  local actual
  actual="$(sha256sum "${file}" | awk '{print $1}')"
  if [[ "${actual}" != "${expected}" ]]; then
    die 1 "SHA256 mismatch for $(basename "${file}")\n  expected: ${expected}\n  got:      ${actual}"
  fi
  ok "SHA256 validated: $(basename "${file}")"
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
  local sums_file
  sums_file="$(mktemp)"
  # shellcheck disable=SC2064
  trap "rm -f ${sums_file}" RETURN

  log.info "Fetching sha256sums.txt from Kron4ek release ${WINE_VERSION} ..."
  gh release download "${WINE_VERSION}" \
    --repo Kron4ek/Wine-Builds \
    --pattern "sha256sums.txt" \
    --output "${sums_file}" ||
    die 1 "gh could not download sha256sums.txt for release ${WINE_VERSION}"

  local hash
  hash="$(grep "${WINE_TARBALL}" "${sums_file}" | awk '{print $1}')"

  [[ -n "${hash}" ]] ||
    die 1 "Could not find hash for ${WINE_TARBALL} in sha256sums.txt"

  ok "Fetched SHA256 for ${WINE_TARBALL}: ${hash}"
  printf '%s' "${hash}"
}

install_wine_runner() {
  if [[ -x "${WINE_BIN}" ]]; then
    ok "Wine runner already present: ${WINE_BIN}"
    return
  fi

  mkdir -p "${RUNNERS_DIR}"
  local tarball="${RUNNERS_DIR}/${WINE_TARBALL}"

  local wine_sha256
  wine_sha256="$(fetch_wine_sha256)"

  log.info "Downloading ${WINE_TARBALL} ..."
  gh release download "${WINE_VERSION}" \
    --repo Kron4ek/Wine-Builds \
    --pattern "${WINE_TARBALL}" \
    --output "${tarball}" ||
    die 1 "gh could not download ${WINE_TARBALL}"

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
  mkdir -p "$(dirname "${WINETRICKS_BIN}")"
  log.info "Downloading winetricks from master branch ..."
  gh api repos/Winetricks/winetricks/contents/src/winetricks \
    -H "Accept: application/vnd.github.raw" \
    -o "${WINETRICKS_BIN}" ||
    die 1 "gh could not download winetricks"
  chmod +x "${WINETRICKS_BIN}"
  ok "winetricks installed: $("${WINETRICKS_BIN}" --version 2>/dev/null | head -1 || true)"
}

# ── step 3: wine-mono ─────────────────────────────────────────────────────────

# Detects the wine-mono version the wine binary was built against by grepping
# the version string embedded in mscoree.so.
detect_mono_version() {
  local mscoree="${WINE_ROOT}/lib/wine/x86_64-unix/mscoree.so"
  [[ -f "${mscoree}" ]] || die 1 "mscoree.so not found at ${mscoree} — wine extraction failed?"

  local version
  version="$(strings "${mscoree}" | grep -oP 'wine-mono-\K[\d.]+' | head -1)"

  if [[ -z "${version}" ]]; then
    log.warn "Could not detect wine-mono version from mscoree.so — using fallback: ${WINE_MONO_VERSION_FALLBACK}"
    version="${WINE_MONO_VERSION_FALLBACK}"
  else
    ok "Detected wine-mono version from mscoree.so: ${version}"
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
  local version="$1"
  local msi_name="wine-mono-${version}-x86.msi"

  log.info "Fetching wine-mono ${version} SHA256 from GitHub release body ..."

  local body
  body="$(gh release view "wine-mono-${version}" \
    --repo wine-mono/wine-mono \
    --json body \
    --jq '.body')" ||
    die 1 "gh could not fetch wine-mono release wine-mono-${version}"

  [[ -n "${body}" && "${body}" != "null" ]] ||
    die 1 "Empty release body for wine-mono ${version} — run 'gh auth status' to verify auth"

  # Extract a 64-char hex string from the line containing the msi filename.
  # Handles formats like:
  #   wine-mono-9.3.0-x86.msi  abc123...64chars
  #   | wine-mono-9.3.0-x86.msi | abc123...64chars |
  #   sha256(wine-mono-9.3.0-x86.msi) = abc123...64chars
  local hash
  hash="$(printf '%s' "${body}" |
    grep -F "${msi_name}" |
    grep -oP '[a-f0-9]{64}' |
    head -1)"

  [[ -n "${hash}" ]] ||
    die 1 "Could not parse SHA256 for ${msi_name} from release body.
Raw body snippet:
$(printf '%s' "${body}" | grep -F "${msi_name}" | head -5 || true)"

  ok "Fetched SHA256 for ${msi_name}: ${hash}"
  printf '%s' "${hash}"
}

stage_wine_mono() {
  local mono_version
  mono_version="$(detect_mono_version)"

  local msi_name="wine-mono-${mono_version}-x86.msi"
  local dest="${MONO_CACHE_DIR}/${msi_name}"

  local mono_sha256
  mono_sha256="$(fetch_mono_sha256 "${mono_version}")"

  if [[ -f "${dest}" ]]; then
    log.info "wine-mono MSI already cached, validating ..."
    if sha256sum "${dest}" | grep -q "${mono_sha256}"; then
      ok "wine-mono already staged and valid: ${dest}"
      return
    else
      log.warn "Cached wine-mono MSI failed validation — re-downloading ..."
      rm -f "${dest}"
    fi
  fi

  mkdir -p "${MONO_CACHE_DIR}"
  log.info "Downloading ${msi_name} ..."
  gh release download "wine-mono-${mono_version}" \
    --repo wine-mono/wine-mono \
    --pattern "${msi_name}" \
    --output "${dest}" ||
    die 1 "gh could not download ${msi_name}"

  validate_sha256 "${dest}" "${mono_sha256}"
  ok "wine-mono staged: ${dest}"
}

# ── step 4: initialize wineprefix ─────────────────────────────────────────────

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

install_winetricks_deps() {
  log.info "Installing winetricks components into WINEPREFIX ..."

  WINEPREFIX="${WINEPREFIX}" \
    WINE="${WINE_BIN}" \
    WINESERVER="${WINE_ROOT}/bin/wineserver" \
    "${WINETRICKS_BIN}" -q \
    corefonts \
    vcrun2019 \
    gdiplus \
    win10

  ok "winetricks components installed"
}

# ── main ──────────────────────────────────────────────────────────────────────

main() {
  printf '\n\033[1mVST Wine Setup\033[0m\n'
  printf 'Wine:       %s (%s)\n' "${WINE_VERSION}" "staging-tkg"
  printf 'Runner:     %s\n' "${WINE_ROOT}"
  printf 'WINEPREFIX: %s\n\n' "${WINEPREFIX}"

  preflight
  install_wine_runner # sha256 fetched dynamically from Kron4ek release assets
  install_winetricks
  stage_wine_mono # version detected from wine binary; sha256 from GitHub API
  init_wineprefix
  install_winetricks_deps

  printf '\n\033[1;32mDone.\033[0m\n'
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
