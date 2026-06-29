#!/usr/bin/env bash
# Package a CMake-built Ultra-Fusion ROS2 tree as a release .deb.
#
# Example:
#   ./scripts/package_ros2_deb_from_build.sh \
#     --source /home/big/workspace/Ultra-Fusion \
#     --version 0.2.0 \
#     --output /home/big/workspace/uf_opensource/paper/releases

set -euo pipefail

SOURCE_ROOT="/home/big/workspace/Ultra-Fusion"
VERSION="${ULTRAFUSION_ROS2_VERSION:-0.2.0}"
PACKAGE_NAME="${ULTRAFUSION_ROS2_PACKAGE_NAME:-ultrafusion-ros2}"
OUTPUT_DIR="${ULTRAFUSION_ROS2_OUTPUT_DIR:-$(pwd)/../releases}"

usage() {
  cat <<EOF
Usage: $(basename "$0") [OPTIONS]

Options:
  --source DIR      Ultra-Fusion source tree with build_ros2 outputs
  --version VER     Debian package version, default ${VERSION}
  --output DIR      Directory for the .deb and .sha256 files
  -h, --help        Show this help message
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --source) SOURCE_ROOT="${2:?--source requires a directory}"; shift 2 ;;
    --version) VERSION="${2:?--version requires a version}"; shift 2 ;;
    --output) OUTPUT_DIR="${2:?--output requires a directory}"; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Unknown option: $1" >&2; usage >&2; exit 1 ;;
  esac
done

BUILD_DIR="$SOURCE_ROOT/build_ros2"
UF_NODE="$BUILD_DIR/src/apps/uf_node"
UF_ADAPTER="$BUILD_DIR/uf_ros2_adapter"
UF_LIB="$BUILD_DIR/libultra_lib.so"

for path in "$UF_NODE" "$UF_ADAPTER" "$UF_LIB"; do
  if [[ ! -x "$path" && ! -f "$path" ]]; then
    echo "Error: missing build artifact: $path" >&2
    exit 1
  fi
done

TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT
PKG_DIR="$TMP_DIR/${PACKAGE_NAME}_${VERSION}_amd64"

mkdir -p \
  "$PKG_DIR/DEBIAN" \
  "$PKG_DIR/opt/ultrafusion/bin" \
  "$PKG_DIR/opt/ultrafusion/lib" \
  "$PKG_DIR/opt/ultrafusion/config/m3dgr" \
  "$PKG_DIR/opt/ultrafusion/rviz" \
  "$PKG_DIR/usr/bin"

install -m 0755 "$UF_NODE" "$PKG_DIR/opt/ultrafusion/bin/uf_node"
install -m 0755 "$UF_ADAPTER" "$PKG_DIR/opt/ultrafusion/bin/uf_ros2_adapter"
install -m 0644 "$UF_LIB" "$PKG_DIR/opt/ultrafusion/lib/libultra_lib.so"

strip --strip-unneeded "$PKG_DIR/opt/ultrafusion/bin/uf_node" || true
strip --strip-unneeded "$PKG_DIR/opt/ultrafusion/bin/uf_ros2_adapter" || true
strip --strip-unneeded "$PKG_DIR/opt/ultrafusion/lib/libultra_lib.so" || true

if command -v patchelf >/dev/null 2>&1; then
  RELEASE_RPATH="/opt/ultrafusion/lib:/opt/ros/humble/lib:/usr/local/lib"
  patchelf --set-rpath "$RELEASE_RPATH" \
    "$PKG_DIR/opt/ultrafusion/bin/uf_node"
  patchelf --set-rpath "$RELEASE_RPATH" \
    "$PKG_DIR/opt/ultrafusion/bin/uf_ros2_adapter"
  patchelf --set-rpath "$RELEASE_RPATH" \
    "$PKG_DIR/opt/ultrafusion/lib/libultra_lib.so"
else
  echo "Warning: patchelf not found; packaged binaries keep their build RPATH." >&2
fi

cp "$SOURCE_ROOT"/config/m3dgr/uf_m3dgr_ros2_*.yaml \
  "$PKG_DIR/opt/ultrafusion/config/m3dgr/"
if [[ -f "$SOURCE_ROOT/config/m3dgr/color.yaml" ]]; then
  cp "$SOURCE_ROOT/config/m3dgr/color.yaml" \
    "$PKG_DIR/opt/ultrafusion/config/m3dgr/color.yaml"
elif [[ -f "$SOURCE_ROOT/config/realsense/color.yaml" ]]; then
  cp "$SOURCE_ROOT/config/realsense/color.yaml" \
    "$PKG_DIR/opt/ultrafusion/config/m3dgr/color.yaml"
fi
if [[ -f "$SOURCE_ROOT/rviz/lio.rviz" ]]; then
  cp "$SOURCE_ROOT/rviz/lio.rviz" "$PKG_DIR/opt/ultrafusion/rviz/lio.rviz"
fi
if [[ -f "$SOURCE_ROOT/rviz/lio_ros2.rviz" ]]; then
  cp "$SOURCE_ROOT/rviz/lio_ros2.rviz" \
    "$PKG_DIR/opt/ultrafusion/rviz/lio_ros2.rviz"
fi

cat >"$PKG_DIR/usr/bin/uf_node" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
source /opt/ros/humble/setup.bash
export LD_LIBRARY_PATH="/opt/ultrafusion/lib:${LD_LIBRARY_PATH:-}"
exec /opt/ultrafusion/bin/uf_node "$@"
EOF
chmod 0755 "$PKG_DIR/usr/bin/uf_node"

cat >"$PKG_DIR/usr/bin/uf-ros2-adapter" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
source /opt/ros/humble/setup.bash
export LD_LIBRARY_PATH="/opt/ultrafusion/lib:${LD_LIBRARY_PATH:-}"
exec /opt/ultrafusion/bin/uf_ros2_adapter "$@"
EOF
chmod 0755 "$PKG_DIR/usr/bin/uf-ros2-adapter"

INSTALLED_SIZE="$(du -sk "$PKG_DIR" | awk '{print $1}')"
cat >"$PKG_DIR/DEBIAN/control" <<EOF
Package: ${PACKAGE_NAME}
Version: ${VERSION}
Section: robotics
Priority: optional
Architecture: amd64
Installed-Size: ${INSTALLED_SIZE}
Maintainer: Ultra-Fusion Team <sjtuyinjie@sjtu.edu.cn>
Depends: ros-humble-rclcpp, ros-humble-std-msgs, ros-humble-geometry-msgs, ros-humble-sensor-msgs, ros-humble-nav-msgs, ros-humble-visualization-msgs, ros-humble-cv-bridge, ros-humble-pcl-conversions, libpcl-dev, libopencv-dev, libgoogle-glog-dev, libgflags-dev, libeigen3-dev, libsuitesparse-dev, libtbb-dev
Description: Ultra-Fusion ROS2 Humble runtime
 Prebuilt Ultra-Fusion ROS2/Humble runtime with M3DGR ROS2 profiles.
EOF

cat >"$PKG_DIR/DEBIAN/postinst" <<'EOF'
#!/usr/bin/env bash
set -e
ldconfig
exit 0
EOF
chmod 0755 "$PKG_DIR/DEBIAN/postinst"

mkdir -p "$OUTPUT_DIR"
DEB_PATH="$OUTPUT_DIR/${PACKAGE_NAME}_${VERSION}_amd64.deb"
dpkg-deb --root-owner-group --build "$PKG_DIR" "$DEB_PATH"
sha256sum "$DEB_PATH" >"${DEB_PATH}.sha256"

echo "Wrote:"
echo "  $DEB_PATH"
echo "  ${DEB_PATH}.sha256"
