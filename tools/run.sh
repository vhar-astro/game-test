#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.."
game_godot_bin="${GODOT_BIN:-$PWD/.tools/godot/4.7.2/godot}"
if [[ ! -x "$game_godot_bin" ]]; then
  echo 'Run ./tools/bootstrap_godot.sh first.' >&2
  exit 1
fi
exec "$game_godot_bin" --path "$PWD" "$@"
