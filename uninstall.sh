#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
TARGET_DIR="$SCRIPT_DIR/MagicPods-portable"
SYMLINK="/usr/local/bin/magicpods"

SYSTEM=0
AUTOSTART=1
HELP=0
while [[ $# -gt 0 ]]; do
  case "$1" in
    --system) SYSTEM=1; shift ;;
    --autostart) AUTOSTART=1; shift ;;
    --help|-h) HELP=1; shift ;;
    *) echo "Unknown option: $1" >&2; echo "Usage: $0 [--system] [--autostart]" >&2; exit 1 ;;
  esac
done

if [[ $HELP -eq 1 ]]; then
  cat <<EOF
Usage: uninstall.sh [--system] [--autostart]

Options:
  --autostart Remove autostart entry (~/.config/autostart/magicpods.desktop).
EOF
  exit 0
fi

echo "==> Uninstalling MagicPods"

# Remove desktop entry

DESKTOP_PATH="/usr/share/applications/magicpods.desktop"
if [[ -f "$DESKTOP_PATH" ]]; then
  echo "Removing system desktop: $DESKTOP_PATH"
  sudo rm -f "$DESKTOP_PATH"
else
  echo "System desktop not found: $DESKTOP_PATH"
fi

DESKTOP_PATH="$HOME/.local/share/applications/magicpods.desktop"
if [[ -f "$DESKTOP_PATH" ]]; then
  echo "Removing user desktop: $DESKTOP_PATH"
  rm -f "$DESKTOP_PATH"
else
  echo "User desktop not found: $DESKTOP_PATH"
fi

# Remove symlink if it points to our bundle
if [[ -L "$SYMLINK" ]]; then
  target=$(readlink -f "$SYMLINK" || true)
  expected="$TARGET_DIR/magicpods.sh"
  if [[ "$target" == "$expected" ]]; then
    echo "Removing symlink $SYMLINK -> $target"
    sudo rm -f "$SYMLINK"
  else
    echo "Symlink $SYMLINK points to $target (not $expected); leaving it untouched" >&2
  fi
elif [[ -e "$SYMLINK" ]]; then
  echo "$SYMLINK exists but is not a symlink; leaving it untouched" >&2
else
  echo "No symlink at $SYMLINK"
fi

# Remove installed icons that came from the bundle
ICON_BASE="$TARGET_DIR/share/icons/hicolor"
if [[ -d "$ICON_BASE" ]]; then
  echo "Removing installed icons from user icon theme"
  for dir in "$ICON_BASE"/*; do
    name=$(basename "$dir")
    if [[ "$name" == "scalable" ]]; then
      srcdir="$dir/apps"
      destdir="$HOME/.local/share/icons/hicolor/scalable/apps"
      if [[ -d "$srcdir" ]]; then
        for f in "$srcdir"/*; do
          [[ -e "$f" ]] || continue
          bn=$(basename "$f")
          if [[ -f "$destdir/$bn" ]]; then
            echo "Removing $destdir/$bn"
            rm -f "$destdir/$bn"
          fi
        done
      fi
    else
      srcdir="$dir/apps"
      destdir="$HOME/.local/share/icons/hicolor/$name/apps"
      if [[ -d "$srcdir" ]]; then
        for f in "$srcdir"/*; do
          [[ -e "$f" ]] || continue
          bn=$(basename "$f")
          if [[ -f "$destdir/$bn" ]]; then
            echo "Removing $destdir/$bn"
            rm -f "$destdir/$bn"
          fi
        done
      fi
    fi
  done
  # try to update icon cache
  if command -v gtk-update-icon-cache >/dev/null 2>&1; then
    gtk-update-icon-cache -f -t "$HOME/.local/share/icons/hicolor" || true
  fi
else
  echo "Bundle icon base not found: $ICON_BASE (skipping icon removal)"
fi

# Remove autostart entry if requested
if [[ $AUTOSTART -eq 1 ]]; then
  AUTOSTART_FILE="$HOME/.config/autostart/magicpods.desktop"
  if [[ -f "$AUTOSTART_FILE" ]]; then
    echo "Removing autostart file: $AUTOSTART_FILE"
    rm -f "$AUTOSTART_FILE"
  else
    echo "No autostart file found: $AUTOSTART_FILE"
  fi
fi

echo "Uninstall complete. You may need to log out/in or run 'update-desktop-database' if icons/menus still show."

exit 0
