# Local contracts

ExplorerPlayer emits noise, attack, resonance, health and death events; the coordinator
applies range/line-of-sight checks and progression effects. SentinelRobot exposes health,
patrol points, player target, hearing and damage, and emits strikes/defeat/alert changes.
GameInterface emits command(action, value); it never mutates world or save state directly.
SaveStore load results explicitly distinguish missing, recovered, invalid and unsupported
profiles. Its can_write_profile preflight protects both active and backup future schemas.
All save snapshots must pass GameSession validation before restore or replacement.

The test runner must complete with ALL_TESTS_OK, exit 0 and no engine errors. tools/check.sh
enforces all three. Linux is the only exported platform. No public network interfaces.
