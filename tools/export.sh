#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.."
game_godot_bin="${GODOT_BIN:-$PWD/.tools/godot/4.7.2/godot}"
game_data_home="${GODOT_DATA_HOME:-$PWD/.tools/godot/4.7.2/data}"
mkdir -p build/infinity-reality
XDG_DATA_HOME="$game_data_home" "$game_godot_bin" --headless --path "$PWD" --export-release "Linux/X11" "$PWD/build/infinity-reality/infinity-reality.x86_64"
cp LICENSE ASSET_LICENSE.md THIRD_PARTY.md build/infinity-reality/
cp assets/fonts/LICENSE.txt build/infinity-reality/FONT_LICENSE.txt
cp docs/licenses/GODOT_LICENSE.txt docs/licenses/GODOT_COPYRIGHT.json docs/licenses/GODOT_LICENSES.json build/infinity-reality/
tar -czf build/infinity-reality-linux-x86_64.tar.gz -C build infinity-reality
