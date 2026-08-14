#!/usr/bin/env bash

# win11-desktop-setup.sh
# Give Linux Mint (Cinnamon) a Windows 11-like look:
#   * installs and applies the Win11 icon theme from this repository
#   * configures panel, window buttons, fonts, effects, Nemo and desktop
#     settings so applications and the desktop feel like Windows 11
#
# Everything is a per-user setting. Run it WITHOUT sudo.
# Every change is written to a restore script first, so the previous
# desktop can be brought back with --restore.

set -euo pipefail

SRC_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
STATE_DIR="${XDG_STATE_HOME:-${HOME}/.local/state}/win11-desktop-setup"

accent=blue
mode=auto
panel_position=bottom
panel_height=48
gtk_theme=""
cursor_theme=""
font_name=""
skip_icons=false
dry_run=false
restore_file=""
do_restore=false
assume_yes=false

RESTORE_SCRIPT=""
CHANGES=0

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
      --no-icons          Do not run install.sh, only change desktop settings
  -n, --dry-run           Print what would change, change nothing
  -y, --yes               Do not ask for confirmation
      --restore [FILE]    Undo a previous run (default: the most recent one)
  -h, --help              Show this help

Examples:
  $0                       # blue accent, follows the current light/dark mode
  $0 --theme purple -m dark
  $0 --panel bottom --panel-height 52 -y
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

schema_exists() {
  gsettings list-schemas 2>/dev/null | grep -Fxq "$1"
}

key_exists() {
  gsettings list-keys "$1" 2>/dev/null | grep -Fxq "$2"
}

theme_installed() {
  local kind=$1 name=$2 dir
  for dir in "${HOME}/.local/share/${kind}" "${HOME}/.${kind}" \
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
  local args=(--theme "${accent}" --apply)

  case ${mode} in
    dark) args+=(dark) ;;
    light) args+=(standard) ;;
    *) args+=(auto) ;;
  esac

  if [[ ${dry_run} == true ]]; then
    info "  would run: ./install.sh ${args[*]}"
    return 0
  fi

  info "Installing the Win11 icon theme (accent: ${accent})..."
  ( cd "${SRC_DIR}" && ./install.sh "${args[@]}" )
}

apply_appearance() {
  local wm_theme

  info "Appearance"

  if [[ -z ${gtk_theme} ]]; then
    if [[ ${mode} == dark ]]; then
      gtk_theme=$(first_available_theme themes \
        "Fluent-round-Dark" "Fluent-Dark" "Windows-11-dark" \
        "Mint-Y-Dark-Aqua" "Mint-Y-Dark-Blue" "Mint-Y-Dark" "Adwaita-dark" || true)
    else
      gtk_theme=$(first_available_theme themes \
        "Fluent-round-Light" "Fluent-Light" "Windows-11" \
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
    if fc-list 2>/dev/null | grep -qi "segoe ui"; then
      font_name="Segoe UI 10"
    elif fc-list 2>/dev/null | grep -qi "selawik"; then
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

print_manual_steps() {
  cat <<EOF

Applied. A few finishing touches still need the GUI (Cinnamon stores
applet options per instance, so a script cannot set them safely):

1. Centred taskbar (the most Windows 11 detail)
   Right-click the panel -> Panel -> Panel edit mode.
   Drag "Menu" and "Grouped window list" into the CENTER zone,
   keep the systray, clock and notifications on the right.
   Turn Panel edit mode off again.

2. Start menu
   Right-click the menu button -> Configure:
   - hide the menu label ("Menu" text)
   - use a Windows-style icon if you prefer
   - enable "Use a categories-less layout" for a Win11 feel.

3. Window list
   Right-click "Grouped window list" -> Configure -> set
   "Show labels" to off, pinned apps as you like. That gives the
   icon-only, centred Windows 11 taskbar.

4. Optional extras (install, then re-run this script):
   sudo apt install fonts-open-sans
   Fluent GTK theme:  https://github.com/vinceliuice/Fluent-gtk-theme
   Windows 11 cursors: https://github.com/yeyushengfan258/Win11-cursors
   After installing, run:  $0 --gtk-theme Fluent-round-Dark -m dark

Undo everything from this run:
  $0 --restore
EOF
}

need_gsettings

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
    --no-icons)
      skip_icons=true
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

if [[ ${do_restore} == true ]]; then
  run_restore "${restore_file}"
  exit 0
fi

[[ ${EUID} -ne 0 ]] || error "Run this script as your normal user, without sudo."

if ! schema_exists org.cinnamon; then
  error "Cinnamon settings were not found. This script targets Linux Mint Cinnamon."
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

if [[ ${skip_icons} == false ]]; then
  install_icons
fi

apply_appearance
apply_window_management
apply_panel
apply_files_and_desktop

info ""
if [[ ${dry_run} == true ]]; then
  info "${CHANGES} setting(s) would change."
  exit 0
fi

info "${CHANGES} setting(s) changed. Previous values saved to:"
info "  ${RESTORE_SCRIPT}"
print_manual_steps
