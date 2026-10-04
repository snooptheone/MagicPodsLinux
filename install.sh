#!/usr/bin/env bash
# Installs the bundle built by build-portable.sh.
#   ./install.sh              per-user install (no sudo): ~/.local/...
#   ./install.sh --system     system-wide install (sudo): /opt, /usr/...
#   ./install.sh --autostart  also start MagicPods in the tray at login
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
BUNDLE_DIR="$SCRIPT_DIR/MagicPods-portable"

AUTOSTART=0
SYSTEM=0
while [[ $# -gt 0 ]]; do
  case "$1" in
    --autostart) AUTOSTART=1 ;;
    --system) SYSTEM=1 ;;
    *)
      echo "Unknown option: $1" >&2
      echo "Usage: $0 [--autostart] [--system]" >&2
      exit 1
      ;;
  esac
  shift
done

if [[ $SYSTEM -eq 1 ]]; then
  INSTALL_DIR="/opt/magicpods"
  BIN_LINK="/usr/local/bin/magicpods"
  DESKTOP_DEST="/usr/share/applications/magicpods.desktop"
  ICON_DEST="/usr/share/icons/hicolor"
  run() { sudo "$@"; }
else
  INSTALL_DIR="$HOME/.local/share/magicpods"
  BIN_LINK="$HOME/.local/bin/magicpods"
  DESKTOP_DEST="$HOME/.local/share/applications/magicpods.desktop"
  ICON_DEST="$HOME/.local/share/icons/hicolor"
  run() { "$@"; }
fi

# Generate a .desktop pointing at the installed copy.
# $1 = destination file, $2 = optional extra Exec args
write_desktop() {
  cat > "$1" <<EOF
[Desktop Entry]
Type=Application
Name=MagicPods
GenericName=Bluetooth Headphones Manager
Comment=Battery and noise control for AirPods, Beats and Galaxy Buds
Exec="$INSTALL_DIR/magicpods.sh"${2:+ $2}
Icon=magicpods
Terminal=false
Categories=Utility;Audio;
StartupWMClass=magicpods
X-GNOME-UsesNotifications=true
EOF
}

if [[ ! -f "$BUNDLE_DIR/magicpods.sh" ]]; then
  echo "ERROR: $BUNDLE_DIR/magicpods.sh not found. Run build-portable.sh first." >&2
  exit 1
fi

echo "==> Installing MagicPods to $INSTALL_DIR"
run rm -rf "$INSTALL_DIR"
run mkdir -p "$INSTALL_DIR"
run cp -a "$BUNDLE_DIR/." "$INSTALL_DIR/"

echo "==> Linking $BIN_LINK"
run mkdir -p "$(dirname "$BIN_LINK")"
run ln -sf "$INSTALL_DIR/magicpods.sh" "$BIN_LINK"

echo "==> Installing desktop entry to $DESKTOP_DEST"
tmp="$(mktemp)"
write_desktop "$tmp"
run install -Dm644 "$tmp" "$DESKTOP_DEST"
rm -f "$tmp"

if [[ -d "$BUNDLE_DIR/share/icons/hicolor" ]]; then
  echo "==> Installing icons to $ICON_DEST"
  run mkdir -p "$ICON_DEST"
  run cp -a "$BUNDLE_DIR/share/icons/hicolor/." "$ICON_DEST/"
  if command -v gtk-update-icon-cache >/dev/null 2>&1; then
    run gtk-update-icon-cache -f -t "$ICON_DEST" || true
  fi
fi

if [[ $AUTOSTART -eq 1 ]]; then
  AUTOSTART_FILE="$HOME/.config/autostart/magicpods.desktop"
  mkdir -p "$(dirname "$AUTOSTART_FILE")"
  write_desktop "$AUTOSTART_FILE" --start-in-tray
  echo "==> Created autostart entry: $AUTOSTART_FILE"
fi

echo "Done. Launch from the application menu or run 'magicpods'."
if [[ $SYSTEM -eq 0 && ":$PATH:" != *":$HOME/.local/bin:"* ]]; then
  echo "Note: $HOME/.local/bin is not in PATH; the 'magicpods' command needs it."
fi
echo "You can now delete $BUNDLE_DIR if you want; the installed copy is independent."
