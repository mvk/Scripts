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

SPACEMACS_REPO="${SPACEMACS_REPO:-"https://github.com/syl20bnr/spacemacs"}"
EMACS_CONF_DIR="${EMACS_CONF_DIR:-"${HOME}/.emacs.d"}"
QUICK_LISP_URL="${QUICK_LISP_URL:-"https://beta.quicklisp.org/quicklisp.lisp"}"
EMACS_SVC_FILE="${EMACS_SVC_FILE:-".config/systemd/user/emacs-headless.service"}"
EMACS_SVC_TPL="${EMACS_SVC_TPL:-"${EMACS_SVC_FILE}.j2"}"
EMACS_SVC_CTX="${EMACS_SVC_CTX:-"${EMACS_SVC_FILE##*/}.context.yaml"}"
SYSTEMD_INSTALL_ROOT="${SYSTEMD_INSTALL_ROOT:-"${HOME}"}"

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

EMACS_CFG_FILE="${EMACS_CFG_FILE:-"${HOME}/.spacemacs"}"
EMACS_CFG_TPL="${EMACS_CFG_TPL:-"${PWD}/$(basename "${EMACS_CFG_FILE}").j2"}"
EMACS_CFG_CTX="${EMACS_CFG_CTX:-"${PWD}/$(basename "${EMACS_CFG_FILE}").context.yaml"}"

SETUP_PACKAGES_SKIP="${SETUP_PACKAGES_SKIP:-"0"}"
SETUP_SPACEMACS_SKIP="${SETUP_SPACEMACS_SKIP:-"0"}"
SETUP_QUICKLISP_SKIP="${SETUP_QUICKLISP_SKIP:-"0"}"
UPDATE_DOT_SPACEMACS_SKIP="${UPDATE_DOT_SPACEMACS_SKIP:-"0"}"
SETUP_EMACS_SERVICE_SKIP="${SETUP_EMACS_SERVICE_SKIP:-"0"}"

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
  run_cmd=(dnf "${op}")
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

skip_disabled() {
  local \
    func_name \
    skip_setup
  local -n \
    skip_setup_ref
  func_name="${1:-"${FUNCNAME[1]}"}"
  skip_setup_ref="${func_name^^}_SKIP"
  skip_setup="${skip_setup_ref}"
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

setup_spacemacs() {
  local \
    repo_url \
    target_dir \
    old_var \
    rc
  repo_url="${1:-"${SPACEMACS_REPO}"}"
  target_dir="${2:-"${EMACS_CONF_DIR}"}"
  skip_disabled "${FUNCNAME[0]}" || return 0
  skip_existing "${FUNCNAME[0]}" "${target_dir}"
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
    ql_setup \
    fname \
    sbclrc \
    rc
  local -a \
    files \
    cmd
  sbclrc="${HOME}/.sbclrc"
  skip_disabled "${FUNCNAME[0]}" || return 0
  skip_existing "${FUNCNAME[0]}" "${sbclrc}"
  ql_url="${1:-"${QUICK_LISP_URL}"}"
  ql_lisp="${ql_url##*/}"
  ql_setup="${2:-"${ql_lisp%%.*}-setup.lisp"}"
  log.info "Start  => Setup of ${ql_lisp%%.*}"
  curl -f -O "${ql_url}" && rc=$? || rc=$?
  log.debug "Downloaded: ${ql_lisp} from: ${ql_url} with rc=${rc}"
  files=(
    "${ql_lisp}"
    "${ql_setup}"
  )
  cmd=(sbcl)
  for fname in "${files[@]}"; do
    cmd+=(--load "${fname}")
  done
  cmd+=(--quit)
  cmd.run 0 "${cmd[@]}"
  rc=$?
  log.debug "sbcl ${ql_setup%%.*} initialized + setup completed with rc=$?"
  cmd.run 0 rm "${files[@]}" && rc=$?
  log.debug "Cleaned up file: ${files[*]}"
  log.info "Finish <= Setup of ${ql_lisp%%.*} with ${rc}"
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

update_dot_spacemacs() {
  local \
    trg_file \
    trg_base \
    tpl_file \
    ctx_file \
    rc
  skip_disabled "${FUNCNAME[0]}" || return 0
  trg_file="${1?cannot continue without trg_file}" # is generated
  trg_base="$(basename "${trg_file}")"
  tpl_file="${2:-"${trg_base}.j2"}"           # must exist
  ctx_file="${3:-"${trg_base}.context.yaml"}" # is generated
  # ensure template exists
  render_template "${trg_file}" "${tpl_file}" "${ctx_file}"
  rc=$?
  return "${rc}"
}

setup_emacs_service() {
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

main() {
  local \
    rc \
    distro_id
  local -a \
    packages
  cmd.run 0 pushd "${PWD}" &>/dev/null || {
    log.fatal "Failed to pushd ${PWD}."
    exit 1
  }
  distro_id="$(run.detect_distro_id)"
  # do some logic here
  setup_packages "${distro_id}"
  rc=$?
  setup_spacemacs \
    "${SPACEMACS_REPO}" \
    "${EMACS_CONF_DIR}"
  rc=$?
  setup_quicklisp "${QUICK_LISP_URL}"
  rc=$?
  update_dot_spacemacs \
    "${EMACS_CFG_FILE}" \
    "${EMACS_CFG_TPL}" \
    "${EMACS_CFG_CTX}"
  rc=$?
  setup_emacs_service \
    "${EMACS_SVC_FILE}" \
    "${EMACS_SVC_TPL}" \
    "${EMACS_SVC_CTX}" \
    "${SYSTEMD_INSTALL_ROOT}"
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
