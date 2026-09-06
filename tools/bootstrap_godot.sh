#!/usr/bin/env bash
set -euo pipefail

# Reproducible local/CI bootstrap for the standard Godot Linux editor.
# The downloaded files live under .tools/, which is intentionally outside the
# game export and should be ignored by the repository.

readonly GODOT_VERSION="4.7.2"
readonly GODOT_VERSION_ID="4.7.2.stable"
readonly EDITOR_SHA256="cadd3204e728a35d3f13adb7fd0d7902636b79f6b95c40c265eb73b6c35329e4"
readonly TEMPLATES_SHA256="f298490b8d44d934be425a5a65a51bf15f422428b229a06a6e11d9ffea248011"
readonly EDITOR_URL="https://downloads.godotengine.org/?flavor=stable&platform=linux.64&slug=linux.x86_64.zip&version=${GODOT_VERSION}"
readonly TEMPLATES_URL="https://downloads.godotengine.org/?flavor=stable&platform=templates&slug=export_templates.tpz&version=${GODOT_VERSION}"

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
repo_dir="$(cd -- "${script_dir}/.." && pwd)"
tool_root="${GODOT_TOOL_ROOT:-${repo_dir}/.tools/godot/${GODOT_VERSION}}"
cache_dir="${tool_root}/cache"
data_dir="${GODOT_DATA_HOME:-${tool_root}/data}"
editor_archive="${cache_dir}/Godot_v${GODOT_VERSION}-stable_linux.x86_64.zip"
templates_archive="${cache_dir}/Godot_v${GODOT_VERSION}-stable_export_templates.tpz"
godot_bin="${tool_root}/godot"
template_dir="${data_dir}/godot/export_templates/${GODOT_VERSION_ID}"

die() {
	printf 'bootstrap_godot: %s\n' "$*" >&2
	exit 1
}

need_command() {
	command -v "$1" >/dev/null 2>&1 || die "required command not found: $1"
}

verify_sha256() {
	local file="$1"
	local expected="$2"
	local actual
	actual="$(sha256sum "$file" | awk '{print $1}')"
	[[ "$actual" == "$expected" ]] || die "checksum mismatch for ${file##*/}: expected ${expected}, got ${actual}"
}

download_verified() {
	local url="$1"
	local destination="$2"
	local expected="$3"
	local part="${destination}.part"

	if [[ -f "$destination" ]]; then
		# verify_sha256 is fail-closed and calls die on mismatch. Isolate that
		# exit so a corrupt cache is removed and can be downloaded again.
		if (verify_sha256 "$destination" "$expected" 2>/dev/null); then
			return
		fi
		rm -f -- "$destination"
	fi
	printf 'Downloading %s\n' "${destination##*/}"
	local attempt=1
	local curl_status=0
	while (( attempt <= 4 )); do
		# Keep an unverified partial between attempts. HTTP/1.1 avoids the
		# stream cancellation seen on the large export-template transfer, while
		# -C - resumes it when the server supports ranges.
		local resume_args=()
		if [[ -s "$part" ]]; then
			resume_args=(--continue-at -)
		fi
		if curl --fail --location --http1.1 --retry 1 --retry-all-errors --retry-delay 2 \
			--retry-max-time 60 --connect-timeout 30 --max-time 300 \
			"${resume_args[@]}" --output "$part" "$url"; then
			curl_status=0
			break
		else
			curl_status=$?
		fi
		# curl 33 means the server rejected the requested Range. Discard only
		# the unverified partial and retry the same pinned URL from byte zero.
		if (( curl_status == 33 )) && [[ -f "$part" ]]; then
			rm -f -- "$part"
		fi
		if (( attempt == 4 )); then
			die "download failed for ${destination##*/} after ${attempt} attempts (curl ${curl_status})"
		fi
		printf 'Download attempt %d failed for %s (curl %d); retrying\n' "$attempt" "${destination##*/}" "$curl_status" >&2
		sleep 2
		attempt=$((attempt + 1))
		done
	[[ "$curl_status" == 0 ]] || die "download failed for ${destination##*/} (curl ${curl_status})"
	if ! verify_sha256 "$part" "$expected"; then
		# Keep the unverified partial for a later retry, but never promote it.
		return 1
	fi
	mv -- "$part" "$destination"
}

need_command curl
need_command sha256sum
need_command unzip
mkdir -p "$cache_dir" "$tool_root" "$template_dir"

download_verified "$EDITOR_URL" "$editor_archive" "$EDITOR_SHA256"
download_verified "$TEMPLATES_URL" "$templates_archive" "$TEMPLATES_SHA256"

if [[ ! -x "$godot_bin" ]] || ! XDG_DATA_HOME="$data_dir" "$godot_bin" --headless --version 2>/dev/null | grep -q "^${GODOT_VERSION}"; then
	extract_dir="$(mktemp -d "${TMPDIR:-/tmp}/infinity-godot-editor.XXXXXX")"
	trap 'rm -rf -- "$extract_dir"' EXIT
	unzip -q "$editor_archive" -d "$extract_dir"
	editor_source="$(find "$extract_dir" -type f \( -name 'Godot_v*.x86_64' -o -name 'godot.linuxbsd.editor.x86_64' \) -print -quit)"
	[[ -n "$editor_source" ]] || die "Godot editor binary was not found in the archive"
	install -m 0755 "$editor_source" "$godot_bin"
	rm -rf -- "$extract_dir"
	trap - EXIT
fi

# A TPZ is a ZIP with a `templates/` directory and version.txt. Extract into
# the versioned directory only when the release template is not already there.
if [[ ! -x "$template_dir/linux_release.x86_64" ]]; then
	extract_dir="$(mktemp -d "${TMPDIR:-/tmp}/infinity-godot-templates.XXXXXX")"
	trap 'rm -rf -- "$extract_dir"' EXIT
	unzip -q "$templates_archive" -d "$extract_dir"
	rm -rf -- "$template_dir"
	mkdir -p "$template_dir"
	if [[ -d "$extract_dir/templates" ]]; then
		cp -a "$extract_dir/templates/." "$template_dir/"
	else
		cp -a "$extract_dir/." "$template_dir/"
	fi
	[[ -x "$template_dir/linux_release.x86_64" ]] || die "Linux release export template was not found after extraction"
	rm -rf -- "$extract_dir"
	trap - EXIT
fi

printf 'Godot %s ready\n' "$GODOT_VERSION"
printf 'GODOT_BIN=%s\n' "$godot_bin"
printf 'GODOT_DATA_HOME=%s\n' "$data_dir"
