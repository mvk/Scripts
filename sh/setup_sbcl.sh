#!/usr/bin/env bash

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" &>/dev/null && pwd)
SCRIPT_NAME="$(basename "${BASH_SOURCE[0]}")" &>/dev/null
SCRIPT_DEBUG="${SCRIPT_DEBUG:-0}"
SCRIPT_FORCE="${SCRIPT_FORCE:-0}"
SCRIPT_ID="${SCRIPT_ID:-"${SCRIPT_NAME%%.*}-$(date +%s || true)"}"
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

EMACS_FLAVOR="${EMACS_FLAVOR:-"spacemacs"}"
EMACS_CFG_REPO="${EMACS_CFG_REPO:-"https://github.com/syl20bnr/spacemacs"}"
QL_URL="${QL_URL:-"https://beta.quicklisp.org/quicklisp.lisp"}"
QL_INIT_FILE="${QL_INIT_FILE:-"${PWD}/quicklisp-init.lisp"}"
EMACS_SVC_FILE="${EMACS_SVC_FILE:-".config/systemd/user/emacs-headless.service"}"
EMACS_SVC_TPL="${EMACS_SVC_TPL:-"${PWD}/${EMACS_SVC_FILE}.j2"}"
EMACS_SVC_CTX="${EMACS_SVC_CTX:-"${PWD}/${EMACS_SVC_FILE##*/}.context.yaml"}"
EMACS_CFG_DIR="${EMACS_CFG_DIR:-"${HOME}/.emacs.d"}"
SYSTEMD_INSTALL_ROOT="${SYSTEMD_INSTALL_ROOT:-"${HOME}"}"
MU4E_ENABLED="${MU4E_ENABLED:-"0"}"

EMACS_CFG_FILE="${EMACS_CFG_FILE:-"${HOME}/.spacemacs"}"
EMACS_CFG_TPL="${EMACS_CFG_TPL:-"${PWD}/$(basename "${EMACS_CFG_FILE}").j2"}"
EMACS_CFG_CTX="${EMACS_CFG_CTX:-"${PWD}/$(basename "${EMACS_CFG_FILE}").context.yaml"}"
SBCL_CFG_FILE="${SBCL_CFG_FILE:-"${HOME}/.sbclrc"}"
SBCL_CFG_TPL="${SBCL_CFG_TPL:-"${PWD}/$(basename "${SBCL_CFG_FILE}").j2"}"
SBCL_CFG_CTX="${SBCL_CFG_CTX:-"${PWD}/$(basename "${SBCL_CFG_FILE}").context.yaml"}"
DESKTOP_FILE="${DESKTOP_FILE:-"${HOME}/.local/share/applications/emacsclient.desktop"}"
DESKTOP_TPL="${DESKTOP_TPL:-"${PWD}/$(basename "${DESKTOP_FILE}").j2"}"
DESKTOP_CTX="${DESKTOP_CTX:-"${PWD}/$(basename "${DESKTOP_FILE}").context.yaml"}"
PLASMA_SHCSRC="${PLASMA_SHCSRC:-"${HOME}/.config/kglobalshortcutsrc"}"
PLASMA_KEY="${PLASMA_KEY:-"_launch"}"
PLASMA_KEY_VAL="${PLASMA_KEY_VAL:-"Ctrl+Meta+E,none,Spacemacs Client CLI Bound"}"
QDBUS_NS="${QDBUS_NS:-"org.kde.KWin"}"

SETUP_PACKAGES_SKIP="${SETUP_PACKAGES_SKIP:-"1"}"
SETUP_EMACS_CFG_DIR_SKIP="${SETUP_EMACS_CFG_DIR_SKIP:-"1"}"
SETUP_QUICKLISP_SKIP="${SETUP_QUICKLISP_SKIP:-"1"}"
SETUP_EMACS_CFG_FILE_SKIP="${SETUP_EMACS_CFG_FILE_SKIP:-"1"}"
SETUP_SBCLRC_FILE_SKIP="${SETUP_SBCLRC_FILE_SKIP:-"1"}"
SETUP_EMACS_SVC_SKIP="${SETUP_EMACS_SVC_SKIP:-"1"}"
SETUP_DESKTOP_FILE_SKIP="${SETUP_DESKTOP_FILE_SKIP:-"0"}"
SETUP_PLASMA_HOOKS_SKIP="${SETUP_PLASMA_HOOKS_SKIP:-"0"}"
declare -A DISTRO_ID_PKG_MGR_MAP

DISTRO_ID_PKG_MGR_MAP['Fedora']="dnf"
DISTRO_ID_PKG_MGR_MAP['RedHat']="dnf"
DISTRO_ID_PKG_MGR_MAP['Debian']="apt"
DISTRO_ID_PKG_MGR_MAP['Ubuntu']="apt"

APT_FLAGS=(
  -y
)
APT_PACKAGES=(
  emacs-gtk
  sbcl
  gcc
  g++
  make
  rlwrap
)

DNF_FLAGS=(
  -y
)
DNF_PACKAGES=(
  emacs
  sbcl
  gcc
  make
  rlwrap
)
if [[ "${MU4E_ENABLED}" -gt 0 ]]; then
  APT_PACKAGES+=(
    git
    meson
    libgmime-3.0-dev
    libxapian-dev
  )
  DNF_PACKAGES+=(
    git
    meson
    gmime30-devel
    xapian-core-devel
  )
fi

log.info "inside the script ${SCRIPT_NAME}"

run.detect_distro_id() {
  local id
  id="${1:-"$(lsb_release -s -i || echo "UNSUPPORTED")"}"
  if ! [[ -v DISTRO_ID_PKG_MGR_MAP["${id}"] ]]; then
    log.fatal "Unsupported distribution id: ${id}"
    die 1 "Supported distribution ids: ${!DISTRO_ID_PKG_MGR_MAP[*]}"
  fi
  echo "${id}"
  return 0
}

run.ensure_apps() {
  local \
    app
  local -a \
    apps
  apps=("${@}")
  if [[ "${#apps[@]}" -eq 0 ]]; then
    log.warn "${FUNCNAME[0]} got 0 apps to ensure"
    return 0
  fi
  for app in "${apps[@]}"; do
    command -v "${app}" >/dev/null || return 1
  done

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
  if [[ "${#packages[@]}" -eq 0 ]]; then
    log.warn "no packages were passed for operation: '${op}'"
  fi

  pkg_runner="runner.${DISTRO_ID_PKG_MGR_MAP["${distro_id}"]}"
  case "${DISTRO_ID_PKG_MGR_MAP["${distro_id}"]}" in
  "apt")
    packages=("${APT_PACKAGES[@]}")
    ;;
  "dnf")
    packages=("${DNF_PACKAGES[@]}")
    ;;
  *)
    log.fatal "Unsupported distribution id: ${distro_id}"
    die 1 "Supported distribution ids: ${!DISTRO_ID_PKG_MGR_MAP[*]}"
    ;;
  esac

  "${pkg_runner}" "${op}" "${packages[@]}"
  return 0
}

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

skip_disabled() {
  local \
    func_name \
    skip_setup
  local -n \
    skip_setup_ref
  func_name="${1:-"${FUNCNAME[1]}"}"
  skip_setup_ref="${func_name^^}_SKIP"
  skip_setup="${skip_setup_ref}"
  # handle unset variable:
  [[ -z "${skip_setup}" ]] && return 0
  if [[ "${skip_setup}" -gt 0 ]]; then
    log.info "Skip running ${func_name}(). [REASON: ${func_name^^}_SKIP=${skip_setup}]"
    return 1
  fi
  return 0
}

skip_existing() {
  local \
    func_name \
    item
  local -a \
    file_paths
  func_name="${1:-"${FUNCNAME[1]}"}"
  shift 1
  file_paths=("${@}")
  for item in "${file_paths[@]}"; do
    if [[ -e "${item}" ]]; then
      if [[ "${SCRIPT_FORCE}" -eq 0 ]]; then
        log.info "Skip running ${func_name}(). [REASON: file path: ${item} already present]"
        return 1
      fi
      # otherwise:
      mv "${item}" "${item}.${SCRIPT_ID}"
      log.debug "renamed ${item} to ${item}.${SCRIPT_ID}"
    fi
  done
  return 0
}

setup_packages() {
  local \
    distro_id
  skip_disabled "${FUNCNAME[0]}" || return 0
  distro_id="${1:-"$(run.detect_distro_id)"}"
  run.pkg "${distro_id}" install
  rc=$?
  log.info "Completed ${func_name} with rc=${rc}"
  return "${rc}"
}

setup_emacs_cfg_dir() {
  local \
    repo_url \
    target_dir \
    old_var \
    rc
  repo_url="${1:-"${EMACS_CFG_REPO}"}"
  target_dir="${2:-"${EMACS_CFG_DIR}"}"
  skip_disabled "${FUNCNAME[0]}" || return 0
  skip_existing "${FUNCNAME[0]}" "${target_dir}" || return 0
  log.info "Start setup spacemacs"
  if [[ -d "${target_dir}" ]]; then
    log.warn "target directory already present: ${target_dir}"
    pushd "${PWD}" >/dev/null || die 1 "failed to 'pushd ${PWD}'"
    cd "${target_dir}" || die 1 "failed to 'cd ${target_dir}'"
    cmd.run 0 git pull
    rc=$?
    log.debug "updated current code-base with rc=${rc}"
    cd ../
  else
    log.info "cloning ${repo_url} for the 1st time into ${target_dir}"
    cmd.run 0 git clone "${repo_url}" "${target_dir}"
    rc=$?
  fi
  log.info "set up ${target_dir} complete"
  old_var="${DO_NOT_EXIT}"
  DO_NOT_EXIT=1
  cmd.run 0 emacs --batch -l "${target_dir}/init.el" && rc=$? || rc=$?
  log.debug "initial run returned rc=${rc} (failures are frequend, do not worry)"
  DO_NOT_EXIT="${old_var}"
  cmd.run 0 emacs --batch -l "${target_dir}/init.el" && rc=$? || rc=$?
  log.info "End setup spacemacs with rc=${rc}"
  return "${rc}"
}

setup_quicklisp() {
  local \
    ql_url \
    ql_lisp \
    ql_init \
    title \
    sbclrc \
    rc
  local -a \
    cmd
  sbclrc="${HOME}/.sbclrc"
  ql_url="${1:-"${QL_URL}"}"
  ql_lisp="${ql_url##*/}"
  title="${ql_lisp%%.*}"
  ql_init="${2:-"${title}-init.lisp"}"
  skip_disabled "${FUNCNAME[0]}" || return 0
  skip_existing "${FUNCNAME[0]}" "${sbclrc}" "${HOME}/${title}" || return 0
  log.info "Start  => Setup of ${title}"
  cmd.run 0 curl -fO "${ql_url}" && rc=$? || rc=$?
  log.debug "Downloaded: ${ql_lisp} from: ${ql_url} with rc=${rc}"
  cmd=(
    sbcl
    --load "${ql_lisp}"
  )
  if [[ ! -f "${ql_init}" ]]; then
    log.fatal "init file ${ql_init} is missing."
  fi
  cmd+=(--load "${ql_init}")
  cmd+=(--quit)
  cmd.run 0 "${cmd[@]}"
  rc=$?
  log.debug "sbcl loaded: ${ql_lisp} & ${ql_init} with rc=$?"
  del_paths "${ql_lisp}"
  log.info "Finish <= Setup of ${title} with rc=${rc}"
  return "${rc}"
}

render_template() {
  local \
    output \
    base \
    template \
    context \
    context_format
  local -a \
    cmd
  output="${1?cannot continue without output}"
  base="$(basename "${output}" || echo "${output##*/}")"
  template="${2:-"${base}.j2"}"
  context="${3:-"${base}.context.yaml"}"
  context_format="${context##*.}"
  [[ -f "${template}" ]] || die 1 "Template is missing: ${template}"
  [[ -f "${context}" ]] || die 1 "Template context is missing: ${context}"
  mkdir -p "${output%/*}"
  log.debug "Ensured folder '${output%/*}' exists"
  log.debug "Launching the template engine"
  # render the template tpl_file using context ctx_file as output trg_file:
  cmd=(minijinja-cli)
  cmd+=(-f "${context_format}")
  cmd+=(-a none)
  cmd+=(-o "${output}")
  cmd+=("${template}" "${context}")
  cmd.run 0 "${cmd[@]}"
  rc=$?
  log.info "Generated output: ${output}, from template: ${template} and context: ${context} with rc=${rc}"
  return "${rc}"
}

setup_emacs_cfg_file() {
  local \
    cfg_file \
    trg_base \
    tpl_file \
    ctx_file \
    rc
  cfg_file="${1?cannot continue without cfg_file}" # is generated
  skip_disabled "${FUNCNAME[0]}" || return 0
  skip_existing "${FUNCNAME[0]}" "${cfg_file}" || return 0
  trg_base="$(basename "${cfg_file}")"
  tpl_file="${2:-"${trg_base}.j2"}"           # must exist
  ctx_file="${3:-"${trg_base}.context.yaml"}" # is generated
  # ensure template exists
  render_template "${cfg_file}" "${tpl_file}" "${ctx_file}"
  rc=$?
  return "${rc}"
}

setup_sbclrc_file() {
  local \
    cfg_file \
    trg_base \
    tpl_file \
    ctx_file \
    rc
  cfg_file="${1?cannot continue without cfg_file}" # is generated
  skip_disabled "${FUNCNAME[0]}" || return 0
  skip_existing "${FUNCNAME[0]}" "${cfg_file}" || return 0
  trg_base="$(basename "${cfg_file}")"
  tpl_file="${2:-"${trg_base}.j2"}"           # must exist
  ctx_file="${3:-"${trg_base}.context.yaml"}" # is generated
  # ensure template exists
  render_template "${cfg_file}" "${tpl_file}" "${ctx_file}"
  rc=$?
  return "${rc}"
}

setup_emacs_svc() {
  local \
    unit_file \
    tpl_file \
    ctx_file \
    install_root \
    rc
  unit_file="${1:-".config/systemd/user/emacs-headless.service"}"
  tpl_file="${2:-"${unit_file}.j2"}"
  ctx_file="${3:-"${unit_file##*/}.context.yaml"}"
  install_root="${4:-"${SYSTEMD_INSTALL_ROOT}"}"
  skip_disabled "${FUNCNAME[0]}" || return 0
  skip_existing "${FUNCNAME[0]}" "${install_root}/${unit_file}" || return 0
  render_template "${install_root}/${unit_file}" "${tpl_file}" "${ctx_file}"
  ## enable the service and start it too
  cmd.run 0 systemctl --user daemon-reload
  rc=$?
  log.info "Reloaded systemd for ${unit_file##*/} with rc=${rc}"
  cmd.run 0 systemctl --user enable "${unit_file##*/}"
  rc=$?
  log.info "Enabled systemd unit for ${unit_file##*/} with rc=${rc}"
  cmd.run 0 systemctl --user start "${unit_file##*/}"
  log.info "Started systemd unit for ${unit_file##*/} with rc=${rc}"
  rc=$?
  return "${rc}"
}

ensure_emacs_flavor() {
  local \
    filepath \
    flavor \
    expected_flavor
  filepath="${1?cannot continue without filepath}"
  flavor="${2?cannot continue withoug flavor}"
  expected_flavor="${2?cannot continue withoug expected_flavor}"
  if [[ "${flavor}" != "${expected_flavor}" ]]; then
    die 1 "Configuration conflict: ${filepath} does not match flavor: ${flavor}. Expected: ${expected_flavor}"
  fi
  return 0
}

ensure_configuration() {
  local \
    flavor \
    config_file
  config_file="${1:-"${EMACS_CFG_FILE}"}"
  flavor="${2:-"${EMACS_FLAVOR}"}"

  case "${config_file##/*}" in
  ".spacemacs")
    ensure_emacs_flavor "${config_file}" "${flavor}" "spacemacs"
    ;;
  "*.el")
    # TODO: add support for doom/vanilla later
    if [[ -v DOOMDIR ]]; then
      die 1 "this script does not support EMACS_FLAVOR=doom"
    fi
    die 1 "this script does not support EMACS_FLAVOR=vanilla"
    ;;
  *)
    die 1 "this script does not support this configuration file: ${config_file}"
    ;;
  esac
  return 0
}

setup_desktop_file() {
  local \
    desktop_file \
    tpl_file \
    ctx_file \
    rc
  local -a \
    cmd

  desktop_file="${1?cannot continue without desktop_file}"
  tpl_file="${2:-"${DESKTOP_TPL}"}"
  ctx_file="${3:-"${DESKTOP_CTX}"}"
  skip_disabled "${FUNCNAME[0]}" || return 0
  skip_existing "${FUNCNAME[0]}" "${desktop_file}" || return 0
  render_template "${desktop_file}" "${tpl_file}" "${ctx_file}"
  cmd=(desktop-file-validate --no-hints "${desktop_file}")
  cmd.run 0 "${cmd[@]}"
  rc=$?
  log.debug "Completed: '${cmd[*]}' with rc=${rc}"
  return "${rc}"
}

setup_plasma_hooks() {
  local \
    shortcutsrc \
    kcfg_group \
    kcfg_key \
    kcfg_value \
    qdbus_ns \
    unit \
    rc
  local -a \
    services \
    cmd
  shortcutsrc="${1?cannot continue without shortcutsrc}"
  kcfg_group="${2?cannot continue without kcfg_group}"
  kcfg_key="${3?cannot continue without kcfg_key}"
  kcfg_value="${4?cannot continue without kfcg_value}"
  qdbus_ns="${5?cannot continue without qdbus_ns}"
  shift 5
  services=("${@}")
  skip_disabled "${FUNCNAME[0]}" || return 0
  cmd=(kbuildsycoca6)
  cmd.run 0 "${cmd[@]}"
  rc=$?
  log.debug "Completed: '${cmd[*]}' with rc=${rc}"
  mkdir -p "${shortcutsrc##*/}"
  log.debug "Ensured folder containing ${shortcutsrc} exists"
  cmd=(kwriteconfig6 --file "${shortcutsrc}" --group "${kcfg_group}" --key "${kcfg_key}" "${kcfg_value}")
  cmd.run 0 "${cmd[@]}"
  rc=$?
  log.debug "Completed: '${cmd[*]}' with rc=${rc}"
  cmd=(qdbus-qt6 "${qdbus_ns}" /KWin "${qdbus_ns}.reconfigure")
  cmd.run 0 "${cmd[@]}"
  rc=$?
  log.debug "Completed: '${cmd[*]}' with rc=${rc}"
  if [[ "${#services[@]}" -eq 0 ]]; then
    log.debug "no user systemd services to restart."
    return "${rc}"
  fi
  log.debug "Restarting user systemd services:"
  for unit in "${services[@]}"; do
    cmd=(systemctl --user restart "${unit}")
    cmd.run 0 "${cmd[@]}"
    rc=$?
    log.debug "User systemd unit ${unit} restarted with rc=${rc}"
  done
  return "${rc}"
}

main() {
  local \
    distro_id \
    kcfg_group \
    rc
  local -a \
    params
  distro_id="${1:-"$(run.detect_distro_id)"}"
  # do some logic here
  cmd.run 0 pushd "${PWD}" &>/dev/null || {
    log.fatal "Failed to pushd ${PWD}."
    exit 1
  }
  setup_packages "${distro_id}"
  rc=$?
  params=("${EMACS_CFG_REPO}" "${EMACS_CFG_DIR}")
  setup_emacs_cfg_dir "${params[@]}"
  rc=$?
  params=("${QL_URL}" "${QL_INIT_FILE}")
  setup_quicklisp "${params[@]}"
  rc=$?
  para
  params=("${SBCL_CFG_FILE}" "${SBCL_CFG_TPL}" "${SBCL_CFG_CTX}")
  setup_sbclrc_file "${params[@]}"
  rc=$?
  params=("${EMACS_CFG_FILE}" "${EMACS_CFG_TPL}" "${EMACS_CFG_CTX}")
  setup_emacs_cfg_file "${params[@]}"
  rc=$?
  params=("${EMACS_SVC_FILE}" "${EMACS_SVC_TPL}" "${EMACS_SVC_CTX}" "${SYSTEMD_INSTALL_ROOT}")
  setup_emacs_svc "${params[@]}"
  rc=$?
  params=("${DESKTOP_FILE}" "${DESKTOP_TPL}" "${DESKTOP_CTX}")
  setup_desktop_file "${params[@]}"
  rc=$?
  kcfg_group="${DESKTOP_FILE##/*}"
  kcfg_group="${kcfg_group%.*}"
  log.debug "Calculated kconfig group: '${kcfg_group}'"
  params=("${PLASMA_SHCSRC}" "${kcfg_group}" "${PLASMA_KEY}" "${PLASMA_KEY_VAL}" "${QDBUS_NS}")
  params+=(
    "plasma-kglobalaccel.service"
  )
  setup_plasma_hooks "${params[@]}"
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
