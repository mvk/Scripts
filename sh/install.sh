#!/bin/bash

URL="${URL:-"https://dl.google.com/dl/cloudsdk/channels/rapid/install_google_cloud_sdk.bash"}"

SCRATCH_PATTERN="${SCRATCH_PATTERN:-"installer.tmp"}"

function gen_scratch() {
  local \
    scratch_pattern \
    scratch
  scratch_pattern="${1:-"${SCRATCH_PATTERN}"}"
  scratch="$(mktemp -d -t "${scratch_pattern}.XXXXXXXXXX" || exit 1)"
  echo "${scratch}"
}

function download {
  local \
    url \
    scratch \
    output

  url="${1?url is mandatory 1st parameter for download()}"
  scratch="${2?scratch is mandatory 2nd parameter for download()}"
  output="${3:-"${scratch}/${url##*/}"}"
  echo "INFO - Downloading file: $url"
  curl -# "$url" >"${output}" || exit
}

function run_installer {
  local \
    installer
  installer="${1?installer is the 1st parameter for run_installer()}"
  shift 1
  chmod 775 "${installer}"

  echo "Running installer: ${installer}"
  "${installer}" "$@"
}

SCRATCH="$(gen_scratch "${SCRATCH_PATTERN}")"
OUTPUT="${SCRATCH}/${URL##*/}"
download "${URL}" "${SCRATCH}" "${OUTPUT}"
run_installer "${OUTPUT}" "${@}"
