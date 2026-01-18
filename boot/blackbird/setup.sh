#!/usr/bin/env bash

# vim: ts=2 sw=2 et

SCRIPT_DEBUG="${SCRIPT_DEBUG:-0}"
KEY_TYPE="${KEY_TYPE:-"rsa"}"
PYTHON_VERSION="${PYTHON_VERSION:-"3.11"}"
std_packages_file="${std_packages_file:-"std.packages.txt"}"
apt_repos_file="${apt_repos_file:-"apt.repos.file"}"

declare -a std_packages

function upd_list_from_file() {
  local \
    line \
    arr_var_name \
    fname
  local -a \
    arr_value
  arr_var_name="${1?FATAL: arr_var_name is empty or unset}"
  fname="${2?FATAL: fname is empty or unset}"

  while read -r line; do
    test "${SCRIPT_DEBUG}" -gt 0 && echo "line: '${line}'"
    arr_value+=("${line}")
  done <"${fname}"
  eval "${arr_var_name}+=(${arr_value[*]})"
}

function setup_ssh_keys() {
  local \
    key_type \
    fname
  key_type="${1:-"rsa"}"
  fname="${2:-"${HOME}/.ssh/id_${key_type}"}"
  if [[ -r "${fname}" ]]; then
    echo "ssh key ${fname} already exists"
    return 0
  fi
  ssh-keygen -t "${key_type}" -f "${fname}"
}


function setup_passwordless_root_login() {
  local \
    count \
    key_path \
    target_path
  key_path="${1:-"${HOME}/.ssh/id_rsa.pub"}"
  target_path="${2:-"/root/.ssh/authorized_keys"}"
  if ! sudo test -r "${target_path}"; then
    sudo mkdir -p "${target_path%/*}"
    sudo chmod 0700 "${target_path%/*}"
    sudo touch "${target_path}"
    sudo chmod 0600 "${target_path}"
  fi
  count="$(sudo grep -wc "$(cat "${key_path}")" "${target_path}" || true)"
  test "${SCRIPT_DEBUG}" -gt 0 && echo "count: ${count}"
  if [[ "${count}" -gt 0 ]]; then
    echo "the key is already in ${target_path}"
    return 0
  fi
  # shellcheck disable=SC2024,SC2002
  cat "${key_path}" | sudo tee -a "${target_path}"

  echo "Testing ssh connection to localhost"
  ssh root@localhost whoami
}

function setup_ansible() {
  local \
    reqs \
    py_version
  reqs="${1:-"ansible.reqs.txt"}"
  py_version="${2:-"${PYTHON_VERSION}"}"
  "python${py_version}" -m venv .venv
  # shellcheck disable=SC1091
  source .venv/bin/activate
  pip3 install -r "${reqs}"

}

function run_ansible() {
  local \
    playbook \
    options
  playbook="${1:-"playbooks/setup.yml"}"
  options="${2:-"-vv"}"
  ansible-playbook -i ./inventory "${playbook}" "${options}"
}

function main() {
  upd_list_from_file "std_packages" "${std_packages_file}"

  sudo apt update
  sudo apt install -y "${std_packages[@]}"
  setup_ssh_keys "${KEY_TYPE}" "${HOME}/.ssh/id_${KEY_TYPE}"
  setup_passwordless_root_login "${HOME}/.ssh/id_rsa.pub" "/root/.ssh/authorized_keys"

  setup_ansible "ansible.reqs.txt"
  run_ansible
  return $?
}


if [[ "${BASH_SOURCE[0]}" = "${0}" ]]; then
  main "${@}"
  exit $?
fi
