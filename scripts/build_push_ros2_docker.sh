#!/usr/bin/env bash
# Build and optionally push the Ultra-Fusion ROS2/Humble runtime image.

set -euo pipefail

VERSION="${ULTRAFUSION_ROS2_VERSION:-0.2.0}"
LOCAL_TAG="${ULTRAFUSION_ROS2_LOCAL_TAG:-ultrafusion-ros2:${VERSION}}"
DOCKERHUB_TAG="${ULTRAFUSION_ROS2_DOCKERHUB_TAG:-maotiandocker/ultrafusion-ros2:${VERSION}}"
ACR_TAG="${ULTRAFUSION_ROS2_ACR_TAG:-registry.cn-hangzhou.aliyuncs.com/bit_robot_image/ultrafusion-ros2:${VERSION}}"
PUSH=0
PUSH_ACR=0

usage() {
  cat <<EOF
Usage: $(basename "$0") [OPTIONS]

Options:
  --push             Push Docker Hub tag after build
  --push-acr         Push Alibaba Cloud ACR tag after build
  --version VERSION  Image version tag, default ${VERSION}
  -h, --help         Show this help message

Environment overrides:
  ULTRAFUSION_ROS2_LOCAL_TAG
  ULTRAFUSION_ROS2_DOCKERHUB_TAG
  ULTRAFUSION_ROS2_ACR_TAG
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --push) PUSH=1; shift ;;
    --push-acr) PUSH_ACR=1; shift ;;
    --version)
      VERSION="${2:?--version requires a value}"
      LOCAL_TAG="ultrafusion-ros2:${VERSION}"
      DOCKERHUB_TAG="maotiandocker/ultrafusion-ros2:${VERSION}"
      ACR_TAG="registry.cn-hangzhou.aliyuncs.com/bit_robot_image/ultrafusion-ros2:${VERSION}"
      shift 2
      ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Unknown option: $1" >&2; usage >&2; exit 1 ;;
  esac
done

docker build -f Dockerfile.ros2 -t "$LOCAL_TAG" .
docker tag "$LOCAL_TAG" "$DOCKERHUB_TAG"
docker tag "$LOCAL_TAG" "$ACR_TAG"

echo "Built:"
echo "  $LOCAL_TAG"
echo "  $DOCKERHUB_TAG"
echo "  $ACR_TAG"

if [[ "$PUSH" -eq 1 ]]; then
  docker push "$DOCKERHUB_TAG"
fi

if [[ "$PUSH_ACR" -eq 1 ]]; then
  docker push "$ACR_TAG"
fi
