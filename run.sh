#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WORKSPACE="${ROOT}/workspace"
RUNTIME="${ROOT}/runtime"
OUTSIDE_FILE="${RUNTIME}/outside.txt"
OUTPUT_USER_ROOT="${RUNTIME}/output_user_root"

resolve_bazel() {
  if [[ -n "${BAZEL:-}" ]]; then
    printf '%s\n' "${BAZEL}"
  elif command -v bazelisk >/dev/null 2>&1; then
    command -v bazelisk
  elif command -v bazel >/dev/null 2>&1; then
    command -v bazel
  else
    echo "Set BAZEL=/absolute/path/to/bazel or put bazel/bazelisk in PATH." >&2
    exit 1
  fi
}

BAZEL="$(resolve_bazel)"

rm -rf "${RUNTIME}"
mkdir -p "${RUNTIME}"

run_target() {
  local target="$1"
  rm -f "${OUTSIDE_FILE}"

  (
    cd "${WORKSPACE}"
    "${BAZEL}" \
      --output_user_root="${OUTPUT_USER_ROOT}" \
      --batch \
      build \
      --spawn_strategy=darwin-sandbox \
      --sandbox_debug \
      --action_env=ESCAPE_TARGET="${OUTSIDE_FILE}" \
      "${target}"
  )
}

bin_dir() {
  readlink "${WORKSPACE}/bazel-bin"
}

echo "[1/4] running control target"
run_target //:control
cat "$(bin_dir)/control.txt"
test ! -e "${OUTSIDE_FILE}"

echo "[2/4] running injected target"
run_target //:escape
cat "$(bin_dir)/escape.txt"
cat "${OUTSIDE_FILE}"

echo "[3/4] locating injected sandbox profile"
PROFILE="$(find "${OUTPUT_USER_ROOT}" -name sandbox.sb -print | sort | tail -n 1)"
echo "${PROFILE}"
grep -n 'regex ".*"' "${PROFILE}"

echo "[4/4] repro completed"
