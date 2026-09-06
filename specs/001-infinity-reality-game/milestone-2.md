# Milestone 2 — character and controllable ship

Starts after the owner merged milestone 1. Branch: `002-character-and-ship`.
The existing Ari rig, animations and original ship model form the visual foundation.
This milestone implements accepted Q140–Q145 and the reported broken mouse controls.
The next authored dimension remains a separate review gate.

## Implementation tasks

- [x] Verify merged first-slice main and create a feature branch before editing.
- [x] Keep existing accepted answers, including the headless bpy workflow clarification;
      give that additional clarification its own Q150 identifier.
- [x] Trace mouse events through the HUD; make decorative controls ignore pointer events.
      Correct yaw/pitch hierarchy and use unscaled pointer displacement for both cameras.
- [x] Add the ExplorerShip actor with direct arcade movement, mouse steering, hover,
      vertical movement, visual banking and a collision-aware camera.
- [x] Add boarding and landing handoffs, input guards and clear localized prompts.
      Require level support under the complete footprint, hull/descent clearance and a safe exit.
- [x] Keep one personal ship; leave it parked during foot travel and carry it during flight travel.
      Pause-to-station carries an occupied ship. No ship combat, fuel or upgrades.
- [x] Add a small disconnected observatory terrace using existing concept-approved models.
      Keep on-foot boundary recovery valid on each surface and constrain flight to the local world.
- [x] Version save snapshots to schema 2 with movement mode, ship dimension/transform and
      recovery pose. Migrate validated schema 1 in memory; keep active/backup safeguards.
- [x] Add ship physics/integration tests and native OS mouse regression tooling.
- [x] Complete final headless checks, native Linux export/rendered inspection and 1080p measurement.
- [ ] Commit, publish a PR with screenshots and evidence, verify Actions, leave review open.

## Team and ownership

GPT-6-Astra integrates main/flight/UI/audio and reuses the original Blender assets.
GPT-5.6-Terra owns ship controller/scene, world collision and flight integration tests.
GPT-5.6-Sol owns save migration tests and performs independent read-only review.
GPT-5.6-Luna owns native mouse probes, aggregate test logs and GitHub Actions monitoring.
Luna handles subsequent log troubleshooting. No new source model requires concept generation;
the existing inspected `assets/concepts` boards cover the ship and observatory modules.

## Validation approach

`tools/check.sh` runs deterministic tests and scene smoke checks. Integration fixtures may
stage a position or progression prerequisites, then use public gameplay controls; this is
separate from a human playthrough. `tools/validate_mouse_host.py` injects real X11 events into
one uniquely titled game window and checks camera motion, attack and cursor capture.
`tools/capture_flight.gd` stages rendered screenshots and samples actual 1920×1080 Vulkan
frames. `tools/export.sh` packages Linux; CI imports, tests, exports and smokes the package.
See `docs/MILESTONE-2.md` for the final measured evidence and exact review scope.
