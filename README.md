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
