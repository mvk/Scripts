#!/usr/bin/env bash
#

PKG="${PKG:-"claude-desktop"}"
DISTRO="${DISTRO:-"$(lsb_release -i -s || true)"}"
DISTRO="${DISTRO,,}"
set -o errexit pipefail
pushd "${PWD}" >/dev/null || {
  echo "FATAL: failed to 'pushd ${PWD}'" >&2
  exit 1
}
git clone git@github.com:dewzor/claude-desktop-fedora.git
cd "${PKG}-${DISTRO}" || {
  echo "FATAL: failed to 'cd ${PKG}-${DISTRO}'" >&2
  exit 1
}
./build-official.sh && sudo dnf install ./build/official/"${PKG}"-*.rpm
popd >/dev/null || {
  echo "FATAL: failed to 'popd'" >&2
  exit 1
}
