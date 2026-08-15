#!/usr/bin/env bash

# win11-desktop-setup.sh
# Give Linux Mint (Cinnamon) a Windows 11-like look:
#   * installs and applies coordinated Desktop, Applications, Icons and
#     Mouse Pointer themes
#   * configures panel, window buttons, fonts, effects, Nemo and desktop
#     settings so applications and the desktop feel like Windows 11
#
# Everything is a per-user setting. Run it WITHOUT sudo.
# Every change is written to a restore script first, so the previous
# desktop can be brought back with --restore.

set -euo pipefail

SRC_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
STATE_DIR="${XDG_STATE_HOME:-${HOME}/.local/state}/win11-desktop-setup"
DATA_DIR="${XDG_DATA_HOME:-${HOME}/.local/share}"

# Companion projects are fetched at immutable revisions. Environment overrides
# exist for downstream packaging and for the offline test suite.
WIN11_GTK_REPOSITORY=${WIN11_GTK_REPOSITORY:-https://github.com/yeyushengfan258/Win11-gtk-theme.git}
WIN11_GTK_REF=${WIN11_GTK_REF:-49e30de3503a49c4c873552b117f8e725393b527}
WIN11_CURSOR_REPOSITORY=${WIN11_CURSOR_REPOSITORY:-https://github.com/0free/windows-11-icons.git}
WIN11_CURSOR_REF=${WIN11_CURSOR_REF:-408e6233586d9e79cca252cfc034caf14bf546b8}
# Selawik is Microsoft's open (OFL) metrics-compatible Segoe UI replacement.
# The winstrap repository ships the compiled TTF files.
WIN11_FONT_REPOSITORY=${WIN11_FONT_REPOSITORY:-https://github.com/winjs/winstrap.git}
WIN11_FONT_REF=${WIN11_FONT_REF:-342cf99031344f48917e14a5c3a728ec5ede8d8f}

accent=blue
mode=auto
panel_position=bottom
panel_height=48
gtk_theme=""
cursor_theme=""
font_name=""
skip_icons=false
skip_font=false
skip_wallpaper=false
skip_taskbar=false
wallpaper_file=""
install_companions=true
dry_run=false
restore_file=""
do_restore=false
assume_yes=false

RESTORE_SCRIPT=""
COMPANION_WORK_DIR=""
CHANGES=0

cleanup() {
  if [[ -n ${COMPANION_WORK_DIR} && -d ${COMPANION_WORK_DIR} ]]; then
    rm -rf -- "${COMPANION_WORK_DIR}"
  fi
}
trap cleanup EXIT

usage() {
  cat <<EOF
Usage: $0 [OPTION]...

Apply a Windows 11-style desktop configuration to Linux Mint Cinnamon.

Options:
  -t, --theme ACCENT      Win11 icon accent to install and apply
                          (default, black, blue, green, nord, purple, red)
                          Default: ${accent}
  -m, --mode MODE         Light/dark mode: auto, light, dark (default: ${mode})
      --panel POSITION    Panel position: bottom, top (default: ${panel_position})
      --panel-height PX   Panel height in pixels (default: ${panel_height})
      --gtk-theme NAME    Override the GTK/Cinnamon theme
      --cursor-theme NAME Override the cursor theme
      --font NAME         Override the interface font (e.g. "Ubuntu 10")
      --wallpaper FILE    Use a custom wallpaper instead of the bundled one
      --no-icons          Do not install or change the icon theme
      --no-font           Do not download the Selawik (Segoe UI-style) font
      --no-wallpaper      Do not change the desktop background
      --no-center-taskbar Do not center the menu and window list on the panel
      --no-companions     Do not download Win11 themes, cursors or fonts
  -n, --dry-run           Print what would change, change nothing
  -y, --yes               Do not ask for confirmation
      --restore [FILE]    Undo a previous run (default: the most recent one)
  -h, --help              Show this help

Examples:
  $0                       # blue accent, follows the current light/dark mode
  $0 --theme purple -m dark
  $0 --panel bottom --panel-height 52 -y
  $0 --wallpaper ~/Pictures/my-background.jpg
  $0 --no-wallpaper --no-font
  $0 --restore
EOF
}

error() {
  printf 'ERROR: %s\n' "$*" >&2
  exit 1
}

warn() {
  printf 'WARNING: %s\n' "$*" >&2
}

info() {
  printf '%s\n' "$*"
}

need_gsettings() {
  command -v gsettings >/dev/null 2>&1 || \
    error "gsettings was not found. Run this script inside a Cinnamon session."
}

SCHEMA_LIST=""

# Lists every installed schema once and caches the result.
#
# Note: no pipe into 'grep -q' here. With 'set -o pipefail' a 'grep -q' that
# exits on the first match makes gsettings die with SIGPIPE (141), which is
# then reported as a failure of the whole pipeline -- so an installed schema
# such as org.cinnamon looked missing on systems with many schemas.
load_schemas() {
  [[ -n ${SCHEMA_LIST} ]] && return 0
  SCHEMA_LIST=$(gsettings list-schemas 2>/dev/null || true)
  [[ -n ${SCHEMA_LIST} ]]
}

# list_contains LINE TEXT
list_contains() {
  local needle=$1 line
  while IFS= read -r line; do
    [[ ${line} == "${needle}" ]] && return 0
  done <<< "$2"
  return 1
}

schema_exists() {
  load_schemas || return 1
  list_contains "$1" "${SCHEMA_LIST}"
}

key_exists() {
  local keys
  keys=$(gsettings list-keys "$1" 2>/dev/null || true)
  [[ -n ${keys} ]] || return 1
  list_contains "$2" "${keys}"
}

# Last-resort check for a running/installed Cinnamon, used only when the
# schema list could not be read at all.
cinnamon_present() {
  gsettings get org.cinnamon panels-enabled >/dev/null 2>&1 && return 0
  [[ ${XDG_CURRENT_DESKTOP:-} == *[Cc]innamon* || ${DESKTOP_SESSION:-} == *cinnamon* ]] \
    && return 0
  command -v cinnamon >/dev/null 2>&1
}

theme_installed() {
  local kind=$1 name=$2 dir
  for dir in "${DATA_DIR}/${kind}" "${HOME}/.${kind}" \
             /usr/share/"${kind}" /usr/local/share/"${kind}"; do
    [[ -d ${dir}/${name} ]] && return 0
  done
  return 1
}

first_available_theme() {
  local kind=$1 name
  shift
  for name in "$@"; do
    if theme_installed "${kind}" "${name}"; then
      printf '%s' "${name}"
      return 0
    fi
  done
  return 1
}

ensure_companion_work_dir() {
  if [[ -z ${COMPANION_WORK_DIR} ]]; then
    COMPANION_WORK_DIR=$(mktemp -d "${TMPDIR:-/tmp}/win11-desktop-setup.XXXXXX") || \
      error "Could not create a temporary directory for companion themes."
  fi
}

# Fetch a reviewed, immutable repository snapshot. Pinning these downloads keeps
# a normal setup reproducible instead of executing whatever happens to be at a
# project's branch tip that day.
fetch_companion_repo() {
  local label=$1 repository=$2 ref=$3 destination=$4 actual

  command -v git >/dev/null 2>&1 || \
    error "git is required to download the ${label}. Install git, or use --no-companions."

  rm -rf -- "${destination}"
  mkdir -p "${destination}"
  git -C "${destination}" init -q
  if ! git -C "${destination}" fetch -q --depth 1 "${repository}" "${ref}"; then
    error "Could not download the ${label} from ${repository}.
Check the internet connection, then retry; or use --no-companions to keep installed themes."
  fi
  git -C "${destination}" checkout -q --detach FETCH_HEAD

  actual=$(git -C "${destination}" rev-parse HEAD)
  [[ ${actual} == "${ref}" ]] || \
    error "The downloaded ${label} revision was ${actual}, expected ${ref}."
}

gtk_companions_installed() {
  [[ -f ${DATA_DIR}/themes/Win11-Light/gtk-3.0/gtk.css && \
     -f ${DATA_DIR}/themes/Win11-Light/cinnamon/cinnamon.css && \
     -f ${DATA_DIR}/themes/Win11-Dark/gtk-3.0/gtk.css && \
     -f ${DATA_DIR}/themes/Win11-Dark/cinnamon/cinnamon.css ]]
}

cursor_companion_installed() {
  [[ -f ${DATA_DIR}/icons/Windows-11-cursors/cursors/default || \
     -f ${DATA_DIR}/icons/Windows-11-cursors/cursors/left_ptr ]]
}

font_companion_installed() {
  [[ -f ${DATA_DIR}/fonts/selawik/selawk.ttf ]]
}

# A Segoe UI-compatible font is already usable when Segoe UI itself or an
# installed Selawik is visible to fontconfig.
segoe_like_font_available() {
  local fonts
  fonts=$(fc-list 2>/dev/null || true)
  grep -qiE "segoe ui|selawik" <<< "${fonts}"
}

install_gtk_companions() {
  local checkout
  ensure_companion_work_dir
  checkout="${COMPANION_WORK_DIR}/gtk"

  info "Downloading the Windows 11 application and desktop themes..."
  fetch_companion_repo "Win11 GTK theme" \
    "${WIN11_GTK_REPOSITORY}" "${WIN11_GTK_REF}" "${checkout}"
  [[ -f ${checkout}/install.sh ]] || \
    error "The Win11 GTK theme download does not contain install.sh."

  mkdir -p "${DATA_DIR}/themes"
  # No tweak compilation is needed: the upstream project ships ready-made CSS.
  # Install both variants so a later light/dark switch does not need a download.
  if ! bash "${checkout}/install.sh" \
      --dest "${DATA_DIR}/themes" --color light dark --size standard; then
    error "The Win11 application and desktop themes could not be installed."
  fi
  gtk_companions_installed || \
    error "The Win11 GTK installer completed but Win11-Light/Win11-Dark are incomplete."
}

install_cursor_companion() {
  local checkout source target temporary
  ensure_companion_work_dir
  checkout="${COMPANION_WORK_DIR}/cursor"
  source="${checkout}/Windows-11-cursors"
  target="${DATA_DIR}/icons/Windows-11-cursors"
  temporary="${DATA_DIR}/icons/.Windows-11-cursors.tmp.$$"

  info "Downloading the Windows 11 mouse-pointer theme..."
  fetch_companion_repo "Windows 11 cursor theme" \
    "${WIN11_CURSOR_REPOSITORY}" "${WIN11_CURSOR_REF}" "${checkout}"
  [[ -f ${source}/index.theme && -d ${source}/cursors ]] || \
    error "The Windows 11 cursor download is incomplete."

  mkdir -p "${DATA_DIR}/icons"
  rm -rf -- "${temporary}"
  cp -a "${source}" "${temporary}"
  rm -rf -- "${target}"
  mv "${temporary}" "${target}"
  cursor_companion_installed || \
    error "The Windows 11 cursor theme could not be installed."
}

install_font_companion() {
  local checkout source target file installed=0
  ensure_companion_work_dir
  checkout="${COMPANION_WORK_DIR}/font"
  source="${checkout}/src/fonts"
  target="${DATA_DIR}/fonts/selawik"

  info "Downloading the Selawik font (Segoe UI-style interface font)..."
  fetch_companion_repo "Selawik font" \
    "${WIN11_FONT_REPOSITORY}" "${WIN11_FONT_REF}" "${checkout}"
  [[ -f ${source}/selawk.ttf ]] || \
    error "The Selawik font download does not contain selawk.ttf."

  mkdir -p "${target}"
  for file in "${source}"/selawk*.ttf; do
    [[ -f ${file} ]] || continue
    cp -f "${file}" "${target}/"
    installed=$((installed + 1))
  done
  (( installed > 0 )) || error "No Selawik font files could be installed."

  if command -v fc-cache >/dev/null 2>&1; then
    fc-cache -f "${target}" >/dev/null 2>&1 || true
  fi
  info "  installed ${installed} Selawik font file(s) to ${target}"
}

# Ensure Cinnamon has real Windows 11 choices for Applications, Desktop and
# Mouse Pointer. Icons are supplied by this repository in install_icons().
install_companion_themes() {
  local target_gtk
  [[ ${mode} == dark ]] && target_gtk=Win11-Dark || target_gtk=Win11-Light

  if [[ ${dry_run} == true ]]; then
    [[ -n ${gtk_theme} ]] || gtk_theme=${target_gtk}
    [[ -n ${cursor_theme} ]] || cursor_theme=Windows-11-cursors
    info "  would ensure Win11-Light, Win11-Dark and Windows-11-cursors are installed"
    if [[ ${skip_font} == false && -z ${font_name} ]] && ! segoe_like_font_available; then
      info "  would install the Selawik font to ${DATA_DIR}/fonts/selawik"
    fi
    return 0
  fi

  if [[ -z ${gtk_theme} ]]; then
    gtk_companions_installed || install_gtk_companions
    gtk_theme=${target_gtk}
  fi

  if [[ -z ${cursor_theme} ]]; then
    cursor_companion_installed || install_cursor_companion
    cursor_theme=Windows-11-cursors
  fi

  # A Segoe UI-style font is only fetched when nothing suitable is installed
  # and the user has not chosen a font explicitly.
  if [[ ${skip_font} == false && -z ${font_name} ]]; then
    if ! segoe_like_font_available && ! font_companion_installed; then
      install_font_companion
    fi
  fi
}

start_restore_script() {
  [[ ${dry_run} == true ]] && return 0
  mkdir -p "${STATE_DIR}"
  RESTORE_SCRIPT="${STATE_DIR}/restore-$(date +%Y%m%d-%H%M%S).sh"
  {
    printf '#!/usr/bin/env bash\n'
    printf '# Restores the Cinnamon settings changed by win11-desktop-setup.sh\n'
    printf '# Created: %s\n' "$(date)"
    printf 'set -uo pipefail\n\n'
  } > "${RESTORE_SCRIPT}"
  chmod +x "${RESTORE_SCRIPT}"
}

# gset SCHEMA KEY VALUE
gset() {
  local schema=$1 key=$2 value=$3 current

  if ! schema_exists "${schema}"; then
    return 0
  fi
  if ! key_exists "${schema}" "${key}"; then
    return 0
  fi

  current=$(gsettings get "${schema}" "${key}" 2>/dev/null || true)
  if [[ ${current} == "${value}" ]]; then
    return 0
  fi

  if [[ ${dry_run} == true ]]; then
    printf '  would set %s %s = %s (now %s)\n' "${schema}" "${key}" "${value}" "${current}"
    CHANGES=$((CHANGES + 1))
    return 0
  fi

  printf 'gsettings set %q %q %q\n' "${schema}" "${key}" "${current}" >> "${RESTORE_SCRIPT}"
  if gsettings set "${schema}" "${key}" "${value}" 2>/dev/null; then
    printf '  %s %s -> %s\n' "${schema}" "${key}" "${value}"
    CHANGES=$((CHANGES + 1))
  else
    warn "Could not set ${schema} ${key}."
  fi
}

detect_mode() {
  local gtk_current='' scheme=''
  gtk_current=$(gsettings get org.cinnamon.desktop.interface gtk-theme 2>/dev/null || true)
  scheme=$(gsettings get org.cinnamon.desktop.interface color-scheme 2>/dev/null || true)
  if [[ ${gtk_current,,} == *dark* || ${scheme,,} == *prefer-dark* ]]; then
    printf 'dark'
  else
    printf 'light'
  fi
}

confirm() {
  local reply
  [[ ${assume_yes} == true || ${dry_run} == true ]] && return 0
  printf 'Apply the Windows 11-style desktop configuration now? [y/N] '
  read -r reply || reply=""
  [[ ${reply,,} == y || ${reply,,} == yes ]]
}

run_restore() {
  local file=${1:-}

  if [[ -z ${file} ]]; then
    file=$(ls -1 "${STATE_DIR}"/restore-*.sh 2>/dev/null | tail -n 1 || true)
    [[ -n ${file} ]] || error "No saved configuration found in ${STATE_DIR}."
  fi
  [[ -f ${file} ]] || error "Restore file '${file}' does not exist."

  info "Restoring settings from ${file}"
  bash "${file}"
  info "Done. Restart Cinnamon with Ctrl+Alt+Esc if the panel looks stale."
}

install_icons() {
  local args=(--dest "${DATA_DIR}/icons" --theme "${accent}") icon_name=Win11

  [[ ${accent} == default ]] || icon_name+="-${accent}"
  [[ ${mode} == dark ]] && icon_name+="-dark"

  if [[ ${dry_run} == true ]]; then
    info "  would run: ./install.sh ${args[*]}"
  else
    info "Installing the Win11 icon theme (accent: ${accent})..."
    ( cd "${SRC_DIR}" && ./install.sh "${args[@]}" )
  fi

  # Apply through gset rather than install.sh --apply so --restore also puts
  # back the user's previous icon selection.
  gset org.cinnamon.desktop.interface icon-theme "'${icon_name}'"
}

apply_appearance() {
  local wm_theme

  info "Appearance"

  if [[ -z ${gtk_theme} ]]; then
    if [[ ${mode} == dark ]]; then
      gtk_theme=$(first_available_theme themes \
        "Win11-Dark" "Fluent-round-Dark" "Fluent-Dark" "Windows-11-dark" \
        "Mint-Y-Dark-Aqua" "Mint-Y-Dark-Blue" "Mint-Y-Dark" "Adwaita-dark" || true)
    else
      gtk_theme=$(first_available_theme themes \
        "Win11-Light" "Win11" "Fluent-round-Light" "Fluent-Light" "Windows-11" \
        "Mint-Y-Aqua" "Mint-Y-Blue" "Mint-Y" "Adwaita" || true)
    fi
  fi

  if [[ -n ${gtk_theme} ]]; then
    gset org.cinnamon.desktop.interface gtk-theme "'${gtk_theme}'"
    gset org.cinnamon.theme name "'${gtk_theme}'"
    wm_theme=${gtk_theme}
    gset org.cinnamon.desktop.wm.preferences theme "'${wm_theme}'"
  else
    warn "No suitable GTK theme found; keeping the current one."
  fi

  if [[ ${mode} == dark ]]; then
    gset org.cinnamon.desktop.interface color-scheme "'prefer-dark'"
    gset org.x.apps.portal color-scheme "'prefer-dark'"
  else
    gset org.cinnamon.desktop.interface color-scheme "'default'"
    gset org.x.apps.portal color-scheme "'default'"
  fi

  if [[ -z ${cursor_theme} ]]; then
    cursor_theme=$(first_available_theme icons \
      "Windows-11-cursors" "Bibata-Modern-Classic" "Adwaita" "DMZ-White" || true)
  fi
  if [[ -n ${cursor_theme} ]]; then
    gset org.cinnamon.desktop.interface cursor-theme "'${cursor_theme}'"
    gset org.cinnamon.desktop.interface cursor-size 24
  fi

  if [[ -z ${font_name} ]]; then
    local fonts
    fonts=$(fc-list 2>/dev/null || true)
    if grep -qi "segoe ui" <<< "${fonts}"; then
      font_name="Segoe UI 10"
    elif grep -qi "selawik" <<< "${fonts}" || font_companion_installed; then
      font_name="Selawik 10"
    else
      font_name="Ubuntu 10"
    fi
  fi
  gset org.cinnamon.desktop.interface font-name "'${font_name}'"
  gset org.cinnamon.desktop.wm.preferences titlebar-font "'${font_name%% [0-9]*} Semi-Bold ${font_name##* }'"
  gset org.gnome.desktop.interface font-name "'${font_name}'"
}

apply_window_management() {
  info "Windows and titlebars"

  # Windows 11 keeps the buttons on the right, minimize first.
  gset org.cinnamon.desktop.wm.preferences button-layout "':minimize,maximize,close'"
  gset org.cinnamon.desktop.wm.preferences focus-mode "'click'"
  gset org.cinnamon.desktop.wm.preferences action-double-click-titlebar "'toggle-maximize'"
  gset org.cinnamon.desktop.wm.preferences action-middle-click-titlebar "'lower'"
  gset org.cinnamon.desktop.wm.preferences resize-with-right-button true
  gset org.cinnamon.desktop.wm.preferences num-workspaces 4

  # Snap Layouts-like tiling behaviour.
  gset org.cinnamon.muffin edge-tiling true
  gset org.cinnamon.muffin tile-hud-threshold 25
  gset org.cinnamon.muffin snap-modifier "'Super'"
  gset org.cinnamon.muffin center-new-windows true
  gset org.cinnamon.muffin attach-modal-dialogs true
  gset org.cinnamon.muffin workspace-cycle false

  # Alt+Tab with window thumbnails, like the Windows 11 task switcher.
  gset org.cinnamon alttab-switcher-style "'icons+thumbnails'"
  gset org.cinnamon alttab-switcher-enforce-primary-monitor true
  gset org.cinnamon alttab-switcher-show-all-workspaces false

  # Subtle, fast animations.
  gset org.cinnamon desktop-effects true
  gset org.cinnamon desktop-effects-workspace "'traditional'"
  gset org.cinnamon startup-animation false
  gset org.cinnamon.desktop.interface gtk-overlay-scrollbars true
}

apply_panel() {
  local monitor=0 zone_sizes symbolic_sizes text_sizes

  info "Panel and taskbar"

  # One panel, centred taskbar buttons are configured by the applet itself,
  # so here we set position, height and icon sizes.
  gset org.cinnamon panels-enabled "['1:${monitor}:${panel_position}']"
  gset org.cinnamon panels-height "['1:${panel_height}']"
  gset org.cinnamon panels-autohide "['1:false']"
  gset org.cinnamon panels-hide-delay "['1:0']"
  gset org.cinnamon panels-show-delay "['1:0']"
  gset org.cinnamon panel-edit-mode false

  zone_sizes="[{\"panelId\": 1, \"left\": 24, \"center\": 24, \"right\": 20}]"
  symbolic_sizes="[{\"panelId\": 1, \"left\": 20, \"center\": 20, \"right\": 20}]"
  text_sizes="[{\"panelId\": 1, \"left\": 0, \"center\": 0, \"right\": 0}]"
  gset org.cinnamon panel-zone-icon-sizes "${zone_sizes}"
  gset org.cinnamon panel-zone-symbolic-icon-sizes "${symbolic_sizes}"
  gset org.cinnamon panel-zone-text-sizes "${text_sizes}"

  # Clock in the Windows 11 style: short date next to the time.
  gset org.cinnamon.desktop.interface clock-show-date true
  gset org.cinnamon.desktop.interface clock-show-seconds false
  gset org.cinnamon.desktop.interface clock-use-24h true

  # Super opens the menu, like the Windows key.
  gset org.cinnamon.desktop.keybindings overlay-key "'Super_L'"
  gset org.cinnamon.desktop.keybindings.wm show-desktop "['<Super>d']"
  gset org.cinnamon.desktop.keybindings.media-keys www "['<Super>b']"
  gset org.cinnamon.desktop.keybindings looking-glass-keybinding "@as []"

  # No hot corner: Windows 11 has none.
  gset org.cinnamon hotcorner-layout \
    "['expo:false:0', 'scale:false:0', 'scale:false:0', 'desktop:false:0']"
}

# Center the menu and the grouped window list on the panel -- the single most
# recognisable Windows 11 taskbar trait. Existing center/right applets are
# kept; only left-zone instances of the menu and the window list move.
apply_centered_taskbar() {
  local current updated

  [[ ${skip_taskbar} == false ]] || return 0
  schema_exists org.cinnamon || return 0
  key_exists org.cinnamon enabled-applets || return 0

  info "Taskbar layout"

  current=$(gsettings get org.cinnamon enabled-applets 2>/dev/null || true)
  # Only proceed on a list value; anything else means the key is unavailable.
  [[ ${current} == \[* ]] || return 0

  if ! command -v python3 >/dev/null 2>&1; then
    warn "python3 is not available; the taskbar was not centered."
    return 0
  fi

  # 'panelN:left:POS:APPLET@ID:INSTANCE' -> same entry in the center zone.
  local status=0
  updated=$(python3 - "$current" 2>/dev/null <<'PYEOF'
import ast, sys
try:
    applets = ast.literal_eval(sys.argv[1])
    assert isinstance(applets, list)
except Exception:
    sys.exit(1)
moved = ("menu@cinnamon.org", "grouped-window-list@cinnamon.org",
         "window-list@cinnamon.org")
out = []
changed = False
for entry in applets:
    parts = str(entry).split(":")
    if len(parts) >= 4 and parts[1] == "left" and parts[3] in moved:
        parts[1] = "center"
        changed = True
    out.append(":".join(parts))
if not changed:
    sys.exit(2)
print("[" + ", ".join("'" + e + "'" for e in out) + "]")
PYEOF
) || status=$?
  case ${status} in
    0) ;;
    2) info "  the menu and window list are already centered"; return 0 ;;
    *) warn "Could not parse the applet layout; leaving the taskbar as it is."
       return 0 ;;
  esac

  [[ -n ${updated} ]] || return 0
  gset org.cinnamon enabled-applets "${updated}"
}

# Windows 11-style "Bloom" wallpaper matching the light/dark mode.
apply_wallpaper() {
  local source target file_uri

  [[ ${skip_wallpaper} == false ]] || return 0
  schema_exists org.cinnamon.desktop.background || return 0

  info "Wallpaper"

  if [[ -n ${wallpaper_file} ]]; then
    source=${wallpaper_file}
  elif [[ ${mode} == dark ]]; then
    source="${SRC_DIR}/wallpapers/win11-bloom-dark.jpg"
  else
    source="${SRC_DIR}/wallpapers/win11-bloom-light.jpg"
  fi

  if [[ ! -f ${source} ]]; then
    warn "Wallpaper '${source}' was not found; keeping the current background."
    return 0
  fi

  # Copy into the user's backgrounds directory so the setting survives even
  # if this repository checkout is deleted later.
  if [[ ${source} == "${SRC_DIR}"/wallpapers/* ]]; then
    target="${DATA_DIR}/backgrounds/win11/$(basename "${source}")"
    if [[ ${dry_run} == true ]]; then
      info "  would copy $(basename "${source}") to ${target}"
    else
      mkdir -p "$(dirname "${target}")"
      cp -f "${source}" "${target}"
    fi
  else
    target=${source}
  fi

  file_uri="file://${target}"
  gset org.cinnamon.desktop.background picture-uri "'${file_uri}'"
  gset org.cinnamon.desktop.background picture-options "'zoom'"
}

apply_files_and_desktop() {
  info "Files and desktop"

  # File Explorer-like Nemo defaults.
  gset org.nemo.preferences default-folder-viewer "'list-view'"
  gset org.nemo.preferences show-hidden-files false
  gset org.nemo.preferences click-policy "'double'"
  gset org.nemo.preferences show-full-path-titles false
  gset org.nemo.preferences show-location-entry false
  gset org.nemo.preferences date-format "'informal'"
  gset org.nemo.preferences quick-renames-with-pause-in-between true
  gset org.nemo.preferences.menu-config selection-menu-open-as-root false
  gset org.nemo.window-state start-with-sidebar true
  gset org.nemo.window-state side-pane-view "'places'"
  gset org.nemo.window-state sidebar-width 200
  gset org.nemo.icon-view default-zoom-level "'standard'"
  gset org.nemo.list-view default-zoom-level "'smaller'"

  # A Windows-like desktop: Home, Computer and Trash only.
  gset org.nemo.desktop computer-icon-visible true
  gset org.nemo.desktop home-icon-visible true
  gset org.nemo.desktop trash-icon-visible true
  gset org.nemo.desktop network-icon-visible false
  gset org.nemo.desktop volumes-visible false
  gset org.nemo.desktop desktop-layout "'true::false'"
  gset org.nemo.desktop use-desktop-grid true

  # Sounds and notifications closer to Windows defaults.
  gset org.cinnamon.desktop.sound event-sounds false
  gset org.cinnamon.desktop.notifications bottom-notifications true
  gset org.cinnamon.desktop.notifications display-notifications true
}

print_theme_summary() {
  local desktop applications icons pointer
  desktop=$(gsettings get org.cinnamon.theme name 2>/dev/null || printf 'unknown')
  applications=$(gsettings get org.cinnamon.desktop.interface gtk-theme 2>/dev/null || printf 'unknown')
  icons=$(gsettings get org.cinnamon.desktop.interface icon-theme 2>/dev/null || printf 'unknown')
  pointer=$(gsettings get org.cinnamon.desktop.interface cursor-theme 2>/dev/null || printf 'unknown')

  cat <<EOF

Windows 11 appearance in Cinnamon Themes:
  Desktop:       ${desktop}
  Applications:  ${applications}
  Icons:         ${icons}
  Mouse Pointer: ${pointer}
EOF
}

print_manual_steps() {
  cat <<EOF

Applied. A few finishing touches still need the GUI (Cinnamon stores
applet options per instance, so a script cannot set them safely):

1. Start menu
   Right-click the menu button -> Configure:
   - hide the menu label ("Menu" text)
   - use a Windows-style icon if you prefer
   - enable "Use a categories-less layout" for a Win11 feel.

2. Window list
   Right-click "Grouped window list" -> Configure -> set
   "Show labels" to off, pinned apps as you like. That gives the
   icon-only, centred Windows 11 taskbar.

If the panel or wallpaper looks stale, restart Cinnamon with
Ctrl+Alt+Esc (or log out and back in).

Restore the previous desktop settings from this run:
  $0 --restore
EOF
}

while (( $# > 0 )); do
  case $1 in
    -t|--theme)
      [[ -n ${2:-} ]] || error "--theme requires a value."
      accent=$2
      shift 2
      ;;
    -m|--mode)
      [[ ${2:-} =~ ^(auto|light|dark)$ ]] || error "--mode must be auto, light or dark."
      mode=$2
      shift 2
      ;;
    --panel)
      [[ ${2:-} =~ ^(top|bottom)$ ]] || error "--panel must be top or bottom."
      panel_position=$2
      shift 2
      ;;
    --panel-height)
      [[ ${2:-} =~ ^[0-9]+$ ]] || error "--panel-height requires a number."
      panel_height=$2
      shift 2
      ;;
    --gtk-theme)
      [[ -n ${2:-} ]] || error "--gtk-theme requires a value."
      gtk_theme=$2
      shift 2
      ;;
    --cursor-theme)
      [[ -n ${2:-} ]] || error "--cursor-theme requires a value."
      cursor_theme=$2
      shift 2
      ;;
    --font)
      [[ -n ${2:-} ]] || error "--font requires a value."
      font_name=$2
      shift 2
      ;;
    --wallpaper)
      [[ -n ${2:-} ]] || error "--wallpaper requires a file path."
      wallpaper_file=$2
      shift 2
      ;;
    --no-icons)
      skip_icons=true
      shift
      ;;
    --no-font)
      skip_font=true
      shift
      ;;
    --no-wallpaper)
      skip_wallpaper=true
      shift
      ;;
    --no-center-taskbar)
      skip_taskbar=true
      shift
      ;;
    --no-companions)
      install_companions=false
      shift
      ;;
    -n|--dry-run)
      dry_run=true
      shift
      ;;
    -y|--yes)
      assume_yes=true
      shift
      ;;
    --restore)
      do_restore=true
      if [[ -n ${2:-} && ${2} != -* ]]; then
        restore_file=$2
        shift
      fi
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      error "Unrecognized option '$1'. Try '$0 --help'."
      ;;
  esac
done

need_gsettings

if [[ ${do_restore} == true ]]; then
  run_restore "${restore_file}"
  exit 0
fi

[[ ${EUID} -ne 0 ]] || error "Run this script as your normal user, without sudo."

if ! load_schemas; then
  # gsettings gave us nothing at all (no dbus session, sandbox, ...).
  if cinnamon_present; then
    warn "Could not read the list of gsettings schemas; continuing anyway."
  else
    error "Cinnamon settings were not found. This script targets Linux Mint Cinnamon.
Cinnamon is either not installed or this is not a Cinnamon session
(XDG_CURRENT_DESKTOP='${XDG_CURRENT_DESKTOP:-unset}')."
  fi
elif ! schema_exists org.cinnamon; then
  error "Cinnamon settings were not found. This script targets Linux Mint Cinnamon.
'gsettings list-schemas' works but does not list org.cinnamon, so the
Cinnamon schemas are not installed. On Linux Mint:
  sudo apt install --reinstall cinnamon-common"
fi

[[ ${accent} =~ ^(default|black|blue|green|nord|purple|red)$ ]] || \
  error "Unknown accent '${accent}'. Use default, black, blue, green, nord, purple or red."

if [[ ${mode} == auto ]]; then
  mode=$(detect_mode)
fi

info "Win11 desktop setup for Linux Mint Cinnamon"
info "  accent: ${accent}   mode: ${mode}   panel: ${panel_position} (${panel_height}px)"
[[ ${dry_run} == true ]] && info "  dry run: nothing will be changed"
info ""

if ! confirm; then
  info "Cancelled."
  exit 0
fi

start_restore_script

if [[ ${install_companions} == true ]]; then
  install_companion_themes
fi

if [[ ${skip_icons} == false ]]; then
  install_icons
fi

apply_appearance
apply_window_management
apply_panel
apply_centered_taskbar
apply_wallpaper
apply_files_and_desktop

info ""
if [[ ${dry_run} == true ]]; then
  info "${CHANGES} setting(s) would change."
  exit 0
fi

info "${CHANGES} setting(s) changed. Previous values saved to:"
info "  ${RESTORE_SCRIPT}"
print_theme_summary
print_manual_steps
