#!/usr/bin/env bash

# Tests win11-desktop-setup.sh against a fake gsettings backend.

set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
WORK_DIR=$(mktemp -d "${TMPDIR:-/tmp}/win11-desktop-test.XXXXXX")
SCRIPT="${REPO_DIR}/win11-desktop-setup.sh"

cleanup() {
  rm -rf "${WORK_DIR}"
}
trap cleanup EXIT

fail() {
  printf 'FAIL: %s\n' "$*" >&2
  exit 1
}

mkdir -p "${WORK_DIR}/bin" "${WORK_DIR}/db"

cat > "${WORK_DIR}/bin/gsettings" <<EOF
#!/usr/bin/env bash
DB="${WORK_DIR}/db"
case \${1:-} in
  list-schemas)
    printf '%s\n' org.cinnamon org.cinnamon.theme org.cinnamon.desktop.interface \\
      org.cinnamon.desktop.wm.preferences org.cinnamon.muffin \\
      org.cinnamon.desktop.keybindings org.nemo.preferences org.nemo.desktop
    ;;
  list-keys)
    printf '%s\n' name gtk-theme icon-theme cursor-theme cursor-size color-scheme \\
      font-name titlebar-font theme button-layout panels-enabled panels-height \\
      edge-tiling alttab-switcher-style overlay-key default-folder-viewer \\
      computer-icon-visible clock-show-date
    ;;
  get)
    key="\$2.\$3"
    if [[ -f \${DB}/\${key} ]]; then cat "\${DB}/\${key}"; else printf "'previous'\n"; fi
    ;;
  set)
    printf '%s\n' "\$4" > "\${DB}/\$2.\$3"
    ;;
  *) exit 1 ;;
esac
EOF
chmod +x "${WORK_DIR}/bin/gsettings"

export PATH="${WORK_DIR}/bin:${PATH}"
export HOME="${WORK_DIR}"
export XDG_DATA_HOME="${HOME}/.local/share"
export XDG_STATE_HOME="${HOME}/.local/state"

bash -n "${SCRIPT}"

# --help works and does not touch settings.
"${SCRIPT}" --help > /dev/null || fail "--help exited non-zero."

# Invalid input is rejected.
if "${SCRIPT}" --theme nosuchcolor -y --no-icons >/dev/null 2>&1; then
  fail "An invalid accent was accepted."
fi
if "${SCRIPT}" --mode sideways -y --no-icons >/dev/null 2>&1; then
  fail "An invalid mode was accepted."
fi
if "${SCRIPT}" --panel left -y --no-icons >/dev/null 2>&1; then
  fail "An invalid panel position was accepted."
fi

# Dry run changes nothing.
"${SCRIPT}" --dry-run --no-icons > /dev/null
if [[ -n $(ls -A "${WORK_DIR}/db") ]]; then
  fail "A dry run wrote settings."
fi
if [[ -d ${WORK_DIR}/.local/state/win11-desktop-setup ]]; then
  fail "A dry run created a restore script."
fi

icon_dry_run=$("${SCRIPT}" --no-companions --mode dark --theme purple --dry-run 2>/dev/null)
if ! grep -Fq "org.cinnamon.desktop.interface icon-theme = 'Win11-purple-dark'" \
    <<< "${icon_dry_run}"; then
  fail "The setup did not select the requested dark icon variant."
fi

# Seed one real selector value so restoration is verified precisely.
printf "'Mint-Y-Aqua'\n" > \
  "${WORK_DIR}/db/org.cinnamon.desktop.interface.icon-theme"

# Pretend the pinned companion packages are already installed. This lets the
# normal path prove all four Cinnamon appearance selectors are used without a
# network dependency in this part of the test.
mkdir -p \
  "${HOME}/.local/share/themes/Win11-Light/gtk-3.0" \
  "${HOME}/.local/share/themes/Win11-Light/cinnamon" \
  "${HOME}/.local/share/themes/Win11-Dark/gtk-3.0" \
  "${HOME}/.local/share/themes/Win11-Dark/cinnamon" \
  "${HOME}/.local/share/icons/Windows-11-cursors/cursors"
: > "${HOME}/.local/share/themes/Win11-Light/gtk-3.0/gtk.css"
: > "${HOME}/.local/share/themes/Win11-Light/cinnamon/cinnamon.css"
: > "${HOME}/.local/share/themes/Win11-Dark/gtk-3.0/gtk.css"
: > "${HOME}/.local/share/themes/Win11-Dark/cinnamon/cinnamon.css"
: > "${HOME}/.local/share/icons/Windows-11-cursors/cursors/default"

# A real run applies the expected Windows 11 settings in all four selectors.
if ! "${SCRIPT}" --panel bottom --panel-height 48 -y \
    > "${WORK_DIR}/setup.log" 2>&1; then
  cat "${WORK_DIR}/setup.log" >&2
  fail "The full desktop setup returned a non-zero status."
fi

assert_value() {
  local key=$1 expected=$2 actual
  actual=$(cat "${WORK_DIR}/db/${key}" 2>/dev/null || true)
  [[ ${actual} == "${expected}" ]] || \
    fail "Expected ${key} to be '${expected}', found '${actual}'."
}

assert_value org.cinnamon.theme.name "'Win11-Light'"
assert_value org.cinnamon.desktop.interface.gtk-theme "'Win11-Light'"
assert_value org.cinnamon.desktop.interface.icon-theme "'Win11-blue'"
assert_value org.cinnamon.desktop.interface.cursor-theme "'Windows-11-cursors'"
assert_value org.cinnamon.desktop.wm.preferences.theme "'Win11-Light'"
assert_value org.cinnamon.desktop.wm.preferences.button-layout "':minimize,maximize,close'"
assert_value org.cinnamon.panels-enabled "['1:0:bottom']"
assert_value org.cinnamon.panels-height "['1:48']"
assert_value org.cinnamon.muffin.edge-tiling "true"
assert_value org.cinnamon.alttab-switcher-style "'icons+thumbnails'"
assert_value org.cinnamon.desktop.keybindings.overlay-key "'Super_L'"
assert_value org.nemo.preferences.default-folder-viewer "'list-view'"
assert_value org.nemo.desktop.computer-icon-visible "true"

# The restore script records the previous values and can undo the run.
restore=$(ls -1 "${WORK_DIR}/.local/state/win11-desktop-setup"/restore-*.sh)
[[ -x ${restore} ]] || fail "No executable restore script was created."
grep -q 'button-layout' "${restore}" || fail "The restore script is missing changed keys."
grep -q 'icon-theme' "${restore}" || fail "The restore script is missing the icon selector."

"${SCRIPT}" --restore > /dev/null
assert_value org.cinnamon.desktop.interface.icon-theme "'Mint-Y-Aqua'"
assert_value org.cinnamon.desktop.wm.preferences.button-layout "'previous'"
assert_value org.cinnamon.panels-enabled "'previous'"

# A custom panel position and height are honoured.
rm -rf "${WORK_DIR}/db" "${WORK_DIR}/.local/state"
mkdir -p "${WORK_DIR}/db"
"${SCRIPT}" --no-icons --panel top --panel-height 40 -y > /dev/null
assert_value org.cinnamon.panels-enabled "['1:0:top']"
assert_value org.cinnamon.panels-height "['1:40']"

# Missing companions are fetched at pinned revisions and installed per-user.
GTK_REPO="${WORK_DIR}/fake-win11-gtk"
CURSOR_REPO="${WORK_DIR}/fake-win11-cursor"
COMPANION_HOME="${WORK_DIR}/companion-home"
mkdir -p "${GTK_REPO}" "${CURSOR_REPO}/Windows-11-cursors/cursors" "${COMPANION_HOME}"
cat > "${GTK_REPO}/install.sh" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
dest=''
while (( $# > 0 )); do
  case $1 in
    -d|--dest) dest=$2; shift 2 ;;
    *) shift ;;
  esac
done
[[ -n ${dest} ]]
for theme in Win11-Light Win11-Dark; do
  mkdir -p "${dest}/${theme}/gtk-3.0" "${dest}/${theme}/cinnamon"
  : > "${dest}/${theme}/gtk-3.0/gtk.css"
  : > "${dest}/${theme}/cinnamon/cinnamon.css"
done
EOF
chmod +x "${GTK_REPO}/install.sh"
printf '[Icon Theme]\nName=Windows 11\n' > \
  "${CURSOR_REPO}/Windows-11-cursors/index.theme"
: > "${CURSOR_REPO}/Windows-11-cursors/cursors/default"

for repository in "${GTK_REPO}" "${CURSOR_REPO}"; do
  git -C "${repository}" init -q
  git -C "${repository}" config user.name test
  git -C "${repository}" config user.email test@example.invalid
  git -C "${repository}" add .
  git -C "${repository}" commit -qm initial
done
GTK_REF=$(git -C "${GTK_REPO}" rev-parse HEAD)
CURSOR_REF=$(git -C "${CURSOR_REPO}" rev-parse HEAD)
rm -rf "${WORK_DIR}/db" && mkdir -p "${WORK_DIR}/db"

HOME="${COMPANION_HOME}" \
XDG_DATA_HOME="${COMPANION_HOME}/.local/share" \
XDG_STATE_HOME="${COMPANION_HOME}/.local/state" \
WIN11_GTK_REPOSITORY="${GTK_REPO}" WIN11_GTK_REF="${GTK_REF}" \
WIN11_CURSOR_REPOSITORY="${CURSOR_REPO}" WIN11_CURSOR_REF="${CURSOR_REF}" \
  "${SCRIPT}" --no-icons -y > /dev/null

[[ -f ${COMPANION_HOME}/.local/share/themes/Win11-Light/gtk-3.0/gtk.css ]] || \
  fail "The light Win11 application theme was not installed."
[[ -f ${COMPANION_HOME}/.local/share/themes/Win11-Dark/cinnamon/cinnamon.css ]] || \
  fail "The dark Win11 desktop theme was not installed."
[[ -f ${COMPANION_HOME}/.local/share/icons/Windows-11-cursors/cursors/default ]] || \
  fail "The Windows 11 cursor theme was not installed."
assert_value org.cinnamon.theme.name "'Win11-Light'"
assert_value org.cinnamon.desktop.interface.gtk-theme "'Win11-Light'"
assert_value org.cinnamon.desktop.interface.cursor-theme "'Windows-11-cursors'"

# Regression: a long schema list must still be detected.
# 'gsettings list-schemas | grep -q' makes gsettings die with SIGPIPE once
# grep exits on the first match; under 'set -o pipefail' that used to be read
# as "Cinnamon is not installed" on systems with many schemas installed.
BIG_DIR=$(mktemp -d "${TMPDIR:-/tmp}/win11-bigschema.XXXXXX")
mkdir -p "${BIG_DIR}/bin" "${BIG_DIR}/db"
cat > "${BIG_DIR}/bin/gsettings" <<EOF
#!/usr/bin/env bash
DB="${BIG_DIR}/db"
case \${1:-} in
  list-schemas)
    for i in \$(seq 1 4000); do printf 'org.example.filler%s\n' "\$i"; done
    printf '%s\n' org.cinnamon org.cinnamon.desktop.interface \\
      org.cinnamon.desktop.wm.preferences org.cinnamon.muffin \\
      org.cinnamon.desktop.keybindings org.nemo.preferences org.nemo.desktop
    for i in \$(seq 4001 8000); do printf 'org.example.filler%s\n' "\$i"; done
    ;;
  list-keys)
    for i in \$(seq 1 500); do printf 'filler-key%s\n' "\$i"; done
    printf '%s\n' gtk-theme color-scheme font-name titlebar-font button-layout \\
      panels-enabled panels-height edge-tiling alttab-switcher-style overlay-key \\
      default-folder-viewer computer-icon-visible clock-show-date
    ;;
  get)
    key="\$2.\$3"
    if [[ -f \${DB}/\${key} ]]; then cat "\${DB}/\${key}"; else printf "'previous'\n"; fi
    ;;
  set)
    printf '%s\n' "\$4" > "\${DB}/\$2.\$3"
    ;;
  *) exit 1 ;;
esac
EOF
chmod +x "${BIG_DIR}/bin/gsettings"

if ! output=$(PATH="${BIG_DIR}/bin:${PATH}" HOME="${BIG_DIR}" \
      XDG_DATA_HOME="${BIG_DIR}/.local/share" \
      XDG_STATE_HOME="${BIG_DIR}/.local/state" \
      "${SCRIPT}" --no-icons --no-companions -y 2>&1); then
  printf '%s\n' "${output}" >&2
  rm -rf "${BIG_DIR}"
  fail "Cinnamon was not detected when many schemas are installed."
fi
[[ -f ${BIG_DIR}/db/org.cinnamon.panels-enabled ]] || {
  rm -rf "${BIG_DIR}"
  fail "No settings were applied with a long schema list."
}
rm -rf "${BIG_DIR}"

# A missing org.cinnamon schema is still reported as an error.
NO_CINN_DIR=$(mktemp -d "${TMPDIR:-/tmp}/win11-nocinn.XXXXXX")
mkdir -p "${NO_CINN_DIR}/bin"
cat > "${NO_CINN_DIR}/bin/gsettings" <<'EOF'
#!/usr/bin/env bash
case ${1:-} in
  list-schemas) printf '%s\n' org.gnome.desktop.interface org.gtk.Settings ;;
  *) exit 1 ;;
esac
EOF
chmod +x "${NO_CINN_DIR}/bin/gsettings"
if PATH="${NO_CINN_DIR}/bin:/usr/bin:/bin" HOME="${NO_CINN_DIR}" \
     "${SCRIPT}" --no-icons -y >/dev/null 2>&1; then
  rm -rf "${NO_CINN_DIR}"
  fail "The script ran even though org.cinnamon is missing."
fi
rm -rf "${NO_CINN_DIR}"

printf 'All desktop setup tests passed.\n'
