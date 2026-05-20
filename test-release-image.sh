#!/usr/bin/env bash

# Run Slivka service tests against one or more slivka-bio image references.
# The test is intentionally native-platform only: do not set --platform here.

set -u -o pipefail
export DOCKER_CLI_HINTS=false

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR" && pwd)"
OUTPUT_DIR="$PROJECT_DIR/release-tests"
COMPOSE=(docker compose)
KEEP_RUNNING=false
PULL_IMAGE=false
START_TIMEOUT=120

DEFAULT_SERVICES=(
  disembl-1.4
  aacon-1.1
  clustalo-1.2.4
  clustalw-2.1
  globplot-2.3
  jronn-3.1b
  msaprobs-0.9.7
  muscle-3.8.1551
  muscle-5.1
  probcons-1.12
  rnaalifold-2.6.4
  tcoffee-13.41.0
)

usage() {
  cat <<EOF
Usage: $(basename "$0") [options] <image:tag> [image:tag...]

Runs docker compose for each image reference on the native Docker platform, executes
\`slivka test-services <service>\` for each expected service, and writes a
JSON summary under release-tests/<image>/<platform>/.

Options:
  -s, --service <id>       Service to test; can be repeated. Defaults to the release service set.
  -o, --output-dir <path>  Directory for JSON summaries and per-service logs.
                           Default: $OUTPUT_DIR
      --pull               Pull the image before starting compose.
      --keep-running       Leave compose services running after tests finish.
      --timeout <seconds>  Seconds to wait for slivka-bio container startup. Default: $START_TIMEOUT
  -h, --help               Show this help.

Examples:
  $(basename "$0") slivka-bio:dev-local
  $(basename "$0") --pull docker.io/drsasp/slivka-bio:latest
  $(basename "$0") --service clustalo-1.2.4 --service jronn-3.1b slivka-bio:dev-local
EOF
}

declare -a IMAGE_REFS=()
declare -a SERVICES=()

while [[ ${1:-} ]]; do
  case "$1" in
    -s|--service)
      SERVICES+=("$2")
      shift 2
      ;;
    -o|--output-dir)
      OUTPUT_DIR="$2"
      shift 2
      ;;
    --pull)
      PULL_IMAGE=true
      shift
      ;;
    --keep-running)
      KEEP_RUNNING=true
      shift
      ;;
    --timeout)
      START_TIMEOUT="$2"
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    -*)
      echo "Unknown option: $1" >&2
      usage
      exit 1
      ;;
    *)
      IMAGE_REFS+=("$1")
      shift
      ;;
  esac
done

if [[ "${#IMAGE_REFS[@]}" -eq 0 ]]; then
  echo "At least one image reference is required." >&2
  usage
  exit 1
fi

for image_ref in "${IMAGE_REFS[@]}"; do
  image_name="${image_ref##*/}"
  if [[ "$image_name" != *:* ]]; then
    echo "Image reference must include an explicit tag: $image_ref" >&2
    exit 1
  fi
done

if [[ "${#SERVICES[@]}" -eq 0 ]]; then
  SERVICES=("${DEFAULT_SERVICES[@]}")
fi

if [[ -n "${DOCKER_DEFAULT_PLATFORM:-}" ]]; then
  echo "DOCKER_DEFAULT_PLATFORM is set to '$DOCKER_DEFAULT_PLATFORM'." >&2
  echo "Unset it before running native-platform release tests." >&2
  exit 1
fi

command -v docker >/dev/null 2>&1 || { echo "Docker is required but was not found in PATH." >&2; exit 1; }

mkdir -p "$OUTPUT_DIR"

safe_name() {
  printf '%s' "$1" | tr '/:@' '---' | tr -cs 'A-Za-z0-9_.-' '-'
}

compose() {
  (cd "$PROJECT_DIR" && "${COMPOSE[@]}" "$@")
}

compose_down() {
  compose down -v --remove-orphans >/dev/null 2>&1 || true
}

compose_up() {
  # Keep this portable for Docker Compose and podman-compose. The app image is
  # pulled or verified before startup; Compose may still fetch dependencies.
  compose up -d
}

container_id() {
  compose ps -q slivka-bio
}

wait_for_slivka_container() {
  local deadline=$((SECONDS + START_TIMEOUT))
  local cid

  while (( SECONDS < deadline )); do
    cid="$(container_id || true)"
    if [[ -n "$cid" ]]; then
      local running
      running="$(docker inspect "$cid" --format '{{.State.Running}}' 2>/dev/null || true)"
      if [[ "$running" == "true" ]]; then
        return 0
      fi
    fi
    sleep 2
  done

  return 1
}

wait_for_slivka_processes() {
  local deadline=$((SECONDS + START_TIMEOUT))
  local running_count

  while (( SECONDS < deadline )); do
    running_count="$(
      compose exec -T slivka-bio supervisorctl status 2>/dev/null \
        | grep -Ec '^slivka-(server|scheduler|local-queue)[[:space:]]+RUNNING' || true
    )"
    if [[ "$running_count" -eq 3 ]]; then
      return 0
    fi
    sleep 2
  done

  return 1
}

inspect_platform() {
  local image_ref="$1"
  docker image inspect "$image_ref" --format '{{.Os}}/{{.Architecture}}{{if .Variant}}/{{.Variant}}{{end}}' 2>/dev/null || true
}

image_exists() {
  local image_ref="$1"
  docker image inspect "$image_ref" >/dev/null 2>&1
}

run_service_test() {
  local service="$1"

  compose exec -T slivka-bio sh -lc '
    if command -v slivka >/dev/null 2>&1; then
      slivka test-services "$1"
    else
      micromamba run -n slivka-installer slivka test-services "$1"
    fi
  ' sh "$service"
}

service_is_installed() {
  local service="$1"

  compose exec -T slivka-bio test -f "/opt/slivka/services/${service}.service.yaml"
}

classify_service_log() {
  local service="$1"
  local log_file="$2"
  local exit_code="$3"
  local installed="$4"

  if [[ "$installed" != true ]]; then
    printf 'missing\tservice file is not installed\t0\t0\t%s\n' "$exit_code"
    return
  fi

  local ok_count
  local problem_count
  ok_count="$(grep -F "[OK]" "$log_file" 2>/dev/null | grep -Fc "(${service}," || true)"
  problem_count="$(grep -Ec '^\[(FAIL|WARN|N/A)\]' "$log_file" 2>/dev/null || true)"

  if [[ "$problem_count" -gt 0 ]]; then
    printf 'failed\tservice test reported FAIL/WARN/N/A\t%s\t%s\t%s\n' "$ok_count" "$problem_count" "$exit_code"
  elif [[ "$ok_count" -gt 0 ]]; then
    printf 'passed\tservice test reported OK\t%s\t%s\t%s\n' "$ok_count" "$problem_count" "$exit_code"
  else
    printf 'failed\tservice test did not report OK\t%s\t%s\t%s\n' "$ok_count" "$problem_count" "$exit_code"
  fi
}

write_summary() {
  local summary_file="$1"
  local image_ref="$2"
  local tag="$3"
  local platform="$4"
  local status_file="$5"

  python3 - "$summary_file" "$image_ref" "$tag" "$platform" "$status_file" "${SERVICES[@]}" <<'PY'
import json
import sys
from datetime import datetime, timezone

summary_file, image_ref, tag, platform, status_file, *expected = sys.argv[1:]

results = []
passed = []
failed = []
missing = []
installed = []

with open(status_file, encoding="utf-8") as handle:
    for line in handle:
        if not line.strip():
            continue
        item = json.loads(line)
        results.append(item)
        if item.get("installed"):
            installed.append(item["service"])
        if item["status"] == "passed":
            passed.append(item["service"])
        elif item["status"] == "missing":
            missing.append(item["service"])
        else:
            failed.append(item["service"])

summary = {
    "image": image_ref,
    "image_tag": tag,
    "platform": platform or None,
    "tested_at": datetime.now(timezone.utc).isoformat(),
    "expected_services": expected,
    "installed_services": installed,
    "passed_services": passed,
    "failed_services": failed,
    "missing_services": missing,
    "results": results,
}

with open(summary_file, "w", encoding="utf-8") as handle:
    json.dump(summary, handle, indent=2)
    handle.write("\n")
PY
}

overall_status=0

for image_ref in "${IMAGE_REFS[@]}"; do
  image_tag="${image_ref##*:}"
  image_repository="${image_ref%:*}"
  export SLIVKA_BIO_IMAGE="$image_repository"
  export SLIVKA_BIO_TAG="$image_tag"
  run_name="$(safe_name "$image_ref")"

  echo "=== Testing $image_ref ==="

  compose_down

  if [[ "$PULL_IMAGE" == true ]]; then
    echo "Pulling $image_ref"
    if ! docker pull "$image_ref"; then
      echo "Failed to pull $image_ref" >&2
      platform=""
      platform_name="unknown-platform"
      tag_output_dir="$OUTPUT_DIR/$run_name/$platform_name"
      status_file="$tag_output_dir/status.jsonl"
      summary_file="$tag_output_dir/summary.json"
      mkdir -p "$tag_output_dir"
      : > "$status_file"
      overall_status=1
      python3 - "$status_file" "${SERVICES[@]}" <<'PY'
import json
import sys
status_file, *services = sys.argv[1:]
with open(status_file, "a", encoding="utf-8") as handle:
    for service in services:
        handle.write(json.dumps({
            "service": service,
            "status": "failed",
            "exit_code": 1,
            "log": None,
            "error": "image pull failed",
        }) + "\n")
PY
      write_summary "$summary_file" "$image_ref" "$image_tag" "" "$status_file"
      echo "Wrote $summary_file"
      continue
    fi
  elif ! image_exists "$image_ref"; then
    echo "Local image not found: $image_ref" >&2
    echo "Build or tag the image first, or rerun with --pull for registry images." >&2
    overall_status=1
    continue
  fi

  platform="$(inspect_platform "$image_ref")"
  platform_name="$(safe_name "${platform:-unknown-platform}")"
  tag_output_dir="$OUTPUT_DIR/$run_name/$platform_name"
  status_file="$tag_output_dir/status.jsonl"
  summary_file="$tag_output_dir/summary.json"

  mkdir -p "$tag_output_dir"
  : > "$status_file"

  echo "Platform: ${platform:-unknown}"
  echo "Output: $summary_file"

  echo "Starting compose services"
  if ! compose_up; then
    echo "Failed to start compose services for $image_ref" >&2
    overall_status=1
    continue
  fi

  if ! wait_for_slivka_container; then
    echo "slivka-bio container did not start within ${START_TIMEOUT}s" >&2
    compose logs --no-color slivka-bio > "$tag_output_dir/slivka-bio-startup.log" 2>&1 || true
    overall_status=1
  elif ! wait_for_slivka_processes; then
    echo "Slivka supervisor processes did not become ready within ${START_TIMEOUT}s" >&2
    compose logs --no-color slivka-bio > "$tag_output_dir/slivka-bio-startup.log" 2>&1 || true
    overall_status=1
  fi

  for service in "${SERVICES[@]}"; do
    log_file="$tag_output_dir/${service}.log"
    echo "Testing service: $service"

    if service_is_installed "$service"; then
      installed=true
    else
      installed=false
    fi

    run_service_test "$service" > "$log_file" 2>&1
    exit_code=$?
    perl -pi -e 's/[ \t]+$//' "$log_file"
    log_path="${log_file#"$PROJECT_DIR/"}"

    IFS=$'\t' read -r status reason ok_count problem_count recorded_exit_code < <(
      classify_service_log "$service" "$log_file" "$exit_code" "$installed"
    )

    if [[ "$status" != "passed" ]]; then
      overall_status=1
    fi

    python3 - "$status_file" "$service" "$status" "$recorded_exit_code" "$log_path" "$installed" "$reason" "$ok_count" "$problem_count" <<'PY'
import json
import sys
(
    status_file,
    service,
    status,
    exit_code,
    log_file,
    installed,
    reason,
    ok_count,
    problem_count,
) = sys.argv[1:]
with open(status_file, "a", encoding="utf-8") as handle:
    handle.write(json.dumps({
        "service": service,
        "status": status,
        "exit_code": int(exit_code),
        "installed": installed == "true",
        "reason": reason,
        "ok_count": int(ok_count),
        "problem_count": int(problem_count),
        "log": log_file,
    }) + "\n")
PY
  done

  write_summary "$summary_file" "$image_ref" "$image_tag" "$platform" "$status_file"
  echo "Wrote $summary_file"

  if [[ "$KEEP_RUNNING" != true ]]; then
    compose_down
  fi
done

exit "$overall_status"
