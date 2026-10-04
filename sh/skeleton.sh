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
  printf '%s\0' "${SCRIPT_DIR}/.${CURR_OS}.env.${SCRIPT_NAME%%.*}.bash"
  printf '%s\0' "${SCRIPT_DIR}/.env.${SCRIPT_NAME%%.*}.bash"
)

# =========================== < START LOCAL VARIABLES > ==============================
# =========================== < END  LOCAL  VARIABLES > ==============================
# =========================== < START LOCAL FUNCTIONS > ==============================
# =========================== < END  LOCAL  FUNCTIONS > ==============================

main() {
  local rc=0
  log.info "Skeleton is running"
  return "${rc}"
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  # only run main upon real execution.
  main "${@}"
  exit $?
else
  log.warn "This script is expecting to be executed."
fi
