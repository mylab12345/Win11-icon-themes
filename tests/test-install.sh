#!/usr/bin/env bash

set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
WORK_DIR=$(mktemp -d "${TMPDIR:-/tmp}/win11-icon-test.XXXXXX")
DEST_DIR="${WORK_DIR}/icons"
XSI_DIR="${WORK_DIR}/hicolor/scalable/actions"
THEME_NAME="Win11-Test"
STANDARD="${DEST_DIR}/${THEME_NAME}-blue"
DARK="${STANDARD}-dark"

cleanup() {
  rm -rf "${WORK_DIR}"
}
trap cleanup EXIT

fail() {
  printf 'FAIL: %s\n' "$*" >&2
  exit 1
}

assert_exists() {
  [[ -e $1 ]] || fail "Expected '$1' to exist."
}

cd "${REPO_DIR}"
bash -n install.sh
mkdir -p "${XSI_DIR}" "${WORK_DIR}/bin"
: > "${XSI_DIR}/xsi-network-wireless-signal-excellent-symbolic.svg"
: > "${XSI_DIR}/xsi-drive-removable-media-symbolic.svg"
: > "${XSI_DIR}/xsi-no-win11-match-symbolic.svg"

cat > "${WORK_DIR}/bin/gsettings" <<'EOF'
#!/usr/bin/env bash
case ${1:-} in
  list-schemas) printf '%s\n' org.cinnamon.desktop.interface org.gnome.desktop.interface ;;
  get) printf "'Mint-Y-Dark-Aqua'\n" ;;
  set) printf '%s\n' "$*" > "${GSETTINGS_LOG}" ;;
  *) exit 1 ;;
esac
EOF
chmod +x "${WORK_DIR}/bin/gsettings"

if ! PATH="${WORK_DIR}/bin:${PATH}" \
  GSETTINGS_LOG="${WORK_DIR}/gsettings.log" \
  XDG_CURRENT_DESKTOP=Cinnamon \
  XSI_ICON_ROOT="${WORK_DIR}/hicolor" ./install.sh \
  --dest "${DEST_DIR}" \
  --name "${THEME_NAME}" \
  --theme blue \
  --apply auto >"${WORK_DIR}/install.log" 2>&1; then
  cat "${WORK_DIR}/install.log" >&2
  fail 'Installer returned a non-zero status.'
fi

assert_exists "${STANDARD}/index.theme"
assert_exists "${DARK}/index.theme"
[[ ! -e ${DEST_DIR}/${THEME_NAME} ]] || fail 'Default accent was installed unexpectedly.'
grep -Fxq "Name=${THEME_NAME}-blue" "${STANDARD}/index.theme" || fail 'Standard theme name is incorrect.'
grep -Fxq "Name=${THEME_NAME}-blue-dark" "${DARK}/index.theme" || fail 'Dark theme name is incorrect.'
grep -Fq 'Windows 11 Fluent-style' "${STANDARD}/index.theme" || fail 'Theme description was not updated.'
grep -Fxq "set org.cinnamon.desktop.interface icon-theme ${THEME_NAME}-blue-dark" \
  "${WORK_DIR}/gsettings.log" || fail 'Cinnamon dark theme was not applied automatically.'

cmp -s colors/color-blue/folder.svg "${STANDARD}/places/scalable/folder.svg" || fail 'Blue accent was not installed.'
cmp -s colors/color-green/folder.svg "${STANDARD}/places/scalable/green-folder.svg" || fail 'Green folder palette is missing.'
assert_exists "${STANDARD}/places/scalable/folder_color_blue_downloads.svg"
assert_exists "${STANDARD}/places/scalable/folder_color_grey_pictures.svg"
[[ $(readlink "${STANDARD}/preferences/22") == 32 ]] || fail 'Preferences link is not portable.'

for alias in \
  hypnotix.svg org.x.Warpinator.svg bulky.svg mintbackup.svg mintreport.svg \
  mintsysadm.svg mintwelcome.svg webapp-manager.svg sticky.svg \
  com.github.maoschanz.drawing.svg celluloid.svg fingwit.svg; do
  assert_exists "${STANDARD}/apps/scalable/${alias}"
done

assert_exists "${STANDARD}/status/symbolic/xsi-network-wireless-signal-excellent-symbolic.svg"
assert_exists "${DARK}/status/symbolic/xsi-network-wireless-signal-excellent-symbolic.svg"
[[ ! -e ${STANDARD}/actions/symbolic/xsi-no-win11-match-symbolic.svg ]] || \
  fail 'An XSI alias was generated without a matching Win11 icon.'

broken_links=$(find "${DEST_DIR}" -xtype l -print)
[[ -z ${broken_links} ]] || {
  printf '%s\n' "${broken_links}" >&2
  fail 'Installed themes contain broken symbolic links.'
}

if ./install.sh --dest "${DEST_DIR}" --theme azure >"${WORK_DIR}/invalid.log" 2>&1; then
  fail 'An invalid theme variant was accepted.'
fi
if ./install.sh --dest "${DEST_DIR}" --name '../unsafe' >"${WORK_DIR}/unsafe.log" 2>&1; then
  fail 'An unsafe theme name was accepted.'
fi

./install.sh --dest "${DEST_DIR}" --name "${THEME_NAME}" --uninstall --theme blue \
  >"${WORK_DIR}/remove.log" 2>&1
[[ ! -e ${STANDARD} && ! -e ${DARK} ]] || fail 'Selected accent was not uninstalled.'

printf 'PASS: installer, folder palettes, Mint aliases and XSI compatibility\n'
