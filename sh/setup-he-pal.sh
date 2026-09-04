#!/usr/bin/env bash

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

echo "LAYOUTS_CURRENT: '${LAYOUTS_CURRENT}'"
echo "VARIANTS_CURRENT: '${VARIANTS_CURRENT}'"

CURR_CMD=()
[[ "${CURR_UID}" -ne 0 ]] && CURR_CMD+=(sudo)
CURR_CMD+=(dnf install -y)
CURR_CMD+=("${PACKAGES[@]}")

echo "CURR_CMD: '${CURR_CMD[*]}'"
"${CURR_CMD[@]}"

SRC="${SRC:-"he-pal"}"
DEST="${XKB_SYMBOLS_TARGET}"

CURR_CMD=()
[[ "${CURR_UID}" -ne 0 ]] && CURR_CMD+=(sudo)
CURR_CMD+=(cp "xkb/symbols/${SRC}" "${DEST}/")

echo "CURR_CMD: '${CURR_CMD[*]}'"
"${CURR_CMD[@]}"
LAYOUT_NEW="${LAYOUT_NEW:-"he-pal"}"
VARIANT_NEW="${VARIANT_NEW:-""}"

if [[ "${LAYOUTS_CURRENT}" =~ *$LAYOUT_NEW* ]]; then
  echo "Found the layout ${LAYOUT_NEW} is already in ${LAYOUTS_CURRENT}"
  exit 0
fi
# 4. Write the updated strings back to your KDE configuration with notify flags
CURR_CMD=()
CURR_CMD+=(
  kwriteconfig6
  --file kxkbrc
  --group Layout
  --key LayoutList "${LAYOUTS_CURRENT},${LAYOUT_NEW}"
  --notify
)
echo "CURR_CMD: '${CURR_CMD[*]}'"
"${CURR_CMD[@]}"

CURR_CMD=()
CURR_CMD+=(
  kwriteconfig6
  --file kxkbrc
  --group Layout
  --key VariantList "${VARIANTS_CURRENT},${VARIANT_NEW}"
  --notify
)
echo "CURR_CMD: '${CURR_CMD[*]}'"
"${CURR_CMD[@]}"
# 5. Force KWin to reload the hardware inputs immediately

CURR_CMD=()
CURR_CMD=(
  qdbus-qt6
  org.kde.KWin
  /KWin org.kde.KWin.reconfigure
)
echo "CURR_CMD: '${CURR_CMD[*]}'"
"${CURR_CMD[@]}"
