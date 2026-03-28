#!/usr/bin/env bash

# Copyright (c) 2026 Max Kovgan <max@kovgans.online>
#
# Permission is hereby granted, free of charge, to any person obtaining a copy
# of this software and associated documentation files (the "Software"), to deal
# in the Software without restriction, including without limitation the rights
# to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
# copies of the Software, and to permit persons to whom the Software is
# furnished to do so, subject to the following conditions:
#
# The above copyright notice and this permission notice shall be included in
# all copies or substantial portions of the Software.
#
# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
# IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
# FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
# AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
# LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
# OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
# SOFTWARE.

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" &>/dev/null && pwd)
SCRIPT_DEBUG="${SCRIPT_DEBUG:-0}"
if [[ -d "${SCRIPT_DIR}/lib" ]]; then
  for fname in "${SCRIPT_DIR}/lib"/*.bash; do
    if [[ ! -r "${fname}" ]]; then
      echo "WARN: failed to read ${fname}"
      continue
    fi
    # shellcheck source=lib/base.bash
    source "${fname}"
  done
fi

GIT_DEFAULT_BRANCH="${GIT_DEFAULT_BRANCH:-"main"}"
log.info "inside the script"

VIMRC="${VIMRC:-"${HOME}/.vimrc"}"
VIMDIR="${VIMDIR:-"${HOME}/.vim"}"
VIMRC_INITIAL="${VIMRC_INITIAL:-"${PWD}/initial.vimrc"}"
SCHEMA="${SCHEMA:-"git"}"
GIT_SRV="${GIT_SRC:-"github.com"}"
PLUGINS_DIR="${VIMDIR}/pack/plugins/start"
VIM_PLUGINS_TO_INSTALL=(
  # Syntax:
  # <team>/<repository>:<branch|tag|ref>
  # "preservim/syntastic"
  "dense-analysis/ale"
  "preservim/nerdtree"
  "majutsushi/tagbar"
  "chase/vim-ansible-yaml"
  "mitsuhiko/vim-jinja"
  "elzr/vim-json"
  "preservim/vim-markdown"
  "PProvost/vim-ps1"
  "sukima/xmledit"
)

setup_git_url() {
  local \
    repository \
    schema \
    server \
    username \
    separator \
    suffix
  repository="${1?"cannot continue without git repository name in the format TEAM/REPOSITORY"}"
  schema="${2:-"${SCHEMA}"}"
  server="${3:-"${GIT_SRV}"}"
  username="${4}"
  separator="/"
  suffix="/"
  result="${schema}://"
  if [[ "${schema}" = "git" ]]; then
    if [[ -z "${username}" ]]; then
      username="git"
    fi
    separator=":"
    suffix=".git"
  fi
  if [[ -n "${username}" ]]; then
    result+="${username}@"
  fi
  result+="${server}${separator}${repository}${suffix}"
  echo -n "${result}"
  return 0
}

install_pathogen() {
  log.info "stage: Install pathogen"
  mkdir -p "${VIMDIR}"/{bundle,autoload}
  curl -LSso "${VIMDIR}/autoload/pathogen.vim" "https://tpo.pe/pathogen.vim"
}

config_git() {
  local branch="${1:-"${GIT_DEFAULT_BRANCH}"}"
  cmd.run 0 git config set --global init.defaultBranch "${branch}"
}

install_plugins() {
  local \
    schema \
    dest \
    plugin \
    teamrepo \
    remote \
    rc \
    ref
  local -a \
    plugins \
    schema="${1?cannot continue without schema}"
  dest="${2?cannot continue without dest}"
  shift 2
  plugins=("${@}")
  if [[ "${#plugins[@]}" -lt 1 ]]; then
    plugins+=("${VIM_PLUGINS_TO_INSTALL[@]}")
  fi
  log.info "Stage: Install plugins"
  log.debug "PWD='${PWD}'"
  cmd.run 0 pushd "${PWD}" &>/dev/null || {
    log.fatal "Failed to pushd current dir ${PWD}"
    exit 1
  }
  test -d "${dest}" || mkdir -p "${dest}"
  cd "${dest}" || {
    log.fatal "Failed to cd into dir ${dest}"
    exit 1
  }
  log.debug "PWD='${PWD}'"
  config_git "${GIT_DEFAULT_BRANCH}"
  rc=0
  for plugin in "${plugins[@]}"; do
    ref=""
    if [[ "${plugin}" == *:* ]]; then
      ref="${plugin##*:}"
    fi
    teamrepo="${plugin%%:*}"
    plugin_dir="${teamrepo##*/}"
    log.debug "ref: '${ref}', teamrepo: '${teamrepo}', plugin_dir: '${plugin_dir}'"
    if [[ ! -d "${plugin_dir}" ]]; then
      mkdir "${plugin_dir}"
      log.warn "Created missing directory: '${plugin_dir}'"
    fi
    cmd.run 0 pushd "${PWD}" &>/dev/null || {
      log.fatal "Failed to pushd"
      exit 1
    }
    cmd.run 0 cd "${plugin_dir}" &>/dev/null || {
      log.fatal "Failed to chrir to '${plugin_dir}'"
      exit 1
    }
    url="$(setup_git_url "${teamrepo}" "${schema}")"
    log.info "Generated url: '${url}'"
    if ! [[ -d ".git" ]]; then
      git init
      git config set advice.detachedHead false
    fi
    for remote in $(git remote || true); do
      git remote remove "${remote}"
      log.debug "Removed remote: '${remote}'"
    done
    remote="origin"
    cmd.run 0 git remote add "${remote}" "${url}"
    if [[ -z "${ref}" ]]; then
      # Returns the 40-character SHA-1 of the default branch
      ref="$(git ls-remote "${url}" HEAD | awk '{print $1}' || true)"
      log.debug "Auto-detected ref='${ref}'"
    fi
    cmd.run 0 git fetch --depth 1 "${remote}" "${ref}"
    cmd.run 0 git checkout FETCH_HEAD
    log.info "Got: ${teamrepo}, from ${url}"
    cmd.run 0 popd &>/dev/null || {
      log.fatal "Failed to get back from ${PWD}"
      exit 1
    }
  done
  cmd.run 0 popd || {
    log.fatal "Failed to get back from ${PWD}"
    exit 1
  }
  return
}

install_vimrc() {
  local \
    init_vimrc \
    dest_vimrc
  init_vimrc="${1:-"${VIMRC_INITIAL}"}"
  dest_vimrc="${2:-"${VIMRC}"}"
  log.info "Stage: Install ${dest_vimrc}"
  if [[ -r "${dest_vimrc}" ]]; then
    TS="$(date +%s)"
    log.info "existing ${dest_vimrc} found => Backing it up as ${dest_vimrc}.${TS}"
    mv "${dest_vimrc}" "${dest_vimrc}.${TS}"
  fi
  if [[ ! -r "${init_vimrc}" ]]; then
    log.fatal "Initial vimrc file not readable: ${init_vimrc}"
    exit 1
  fi
  cp "${init_vimrc}" "${dest_vimrc}"
}

main() {
  local \
    schema \
    rc
  schema="${1}"
  cmd.run 0 pushd "${PWD}" &>/dev/null || {
    log.fatal "Failed to pushd ${PWD}."
    exit 1
  }
  # install_pathogen
  install_plugins "${schema}" "${PLUGINS_DIR}" "${VIM_PLUGINS_TO_INSTALL[@]}"
  rc=$?
  if [[ "${rc}" -ne 0 ]]; then
    log.error "Failed to install plugins with rc=${rc}"
    exit "${rc}"
  fi
  install_vimrc
  rc=$?
  cmd.run 0 popd &>/dev/null || {
    log.fatal "Failed to get back from '${PWD}'"
    exit 1
  }
  return "${rc}"
}

# bats ./test_setupvim.bats current $0: '/usr/lib/bats/bats-exec-test'

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  # only run main upon real execution.
  main "${@}"
  exit $?
else
  log.warn "This script is expecting to be executed."
fi
