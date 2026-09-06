# Run Infinity Reality

Linux x86_64 with Vulkan graphics is required. Network is needed only to bootstrap
development tools and use GitHub; the game itself is offline.

```bash
./tools/bootstrap_godot.sh
./tools/run.sh
```

Choose one of three profiles and New game. WASD moves, mouse looks, Shift runs, Space
jumps, E interacts, left mouse swings the blade, 1 uses resonance after it is found,
and Escape pauses. Settings include arrow movement, hold-E, inverted look, FOV,
sensitivity, audio volume and English/Russian.

Follow the light through the prism court. E opens the mechanism camera. Rotate prisms
until the beam reaches the receiver; hints appear after 90 seconds. The gate leads to the
sentinel. Defeat it, collect resonance and use it on the marked lock. Collect the crystal
and enter the portal. The station returns you to visited areas. The ship can now be piloted.

## Fly the ship

Approach either side of the ship and press E to board and take off. Mouse movement steers;
W/S flies forward/backward, A/D strafes, Space rises and Ctrl descends. Releasing movement
keys holds position. Arrow-key layout also works in flight. E lands and disembarks when a
wide, level surface and clear exit are available. The HUD explains blocked landings.
Try the separate observatory island west of the forest court. Its open southern terrace
has room for landing. You can walk around it and board again at the same position.

Approach an unlocked portal in flight and press E to carry the ship through. On-foot portal
travel leaves your single ship where you parked it. Pause → station while flying carries
the ship to the station. Flying does not grant puzzle rewards or weapon/ability use.

Escape releases the pointer; Resume captures it again. Switching away from the game pauses
movement. Mouse sensitivity, inversion and FOV apply to both cameras.

Existing schema-1 profiles migrate in memory on Continue; the next save writes schema 2.
Both the current position (including mid-flight hover) and encounter checkpoint are saved.
Newer unsupported save versions remain untouched.

## Validate and export

```bash
./tools/check.sh
./tools/export.sh
./build/infinity-reality/infinity-reality.x86_64
```

Checks reject Godot runtime errors as well as nonzero exit codes. See docs/VALIDATION.md
for measured evidence and limitations. Normal profiles are in Godot user://saves, usually
~/.local/share/godot/app_userdata/Infinity Reality/saves on Linux. Tests use isolated roots.
Settings and rotating local logs are adjacent. No telemetry or online service.

## Rebuild original assets

```bash
~/blender-5.2.1-linux-x64/blender -b -noaudio --factory-startup --python assets/src/build_assets.py
python3 assets/src/build_audio.py
```

Imagegen concepts were inspected before models were built. Their prompts and interpretation
are in assets/concepts/README.md. This slice is one puzzle/robot, not the full four-dimension game.
