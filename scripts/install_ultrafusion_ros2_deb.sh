#!/usr/bin/env bash
# Download and install the Ultra-Fusion ROS2/Humble release .deb.
#
# Usage:
#   ./scripts/install_ultrafusion_ros2_deb.sh
#   ./scripts/install_ultrafusion_ros2_deb.sh --mirror
#   ./scripts/install_ultrafusion_ros2_deb.sh --deb /path/to/ultrafusion-ros2_0.2.0_amd64.deb

set -euo pipefail

VERSION="${ULTRAFUSION_ROS2_VERSION:-0.2.0}"
DEB_NAME="${ULTRAFUSION_ROS2_DEB_NAME:-ultrafusion-ros2_${VERSION}_amd64.deb}"
TAG="${ULTRAFUSION_ROS2_RELEASE_TAG:-v${VERSION}}"
GITHUB_REPO="${ULTRAFUSION_GITHUB_REPO:-sjtuyinjie/Ultra-Fusion}"
GITHUB_URL="${ULTRAFUSION_ROS2_GITHUB_URL:-https://github.com/${GITHUB_REPO}/releases/download/${TAG}/${DEB_NAME}}"
MIRROR_URL="${ULTRAFUSION_ROS2_MIRROR_URL:-http://47.100.60.229:8088/loc_map/releases/ultrafusion/${DEB_NAME}}"
SHA256="${ULTRAFUSION_ROS2_SHA256:-0a589e6f739038e3e2fa83d6d444d0d84b638854114bc8f8d7f7ac4b2a1dd225}"

USE_MIRROR=0
LOCAL_DEB=""

usage() {
  cat <<EOF
Usage: $(basename "$0") [OPTIONS]

Download and install the Ultra-Fusion ROS2/Humble release package.

Options:
  --mirror          Download from the project mirror instead of GitHub Releases
  --deb PATH        Install a local .deb file (skip download)
  --sha256 HASH     Verify the package with this SHA256 checksum
  -h, --help        Show this help message

Environment overrides:
  ULTRAFUSION_ROS2_VERSION
  ULTRAFUSION_ROS2_DEB_NAME
  ULTRAFUSION_ROS2_RELEASE_TAG
  ULTRAFUSION_ROS2_GITHUB_URL
  ULTRAFUSION_ROS2_MIRROR_URL
  ULTRAFUSION_ROS2_SHA256
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --mirror) USE_MIRROR=1; shift ;;
    --deb) LOCAL_DEB="${2:?--deb requires a path}"; shift 2 ;;
    --sha256) SHA256="${2:?--sha256 requires a hash}"; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Unknown option: $1" >&2; usage >&2; exit 1 ;;
  esac
done

if [[ "$(id -u)" -ne 0 ]]; then
  SUDO="sudo"
else
  SUDO=""
fi

if [[ -n "$LOCAL_DEB" ]]; then
  DEB_PATH="$LOCAL_DEB"
  if [[ ! -f "$DEB_PATH" ]]; then
    echo "Error: deb not found: $DEB_PATH" >&2
    exit 1
  fi
else
  DEB_PATH="$(mktemp /tmp/ultrafusion-ros2.XXXXXX.deb)"
  trap 'rm -f "$DEB_PATH"' EXIT

  if [[ "$USE_MIRROR" -eq 1 ]]; then
    URL="$MIRROR_URL"
    echo "Downloading from mirror: $URL"
  else
    URL="$GITHUB_URL"
    echo "Downloading from GitHub Releases: $URL"
  fi

  if command -v wget >/dev/null 2>&1; then
    wget -O "$DEB_PATH" "$URL"
  elif command -v curl >/dev/null 2>&1; then
    curl -fsSL -o "$DEB_PATH" "$URL"
  else
    echo "Error: wget or curl is required." >&2
    exit 1
  fi
fi

if [[ -n "$SHA256" ]]; then
  echo "Verifying SHA256 checksum..."
  echo "${SHA256}  ${DEB_PATH}" | sha256sum -c -
else
  echo "Warning: no SHA256 checksum configured; skipping checksum verification." >&2
fi

echo "Installing ${DEB_PATH} ..."
$SUDO dpkg -i "$DEB_PATH" || true
$SUDO apt-get install -f -y

echo ""
echo "Ultra-Fusion ROS2 v${VERSION} installed."
echo "  Binary : uf_node  (/opt/ultrafusion/bin/uf_node)"
echo "  Configs: /opt/ultrafusion/config/"
echo "  RViz   : rviz2 -d /opt/ultrafusion/rviz/lio_ros2.rviz"
echo ""
echo "Quick test:"
echo "  source /opt/ros/humble/setup.bash"
echo "  uf_node /opt/ultrafusion/config/m3dgr/uf_m3dgr_ros2_lvwio.yaml"
