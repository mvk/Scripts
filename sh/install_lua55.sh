#!/usr/bin/env bash

set -o pipefail

LUA_RELEASE="${LUA_RELEASE:-"5.5.0"}"
LUA_DL_ROOT="${LUA_DL_ROOT:-"https://www.lua.org/ftp"}"
LUA_PACKAGE="${LUA_PACKAGE:-"lua-${LUA_RELEASE}.tar.gz"}"
LUA_PREFIX="${LUA_PREFIX:-"${HOME}/.local"}"
#PKG_CONFIG_PATH="${PKG_CONFIG_PATH:-"${LUA_PREFIX}/lib/pkgconfig"}"
SHELL_CONFIG_FILE="${SHELL_CONFIG_FILE:-"${HOME}/.bashrc.d/75-hypr-env.bash"}"

ensure_apps() {
  local -a \
    apps
  local app
  apps=("${@}")

  for app in "${apps[@]}"; do
    if ! command -v "${app}"; then
      echo "FATAL: mandatory app: ${app} is not installed. please install it."
      exit 1
    fi
  done
}

download() {
  local \
    url \
    release \
    checksum \
    actual_checksum \
    folder \
    rc
  url="${1?cannot continue without url}"
  folder="${2:-"${PWD}"}"
  release="${url##*/}"
  echo "DEBUG - detected release: ${release}"
  index="${url%/*}/"
  echo "DEBUG - detected index: ${index}"
  cd "${folder}" || exit $?
  echo "About to fetch: ${index} for release ${release}"
  checksum="$(curl -f -R "${index}" | xq -q "table tr:has(td:first-child:contains('${release}')) td:nth-child(4)")"
  echo "INFO: found release checksum ${checksum}"
  rc=0
  if [[ -r "${release}" ]]; then
    echo "the resulting file ${release} exists"
    actual_checksum=$(sha256sum "${release}" | cut -d' ' -f1)
    if [[ "${checksum}" = "${actual_checksum}" ]]; then
      echo "INFO Skip download. [REASON: existing file ${release} matches the checksum]"
      return "${rc}"
    fi
    echo "WARN - Downloading. [REASON: existing file ${release} has checksum mismatch]"
    echo -e "> expected: ${checksum}"
    echo -e "<   actual: ${actual_checksum}"
  fi
  curl -f -R -O "${url}" && rc=$? || rc=$?
  echo "Download the url ${url} with rc=${rc}"
  return "${rc}"
}

unpack() {
  local \
    file \
    folder \
    root
  file="${1?cannot continue without file}"
  folder="${2:-"${PWD}"}"
  cd "${folder}" || exit $?
  root="$(tar -tf "${file}" | sed -e 's@/.*@@' | uniq)"
  tar -zxf "${file}"
  echo "${root}"

}

build_install() {
  local \
    install_prefix \
    build_target \
    install_target
  install_prefix="${1?cannot continue without install_prefix}"
  build_target="${2:-"posix"}"
  install_target="${3:-"install"}"
  make "${build_target}"
  make "${install_target}" INSTALL_TOP="${install_prefix}"

}

gen_pkg_config() {
  local \
    prefix \
    release \
    name \
    pkg_config_path \
    release_maj_min
  prefix="${1?cannot continue without prefix}"
  release="${2?cannot continue without release}"
  name="${3?cannot continue without name}"
  pkg_config_path="${4:-"${prefix}/lib/pkgconfig"}"
  mkdir -p "${pkg_config_path}"

  {
    echo -e "prefix=${prefix}"
    echo -e "exec_prefix=\${prefix}"
    echo -e "libdir=\${exec_prefix}/lib"
    echo -e "includedir=\${prefix}/include"
    echo -e "Name: ${name^}"
    echo -e "Description: ${name^} language engine (for Hyprland)"
    echo -e "Version: ${release}"
    echo -e "Requires:"
    echo -e "Libs: -L\${libdir} -llua -lm -ldl"
    echo -e "Cflags: -I\${includedir}"
  } >"${pkg_config_path}/${name}.pc"
  echo "INFO: created ${pkg_config_path}/${name}.pc"
  cd "${pkg_config_path}" || {
    echo "FATAL: failed to chdir to ${pkg_config_path}"
    exit 1
  }
  release_maj_min="${release%.*}"
  ln -sf "${name}.pc" "${name}${release_maj_min//./}.pc"
  ln -sf "${name}.pc" "${name}-${release_maj_min}.pc"
  echo "created symlinks"
  return 0
}

update_env_file() {
  local \
    filename \
    variable \
    value \
    current_value \
    item
  local -a \
    current_values
  filename="${1?cannot continue without filename}"
  variable="${2?cannot continue without variable}"
  value="${3?cannot continue without value}"

  # 1. Get current_value and split it by ":" into an array
  # Looks for lines like: export VAR="val" or VAR=val
  current_value="${!variable}"

  IFS=':' read -r -a current_values <<<"$current_value"

  # 2. Check if current_values already contains the new value
  for item in "${current_values[@]}"; do
    if [[ "$item" == "$value" ]]; then
      return 0
    fi
  done

  # 3. If variable exists, add the export line directly AFTER it
  if grep -q -E "^(export )?${variable}=" "$filename"; then
    # Works natively on Linux. For macOS/BSD sed, use: sed -i '' "/.../a..."
    sed -i "/^\(export \)\?${variable}=/a export ${variable}=\"${value}:\\\$${variable}\"" "$filename"
  else
    echo -e "\nexport ${variable}=\"${value}:\$${variable}\"" >>"${filename}"
  fi
}

main() {
  local \
    shell_config
  local -a \
    shell_config_files \
    required_apps

  required_apps=(
    curl
    sha256sum
    xq
  )

  ensure_apps "${required_apps[@]}"

  pushd "${PWD}" >/dev/null || {
    echo "FATAL: failed to push ${PWD} onto shell stack"
    exit 1
  }

  download "${LUA_DL_ROOT}/${LUA_PACKAGE}"
  RESULT_DIR="$(unpack "${LUA_PACKAGE}")"
  cd "${RESULT_DIR}" || {
    echo "FATAL: failed to chdir to ${RESULT_DIR}"
    exit 1
  }

  build_install "${LUA_PREFIX}"

  popd || {
    echo "FATAL: failed to pop folder from the shell stack"
    exit 1
  }

  gen_pkg_config "${LUA_PREFIX}" "${LUA_RELEASE}" "lua"

  shell_config_files=(
    "${SHELL_CONFIG_FILE}"
    "${HOME}/.bashrc"
  )
  for shell_config in "${shell_config_files[@]}"; do
    [[ -f "${shell_config}" ]] || continue
    update_env_file "${shell_config}" "PKG_CONFIG_PATH" "${LUA_PREFIX}/lib/pkgconfig"
  done

}

main "${@}"
exit 0
