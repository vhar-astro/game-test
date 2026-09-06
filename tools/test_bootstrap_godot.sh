#!/usr/bin/env bash
set -euo pipefail

# Exercise download_verified without downloading the pinned Godot archives.
# The fake curl models a dropped transfer, a resumable Range request and a
# successful full response; the helper itself still performs real SHA checks.
script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
repo_dir="$(cd -- "${script_dir}/.." && pwd)"
test_root="$(mktemp -d "${TMPDIR:-/tmp}/bootstrap-godot-test.XXXXXX")"
trap 'rm -rf -- "$test_root"' EXIT

fake_bin="$test_root/bin"
mkdir -p "$fake_bin"
cat > "$fake_bin/curl" <<'FAKE_CURL'
#!/usr/bin/env bash
set -euo pipefail
output=""
has_resume=false
while (($#)); do
  case "$1" in
    --output) output="$2"; shift 2 ;;
    --continue-at) has_resume=true; shift 2 ;;
    *) shift ;;
  esac
done
count_file="${FAKE_CURL_COUNT_FILE:?}"
count=0
if [[ -f "$count_file" ]]; then count="$(<"$count_file")"; fi
count=$((count + 1))
printf '%s' "$count" > "$count_file"
case "${FAKE_CURL_SCENARIO:?}" in
  resume)
    if (( count == 1 )); then
      printf 'abcde' > "$output"
      exit 92
    fi
    [[ "$has_resume" == true ]] || exit 21
    printf 'fghij' >> "$output"
    ;;
  fresh)
    printf 'abcdefghij' > "$output"
    ;;
  range_rejected)
    if [[ "$has_resume" == true ]]; then
      exit 33
    fi
    printf 'abcdefghij' > "$output"
    ;;
  mismatch)
    printf 'wrong-data' > "$output"
    ;;
  *) exit 22 ;;
esac
FAKE_CURL
chmod +x "$fake_bin/curl"

# Keep this test coupled to the production helper bodies without sourcing the
# bootstrap entrypoint, which would otherwise download the real archives.
helper_source="$(sed -n '/^die()/,/^}/p' "$repo_dir/tools/bootstrap_godot.sh")
$(sed -n '/^verify_sha256()/,/^}/p' "$repo_dir/tools/bootstrap_godot.sh")
$(sed -n '/^download_verified()/,/^}/p' "$repo_dir/tools/bootstrap_godot.sh")"
eval "$helper_source"

expected="$(printf 'abcdefghij' | sha256sum | awk '{print $1}')"

resume_destination="$test_root/resume.bin"
FAKE_CURL_SCENARIO=resume FAKE_CURL_COUNT_FILE="$test_root/resume.count" PATH="$fake_bin:$PATH" \
  download_verified "https://example.invalid/resume" "$resume_destination" "$expected"
[[ "$(<"$resume_destination")" == abcdefghij && ! -e "$resume_destination.part" ]]

fresh_destination="$test_root/fresh.bin"
printf 'corrupt-cache' > "$fresh_destination"
FAKE_CURL_SCENARIO=fresh FAKE_CURL_COUNT_FILE="$test_root/fresh.count" PATH="$fake_bin:$PATH" \
  download_verified "https://example.invalid/fresh" "$fresh_destination" "$expected"
[[ "$(<"$fresh_destination")" == abcdefghij && ! -e "$fresh_destination.part" ]]

range_destination="$test_root/range.bin"
printf 'abcde' > "$range_destination.part"
FAKE_CURL_SCENARIO=range_rejected FAKE_CURL_COUNT_FILE="$test_root/range.count" PATH="$fake_bin:$PATH" \
  download_verified "https://example.invalid/range" "$range_destination" "$expected"
[[ "$(<"$range_destination")" == abcdefghij && ! -e "$range_destination.part" ]]

mismatch_destination="$test_root/mismatch.bin"
if (FAKE_CURL_SCENARIO=mismatch FAKE_CURL_COUNT_FILE="$test_root/mismatch.count" PATH="$fake_bin:$PATH" \
  download_verified "https://example.invalid/mismatch" "$mismatch_destination" "$expected"); then
  printf '%s\n' 'bootstrap test expected checksum failure' >&2
  exit 1
fi
[[ ! -e "$mismatch_destination" && -e "$mismatch_destination.part" ]]

printf '%s\n' 'BOOTSTRAP_DOWNLOAD_TEST_OK'
