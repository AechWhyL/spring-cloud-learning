#!/usr/bin/env bash

set -euo pipefail
SEATA_VERSION=2.5.0

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
IMAGE="${SEATA_IMAGE:-apache/seata-server:${SEATA_VERSION}}"
CONTAINER_NAME="${SEATA_TEMP_CONTAINER_NAME:-seata-150-config-exporter-$$}"
CONTAINER_PATH="${SEATA_CONTAINER_RESOURCES_PATH:-/seata-server/resources}"
OUTPUT_DIR="${SEATA_OUTPUT_DIR:-${SCRIPT_DIR}/seata-server-${SEATA_VERSION}-resources}"
FORCE_OVERWRITE="${FORCE_OVERWRITE:-0}"
STARTUP_WAIT_SECONDS="${STARTUP_WAIT_SECONDS:-20}"

cleanup() {
  if docker ps -a --format '{{.Names}}' | grep -Fxq "${CONTAINER_NAME}"; then
    docker rm -f "${CONTAINER_NAME}" >/dev/null 2>&1 || true
  fi
}

log() {
  printf '[seata-export] %s\n' "$*"
}

require_command() {
  if ! command -v "$1" >/dev/null 2>&1; then
    printf 'Missing required command: %s\n' "$1" >&2
    exit 1
  fi
}

wait_for_container_running() {
  local elapsed=0
  local status

  while (( elapsed < STARTUP_WAIT_SECONDS )); do
    status="$(docker inspect -f '{{.State.Status}}' "${CONTAINER_NAME}" 2>/dev/null || true)"
    if [[ "${status}" == "running" ]]; then
      return 0
    fi
    if [[ "${status}" == "exited" || "${status}" == "dead" ]]; then
      docker logs "${CONTAINER_NAME}" >&2 || true
      printf 'Temporary container exited before config export completed.\n' >&2
      exit 1
    fi
    sleep 1
    elapsed=$((elapsed + 1))
  done

  docker logs "${CONTAINER_NAME}" >&2 || true
  printf 'Timed out waiting for container to reach running state after %s seconds.\n' "${STARTUP_WAIT_SECONDS}" >&2
  exit 1
}

prepare_output_dir() {
  if [[ -e "${OUTPUT_DIR}" && "${FORCE_OVERWRITE}" != "1" ]]; then
    printf 'Output path already exists: %s\n' "${OUTPUT_DIR}" >&2
    printf 'Set FORCE_OVERWRITE=1 to replace it.\n' >&2
    exit 1
  fi

  rm -rf "${OUTPUT_DIR}"
  mkdir -p "${OUTPUT_DIR}"
}

main() {
  require_command docker
  trap cleanup EXIT

  if docker ps -a --format '{{.Names}}' | grep -Fxq "${CONTAINER_NAME}"; then
    printf 'Container name already exists: %s\n' "${CONTAINER_NAME}" >&2
    printf 'Set SEATA_TEMP_CONTAINER_NAME to another value and retry.\n' >&2
    exit 1
  fi

  prepare_output_dir

  log "Starting temporary container ${CONTAINER_NAME} from ${IMAGE}"
  docker run -d --name "${CONTAINER_NAME}" "${IMAGE}" >/dev/null

  log "Waiting for container to become ready enough for export"
  wait_for_container_running

  log "Copying ${CONTAINER_PATH} to ${OUTPUT_DIR}"
  docker cp "${CONTAINER_NAME}:${CONTAINER_PATH}/." "${OUTPUT_DIR}"

  log "Export completed"
  log "Files are available in ${OUTPUT_DIR}"
}

main "$@"
