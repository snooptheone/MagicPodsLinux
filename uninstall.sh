#!/usr/bin/env bash
# Removes everything install.sh (user or --system) created, plus leftovers of
# older installs that pointed at the repo's MagicPods-portable/ directly.
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
BUNDLE_DIR="$SCRIPT_DIR/MagicPods-portable"

KEEP_AUTOSTART=0
PURGE=0
while [[ $# -gt 0 ]]; do
  case "$1" in
    --keep-autostart) KEEP_AUTOSTART=1 ;;
    --purge) PURGE=1 ;;
    -h|--help)
      cat <<EOF
Usage: uninstall.sh [--keep-autostart] [--purge]

  --keep-autostart  Keep ~/.config/autostart/magicpods.desktop.
  --purge           Also delete the build output $BUNDLE_DIR.
EOF
      exit 0
      ;;
    *) echo "Unknown option: $1" >&2; exit 1 ;;
  esac
  shift
done

# remove <path> [sudo]: delete if present, with sudo only when asked.
remove() {
  [[ -e "$1" || -L "$1" ]] || return 0
  echo "Removing $1"
  if [[ "${2:-}" == sudo ]]; then sudo rm -rf "$1"; else rm -rf "$1"; fi
}

echo "==> Uninstalling MagicPods"

# User install
remove "$HOME/.local/share/magicpods"
remove "$HOME/.local/bin/magicpods"
remove "$HOME/.local/share/applications/magicpods.desktop"

# System install (only touches sudo if something is there)
remove /opt/magicpods sudo
remove /usr/share/applications/magicpods.desktop sudo

# /usr/local/bin/magicpods: system install, or an old one pointing at the repo bundle
LINK=/usr/local/bin/magicpods
if [[ -L "$LINK" ]]; then
  target="$(readlink -f "$LINK" || true)"
  if [[ "$target" == /opt/magicpods/* || "$target" == "$BUNDLE_DIR"/* ]]; then
    remove "$LINK" sudo
  else
    echo "Symlink $LINK points to $target; leaving it untouched" >&2
  fi
fi

# Icons (png app icon, plus UI svgs that older builds copied into the theme)
for base in "$HOME/.local/share/icons/hicolor" /usr/share/icons/hicolor; do
  [[ -d "$base" ]] || continue
  s=""; [[ "$base" == /usr/* ]] && s=sudo
  for f in "$base"/*/apps/magicpods.png; do remove "$f" $s; done
  for svg in "$SCRIPT_DIR"/src/app/qml/assets/icons/*.svg; do
    remove "$base/scalable/apps/$(basename "$svg")" $s
  done
  if command -v gtk-update-icon-cache >/dev/null 2>&1; then
    if [[ -n "$s" ]]; then sudo gtk-update-icon-cache -f -t "$base" || true
    else gtk-update-icon-cache -f -t "$base" || true; fi
  fi
done

[[ $KEEP_AUTOSTART -eq 1 ]] || remove "$HOME/.config/autostart/magicpods.desktop"
[[ $PURGE -eq 0 ]] || remove "$BUNDLE_DIR"

echo "Uninstall complete."
