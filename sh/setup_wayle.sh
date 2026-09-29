#!/usr/bin/env bash

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" &>/dev/null && pwd)
SCRIPT_NAME="$(basename "${BASH_SOURCE[0]}")" &>/dev/null
SCRIPT_DEBUG="${SCRIPT_DEBUG:-0}"
SCRIPT_FORCE="${SCRIPT_FORCE:-0}"
SCRIPT_ID="${SCRIPT_ID:-"${SCRIPT_NAME%%.*}-$(date +%s || true)"}"
if ! declare -p EMACS_CFG_FILES 2>/dev/null | grep -q '^declare -A'; then
  declare -A EMACS_CFG_FILES
else
  EMACS_CFG_FILES=()
fi
SCRIPT_OS="${SCRIPT_OS:-"$(uname -s || true)"}"

if [[ -d "${SCRIPT_DIR}/lib" ]]; then
  for fname in "${SCRIPT_DIR}/lib"/*.bash; do
    [[ -r "${fname}" ]] || {
      echo "WARN: failed to read ${fname}"
      continue
    }
    # shellcheck source=lib/base.bash
    source "${fname}"
  done
fi

declare -a CURL_OPTS
CURL_OPTS=(
  --proto '=https'
  --tlsv1.2 -sSf
)
RUSTUP_URL="${RUSTUP_URL:-"https://sh.rustup.rs"}"
RUSTUP_PROFILE="${RUSTUP_PROFILE:-"complete"}"
WAYLE_REPO_URL="${WAYLE_REPO_URL:-"https://github.com/wayle-rs/wayle"}"
WAYLE_REF="${WAYLE_REF:-"master"}"
SETUP_PACKAGES_SKIP="${SETUP_PACKAGES_SKIP:-0}"
SETUP_RUST_SKIP="${SETUP_RUST_SKIP:-0}"
SETUP_WAYLE_SKIP="${SETUP_WAYLE_SKIP:-0}"
declare -A DISTRO_ID_PKG_MGR_MAP

DISTRO_ID_PKG_MGR_MAP['Fedora']="dnf"
DISTRO_ID_PKG_MGR_MAP['RedHat']="dnf"
DISTRO_ID_PKG_MGR_MAP['Debian']="apt"
DISTRO_ID_PKG_MGR_MAP['Ubuntu']="apt"
# DISTRO_ID_PKG_MGR_MAP['Darwin']="brew"

APT_FLAGS=(
  -y
)
APT_PACKAGES=(
  build-essential
  clang
  cmake
  git
  libfftw3-dev
  libgtk-4-dev
  libgtk4-layer-shell-dev
  libgtksourceview-5-dev
  libpipewire-0.3-dev
  libpulse-dev
  libudev-dev
  pkg-config
)

DNF_FLAGS=(
  -y
)

DNF_PACKAGES=(
  clang
  cmake
  fftw-devel
  gcc
  git
  gtk4-devel
  gtk4-layer-shell-devel
  gtksourceview5-devel
  pipewire-devel
  pkgconf-pkg-config
  pulseaudio-libs-devel
  systemd-devel
)

BREW_PACKAGES=(
  emacs-app@nightly
  fd
  llvm@21
  make
  ripgrep
  rlwrap
)
if [[ "${MU4E_ENABLED}" -gt 0 ]]; then
  APT_PACKAGES+=(
    bluez
    bus-user-session
    network-manager
    pipewire-pulse
    power-profiles-daemon
    upower
    wireplumber
  )
  DNF_PACKAGES+=(
    NetworkManager
    bluez
    pipewire-pulseaudio
    power-profiles-daemon
    upower
    wireplumber
  )
  BREW_PACKAGES+=(
    git
    gmime
    meson
    xapian
  )
fi

log.info "inside the script ${SCRIPT_NAME}"

del_paths() {
  local curr idx len msg rc
  local -a paths
  paths=("${@}")
  len="${#paths[@]}"
  [[ "${len}" -eq 0 ]] && return 0
  for ((idx = 0; idx < len; idx++)); do
    curr="${paths[${idx}]}"
    msg="Deleted $(test -d "${curr}" && echo "folder" || echo "file") ${curr} with"
    cmd.run 0 rm -fr "${curr}" && rc=$? || rc=$?
    log.debug "${msg} rc=${rc} [$((idx + 1)) of ${len}]"
  done
  log.debug "Deleted ${len} files/folders"
  return 0
}

setup_rustup() {
  local \
    rustup_url \
    rustup_profile
  local -a \
    apps
  rustup_url="${1:-"${RUSTUP_URL}"}"
  rustup_profile="${2:-"${RUSTUP_PROFILE}"}"
  skip_disabled "${FUNCNAME[0]}" || return 0
  log.info "in ${FUNCNAME[0]}(${*})"
  apps=(
    rustc
    rustup
  )
  if run.ensure_apps "${apps[@]}"; then
    log.info "the apps: ${apps[*]} are already installed"
    return 0
  else
    log.error "cannot find ${apps[*]} on PATH"
    exit 0
  fi

  cmd.run 0 curl "${CURL_OPTS[@]}" "${rustup_url}" -o /tmp/rustup.sh
  cmd.run 0 bash /tmp/rustup.sh --profile "${rustup_profile}" --yes
}

setup_wayle() {
  local \
    repo_url \
    local_path \
    ref \
    rc
  repo_url="${1?cannot continue without repo_url}"
  ref="${2:-"${WAYLE_REF}"}"
  local_path="${3:-""}"
  skip_disabled "${FUNCNAME[0]}" || return 0
  if [[ -z "${local_path}" ]]; then
    # remote 2 prefixes:
    tmp_var="${repo_url}"
    tmp_var="${tmp_var//https:\/\//}"
    tmp_var="${tmp_var//git@/}"
    log.debug "calculated subdir for local_folder: ${tmp_var}"
    local_path="${HOME}/src/${tmp_var}"
  fi
  run.git_clone_lazy "${repo_url}" "${local_path}" "${ref}"

  pushd "${PWD}" >/dev/null || die 1 "failed to 'pushd ${PWD}'"
  cd "${local_path}" || {
    popd >/dev/null || die 1 "failed to 'cd ${local_path}' and then popd'"
    die 1 "Failed to 'cd ${local_path}'"
  }
  cmd.run 0 cargo install --path wayle
  cmd.run 0 cargo install --path crates/wayle-settings
  cmd.run 0 wayle icons setup
  cmd.run 0 wayle panel start
  rc=$?
  popd >/dev/null || die 1 "failed to 'popd'"
  return "${rc}"
}

main() {
  local \
    distro_id \
    rc
  local -a \
    params
  distro_id="${1:-"$(run.detect_distro_id)"}"
  log.info "Running on ${distro_id}"
  # do some logic here
  cmd.run 0 pushd "${PWD}" &>/dev/null || {
    log.fatal "Failed to pushd ${PWD}."
    exit 1
  }
  setup_packages "${distro_id}"
  rc=$?
  params=(
    "${RUSTUP_URL}"
    "${RUSTUP_PROFILE}"
  )
  setup_rustup "${params[@]}"
  rc=$?
  params=(
    "${WAYLE_REPO_URL}"
    "${WAYLE_REF}"
  )
  setup_wayle "${params[@]}"
  rc=$?
  cmd.run 0 popd &>/dev/null || {
    log.fatal "Failed to get back from '${PWD}'"
    exit 1
  }
  return "${rc}"
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  # only run main upon real execution.
  main "${@}"
  exit $?
else
  log.warn "This script is expecting to be executed."
fi
