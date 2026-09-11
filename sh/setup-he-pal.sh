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
declare -a PACKAGES
declare -a CURR_CMD

PACKAGES=(
  culmus-fonts-all
  google-noto-sans-phoenician-fonts
)

XKB_SYMBOLS_TARGET="${XKB_SYMBOLS_TARGET:-"${HOME}/.config/xkb/symbols"}"

CURR_UID="$(id -u || true)"
if [[ "${CURR_UID}" -eq 0 ]]; then
  XKB_SYMBOLS_TARGET="/usr/share/xkeyboard-config-2/symbols"
fi

LAYOUTS_CURRENT="${LAYOUTS_CURRENT:-"$(kreadconfig6 --file kxkbrc --group Layout --key LayoutList || true)"}"
VARIANTS_CURRENT="${VARIANTS_CURRENT:-"$(kreadconfig6 --file kxkbrc --group Layout --key VariantList || true)"}"

log.debug "LAYOUTS_CURRENT: '${LAYOUTS_CURRENT}'"
log.debug "VARIANTS_CURRENT: '${VARIANTS_CURRENT}'"

CURR_CMD=()
[[ "${CURR_UID}" -ne 0 ]] && CURR_CMD+=(sudo)
CURR_CMD+=(dnf install -y)
CURR_CMD+=("${PACKAGES[@]}")

log.debug "CURR_CMD: '${CURR_CMD[*]}'"
"${CURR_CMD[@]}"

SRC="${SRC:-"he-pal"}"
DEST="${XKB_SYMBOLS_TARGET}"

CURR_CMD=()
CURR_CMD+=(cp "xkb/symbols/${SRC}" "${DEST}/")

echo "CURR_CMD: '${CURR_CMD[*]}'"
"${CURR_CMD[@]}"
LAYOUT_NEW="${LAYOUT_NEW:-"he-pal"}"
VARIANT_NEW="${VARIANT_NEW:-""}"

if [[ ! ",${LAYOUTS_CURRENT}," =~ ^.*$LAYOUT_NEW.*$ ]]; then
  declare -A ITEMS
  ITEMS['LayoutList']="${LAYOUTS_CURRENT},${LAYOUT_NEW}"
  ITEMS['VariantList']="${VARIANTS_CURRENT},${VARIANT_NEW}"
  for key in "${!ITEMS[@]}"; do
    CURR_CMD=()
    CURR_CMD+=(
      kwriteconfig6
      --file kxkbrc
      --group Layout
      --key "${key}" "${ITEMS[${key}]}"
      --notify
    )
    log.debug "CURR_CMD: '${CURR_CMD[*]}'"
    "${CURR_CMD[@]}"
    RC=$?
    log.info "Updated ${key} with: ${ITEMS[${key}]} and RC=${RC}"
  done
else
  log.warn "Found the layout ${LAYOUT_NEW} is already in ${LAYOUTS_CURRENT}"
fi
# 5. Force KWin to reload the hardware inputs immediately
CURR_CMD=()
CURR_CMD=(
  qdbus-qt6
  org.kde.KWin
  /KWin org.kde.KWin.reconfigure
)
log.debug "CURR_CMD: '${CURR_CMD[*]}'"
"${CURR_CMD[@]}"
RC=$?
log.debug "Refreshed kwin returned RC=${RC}"

SRC="fontconfig/fonts.conf"
DST="${HOME}/.config"

mkdir -p "${DST}/${SRC%/*}"
cp "${SRC}" "${DST}/${SRC}"

fc-cache -vf
RC=$?

exit "${RC}"
