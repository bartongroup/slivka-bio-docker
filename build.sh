#!/usr/bin/env bash

# Build script for slivka-bio-docker/Dockerfile
# - Uses the parent directory as build context so COPY paths work
# - Supports BuildKit and optional buildx multi-arch builds
# - Keeps defaults aligned with compose.build.yml

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DOCKERFILE_PATH="$SCRIPT_DIR/Dockerfile"
# Build context is one level up from slivka-bio-docker/
BUILD_CONTEXT="$(cd "$SCRIPT_DIR/.." && pwd)"

# Defaults
IMAGE_TAG="slivka-bio:dev-local"  # matches compose.build.yml
declare -a IMAGE_TAGS=("$IMAGE_TAG")
PLATFORM=""                              # e.g. linux/amd64,linux/arm64
PUSH=false
LOAD=false                      # for single-arch buildx load into local docker
NO_CACHE=false
declare -a BUILD_ARGS=()
BUILD_ARGS_SET=0

usage() {
  cat <<EOF
Usage: $(basename "$0") [options]

Options:
  -t, --tag <name:tag>       Image tag (default: ${IMAGE_TAG}); can be used multiple times
  -p, --platform <list>      Target platform(s) for buildx (e.g. linux/arm64,linux/amd64)
      --push                 Push the image (requires buildx)
      --load                 Load the image into local docker (single-arch buildx)
      --no-cache             Do not use cache
      --build-arg k=v        Add a build-arg (can be used multiple times)
  -h, --help                 Show this help

Examples:
  # Native local build using BuildKit (matches compose.build.yml)
  $(basename "$0")

  # Native local build with an explicit tag
  $(basename "$0") -t slivka-bio:dev-local

  # Multi-platform release candidate build and push
  $(basename "$0") -t drsasp/slivka-bio:installer-rc \
    -p linux/amd64,linux/arm64 --push

  # Promote the same multi-platform build to immutable and latest tags
  $(basename "$0") \
    -t drsasp/slivka-bio:vYYYY.MM.DD \
    -t drsasp/slivka-bio:latest \
    -p linux/amd64,linux/arm64 --push

  # Single-platform buildx build loaded into the local daemon
  $(basename "$0") -t slivka-bio:dev-local -p linux/arm64 --load

Note:
  Docker should pull/use the native platform image by default. Do not use
  this script to create a forced amd64-emulation workflow for Apple Silicon.
EOF
}

# Parse args
while [[ ${1:-} ]]; do
  case "$1" in
    -t|--tag)
      if [[ "${#IMAGE_TAGS[@]}" -eq 1 && "${IMAGE_TAGS[0]}" == "$IMAGE_TAG" ]]; then
        IMAGE_TAGS=()
      fi
      IMAGE_TAGS+=("$2")
      IMAGE_TAG="${IMAGE_TAGS[0]}"
      shift 2;;
    -p|--platform)
      PLATFORM="$2"; shift 2;;
    --push)
      PUSH=true; shift;;
    --load)
      LOAD=true; shift;;
    --no-cache)
      NO_CACHE=true; shift;;
    --build-arg)
      BUILD_ARGS+=("--build-arg" "$2"); BUILD_ARGS_SET=1; shift 2;;
    -h|--help)
      usage; exit 0;;
    *)
      echo "Unknown option: $1" >&2
      usage; exit 1;;
  esac
done

# Preflight checks
command -v docker >/dev/null 2>&1 || { echo "Docker is required but not found in PATH" >&2; exit 1; }

if [[ "$PUSH" == true && "$LOAD" == true ]]; then
  echo "Use either --push or --load, not both" >&2
  exit 1
fi

if [[ "$LOAD" == true && "$PLATFORM" == *,* ]]; then
  echo "--load only supports a single target platform" >&2
  exit 1
fi

if [[ "$PUSH" == true && -z "$PLATFORM" ]]; then
  echo "Refusing to push without --platform. Use -p linux/amd64,linux/arm64 for release images." >&2
  exit 1
fi

[[ -f "$DOCKERFILE_PATH" ]] || { echo "Dockerfile not found at $DOCKERFILE_PATH" >&2; exit 1; }
[[ -d "$BUILD_CONTEXT/slivka-bio-docker" ]] || { echo "Expected directory not found: $BUILD_CONTEXT/slivka-bio-docker" >&2; exit 1; }
[[ -d "$BUILD_CONTEXT/slivka-bio-installer/slivka-bio-installer" ]] || { echo "Expected directory not found: $BUILD_CONTEXT/slivka-bio-installer/slivka-bio-installer" >&2; exit 1; }

# Quick check of required copied files referenced in Dockerfile
[[ -f "$BUILD_CONTEXT/slivka-bio-docker/config.yaml" ]] || { echo "Missing: slivka-bio-docker/config.yaml" >&2; exit 1; }
[[ -f "$BUILD_CONTEXT/slivka-bio-docker/_profiles.yaml" ]] || { echo "Missing: slivka-bio-docker/_profiles.yaml" >&2; exit 1; }
[[ -f "$BUILD_CONTEXT/slivka-bio-docker/scripts/jalview_parser.py" ]] || { echo "Missing: slivka-bio-docker/scripts/jalview_parser.py" >&2; exit 1; }
[[ -f "$BUILD_CONTEXT/slivka-bio-docker/bin/JRonn.sh" ]] || { echo "Missing: slivka-bio-docker/bin/JRonn.sh" >&2; exit 1; }
[[ -f "$BUILD_CONTEXT/slivka-bio-docker/service-patches/jronn-3.1b.service.yaml" ]] || { echo "Missing: slivka-bio-docker/service-patches/jronn-3.1b.service.yaml" >&2; exit 1; }

# Key path info
echo "Dockerfile : $DOCKERFILE_PATH"
echo "Build ctx  : $BUILD_CONTEXT"
if [[ "${#IMAGE_TAGS[@]}" -eq 1 ]]; then
  echo "Image tag  : ${IMAGE_TAGS[0]}"
else
  echo "Image tags :"
  for tag in "${IMAGE_TAGS[@]}"; do
    echo "  - $tag"
  done
fi
if [[ -n "$PLATFORM" ]]; then
  echo "Platforms  : $PLATFORM"
else
  echo "Platforms  : native Docker default"
fi
[[ "$PUSH" == true ]] && echo "Output     : push to registry"
[[ "$LOAD" == true ]] && echo "Output     : load into local Docker daemon"
[[ "$NO_CACHE" == true ]] && echo "Cache      : disabled"

# Decide between docker build and buildx build
USE_BUILDX=false
if [[ -n "$PLATFORM" || "$PUSH" == true || "$LOAD" == true ]]; then
  USE_BUILDX=true
fi

if [[ "$USE_BUILDX" == true ]]; then
  if ! docker buildx version >/dev/null 2>&1; then
    echo "docker buildx is required for --platform/--push/--load" >&2
    exit 1
  fi
  # Ensure a usable builder exists
  if ! docker buildx inspect --builder default >/dev/null 2>&1; then
    echo "Creating and selecting a buildx builder..."
    docker buildx create --name default --use >/dev/null
  fi

  CMD=(docker buildx build -f "$DOCKERFILE_PATH")
  for tag in "${IMAGE_TAGS[@]}"; do
    CMD+=(-t "$tag")
  done
  [[ -n "$PLATFORM" ]] && CMD+=(--platform "$PLATFORM")
  [[ "$PUSH" == true ]] && CMD+=(--push)
  [[ "$LOAD" == true ]] && CMD+=(--load)
  [[ "$NO_CACHE" == true ]] && CMD+=(--no-cache)
  if [[ "$BUILD_ARGS_SET" -eq 1 ]]; then
    CMD+=("${BUILD_ARGS[@]}")
  fi
  CMD+=("$BUILD_CONTEXT")
else
  # Enable BuildKit for better caching even without buildx
  export DOCKER_BUILDKIT=${DOCKER_BUILDKIT:-1}
  CMD=(docker build -f "$DOCKERFILE_PATH")
  for tag in "${IMAGE_TAGS[@]}"; do
    CMD+=(-t "$tag")
  done
  [[ "$NO_CACHE" == true ]] && CMD+=(--no-cache)
  if [[ "$BUILD_ARGS_SET" -eq 1 ]]; then
    CMD+=("${BUILD_ARGS[@]}")
  fi
  CMD+=("$BUILD_CONTEXT")
fi

echo "> ${CMD[*]}"
"${CMD[@]}"

if [[ "${#IMAGE_TAGS[@]}" -eq 1 ]]; then
  echo "Build completed: ${IMAGE_TAGS[0]}"
else
  echo "Build completed with tags: ${IMAGE_TAGS[*]}"
fi
