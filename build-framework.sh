#!/usr/bin/env bash
# Build the upgrade candidate from committed, reviewed release inputs.
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/releases/framework.env"
PLATFORMS=""
PUSH=false
LOAD=false
TAG="slivka-bio:${CANDIDATE_TAG}"
while [[ $# -gt 0 ]]; do
  case "$1" in
    --platform) PLATFORMS="$2"; shift 2;;
    --tag) TAG="$2"; shift 2;;
    --push) PUSH=true; shift;;
    --load) LOAD=true; shift;;
    --help|-h)
      echo "Usage: $0 [--tag IMAGE:TAG] [--platform linux/arm64[,linux/amd64]] [--load|--push]"
      exit 0;;
    *) echo "Unknown option: $1" >&2; exit 1;;
  esac
done
if [[ "$PUSH" == true ]]; then
  [[ "$LOAD" == false && -n "$PLATFORMS" ]] || { echo 'Push requires --platform and cannot use --load.' >&2; exit 1; }
  [[ -z "$(git -C "$SCRIPT_DIR" status --porcelain)" ]] || { echo 'Commit the release inputs before publishing.' >&2; exit 1; }
  [[ "${TAG##*:}" == "$CANDIDATE_TAG" ]] || { echo "Publish only the reviewed candidate tag: $CANDIDATE_TAG" >&2; exit 1; }
  if docker buildx imagetools inspect "$TAG" >/dev/null 2>&1; then
    echo "Refusing to overwrite existing versioned tag: $TAG" >&2; exit 1
  fi
fi
if [[ "$LOAD" == true && "$PLATFORMS" == *,* ]]; then
  echo '--load requires a single platform.' >&2; exit 1
fi
DIRTY=false
[[ -z "$(git -C "$SCRIPT_DIR" status --porcelain)" ]] || DIRTY=true
CMD=(docker buildx build -f "$SCRIPT_DIR/Dockerfile.framework" -t "$TAG"
  --build-arg "BASE_IMAGE=$COMPATIBILITY_IMAGE"
  --build-arg "SLIVKA_FRAMEWORK_REPO=$SLIVKA_FRAMEWORK_REPO"
  --build-arg "SLIVKA_FRAMEWORK_REF=$SLIVKA_FRAMEWORK_REF"
  --build-arg "SLIVKA_FRAMEWORK_VERSION=$SLIVKA_FRAMEWORK_VERSION"
  --build-arg "SLIVKA_BIO_DOCKER_REVISION=$(git -C "$SCRIPT_DIR" rev-parse HEAD)"
  --build-arg "SLIVKA_BIO_DOCKER_DIRTY=$DIRTY")
[[ -z "$PLATFORMS" ]] || CMD+=(--platform "$PLATFORMS")
[[ "$PUSH" == false ]] || CMD+=(--push)
[[ "$LOAD" == false ]] || CMD+=(--load)
CMD+=("$SCRIPT_DIR")
"${CMD[@]}"
