#!/usr/bin/env bash

SCRIPT_DEBUG="${SCRIPT_DEBUG:-"0"}"
DATE_OPTS="${DATE_OPTS:-"--rfc-3339=ns"}"
EXIT_FAILURE="${EXIT_FAILURE:-1}"

log.msg() {
  local \
    level \
    rc
  local -a \
    msg
  level="${1?cannot continue without level}"
  level="${level^^}"
  shift 1
  msg=("${@}")
  if [[ "${level}" = "DEBUG" && "${SCRIPT_DEBUG}" -lt 1 ]]; then
    return 0
  fi
  if [[ "${level}" = "TRACE" && "${SCRIPT_DEBUG}" -lt 2 ]]; then
    return 0
  fi
  rc=0
  echo -e "$(date "${DATE_OPTS}" || true) - ${level} - ${msg[*]}"
  # shellcheck disable=SC2320
  rc=$?
  return "${rc}"
}

log.debug() {
  local \
    level
  level="${FUNCNAME[0]##*.}"
  level="${level^^}"
  log.msg "${level}" "${@}"
  return $?
}

log.trace() {
  local \
    level
  level="${FUNCNAME[0]##*.}"
  level="${level^^}"
  log.msg "${level}" "${@}"
  return $?
}

log.info() {
  local \
    level
  level="${FUNCNAME[0]##*.}"
  level="${level^^}"
  log.msg "${level}" "${@}"
  return $?
}

log.warn() {
  local \
    level
  level="${FUNCNAME[0]##*.}"
  level="${level^^}"
  log.msg "${level}" "${@}"
  return $?
}

log.error() {
  local \
    level
  level="${FUNCNAME[0]##*.}"
  level="${level^^}"
  log.msg "${level}" "${@}"
  return $?
}

log.fatal() {
  local \
    level
  level="${FUNCNAME[0]##*.}"
  level="${level^^}"
  log.msg "${level}" "${@}"
  return $?
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
  return "${rc}"
}
