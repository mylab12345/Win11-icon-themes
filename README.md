# Win11 Icon Theme

A colorful Windows 11 Fluent-style icon theme for Linux desktops.

![Win11 icon theme preview](View-1.png)

## Linux Mint 22.3 support

This fork is ready for Linux Mint 22.3 **Zena**, including Cinnamon 6.6:

- XApp Symbolic Icon (`xsi-*`) aliases are generated during installation, keeping Cinnamon panels and XApps visually consistent instead of falling back to mixed icon styles.
- Current Linux Mint apps are covered, including Nemo, Hypnotix, Warpinator, Bulky, Sticky, Drawing, Web Apps, System Information, System Administration, Backup Tool and Welcome Screen.
- The installer can apply the icon theme directly on Cinnamon, MATE or Xfce.
- Standard and dark variants are installed together. `--apply auto` follows the current light/dark desktop style.
- All bundled folder palettes are installed, and legacy folder-color links no longer produce missing icons.

## Recommended setup for Linux Mint

Run the installer **without `sudo`** so the theme is installed only for your user:

```bash
./install.sh --theme blue --apply
```

Blue gives Mint a clean Windows 11-style accent. The installer automatically selects `Win11-blue` or `Win11-blue-dark` based on the current desktop theme.

For a more colorful look, try another folder accent:

```bash
./install.sh --theme purple --apply
./install.sh --theme green --apply dark
./install.sh --theme nord --apply
```

To install several accents at once:

```bash
./install.sh --theme blue green purple
```

When several accents are installed with `--apply`, the first one is applied.

### Apply manually

If you prefer the graphical settings:

1. Open **System Settings → Themes**.
2. Open **Advanced settings** if it is shown.
3. Set **Icons** to `Win11-blue` for a light panel or `Win11-blue-dark` for a dark panel.

For a polished Cinnamon layout, use a matching light/dark Mint-Y control theme, keep panel icons at their default symbolic size, and use the Cinnamon 6.6 menu settings to enlarge application icons slightly (24–28 px) and hide descriptions for a cleaner launcher.

## Windows 11-style desktop for Linux Mint Cinnamon

Icons alone only change half the look. `win11-desktop-setup.sh` gives all four
selectors in **System Settings → Themes** a Windows 11 appearance, then configures
the Cinnamon desktop itself — panel, window buttons, tiling, fonts, Nemo and
desktop icons — so applications and the desktop behave like Windows 11.

```bash
./win11-desktop-setup.sh
```

Run it **without `sudo`**: everything it touches is per-user. On the first run it
uses `git` and an internet connection to download pinned snapshots of the
[Win11 GTK theme](https://github.com/yeyushengfan258/Win11-gtk-theme) and the
[Windows 11 cursor theme](https://github.com/0free/windows-11-icons). Subsequent
runs reuse the installed copies.

### What it changes

| Area | Windows 11 behaviour applied |
| --- | --- |
| Desktop | Installs and applies `Win11-Light` / `Win11-Dark` to Cinnamon's panel, menu and dialogs |
| Applications | Applies the matching `Win11-Light` / `Win11-Dark` GTK theme |
| Icons | Installs and applies `Win11-blue` / `Win11-blue-dark` via `install.sh` |
| Mouse Pointer | Installs and applies `Windows-11-cursors` |
| Font | Installs Microsoft's open **Selawik** font (a Segoe UI-metric twin) when no Segoe-style font is present, and uses it everywhere |
| Wallpaper | Applies a bundled Windows 11 "Bloom"-style wallpaper matching the light/dark mode (or `--wallpaper FILE` for your own) |
| Taskbar | Moves the menu and the grouped window list to the **center** of the panel, the signature Windows 11 layout |
| Titlebars | Uses the matching Win11 window theme, with buttons on the right in `minimize, maximize, close` order |
| Snapping | Edge tiling, Snap Layouts-style tile HUD, `Super` as snap modifier, new windows centred |
| Task switcher | Alt+Tab with icons **and** window thumbnails |
| Panel | Single 48 px bottom panel, no autohide, no hot corner, Win11-like icon sizes |
| Keyboard | `Super` opens the menu, `Super+D` shows the desktop |
| Clock | Time plus short date in the tray |
| Files | Nemo defaults to list view, places sidebar, double click, informal dates |
| Desktop icons | Home, Computer and Trash icons only, grid aligned |

### Common variations

```bash
./win11-desktop-setup.sh --theme purple --mode dark   # different accent, forced dark
./win11-desktop-setup.sh --panel bottom --panel-height 52
./win11-desktop-setup.sh --wallpaper ~/Pictures/bg.jpg # your own background
./win11-desktop-setup.sh --no-icons                   # keep the current icon theme
./win11-desktop-setup.sh --no-wallpaper --no-font     # keep background and font
./win11-desktop-setup.sh --no-center-taskbar          # keep the left-aligned panel layout
./win11-desktop-setup.sh --no-companions              # stay offline/use installed themes
./win11-desktop-setup.sh --dry-run                    # show changes, change nothing
./win11-desktop-setup.sh --gtk-theme MyTheme --cursor-theme MyCursors
```

Full option list: `./win11-desktop-setup.sh --help`.

### Companion downloads and offline use

The companion themes are fetched directly from their upstream projects at
immutable revisions, then installed under `${XDG_DATA_HOME:-~/.local/share}`:

| Component | Pinned source | License note |
| --- | --- | --- |
| Desktop and Applications | [`yeyushengfan258/Win11-gtk-theme@49e30de`](https://github.com/yeyushengfan258/Win11-gtk-theme/tree/49e30de3503a49c4c873552b117f8e725393b527) | GPL-3.0 |
| Mouse Pointer | [`0free/windows-11-icons@408e623`](https://github.com/0free/windows-11-icons/tree/408e6233586d9e79cca252cfc034caf14bf546b8) | Upstream does not declare a license |
| Font (Selawik) | [`winjs/winstrap@342cf99`](https://github.com/winjs/winstrap/tree/342cf99031344f48917e14a5c3a728ec5ede8d8f) (`src/fonts/selawk*.ttf`) | Selawik is Microsoft's open Segoe UI-compatible font, SIL OFL 1.1 |

The Selawik font is only downloaded when neither Segoe UI nor Selawik is
already available on the system, and can be skipped with `--no-font`.

The cursor files are **not bundled or redistributed by this repository**. The
setup script copies them from that pinned upstream snapshot at runtime. Review
that project's terms before using them.

If a required download cannot be fetched, setup stops with an error and leaves
existing theme selections alone. For an offline run, use `--no-companions`; the
script will use compatible themes already installed on the system. You can also
provide exact installed names with `--gtk-theme` and `--cursor-theme`. To get all
four exact defaults while offline, run once online first or install the pinned
companions yourself.

Cinnamon stores the resulting selectors as follows (the icon accent changes
with `--theme`):

| Themes field | Light mode | Dark mode |
| --- | --- | --- |
| Desktop | `Win11-Light` | `Win11-Dark` |
| Applications | `Win11-Light` | `Win11-Dark` |
| Icons | `Win11-blue` | `Win11-blue-dark` |
| Mouse Pointer | `Windows-11-cursors` | `Windows-11-cursors` |

### Undo

Every run writes the previous values to a restore script in
`~/.local/state/win11-desktop-setup/`:

```bash
./win11-desktop-setup.sh --restore                    # undo the most recent run
./win11-desktop-setup.sh --restore ~/.local/state/win11-desktop-setup/restore-20260814-101500.sh
```

### Finishing touches (GUI only)

Cinnamon stores applet options per instance, so these last steps are safest by hand:

1. **Centred taskbar** — right-click the panel → *Panel* → *Panel edit mode*, drag
   *Menu* and *Grouped window list* into the **center** zone, keep the systray and
   clock on the right, then leave edit mode.
2. **Start button** — right-click the menu applet → *Configure*, clear the "Menu"
   text label and use a categories-less layout.
3. **Icon-only taskbar** — right-click *Grouped window list* → *Configure* → turn
   labels off and pin your favourite apps.
4. **Confirm the four themes** — open **System Settings → Themes → Advanced
   settings**. Desktop and Applications should show `Win11-Light` or
   `Win11-Dark`, Icons should show the selected `Win11` accent, and Mouse Pointer
   should show `Windows 11`.

## Install options

```text
Usage: ./install.sh [OPTION]...

  -d, --dest DIR          Destination directory
                          Default: ~/.local/share/icons
  -n, --name NAME         Installed theme name (default: Win11)
  -t, --theme VARIANT     Folder accent(s):
                          default, black, blue, green, nord, purple, red, all
                          Multiple values are accepted (default: default/yellow)
  -a, --alternative       Use alternative macOS-inspired app/device icons
      --apply [MODE]      Apply the first installed accent
                          MODE: auto, standard, dark (default: auto)
  -r, --remove,
  -u, --uninstall         Remove selected accents, or all if none are selected
  -h, --help              Show help
```

The optional `gtk-update-icon-cache` command is used when available. A missing cache utility does not prevent installation.

### Custom destination or system-wide install

A custom user destination:

```bash
./install.sh --dest "$HOME/.icons" --theme blue
```

A system-wide install (manual theme selection is recommended afterward):

```bash
sudo ./install.sh --theme blue
```

Do not combine `sudo` with `--apply`; desktop settings belong to your regular user session.

## Uninstall

Remove every Win11 accent installed in the destination:

```bash
./install.sh --uninstall
```

Remove only selected accents:

```bash
./install.sh --uninstall --theme blue purple
```

## Other previews

![Applications and folders](View-2.png)
![Icon details](View-3.png)
![Desktop preview](View-4.png)

## Donate

If you like the original project, you can [buy the author a coffee with PayPal](https://www.paypal.me/yeyushengfan258).
