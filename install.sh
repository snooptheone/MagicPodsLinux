#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
TARGET_DIR="$SCRIPT_DIR/MagicPods-portable"
DESKTOP_DEST="$HOME/.local/share/applications/magicpods.desktop"
BIN_LINK="/usr/local/bin/magicpods"

# Generate a .desktop for the current install location (absolute Exec path).
# $1 = destination file, $2 = optional extra Exec args
write_desktop() {
  cat > "$1" <<EOF
[Desktop Entry]
Type=Application
Name=MagicPods
GenericName=Bluetooth Headphones Manager
Comment=Battery and noise control for AirPods, Beats and Galaxy Buds
Exec="$TARGET_DIR/magicpods.sh"${2:+ $2}
Icon=magicpods
Terminal=false
Categories=Utility;Audio;
StartupWMClass=magicpods
X-GNOME-UsesNotifications=true
EOF
  chmod +x "$1"
}

# CLI options
AUTOSTART=0
SYSTEM=0
while [[ $# -gt 0 ]]; do
  case "$1" in
    --autostart)
      AUTOSTART=1
      shift
      ;;
    --system)
      SYSTEM=1
      shift
      ;;
    *)
      echo "Unknown option: $1" >&2
      echo "Usage: $0 [--autostart] [--system]" >&2
      exit 1
      ;;
  esac
done

if [[ $SYSTEM -eq 1 ]]; then
  DESKTOP_DEST="/usr/share/applications/magicpods.desktop"
fi

echo "==> Installing MagicPods launcher"

if [[ ! -d "$TARGET_DIR" ]]; then
  echo "ERROR: target directory $TARGET_DIR not found. Run build-portable.sh first." >&2
  exit 1
fi

if [[ ! -f "$TARGET_DIR/magicpods.sh" ]]; then
  echo "ERROR: $TARGET_DIR/magicpods.sh not found." >&2
  exit 1
fi

if ! command -v sudo >/dev/null 2>&1; then
  echo "ERROR: sudo is required to create system symlink at $BIN_LINK" >&2
  exit 1
fi

echo "Requesting sudo privileges..."
sudo -v

echo "Creating symlink: $BIN_LINK -> $TARGET_DIR/magicpods.sh"
sudo ln -sf "$TARGET_DIR/magicpods.sh" "$BIN_LINK"

echo "Setting executable bits"
sudo chmod +x "$TARGET_DIR/magicpods.sh"
if [[ -f "$TARGET_DIR/bin/magicpods" ]]; then
  sudo chmod +x "$TARGET_DIR/bin/magicpods"
fi

echo "Installing desktop entry to $DESKTOP_DEST"
if [[ $SYSTEM -eq 1 ]]; then
  tmp="$(mktemp)"
  write_desktop "$tmp"
  sudo install -Dm755 "$tmp" "$DESKTOP_DEST"
  rm -f "$tmp"
else
  mkdir -p "$(dirname "$DESKTOP_DEST")"
  write_desktop "$DESKTOP_DEST"
fi

# Install bundled icon into the user's icon theme so Icon=magicpods resolves
# Install bundled icons (multiple sizes and SVGs) into the user's icon theme
ICON_BASE="$TARGET_DIR/share/icons/hicolor"
if [[ -d "$ICON_BASE" ]]; then
  echo "Installing bundled icons from $ICON_BASE"
  for dir in "$ICON_BASE"/*; do
    name=$(basename "$dir")
    # match patterns like 16x16, 32x32, scalable, etc.
    if [[ -d "$dir" ]]; then
      if [[ "$name" == scalable ]]; then
        # scalable/apps -> copy SVGs
        srcdir="$dir/apps"
        destdir="$HOME/.local/share/icons/hicolor/scalable/apps"
        if [[ -d "$srcdir" ]]; then
          mkdir -p "$destdir"
          cp -f "$srcdir"/* "$destdir/" 2>/dev/null || true
        fi
      else
        # e.g. 256x256/apps
        srcdir="$dir/apps"
        destdir="$HOME/.local/share/icons/hicolor/$name/apps"
        if [[ -d "$srcdir" ]]; then
          mkdir -p "$destdir"
          cp -f "$srcdir"/* "$destdir/" 2>/dev/null || true
        fi
      fi
    fi
  done
  # update icon cache if available
  if command -v gtk-update-icon-cache >/dev/null 2>&1; then
    gtk-update-icon-cache -f -t "$HOME/.local/share/icons/hicolor" || true
  fi
else
  echo "No bundled icons found in $ICON_BASE; skipping icon installation." >&2
fi

echo "Installation complete. You can now run 'magicpods' from the shell or find MagicPods in your application menu."
echo "If the menu doesn't show it immediately, try:"
echo "  update-desktop-database ~/.local/share/applications || true"

if [[ $AUTOSTART -eq 1 ]]; then
  AUTOSTART_DIR="$HOME/.config/autostart"
  AUTOSTART_FILE="$AUTOSTART_DIR/magicpods.desktop"
  mkdir -p "$AUTOSTART_DIR"
  write_desktop "$AUTOSTART_FILE" --start-in-tray
  echo "Created autostart entry: $AUTOSTART_FILE"
fi

exit 0
