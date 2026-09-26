#!/usr/bin/env bash

SCRIPT_DEBUG="${SCRIPT_DEBUG:-"0"}"
DATE_OPTS="${DATE_OPTS:-"--rfc-3339=sec"}"
EXIT_FAILURE="${EXIT_FAILURE:-1}"
DO_NOT_EXIT="${DO_NOT_EXIT:-"0"}"
CURR_OS="$(uname -s || true)"

case "${CURR_OS}" in
"Linux")
  DATE="$(command -v date || true)"
  ;;
"Darwin")
  DATE="$(command -v gdate || true)"
  ;;
*)
  echo -e "FATAL: unsupported Operating System: ${CURR_OS}" >&2
  exit 1
  ;;
esac

log.msg() {
  local level="${1?cannot continue without level}"
  local rc=0
  level="${level^^}"
  shift 1
  [[ "${level}" = "DEBUG" && "${SCRIPT_DEBUG}" -lt 1 ]] && return "${rc}"
  [[ "${level}" = "TRACE" && "${SCRIPT_DEBUG}" -lt 2 ]] && return "${rc}"
  case "${level}" in
  "DEBUG" | "ERROR" | "FATAL" | "TRACE")
    # These levels print to stderr
    echo -e "$("${DATE}" "${DATE_OPTS}" || true) - ${level} - ${*}" >&2
    # shellcheck disable=SC2320
    rc=$?
    ;;
  *)
    echo -e "$("${DATE}" "${DATE_OPTS}" || true) - ${level} - ${*}"
    # shellcheck disable=SC2320
    rc=$?
    ;;
  esac
  return "${rc}"
}

log.debug() {
  local level="${FUNCNAME[0]##*.}"
  log.msg "${level^^}" "${@}"
  return $?
}

log.error() {
  local level="${FUNCNAME[0]##*.}"
  log.msg "${level^^}" "${@}"
  return $?
}

log.fatal() {
  local level="${FUNCNAME[0]##*.}"
  log.msg "${level^^}" "${@}"
  return $?
}

log.info() {
  local level="${FUNCNAME[0]##*.}"
  log.msg "${level^^}" "${@}"
  return $?
}

log.trace() {
  local level="${FUNCNAME[0]##*.}"
  log.msg "${level^^}" "${@}"
  return $?
}

log.warn() {
  local level="${FUNCNAME[0]##*.}"
  log.msg "${level^^}" "${@}"
  return $?
}

die() {
  local rc="${1?cannot continue without rc}"
  shift 1
  local exit_func="exit"
  log.fatal "${@}"
  [[ "${DO_NOT_EXIT}" -gt 0 ]] && exit_func="return"
  "${exit_func}" "${rc}"
}

cmd.run() {
  local \
    success_rc \
    rc
  local -a \
    cmd
  success_rc="${1?cannot continue without success_rc}"
  shift 1
  cmd=("${@}")
  log.debug "Executing cmd: '${cmd[*]}'"
  "${cmd[@]}"
  rc=$?
  if [[ "${rc}" -ne "${success_rc}" ]]; then
    log.debug "cmd failed with rc=${rc}"
    if [[ "${EXIT_FAILURE}" -gt 0 ]]; then
      exit "${rc}"
    fi
  fi
  log.debug "cmd succeeded with rc=${rc}"
  return "${rc}"
}

run.detect_distro_id() {
  local \
    os \
    id
  os="$(uname -s || true)"
  case "${os}" in
  "Darwin")
    id="${os}"
    ;;
  "Linux")
    id="${1:-"$(lsb_release -s -i || echo "UNSUPPORTED")"}"
    ;;
  *)
    die 1 "Unsupported OS: ${os}"
    ;;
  esac
  if ! [[ -v DISTRO_ID_PKG_MGR_MAP["${id}"] ]]; then
    log.fatal "Unsupported distribution id: ${id}"
    die 1 "Supported distribution ids: ${!DISTRO_ID_PKG_MGR_MAP[*]}"
  fi
  echo "${id}"
  return 0
}

run.ensure_apps() {
  local app
  local -a apps=("${@}")
  [[ "${#apps[@]}" -eq 0 ]] && {
    log.warn "${FUNCNAME[0]} got 0 apps to ensure"
    return 0
  }
  for app in "${apps[@]}"; do command -v "${app}" >/dev/null || return 1; done
  return 0
}

runner.dnf() {
  local \
    op \
    curr_uid
  local -a \
    packages \
    run_cmd
  op="${1?cannot continue without op}"
  shift 1
  packages=("${@}")
  if [[ "${#packages[@]}" -eq 0 ]]; then
    log.warn "no packages were passed for operation: '${op}'"
  fi
  run_cmd=()
  curr_uid="$(id -u || true)"
  if [[ "${curr_uid}" -ne "0" ]]; then
    run_cmd+=(sudo)
    log.debug "prepended sudo to the command. [REASON: uid=${curr_uid} (!= 0) ]"
  fi
  run_cmd+=(dnf "${op}")
  if [[ "${#DNF_FLAGS[@]}" -gt 0 ]]; then
    run_cmd+=("${DNF_FLAGS[@]}")
  fi
  run_cmd+=("${packages[@]}")
  cmd.run 0 "${run_cmd[@]}"
}

runner.apt() {
  local op
  local -a \
    packages \
    run_cmd
  op="${1?cannot continue without op}"
  shift 1
  packages=("${@}")
  if [[ "${#packages[@]}" -eq 0 ]]; then
    log.warn "no packages were passed for operation: '${op}'"
  fi
  run_cmd=(apt "${op}")
  if [[ "${#APT_FLAGS[@]}" -gt 0 ]]; then
    run_cmd+=("${APT_FLAGS[@]}")
  fi
  run_cmd+=("${packages[@]}")
  cmd.run 0 "${run_cmd[@]}"
}

runner.brew() {
  local op
  local -a \
    packages \
    run_cmd
  op="${1?cannot continue without op}"
  shift 1
  packages=("${@}")
  if [[ "${#packages[@]}" -eq 0 ]]; then
    log.warn "no packages were passed for operation: '${op}'"
  fi
  run_cmd=(brew "${op}")
  run_cmd+=("${packages[@]}")
  cmd.run 0 "${run_cmd[@]}"
}

run.pkg() {
  local \
    distro_id \
    op \
    pkg_runner
  local -a \
    packages
  distro_id="${1?cannot continue without distro_id}"
  log.debug "Detected distro id: ${distro_id}"
  op="${2?cannot continue without op}"
  log.debug "detected operation: '${op}'"
  pkg_runner="runner.${DISTRO_ID_PKG_MGR_MAP["${distro_id}"]}"
  case "${DISTRO_ID_PKG_MGR_MAP["${distro_id}"]}" in
  "apt")
    packages=("${APT_PACKAGES[@]}")
    ;;
  "dnf")
    packages=("${DNF_PACKAGES[@]}")
    ;;
  "brew")
    packages=("${BREW_PACKAGES[@]}")
    ;;
  *)
    log.fatal "Unsupported distribution id: ${distro_id}"
    die 1 "Supported distribution ids: ${!DISTRO_ID_PKG_MGR_MAP[*]}"
    ;;
  esac
  if [[ "${#EXTRA_PACKAGES[@]}" -gt 0 ]]; then

    packages+=("${EXTRA_PACKAGES[@]}")
  fi
  "${pkg_runner}" "${op}" "${packages[@]}"
  return 0
}
