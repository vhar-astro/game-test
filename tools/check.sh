#!/usr/bin/env bash
set -euo pipefail

# Run the deterministic, headless validation entrypoint used locally and in CI.

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
repo_dir="$(cd -- "${script_dir}/.." && pwd)"
godot_bin="${GODOT_BIN:-${repo_dir}/.tools/godot/4.7.2/godot}"
godot_data_home="${GODOT_DATA_HOME:-${repo_dir}/.tools/godot/4.7.2/data}"
check_tmp_dir="${CHECK_TMP_DIR:-${repo_dir}/.tools/godot/4.7.2/tmp}"

die() {
	printf 'check: %s\n' "$*" >&2
	exit 1
}

command -v timeout >/dev/null 2>&1 || die "required command not found: timeout"
command -v tee >/dev/null 2>&1 || die "required command not found: tee"
[[ -x "$godot_bin" ]] || die "Godot editor not found at ${godot_bin}; run tools/bootstrap_godot.sh"
[[ -f "$repo_dir/project.godot" ]] || die "project.godot is missing"
[[ -f "$repo_dir/tests/run.gd" ]] || die "tests/run.gd is missing"

export XDG_DATA_HOME="$godot_data_home"
export XDG_CONFIG_HOME="${GODOT_CONFIG_HOME:-${godot_data_home}/config}"
export XDG_CACHE_HOME="${GODOT_CACHE_HOME:-${godot_data_home}/cache}"
cd "$repo_dir"
mkdir -p "$check_tmp_dir"
check_log="$(mktemp "$check_tmp_dir/check.XXXXXX.log")"
trap 'rm -f -- "$check_log"' EXIT

run_godot() {
	timeout --foreground "${GODOT_TIMEOUT_SECONDS:-180}s" "$godot_bin" "$@" 2>&1 | tee -a "$check_log"
	return "${PIPESTATUS[0]}"
}

printf '%s\n' 'Importing project resources'
if ! run_godot --headless --path . --import; then
	die "Godot import exited unsuccessfully"
fi

printf '%s\n' 'Running headless test runner'
if ! run_godot --headless --path . --script tests/run.gd; then
	die "Godot test runner exited unsuccessfully"
fi

if grep -Eq '(^|[[:space:]])(SCRIPT ERROR|ERROR:)' "$check_log"; then
	die "Godot reported SCRIPT ERROR/ERROR; inspect the captured command output"
fi
if ! grep -q '^ALL_TESTS_OK$' "$check_log"; then
	die "test runner did not emit ALL_TESTS_OK"
fi

printf '%s\n' 'Headless checks passed'
