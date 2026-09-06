# State and identity

GameSession validates player transforms/health, scene and visited scenes, prism directions,
hint time/step, memory IDs and ordered flags: puzzle → robot → artifact → lock → crystal.
Restore validates the entire snapshot before mutation. Rewards are idempotent. Ruins
requires a crystal; forest and hub remain accessible.

SaveStore profiles 0–2 have JSON envelopes {version,resume,checkpoint}. Both snapshots use
the same schema. Checkpoints precede encounters; resume advances on rewards/transitions/exit.
A validated backup protects atomic replacement. Future schemas cannot be overwritten.
Shared settings are separate from profile progress.

DimensionDefinition, PuzzleDefinition and AbilityDefinition are typed Resources with
checked-in .tres instances for scene/gravity, prism target/hints and resonance cooldown.
The game exposes no network API.
