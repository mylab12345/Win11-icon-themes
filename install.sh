#!/usr/bin/env bash

set -euo pipefail

ROOT_UID=0
SRC_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
THEME_NAME="Win11"
COLOR_VARIANTS=('' '-dark')
THEME_VARIANTS=('' '-black' '-blue' '-green' '-nord' '-purple' '-red')

if [[ ${EUID} -eq ${ROOT_UID} ]]; then
  DEST_DIR="/usr/share/icons"
else
  DEST_DIR="${XDG_DATA_HOME:-${HOME}/.local/share}/icons"
fi

dest="${DEST_DIR}"
name="${THEME_NAME}"
themes=()
remove=false
alternative=false
apply=false
apply_mode=auto
themes_explicit=false
cache_warning_shown=false

usage() {
  cat <<EOF
Usage: $0 [OPTION]...

Install the Win11 icon theme. Both standard and dark icon variants are
installed so the desktop can use the correct panel icons in either mode.

Options:
  -d, --dest DIR          Destination directory (default: ${DEST_DIR})
  -n, --name NAME         Installed theme name (default: ${THEME_NAME})
  -t, --theme VARIANT     Folder accent(s):
                          default, black, blue, green, nord, purple, red, all
                          Multiple values are accepted (default: default/yellow)
  -a, --alternative       Use the alternative macOS-inspired app/device icons
      --apply [MODE]      Apply the first installed accent to the current desktop
                          MODE: auto, standard, dark (default: auto)
  -r, --remove,
  -u, --uninstall         Remove selected accents, or all accents if none selected
  -h, --help              Show this help

Linux Mint 22.3 recommendation:
  $0 --theme blue --apply
EOF
}

error() {
  printf 'ERROR: %s\n' "$*" >&2
  exit 1
}

warn() {
  printf 'WARNING: %s\n' "$*" >&2
}

require_value() {
  local option=$1
  local value=${2:-}
  [[ -n ${value} && ${value} != -* ]] || error "${option} requires a value."
}

variant_suffix() {
  case $1 in
    default) printf '%s' '' ;;
    black|blue|green|nord|purple|red) printf -- '-%s' "$1" ;;
    *) return 1 ;;
  esac
}

add_theme() {
  local suffix=$1
  local current

  for current in "${themes[@]}"; do
    [[ ${current} == "${suffix}" ]] && return
  done
  themes+=("${suffix}")
}

parse_theme() {
  local value=$1
  local suffix

  if [[ ${value} == all ]]; then
    for suffix in "${THEME_VARIANTS[@]}"; do
      add_theme "${suffix}"
    done
  elif suffix=$(variant_suffix "${value}"); then
    add_theme "${suffix}"
  else
    error "Unrecognized theme variant '${value}'. Try '$0 --help'."
  fi
}

is_budgie() {
  local desktop="${XDG_CURRENT_DESKTOP:-}:${DESKTOP_SESSION:-}"
  [[ ${desktop,,} == *budgie* ]]
}

configure_index() {
  local theme_dir=$1
  local installed_name=$2

  sed -i \
    -e "s/^Name=.*/Name=${installed_name}/" \
    -e 's/^Comment=.*/Comment=Windows 11 Fluent-style icon theme for Linux desktops./' \
    "${theme_dir}/index.theme"
}

# Add complete folder palettes. Besides making folder-color extensions useful,
# this resolves the historical green-folder.svg-style links in the source tree.
install_folder_palettes() {
  local theme_dir=$1
  local places_dir="${theme_dir}/places/scalable"
  local manifest_dir="${SRC_DIR}/colors/color-blue"
  local palette source_dir icon base renamed
  local alias source_prefix suffix
  local -a palettes=(
    "yellow:${SRC_DIR}/src/places/scalable"
    "black:${SRC_DIR}/colors/color-black"
    "blue:${SRC_DIR}/colors/color-blue"
    "green:${SRC_DIR}/colors/color-green"
    "nord:${SRC_DIR}/colors/color-nord"
    "purple:${SRC_DIR}/colors/color-purple"
    "red:${SRC_DIR}/colors/color-red"
  )

  [[ -d ${places_dir} ]] || return

  for palette in "${palettes[@]}"; do
    source_dir=${palette#*:}
    palette=${palette%%:*}

    for icon in "${manifest_dir}"/*.svg; do
      base=${icon##*/}
      case ${base} in
        folder.svg) renamed="${palette}-folder.svg" ;;
        folder-*) renamed="${palette}-${base}" ;;
        user-*) renamed="${palette}-${base}" ;;
        *) continue ;;
      esac
      cp -f "${source_dir}/${base}" "${places_dir}/${renamed}"
    done
  done

  # Legacy folder-color names use grey, orange and pink. Map them to the
  # closest bundled Win11 palettes while retaining every real palette too.
  for alias in yellow black blue green nord purple red grey orange pink; do
    case ${alias} in
      grey) source_prefix=black ;;
      orange) source_prefix=yellow ;;
      pink) source_prefix=purple ;;
      *) source_prefix=${alias} ;;
    esac

    for icon in "${manifest_dir}"/*.svg; do
      base=${icon##*/}
      case ${base} in
        folder.svg)
          renamed="${alias}-folder.svg"
          suffix=folder
          ;;
        folder-*)
          renamed="${alias}-${base}"
          suffix=${base#folder-}
          suffix=${suffix%.svg}
          ;;
        user-desktop.svg)
          renamed="${alias}-user-desktop.svg"
          suffix=desktop
          ;;
        *) continue ;;
      esac

      if [[ ${alias} != ${source_prefix} ]]; then
        case ${base} in
          folder.svg) ln -sfn "${source_prefix}-folder.svg" "${places_dir}/${renamed}" ;;
          folder-*) ln -sfn "${source_prefix}-${base}" "${places_dir}/${renamed}" ;;
          user-*) ln -sfn "${source_prefix}-${base}" "${places_dir}/${renamed}" ;;
        esac
      fi

      ln -sfn "${renamed}" "${places_dir}/folder_color_${alias}_${suffix}.svg"
    done

    # Common Nemo folder-color extension names use plural display labels.
    ln -sfn "${alias}-folder-download.svg" "${places_dir}/folder_color_${alias}_downloads.svg"
    ln -sfn "${alias}-folder-images.svg" "${places_dir}/folder_color_${alias}_pictures.svg"
    ln -sfn "${alias}-folder.svg" "${places_dir}/folder_color_${alias}.svg"
    ln -sfn "${alias}-folder.svg" "${places_dir}/folder-${alias}.svg"
  done
}

# Linux Mint 22.3 moved Cinnamon and XApps to xsi-* symbolic icon names. XSI
# itself is installed in hicolor. Discover those names and alias every matching
# Win11 icon so controls and panel indicators retain this theme's visual style.
install_xsi_aliases() {
  local theme_dir=$1
  local xsi_root=${XSI_ICON_ROOT:-/usr/share/icons/hicolor}
  local xsi_path xsi_name target_name target count=0
  local -A xsi_names=()

  [[ -d ${xsi_root} ]] || return 0

  while IFS= read -r -d '' xsi_path; do
    xsi_names["${xsi_path##*/}"]=1
  done < <(find "${xsi_root}" \( -type f -o -type l \) -name 'xsi-*.svg' -print0)
  (( ${#xsi_names[@]} > 0 )) || return 0

  # Walk the installed theme once rather than searching it separately for
  # hundreds of XSI names.
  while IFS= read -r -d '' target; do
    target_name=${target##*/}
    [[ ${target_name} != xsi-* ]] || continue
    xsi_name="xsi-${target_name}"

    if [[ -n ${xsi_names[${xsi_name}]+present} ]]; then
      ln -sfn "${target_name}" "$(dirname "${target}")/${xsi_name}"
      ((count += 1))
    fi
  done < <(find "${theme_dir}" \
    -path '*/symbolic/*' \
    ! -path '*@2x*' \
    \( -type f -o -type l \) \
    -name '*.svg' \
    -print0)

  if (( count > 0 )); then
    printf '  Added %d Linux Mint XSI compatibility aliases.\n' "${count}"
  fi
}

update_icon_cache() {
  local theme_dir=$1

  if command -v gtk-update-icon-cache >/dev/null 2>&1; then
    if ! gtk-update-icon-cache -f -t "${theme_dir}" >/dev/null; then
      warn "Could not update the icon cache for '${theme_dir}'."
    fi
  elif [[ ${cache_warning_shown} == false ]]; then
    warn "gtk-update-icon-cache was not found; installation can continue without a cache."
    cache_warning_shown=true
  fi
}

install_standard() {
  local theme_dir=$1
  local theme=$2

  mkdir -p "${theme_dir}/status"
  cp -a "${SRC_DIR}/src/"{actions,animations,apps,categories,devices,emotes,emblems,mimes,places,preferences} "${theme_dir}/"
  cp -a "${SRC_DIR}/src/status/"{16,22,24,32,symbolic} "${theme_dir}/status/"

  if [[ ${alternative} == true ]]; then
    cp -a "${SRC_DIR}/alternative/." "${theme_dir}/"
  fi

  if [[ -n ${theme} ]]; then
    cp -a "${SRC_DIR}/colors/color${theme}/." "${theme_dir}/places/scalable/"
  fi

  if is_budgie; then
    cp -a "${SRC_DIR}/src/status/symbolic-budgie/." "${theme_dir}/status/symbolic/"
  fi

  rm -f "${theme_dir}/places/scalable/user-trash-dark.svg" \
        "${theme_dir}/places/scalable/user-trash-full-dark.svg"

  cp -a "${SRC_DIR}/links/"{actions,apps,categories,devices,emotes,emblems,mimes,places,status,preferences} "${theme_dir}/"
  ln -sfn 32 "${theme_dir}/preferences/22"

  install_folder_palettes "${theme_dir}"
}

install_dark() {
  local theme_dir=$1
  local dest_dir=$2
  local base_name=$3
  local theme=$4
  local base_theme_name="${base_name}${theme}"
  local directory

  mkdir -p "${theme_dir}/"{apps,categories,emblems,devices,mimes,places,status}

  cp -a "${SRC_DIR}/src/actions" "${theme_dir}/"
  cp -a "${SRC_DIR}/src/apps/"{22,32,symbolic} "${theme_dir}/apps/"
  cp -a "${SRC_DIR}/src/categories/"{22,symbolic} "${theme_dir}/categories/"
  cp -a "${SRC_DIR}/src/emblems/symbolic" "${theme_dir}/emblems/"
  cp -a "${SRC_DIR}/src/mimes/symbolic" "${theme_dir}/mimes/"
  cp -a "${SRC_DIR}/src/devices/"{16,22,24,32,symbolic} "${theme_dir}/devices/"
  cp -a "${SRC_DIR}/src/places/"{16,22,24,scalable,symbolic} "${theme_dir}/places/"
  cp -a "${SRC_DIR}/src/status/symbolic" "${theme_dir}/status/"

  if [[ ${alternative} == true ]]; then
    cp -a "${SRC_DIR}/alternative/apps/symbolic/." "${theme_dir}/apps/symbolic/"
    cp -a "${SRC_DIR}/alternative/places/scalable/." "${theme_dir}/places/scalable/"
  fi

  if [[ -n ${theme} ]]; then
    cp -a "${SRC_DIR}/colors/color${theme}/." "${theme_dir}/places/scalable/"
  fi

  if is_budgie; then
    cp -a "${SRC_DIR}/src/status/symbolic-budgie/." "${theme_dir}/status/symbolic/"
  fi

  mv -f "${theme_dir}/places/scalable/user-trash-dark.svg" \
        "${theme_dir}/places/scalable/user-trash.svg"
  mv -f "${theme_dir}/places/scalable/user-trash-full-dark.svg" \
        "${theme_dir}/places/scalable/user-trash-full.svg"

  for directory in \
    "${theme_dir}/actions/16" "${theme_dir}/actions/22" "${theme_dir}/actions/24" "${theme_dir}/actions/32" \
    "${theme_dir}/apps/22" "${theme_dir}/apps/32" \
    "${theme_dir}/categories/22" \
    "${theme_dir}/devices/16" "${theme_dir}/devices/22" "${theme_dir}/devices/24" "${theme_dir}/devices/32" \
    "${theme_dir}/places/16" "${theme_dir}/places/22" "${theme_dir}/places/24" \
    "${theme_dir}/actions/symbolic" "${theme_dir}/apps/symbolic" "${theme_dir}/categories/symbolic" \
    "${theme_dir}/emblems/symbolic" "${theme_dir}/devices/symbolic" "${theme_dir}/mimes/symbolic" \
    "${theme_dir}/places/symbolic" "${theme_dir}/status/symbolic"; do
    find "${directory}" -maxdepth 1 -type f -name '*.svg' -exec sed -i 's/#363636/#dedede/g' {} +
  done

  cp -a "${SRC_DIR}/links/actions/"{16,22,24,32,symbolic} "${theme_dir}/actions/"
  cp -a "${SRC_DIR}/links/devices/"{16,22,24,32,symbolic} "${theme_dir}/devices/"
  cp -a "${SRC_DIR}/links/places/"{16,22,24,scalable,symbolic} "${theme_dir}/places/"
  cp -a "${SRC_DIR}/links/apps/"{22,symbolic} "${theme_dir}/apps/"
  cp -a "${SRC_DIR}/links/categories/"{22,symbolic} "${theme_dir}/categories/"
  cp -a "${SRC_DIR}/links/mimes/symbolic" "${theme_dir}/mimes/"
  cp -a "${SRC_DIR}/links/status/symbolic" "${theme_dir}/status/"

  (
    cd "${dest_dir}"
    ln -sfn "../${base_theme_name}/animations" "${base_theme_name}-dark/animations"
    ln -sfn "../${base_theme_name}/emotes" "${base_theme_name}-dark/emotes"
    ln -sfn "../${base_theme_name}/preferences" "${base_theme_name}-dark/preferences"
    ln -sfn "../../${base_theme_name}/categories/32" "${base_theme_name}-dark/categories/32"
    ln -sfn "../../${base_theme_name}/emblems/16" "${base_theme_name}-dark/emblems/16"
    ln -sfn "../../${base_theme_name}/emblems/22" "${base_theme_name}-dark/emblems/22"
    ln -sfn "../../${base_theme_name}/emblems/24" "${base_theme_name}-dark/emblems/24"
    ln -sfn "../../${base_theme_name}/mimes/16" "${base_theme_name}-dark/mimes/16"
    ln -sfn "../../${base_theme_name}/mimes/22" "${base_theme_name}-dark/mimes/22"
    ln -sfn "../../${base_theme_name}/mimes/scalable" "${base_theme_name}-dark/mimes/scalable"
    ln -sfn "../../${base_theme_name}/apps/scalable" "${base_theme_name}-dark/apps/scalable"
    ln -sfn "../../${base_theme_name}/devices/scalable" "${base_theme_name}-dark/devices/scalable"
    ln -sfn "../../${base_theme_name}/status/16" "${base_theme_name}-dark/status/16"
    ln -sfn "../../${base_theme_name}/status/22" "${base_theme_name}-dark/status/22"
    ln -sfn "../../${base_theme_name}/status/24" "${base_theme_name}-dark/status/24"
    ln -sfn "../../${base_theme_name}/status/32" "${base_theme_name}-dark/status/32"
  )

  install_folder_palettes "${theme_dir}"
}

install_theme_variant() {
  local dest_dir=$1
  local base_name=$2
  local theme=$3
  local color=$4
  local installed_name="${base_name}${theme}${color}"
  local theme_dir="${dest_dir}/${installed_name}"
  local category

  [[ -e ${theme_dir} || -L ${theme_dir} ]] && rm -rf -- "${theme_dir}"
  printf "Installing '%s'...\n" "${theme_dir}"

  mkdir -p "${theme_dir}"
  cp -a "${SRC_DIR}/COPYING" "${SRC_DIR}/AUTHORS" "${theme_dir}/"
  cp -a "${SRC_DIR}/src/index.theme" "${theme_dir}/"
  configure_index "${theme_dir}" "${installed_name}"

  if [[ -z ${color} ]]; then
    install_standard "${theme_dir}" "${theme}"
  else
    install_dark "${theme_dir}" "${dest_dir}" "${base_name}" "${theme}"
  fi

  install_xsi_aliases "${theme_dir}"

  for category in actions animations apps categories devices emotes emblems mimes places preferences status; do
    [[ -e ${theme_dir}/${category} || -L ${theme_dir}/${category} ]] && \
      ln -sfn "${category}" "${theme_dir}/${category}@2x"
  done

  update_icon_cache "${theme_dir}"
}

uninstall_theme_variant() {
  local theme_dir=$1

  if [[ -e ${theme_dir} || -L ${theme_dir} ]]; then
    printf "Removing '%s'...\n" "${theme_dir}"
    rm -rf -- "${theme_dir}"
  else
    printf "Not installed: '%s'\n" "${theme_dir}"
  fi
}

schema_exists() {
  local schema=$1
  command -v gsettings >/dev/null 2>&1 && \
    gsettings list-schemas 2>/dev/null | grep -Fx "${schema}" >/dev/null
}

detect_apply_mode() {
  local gtk_theme='' color_scheme=''
  local schema

  for schema in org.cinnamon.desktop.interface org.gnome.desktop.interface org.mate.interface; do
    if schema_exists "${schema}"; then
      gtk_theme=$(gsettings get "${schema}" gtk-theme 2>/dev/null || true)
      color_scheme=$(gsettings get "${schema}" color-scheme 2>/dev/null || true)
      break
    fi
  done

  if [[ ${gtk_theme,,} == *dark* || ${color_scheme,,} == *prefer-dark* ]]; then
    printf '%s' dark
  else
    printf '%s' standard
  fi
}

apply_icon_theme() {
  local installed_name=$1
  local mode=$2
  local desktop="${XDG_CURRENT_DESKTOP:-}:${DESKTOP_SESSION:-}"

  [[ ${EUID} -ne ${ROOT_UID} ]] || error "--apply must be run as your desktop user, without sudo."

  if [[ ${mode} == auto ]]; then
    mode=$(detect_apply_mode)
  fi
  [[ ${mode} == dark ]] && installed_name+="-dark"

  desktop=${desktop,,}
  if [[ ${desktop} == *cinnamon* ]] && schema_exists org.cinnamon.desktop.interface; then
    gsettings set org.cinnamon.desktop.interface icon-theme "${installed_name}"
  elif [[ ${desktop} == *mate* ]] && schema_exists org.mate.interface; then
    gsettings set org.mate.interface icon-theme "${installed_name}"
  elif [[ ${desktop} == *xfce* ]] && command -v xfconf-query >/dev/null 2>&1; then
    xfconf-query -c xsettings -p /Net/IconThemeName -s "${installed_name}"
  elif schema_exists org.cinnamon.desktop.interface; then
    gsettings set org.cinnamon.desktop.interface icon-theme "${installed_name}"
  elif schema_exists org.gnome.desktop.interface; then
    gsettings set org.gnome.desktop.interface icon-theme "${installed_name}"
  elif schema_exists org.mate.interface; then
    gsettings set org.mate.interface icon-theme "${installed_name}"
  elif command -v xfconf-query >/dev/null 2>&1; then
    xfconf-query -c xsettings -p /Net/IconThemeName -s "${installed_name}"
  else
    error "Could not detect Cinnamon, MATE, Xfce or GNOME. Select '${installed_name}' in your desktop's appearance settings."
  fi

  printf "Applied icon theme '%s'.\n" "${installed_name}"
}

while (( $# > 0 )); do
  case ${1} in
    -d|--dest)
      require_value "$1" "${2:-}"
      dest=$2
      shift 2
      ;;
    -n|--name)
      require_value "$1" "${2:-}"
      name=$2
      shift 2
      ;;
    -t|--theme)
      shift
      (( $# > 0 )) || error "--theme requires at least one variant."
      themes_explicit=true
      found_theme=false
      while (( $# > 0 )) && [[ ${1} != -* ]]; do
        parse_theme "$1"
        found_theme=true
        shift
      done
      [[ ${found_theme} == true ]] || error "--theme requires at least one variant."
      ;;
    -a|--alternative)
      alternative=true
      shift
      ;;
    -b|--bold)
      error "The --bold assets are not included in this repository."
      ;;
    --apply)
      apply=true
      if (( $# > 1 )) && [[ ${2} =~ ^(auto|standard|dark)$ ]]; then
        apply_mode=$2
        shift
      fi
      shift
      ;;
    --apply=*)
      apply=true
      apply_mode=${1#*=}
      [[ ${apply_mode} =~ ^(auto|standard|dark)$ ]] || error "Invalid --apply mode '${apply_mode}'."
      shift
      ;;
    -r|--remove|-u|--uninstall)
      remove=true
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      error "Unrecognized installation option '$1'. Try '$0 --help'."
      ;;
  esac
done

[[ ${name} =~ ^[A-Za-z0-9._-]+$ ]] || error "Theme name may contain only letters, numbers, dots, underscores and hyphens."
[[ ${dest} != / ]] || error "Refusing to use '/' as the destination directory."

if [[ ${remove} == true ]]; then
  [[ ${apply} == false ]] || error "--apply cannot be combined with --uninstall."
  if [[ ${themes_explicit} == false ]]; then
    themes=("${THEME_VARIANTS[@]}")
  fi
  for theme in "${themes[@]}"; do
    for color in "${COLOR_VARIANTS[@]}"; do
      uninstall_theme_variant "${dest}/${name}${theme}${color}"
    done
  done
  exit 0
fi

if (( ${#themes[@]} == 0 )); then
  themes=("${THEME_VARIANTS[0]}")
fi

mkdir -p "${dest}"
for theme in "${themes[@]}"; do
  for color in "${COLOR_VARIANTS[@]}"; do
    install_theme_variant "${dest}" "${name}" "${theme}" "${color}"
  done
done

if [[ ${apply} == true ]]; then
  apply_icon_theme "${name}${themes[0]}" "${apply_mode}"
else
  printf '\nInstalled successfully. Select %s in your desktop appearance settings.\n' "${name}${themes[0]}"
fi
