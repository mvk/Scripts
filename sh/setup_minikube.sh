#!/usr/bin/env bash

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" &>/dev/null && pwd)
SCRIPT_NAME="$(basename "${BASH_SOURCE[0]}")" &>/dev/null
SCRIPT_DEBUG="${SCRIPT_DEBUG:-0}"
SCRIPT_FORCE="${SCRIPT_FORCE:-0}"
SCRIPT_ID="${SCRIPT_ID:-"${SCRIPT_NAME%%.*}-$(date +%s || true)"}"
CURR_OS="${CURR_OS:-"$(uname -s || true)"}"

while read -r fname; do
  echo "fname: ${fname}"
  [[ -r "${fname}" ]] || {
    echo "WARN: failed to read ${fname}. [REASON: file unreadable]"
    continue
  }
  # shellcheck source=lib/base.bash
  source "${fname}"
  echo "loaded: ${fname}"
done < <(
  find "${SCRIPT_DIR}/lib" -type f -name '*.bash'
  echo "${SCRIPT_DIR}/.${CURR_OS}.env.${SCRIPT_NAME%%.*}.bash"
  echo "${SCRIPT_DIR}/.env.${SCRIPT_NAME%%.*}.bash"
)

# =========================== < START LOCAL VARIABLES > ==============================
OS=""
CURR_ARCH="${CURR_ARCH:-"$(uname -m || true)"}"
ARCH=""
RELEASE="${RELEASE:-"latest"}"
URL="${URL:-"https://github.com/kubernetes/minikube"}"

# =========================== < END  LOCAL  VARIABLES > ==============================
# =========================== < START LOCAL FUNCTIONS > ==============================
detect_os() {
  local curr
  local -n target
  curr="${1?cannot continue without curr}"
  target="${2:-"OS"}"
  case "${curr}" in
  "Linux" | "Darwin")
    target="${curr,,}"
    ;;
  *)
    die 1 "Unsupported Operating System: ${curr}. This script only supports linux or darwin."
    ;;
  esac
}

detect_arch() {
  local curr
  local -n target
  curr="${1?cannot continue without curr}"
  target="${2:-"ARCH"}"
  case "${curr}" in
  "x86_64")
    target="amd64"
    ;;
  "aarch64" | "arm64")
    target="arm64"
    ;;
  *)
    die 1 "Unsupported architecture: ${curr}. This script only supports amd64 or arm64."
    ;;
  esac
}

# =========================== < END  LOCAL  FUNCTIONS > ==============================

main() {
  local \
    out_file \
    utility \
    url \
    rc
  rc=0
  url="${1:-"${URL}"}"
  detect_os "${CURR_OS}" "OS"
  log.info "Detected OS: ${OS}"
  detect_arch "${CURR_ARCH}" "ARCH"
  log.info "Detected ARCH: ${ARCH}"
  url="${url}/releases/${RELEASE}/download/minikube-${OS}-${ARCH}"
  out_file="${url##*/}"
  log.info "out_file=${out_file}"
  utility="${out_file%%-*}"
  log.info "utility=${utility}"
  cmd.run 0 curl -LO "${url}"
  cmd.run 0 sudo install "${out_file}" "/usr/local/bin/${utility}"
  cmd.run 0 rm -f "${out_file}"
  return "${rc}"
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  # only run main upon real execution.
  main "${@}"
  exit $?
else
  log.warn "This script is expecting to be executed."
fi
