#!/bin/bash
# Build release project first to /build

set -euo pipefail

if [[ "$(id -u)" -eq 0 ]]; then
  echo "Run ./build-portable.sh without sudo." >&2
  exit 1
fi

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
TARGET_DIR="$SCRIPT_DIR/MagicPods-portable"
BUILD_DIR="$SCRIPT_DIR/build"
# Override with: QMAKE=/path/to/qmake ./build-portable.sh
QMAKE="${QMAKE:-$HOME/.Qt/6.11.1/gcc_64/bin/qmake}"
QT_PLUGINS_DIR="$("$QMAKE" -query QT_INSTALL_PLUGINS)"
DOCKER_OUT="$(mktemp -d "${TMPDIR:-/tmp}/magicpodscore-runtime.XXXXXX")"
# Use docker directly when the user can reach the daemon (member of the
# "docker" group); fall back to sudo otherwise.
if docker info >/dev/null 2>&1; then
  DOCKER=(docker)
else
  echo "==> No access to the docker daemon; using sudo (or: sudo usermod -aG docker \$USER, then re-login)"
  sudo -v
  DOCKER=(sudo docker)
fi

cleanup() {
  rm -rf "$DOCKER_OUT" 2>/dev/null || sudo rm -rf "$DOCKER_OUT" # root-owned if built via sudo docker
}
trap cleanup EXIT

# Ensure build directory exists and perform CMake configure+build so the
# rest of the script (cqtdeployer and packaging) can rely on $BUILD_DIR/magicpods
if ! command -v cmake >/dev/null 2>&1; then
  echo "ERROR: cmake not found. Please install cmake to build the project." >&2
  exit 1
fi

echo "==> Preparing build directory: $BUILD_DIR"
mkdir -p "$BUILD_DIR"

echo "==> Configuring project (Release)"
cmake -S "$SCRIPT_DIR" -B "$BUILD_DIR" -DCMAKE_BUILD_TYPE=Release

echo "==> Building project"
cmake --build "$BUILD_DIR" --config Release --parallel "$(nproc)"


echo "==> Removing old $TARGET_DIR"
rm -rf "$TARGET_DIR"

echo "==> Building portable frontend bundle"
cqtdeployer \
  -bin "$BUILD_DIR/magicpods" \
  -targetDir "$TARGET_DIR" \
  -qmake "$QMAKE" \
  -qmlDir "$SCRIPT_DIR/src/app/qml" \
  -extraLibs libxcb-cursor

[[ -f "$QT_PLUGINS_DIR/platforms/libqwayland.so" ]] || { echo "ERROR: libqwayland.so not found in $QT_PLUGINS_DIR" >&2; exit 1; }
cp "$QT_PLUGINS_DIR/platforms/libqwayland.so" "$TARGET_DIR/plugins/platforms/"
grep -q '^export CQT_RUN_FILE=' "$TARGET_DIR/magicpods.sh" || { echo "ERROR: CQT_RUN_FILE line missing in magicpods.sh (cqtdeployer output changed)" >&2; exit 1; }
sed -i '/^export CQT_RUN_FILE=/a export MAGICPODSCORE_LIBDIR="$BASE_DIR"/bin/modules/lib' "$TARGET_DIR/magicpods.sh"

echo "==> Building MagicPodsCore runtime with Docker"
"${DOCKER[@]}" buildx build \
  -f "$SCRIPT_DIR/Dockerfile.magicpodscore" \
  --target runtime_export_stage \
  -o type=local,dest="$DOCKER_OUT" \
  "$SCRIPT_DIR"

echo "==> Copying MagicPodsCore runtime into $TARGET_DIR"
mkdir -p "$TARGET_DIR/bin/modules" "$TARGET_DIR/bin/modules/lib"

if [[ ! -f "$DOCKER_OUT/bin/modules/magicpodscore" ]]; then
  echo "ERROR: $DOCKER_OUT/bin/modules/magicpodscore not found" >&2
  exit 1
fi

cp -f "$DOCKER_OUT/bin/modules/magicpodscore" "$TARGET_DIR/bin/modules/magicpodscore"

if [[ -d "$DOCKER_OUT/lib" ]]; then
  cp -a "$DOCKER_OUT/lib/." "$TARGET_DIR/bin/modules/lib/"
fi

# Files exported by "sudo docker" are root-owned; hand them back to the user.
[[ "${DOCKER[0]}" == sudo ]] && sudo chown -R "$(id -u):$(id -g)" "$TARGET_DIR"

# Install icons inside the bundle (collect logos from QML assets)
ICON_IMAGES_DIR="$SCRIPT_DIR/src/app/qml/assets/images"

declare -a SIZES=(16 32 48 256 512)
for size in "${SIZES[@]}"; do
  src="$ICON_IMAGES_DIR/logo-${size}.png"
  if [[ -f "$src" ]]; then
    destdir="$TARGET_DIR/share/icons/hicolor/${size}x${size}/apps"
    mkdir -p "$destdir"
    cp -f "$src" "$destdir/magicpods.png"
    echo "Copied $src -> $destdir/magicpods.png"
  fi
done

echo "==> Done: $TARGET_DIR"
echo "Run ./install.sh to install the launcher (it generates the .desktop for this location)."
