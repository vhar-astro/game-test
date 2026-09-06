<!--
Sync Impact Report
- Version change: (template, unversioned) → 1.0.0
- Modified principles: none renamed (first ratification)
- Added sections:
  - Core Principles → I. Exhaustive Interrogation Before Delegation (the only principle for now)
  - Question Quota & Coverage Taxonomy
  - Specification Workflow
  - Governance
- Removed sections: template placeholders PRINCIPLE_2..5 (user requested no further principles)
- Templates / commands updated:
  - ✅ .specify/templates/spec-template.md (added Clarifications + Open Questions Ledger sections)
  - ✅ .specify/templates/plan-template.md (Constitution Check gate lists the quota gate)
  - ✅ .claude/skills/speckit-specify/SKILL.md (3-marker cap replaced by constitution quota)
  - ✅ .claude/skills/speckit-clarify/SKILL.md (5-question cap replaced by constitution quota, batching)
  - ✅ .specify/templates/tasks-template.md (no change required: no testing/observability principle)
  - ✅ .specify/templates/checklist-template.md (no change required)
- Follow-up TODOs: none. Additional engineering principles deliberately deferred by the user.
-->
# Game-Test Constitution

## Core Principles

### I. Exhaustive Interrogation Before Delegation

The purpose of this repository is to produce one fine-grained `SPEC.md` for a 3D game that
will be handed to an external code-generation model (GPT-6-Astra) for implementation.
Because the implementing model will not be able to ask us anything, every ambiguity MUST be
resolved by us, interactively, before the spec leaves this repository.

- The specify and clarify phases combined MUST ask the human at least **100 distinct
  questions** (`MIN_QUESTIONS = 100`) per feature spec before the spec may be marked
  ready for planning or export. A question counts once; retries and disambiguation
  follow-ups for the same question do not count.
- Agents MUST NOT silently substitute "reasonable defaults" for game-design decisions.
  A default MAY be proposed as the recommended option, but the human MUST confirm it.
  Anything the human has not confirmed stays in the Open Questions Ledger.
- Every question MUST be answerable in one turn: multiple choice (2 to 5 options, with a
  recommended option first) or a short answer (at most 5 words), so a 100-question session
  remains tractable.
- Every accepted answer MUST be written back into the spec immediately, both as a
  `Q → A` line under `## Clarifications` and as a concrete, testable statement in the
  section it affects.

Rationale: a vibe-coded game built by a model with no back-channel to the designer fails
mostly on unstated intent, not on code. Paying for 100 answers up front is cheaper than
paying for 100 regenerations later. No further engineering principles are adopted at this
time; they may be added by amendment once the spec exists.

## Question Quota & Coverage Taxonomy

The 100-question floor is a minimum, not a target. Questions MUST be spread across the
taxonomy below so the count is not padded from a single category. Each category MUST
receive at least the number of questions in parentheses before the quota is considered
met; the remaining questions go wherever uncertainty is highest.

1. Vision & scope (5): genre, elevator pitch, references, target session length, what is
   explicitly out of scope for v1.
2. Target platform & runtime (6): desktop / web / mobile / console, OS versions, input
   devices, minimum hardware, offline vs online, distribution channel.
3. Engine & technology (6): engine or framework, language, rendering API, asset pipeline,
   build tooling, third-party libraries allowed or forbidden.
4. Camera & controls (8): camera type, follow behaviour, FOV, control scheme per input
   device, remapping, sensitivity, accessibility toggles, gamepad support.
5. Player character & movement (8): move set, speeds, jump/gravity model, collision,
   animations, stamina or resource, states (swim, climb, crouch), death and respawn.
6. Core gameplay loop & mechanics (10): the moment-to-moment loop, win/lose conditions,
   scoring, combat or interaction model, difficulty, progression, economy, crafting,
   inventory, checkpoints.
7. World, levels & environment (8): world size and structure, level count, procedural vs
   authored, biomes, day/night, weather, destructibility, streaming and loading.
8. Entities, enemies & AI (6): enemy roster, behaviours, perception, pathfinding, spawn
   rules, boss or elite encounters.
9. Art direction & rendering (8): visual style, colour palette, lighting model, shadows,
   post-processing, particle budget, LOD strategy, target resolution and frame rate.
10. Audio (5): music style, adaptive music, SFX categories, spatial audio, volume mixing
    and mute behaviour.
11. UI, HUD & menus (7): HUD elements, main menu flow, pause, settings screens, in-game
    prompts, localisation, font and readability rules.
12. Narrative & content (4): story presence, dialogue system, cutscenes, text volume.
13. Multiplayer & networking (4): single vs multi, co-op or competitive, netcode model,
    matchmaking; confirm "none" explicitly if single-player.
14. Persistence & saves (4): save slots, autosave, cloud sync, save-file format and
    versioning.
15. Performance & quality bars (5): frame-rate floor, load-time ceiling, memory budget,
    build size, crash-free target.
16. Testing, telemetry & acceptance (4): how "done" is verified, automated test
    expectations, analytics or crash reporting, playtest acceptance criteria.
17. Project process & delivery (2): repository layout the implementer must follow,
    milestone order, licensing of assets and code.

Minimum category coverage sums to 100. If a category is declared not applicable by the
human (for example "no multiplayer"), that declaration itself counts as the category's
questions being answered, and the freed quota MUST be reassigned to the highest-uncertainty
categories so the 100 total still holds.

## Specification Workflow

- `/speckit-specify` MUST NOT invent defaults for the taxonomy above. It MUST record every
  unconfirmed decision as a `[NEEDS CLARIFICATION: <question>]` marker and mirror each one
  into the spec's `## Open Questions Ledger`. There is no upper limit on markers; the
  3-marker cap of stock Spec Kit is superseded by this constitution.
- `/speckit-clarify` MUST drain the ledger interactively until at least `MIN_QUESTIONS`
  have been accepted and no category in the taxonomy is below its minimum. The stock
  5-question cap is superseded. Questions MAY be presented in numbered batches of up to
  10 per turn to keep the session moving; the human MAY request one at a time.
- The clarify session MAY span several invocations. The running count is stored in the
  spec under `## Clarifications` as `**Questions accepted so far**: N / 100` and MUST be
  updated after each write.
- A spec is **not ready** for `/speckit-plan`, `/speckit-analyze`, or export to GPT-6-Astra
  while the accepted-question count is below 100 or the ledger has open items. Those
  commands MUST refuse and report the shortfall.
- The exported `SPEC.md` handed to GPT-6-Astra MUST contain the full `## Clarifications`
  log so the implementer can see the reasoning behind every decision.

## Governance

This constitution supersedes stock Spec Kit defaults wherever the two conflict, in
particular the question and marker caps in the specify and clarify commands.

- Amendments are made by running `/speckit-constitution` with the proposed change; the
  change MUST be recorded in the Sync Impact Report comment at the top of this file and
  propagated to the templates and skills listed there in the same change.
- Versioning follows semantic versioning: MAJOR for removing or redefining a principle or
  lowering `MIN_QUESTIONS`; MINOR for adding a principle, a taxonomy category, or raising
  a minimum; PATCH for wording and clarification.
- Compliance is checked at every phase gate: `/speckit-plan` Constitution Check MUST show
  the accepted-question count and taxonomy coverage; `/speckit-analyze` treats a shortfall
  as CRITICAL.

**Version**: 1.0.0 | **Ratified**: 2026-09-06 | **Last Amended**: 2026-09-06
