#!/usr/bin/env bash

# Build script for slivka-bio-docker/Dockerfile
# - Uses this repository as the build context
# - Clones slivka-bio-installer from a pinned URL/ref inside the Docker build
# - Supports BuildKit and optional buildx multi-arch builds
# - Keeps defaults aligned with compose.build.yml

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DOCKERFILE_PATH="$SCRIPT_DIR/Dockerfile"
BUILD_CONTEXT="$SCRIPT_DIR"

# Defaults
IMAGE_TAG="slivka-bio:dev-local"  # matches compose.build.yml
declare -a IMAGE_TAGS=("$IMAGE_TAG")
PLATFORM=""                              # e.g. linux/amd64,linux/arm64
PUSH=false
LOAD=false                      # for single-arch buildx load into local docker
NO_CACHE=false
declare -a BUILD_ARGS=()
BUILD_ARGS_SET=0
INSTALLER_OVERRIDE=false
SLIVKA_BIO_INSTALLER_REPO=""
SLIVKA_BIO_INSTALLER_REF=""

usage() {
  cat <<EOF
Usage: $(basename "$0") [options]

Options:
  -t, --tag <name:tag>       Image tag (default: ${IMAGE_TAG}); can be used multiple times
  -p, --platform <list>      Target platform(s) for buildx (e.g. linux/arm64,linux/amd64)
      --push                 Push the image (requires buildx)
      --load                 Load the image into local docker (single-arch buildx)
      --no-cache             Do not use cache
      --installer-repo <url>  Installer repository URL
      --installer-ref <ref>   Installer commit, tag, or branch
      --build-arg k=v        Add a build-arg (can be used multiple times)
  -h, --help                 Show this help

Examples:
  # Native local build using BuildKit (matches compose.build.yml)
  $(basename "$0")

  # Native local build with an explicit tag
  $(basename "$0") -t slivka-bio:dev-local

  # Build against a different installer fork/ref
  $(basename "$0") \
    --installer-repo https://github.com/example/slivka-bio-installer.git \
    --installer-ref feature-branch

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
    --installer-repo)
      SLIVKA_BIO_INSTALLER_REPO="$2"; INSTALLER_OVERRIDE=true; shift 2;;
    --installer-ref)
      SLIVKA_BIO_INSTALLER_REF="$2"; INSTALLER_OVERRIDE=true; shift 2;;
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

if [[ "$PUSH" == true && "$INSTALLER_OVERRIDE" == true ]]; then
  echo "Refusing to push with --installer-repo/--installer-ref overrides." >&2
  echo "For release builds, update the pinned installer ARGs in Dockerfile and commit them." >&2
  exit 1
fi

[[ -f "$DOCKERFILE_PATH" ]] || { echo "Dockerfile not found at $DOCKERFILE_PATH" >&2; exit 1; }

DEFAULT_INSTALLER_REPO="$(sed -n 's/^ARG SLIVKA_BIO_INSTALLER_REPO=//p' "$DOCKERFILE_PATH" | head -n 1)"
DEFAULT_INSTALLER_REF="$(sed -n 's/^ARG SLIVKA_BIO_INSTALLER_REF=//p' "$DOCKERFILE_PATH" | head -n 1)"
[[ -n "$DEFAULT_INSTALLER_REPO" ]] || { echo "Missing SLIVKA_BIO_INSTALLER_REPO ARG in Dockerfile" >&2; exit 1; }
[[ -n "$DEFAULT_INSTALLER_REF" ]] || { echo "Missing SLIVKA_BIO_INSTALLER_REF ARG in Dockerfile" >&2; exit 1; }

GIT_REVISION="unknown"
GIT_SOURCE="unknown"
GIT_DIRTY="unknown"
if git -C "$SCRIPT_DIR" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  GIT_REVISION="$(git -C "$SCRIPT_DIR" rev-parse HEAD)"
  GIT_SOURCE="$(git -C "$SCRIPT_DIR" config --get remote.origin.url || true)"
  [[ -n "$GIT_SOURCE" ]] || GIT_SOURCE="unknown"
  if [[ -n "$(git -C "$SCRIPT_DIR" status --porcelain)" ]]; then
    GIT_DIRTY=true
  else
    GIT_DIRTY=false
  fi
fi

if [[ "$PUSH" == true && "$GIT_DIRTY" == true ]]; then
  echo "Refusing to push from a dirty working tree." >&2
  echo "Commit or stash local changes before creating a release image." >&2
  exit 1
fi

# Quick check of required copied files referenced in Dockerfile
[[ -f "$BUILD_CONTEXT/config.yaml" ]] || { echo "Missing: config.yaml" >&2; exit 1; }
[[ -f "$BUILD_CONTEXT/service-patches/_profiles.yaml" ]] || { echo "Missing: _profiles.yaml" >&2; exit 1; }
[[ -f "$BUILD_CONTEXT/scripts/jalview_parser.py" ]] || { echo "Missing: scripts/jalview_parser.py" >&2; exit 1; }
[[ -f "$BUILD_CONTEXT/bin/JRonn.sh" ]] || { echo "Missing: bin/JRonn.sh" >&2; exit 1; }
[[ -f "$BUILD_CONTEXT/service-patches/jronn-3.1b.service.yaml" ]] || { echo "Missing: service-patches/jronn-3.1b.service.yaml" >&2; exit 1; }

# Key path info
echo "Dockerfile : $DOCKERFILE_PATH"
echo "Build ctx  : $BUILD_CONTEXT"
echo "Source     : $GIT_SOURCE"
echo "Revision   : $GIT_REVISION"
echo "Dirty      : $GIT_DIRTY"
if [[ "$INSTALLER_OVERRIDE" == true ]]; then
  echo "Installer  : ${SLIVKA_BIO_INSTALLER_REPO:-$DEFAULT_INSTALLER_REPO}"
  echo "Installer ref: ${SLIVKA_BIO_INSTALLER_REF:-$DEFAULT_INSTALLER_REF}"
else
  echo "Installer  : Dockerfile default ($DEFAULT_INSTALLER_REPO)"
  echo "Installer ref: Dockerfile default ($DEFAULT_INSTALLER_REF)"
fi
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
  [[ -n "$SLIVKA_BIO_INSTALLER_REPO" ]] && CMD+=(--build-arg "SLIVKA_BIO_INSTALLER_REPO=$SLIVKA_BIO_INSTALLER_REPO")
  [[ -n "$SLIVKA_BIO_INSTALLER_REF" ]] && CMD+=(--build-arg "SLIVKA_BIO_INSTALLER_REF=$SLIVKA_BIO_INSTALLER_REF")
  CMD+=(--build-arg "SLIVKA_BIO_DOCKER_REVISION=$GIT_REVISION")
  CMD+=(--build-arg "SLIVKA_BIO_DOCKER_SOURCE=$GIT_SOURCE")
  CMD+=(--build-arg "SLIVKA_BIO_DOCKER_DIRTY=$GIT_DIRTY")
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
  [[ -n "$SLIVKA_BIO_INSTALLER_REPO" ]] && CMD+=(--build-arg "SLIVKA_BIO_INSTALLER_REPO=$SLIVKA_BIO_INSTALLER_REPO")
  [[ -n "$SLIVKA_BIO_INSTALLER_REF" ]] && CMD+=(--build-arg "SLIVKA_BIO_INSTALLER_REF=$SLIVKA_BIO_INSTALLER_REF")
  CMD+=(--build-arg "SLIVKA_BIO_DOCKER_REVISION=$GIT_REVISION")
  CMD+=(--build-arg "SLIVKA_BIO_DOCKER_SOURCE=$GIT_SOURCE")
  CMD+=(--build-arg "SLIVKA_BIO_DOCKER_DIRTY=$GIT_DIRTY")
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
