# PILLARS Prompt 003 — Round Lifecycle Design

## Scope

Prompt 003 replaces temporary join-time spawning with the first reusable, server-authoritative round lifecycle:

`WAITING → COUNTDOWN → STARTING → ACTIVE → ENDING → WAITING`

The system selects participants, performs a fresh unbiased shuffle every round, assigns and spawns players through `PlayerSpawnService`, tracks living participants, determines a winner or no-winner result, cleans the round, and repeats. It does not add lobby characters, spectators, combat, items, cover, expansion, Artifacts, storm, UI, progression, or other later systems.

## Ownership and Existing-System Integration

`RoundService` becomes the sole production owner of:

- deciding which connected players participate;
- starting and cancelling countdowns;
- assigning and spawning participants;
- tracking round participants and living players;
- detecting round completion;
- clearing assignments and characters between rounds.

`PlayerSpawnService` remains unchanged in responsibility. It owns the authoritative gameplay-context player-to-pillar and pillar-to-player maps, resolves existing arena spawn markers, controls character loading and positioning, releases individual assignments, and clears all assignments.

The temporary `DevelopmentSpawnBootstrap` and its bootstrap-specific test are removed so no second component can automatically assign or spawn on join. `Players.CharacterAutoLoads` remains `false`, but production ownership of that setting moves to `RoundService` startup. `StudioAssignmentDiagnostics` remains stateless, is reused by round startup, and receives a focused test independent of the removed bootstrap.

`ArenaService` continues to generate the arena before `RoundService` starts. No Rojo mappings or arena geometry change.

## Modules

### `RoundConfig`

A frozen configuration table centralizes:

- `MIN_PLAYERS = 2`
- `COUNTDOWN_DURATION = 5`
- `END_ROUND_DELAY = 3`
- a short waiting eligibility-check interval for the prototype

Tests provide a copied configuration with short deterministic durations; production constants are not mutated.

### `RoundState`

A frozen table defines `WAITING`, `COUNTDOWN`, `STARTING`, `ACTIVE`, and `ENDING`. It also owns transition validation.

Allowed transitions are intentionally limited to:

- `WAITING → COUNTDOWN`
- `COUNTDOWN → STARTING`
- `COUNTDOWN → WAITING` when eligibility drops below the minimum
- `STARTING → ACTIVE`
- `STARTING → WAITING` when setup aborts
- `ACTIVE → ENDING`
- `ENDING → WAITING`

Self-transitions and all other transitions are rejected. Initial construction begins in `WAITING` without treating that initialization as a transition.

### `RoundShuffle`

`RoundShuffle.ShuffledCopy(players, random)` copies the participant list and applies an in-place Fisher–Yates shuffle to the copy using the supplied `Random`-compatible source. The caller's list is not mutated.

Production supplies a server-created `Random` instance. Tests supply deterministic `NextInteger` results. Every round invokes the shuffle again. The shuffle is unbiased and has no anti-repeat behavior, so a returning participant may legitimately receive the same pillar in consecutive rounds.

### `RoundController`

`RoundController` owns one round state machine and all per-round state. It receives only the narrow dependencies needed for deterministic testing:

- eligible-player provider;
- time/wait function;
- random source;
- `PlayerSpawnService` interface;
- round configuration.

The production controller uses actual Roblox services and the real `PlayerSpawnService`. Tests use controlled eligible-player lists and time/random sources while retaining real arena geometry, character Models, Humanoids, death signals, and the real spawn service wherever spawning behavior is under test.

The controller exposes read-only queries suitable for other gameplay-server modules and future adapters, such as current state, alive count, participant membership, and current winner. No client communication is added.

### `RoundService`

`RoundService` creates and owns exactly one production `RoundController`. Its idempotent `Start()` method:

1. sets `Players.CharacterAutoLoads = false`;
2. connects one server-session `Players.PlayerRemoving` listener;
3. starts exactly one lifecycle coroutine.

`RoundService` supplies `Players:GetPlayers()`, `task.wait`, `Random.new()`, `RoundConfig`, and the real `PlayerSpawnService`. The server entry point generates the arena and starts `RoundService`; it no longer starts `DevelopmentSpawnBootstrap`.

## State and Round Data

The controller keeps session control separate from round data.

Session control consists of:

- a `_running` guard that prevents a second lifecycle coroutine;
- a monotonically increasing round generation;
- the current `RoundState`.

Per-round data consists of:

- selected players for the current generation;
- successfully spawned participants;
- alive-set membership;
- expected pillar index per participant;
- exact character Model per participant;
- Humanoid death connections;
- winner, if any;
- a cleanup guard for the generation.

Players who join after selection begins are absent from the selected snapshot and all current-round tables. They receive no assignment and no character during `STARTING`, `ACTIVE`, or `ENDING`. Because eligibility is collected again after returning to `WAITING`, they can participate in a later round.

## Lifecycle

### WAITING

`WAITING` contains no round assignments or participant characters. The controller checks the current eligible-player provider at a short configurable interval without logging each check.

Eligibility currently means a player returned by the provider whose direct parent is the `Players` service. No lobby, ready status, or persistence exists yet.

While fewer than `MIN_PLAYERS` are eligible, the controller stays in `WAITING`. It does not assign pillars or spawn characters. Once the threshold is reached, it transitions to `COUNTDOWN`.

### COUNTDOWN

The countdown logs the state and remaining whole seconds. After every wait, the controller verifies both its generation/state token and current eligible-player count.

If eligibility falls below `MIN_PLAYERS`, the controller intentionally transitions `COUNTDOWN → WAITING`. It creates no assignments or characters. Otherwise, completion transitions to `STARTING`.

Players joining during the countdown may be included because participant selection has not happened yet. Players joining once `STARTING` begins are deferred to a future round.

### STARTING

Setup performs these operations in order:

1. Increment and capture a new round generation.
2. Clear any previous `PlayerSpawnService` assignments.
3. Collect one eligible-player snapshot.
4. Take at most the first `ArenaConfig.PLAYER_COUNT` players from that snapshot.
5. Create a fresh shuffled copy.
6. Assign shuffled players sequentially through `PlayerSpawnService`, causing randomized pillar ownership.
7. Spawn assigned players sequentially at their existing marker transforms.
8. For each successful living spawn, record the participant, expected pillar, exact character, and alive membership, then connect a generation-scoped `Humanoid.Died` listener.
9. Revalidate every pending living participant before entering `ACTIVE`.

Sequential spawning keeps cancellation and partial failure understandable at the eight-player limit. No pillar is reused during setup after a participant dies; all round assignments are cleared during abort or normal ending cleanup.

An assignment or spawn failure releases that player's assignment and excludes them from the valid participant set. A player who disconnects during setup is likewise released and excluded. Setup continues for the remaining selected players. If at least `MIN_PLAYERS` valid living participants remain after final validation, the round enters `ACTIVE`; otherwise setup performs complete partial cleanup and intentionally transitions `STARTING → WAITING` without an ending delay.

Final pre-active validation requires every remaining participant to:

- still be directly connected;
- still reference the exact recorded round character through `Player.Character`;
- have that character still parented;
- have a living Humanoid;
- still own the recorded pillar according to `PlayerSpawnService`.

Invalid entries are idempotently removed from pending alive state. Disconnected or assignment-invalid players are released. Their recorded characters remain cleanup-owned and are removed during abort cleanup.

### Death During STARTING

Death listeners accept callbacks during both `STARTING` and `ACTIVE` when the callback generation matches the current round.

During `STARTING`, a death removes the player from pending alive state exactly once and logs a setup-participant loss. It does not evaluate a winner or transition to `ENDING`. Final setup validation determines whether enough valid living players remain.

A nearly simultaneous death and disconnect cannot process the player twice because alive-set removal is the idempotency gate.

### ACTIVE

On entry, every remaining validated participant is alive. The controller immediately evaluates the count defensively, then waits for death or player-removal events rather than polling every frame.

During `ACTIVE`, the first valid elimination removes one alive-set entry and logs the player and remaining count. Duplicate death events, stale characters, generation-mismatched callbacks, and death-after-cleanup callbacks do nothing.

When exactly one alive participant remains, that player is recorded as the winner and the controller transitions to `ENDING`. When zero remain, the winner is `nil` and the controller transitions safely to `ENDING`. Death by any cause is equivalent; kill attribution is outside this phase.

### Player Removal

`RoundService` forwards the single session-level `PlayerRemoving` event to the controller.

- `WAITING`: no round work is required.
- `COUNTDOWN`: the next eligibility check cancels if the count is now insufficient.
- `STARTING`: the player is idempotently removed from pending alive state, any assignment is released, and setup continues or later aborts based on final validation.
- `ACTIVE`: the player is idempotently eliminated, their assignment is released, and the normal win condition is evaluated.
- `ENDING`: their assignment is released without changing the already-recorded result.

Non-participants never enter elimination handling. Players who join during `STARTING`, `ACTIVE`, or `ENDING` are not assigned, spawned, or added to current-round state.

### ENDING

`ENDING` records and logs the winner or a no-winner result, then waits `END_ROUND_DELAY`. Death callbacks during `ENDING` do not change the result because elimination accepts only `STARTING` and `ACTIVE`, and winner evaluation accepts only `ACTIVE`.

After the delay, cleanup runs once and transitions to `WAITING`. If enough players remain connected, the normal waiting check begins another countdown.

## Cancellation and Concurrency Safety

The lifecycle uses one coroutine rather than detached countdown or round-start tasks. `Start()` returns without creating another loop when already running.

Every asynchronous continuation captures the current round generation and validates the generation plus expected state before mutating round data. This prevents an old countdown, spawn completion, death callback, or ending delay from advancing a later round.

Assignment and alive-set mutations do not yield. Alive-set membership is the single elimination gate, so death and disconnect races remove at most one living participant. `PlayerSpawnService` retains its per-player concurrent-spawn and leave-during-load safeguards.

Cleanup has a per-generation guard. A second request to clean the same generation is a no-op.

## Cleanup

Both normal ending cleanup and aborted setup cleanup use the same operation, with only the state transition destination differing.

Cleanup order is:

1. Mark the generation as cleaning up.
2. Disconnect every round-specific Humanoid death listener.
3. Destroy only the exact character Models recorded for this round and still parented.
4. Clear all `PlayerSpawnService` assignments.
5. Clear selected, participant, alive, expected-pillar, character, listener, and winner data.

Listeners are disconnected before characters are destroyed, so destruction cannot generate elimination work. Characters created outside the recorded round map are not destroyed. Cleanup leaves connected players characterless during `WAITING` and `COUNTDOWN`.

## Studio Diagnostics

Diagnostics execute only when `RunService:IsStudio()` and store no gameplay state.

Meaningful output includes:

```text
PILLARS round state: WAITING
PILLARS round state: COUNTDOWN
PILLARS countdown: 5
PILLARS round state: STARTING
PILLARS round starting with 4 selected players
PILLARS Studio assignment: Player3 -> Pillar 1 | Pillar 1 -> Player3
PILLARS round state: ACTIVE
PILLARS eliminated: Player2 (alive: 3)
PILLARS winner: Player4
PILLARS round state: ENDING
PILLARS round cleanup complete
```

Setup deaths use a distinct message such as `PILLARS setup participant lost: Player2`. A no-winner ending is also explicit.

`StudioAssignmentDiagnostics` is called using the same `PlayerSpawnService` reference used by round setup, so its reciprocal assignment line reads the authoritative gameplay-context maps. Studio verification must not require stateful gameplay modules from the Server Command Bar because that uses a separate execution context. The Command Bar may directly modify a real character's Humanoid health to drive test deaths.

## Testing Strategy

Tests are split by responsibility and run through a dedicated Prompt 003 Studio `RunScript` harness.

### State and Shuffle Tests

- Verify the normal transition chain.
- Verify `COUNTDOWN → WAITING` and `STARTING → WAITING` cancellation paths.
- Reject every unintended transition rather than weakening validation.
- Verify Fisher–Yates uses a copied list and deterministic supplied random choices.
- Verify repeated shuffle calls consult randomness again.
- Do not require different consecutive assignments; legitimate repeats are accepted.

### Controller Lifecycle Tests

- Stay `WAITING` below `MIN_PLAYERS` without assignments or characters.
- Enter `COUNTDOWN` at the threshold.
- Cancel countdown if the population falls below the threshold.
- Select no more than `ArenaConfig.PLAYER_COUNT` participants.
- Exclude players who join after the `STARTING` selection snapshot from `STARTING`, `ACTIVE`, and `ENDING`; confirm they become eligible after the next `WAITING` state.
- Prove shuffled order is passed to sequential assignment.
- Give every successfully selected participant a unique pillar and matching marker spawn.
- Enter `ACTIVE` only after successful setup and final living-participant validation.
- Begin `ACTIVE` with every valid participant alive.
- Process a `STARTING` death once without winner evaluation.
- Revalidate connection, exact character, living Humanoid, and expected assignment before `ACTIVE`.
- On one participant's assignment/spawn failure or setup disconnection, release them and continue when at least `MIN_PLAYERS` remain.
- When setup failure/disconnection leaves fewer than `MIN_PLAYERS`, abort to `WAITING` with all partial listeners, characters, assignments, and round tables cleaned.
- Process an `ACTIVE` Humanoid death exactly once and never respawn that player during the round.
- Treat death-plus-disconnect as one elimination.
- Remove an active disconnect from alive tracking, release its assignment, and evaluate the result.
- Record the sole survivor as winner.
- End safely with no winner when zero survive.
- Ignore stale death callbacks after cleanup or generation change.
- Clean listeners, recorded characters, assignments, participant/alive state, and winner.
- Run a second and third lifecycle without stale state, duplicate callbacks, or overlapping loops.
- Invoke a fresh shuffle every round while allowing coincidental pillar repeats.

### Regression Tests

- Retain `PlayerSpawnService` assignment, lookup, controlled spawning, concurrency, and leave-during-spawn tests.
- Move `StudioAssignmentDiagnostics` coverage out of the removed bootstrap test and retain reciprocal/inconsistency checks.
- Retain Prompt 001 arena layout, generation, regeneration, marker, void coverage, and touch-elimination tests.
- Build the complete Rojo project and run `git diff --check`.

## Four-Client Studio Verification

Run Studio in Server & Clients mode with four clients and inspect the server Output.

1. Confirm `WAITING`, `COUNTDOWN`, countdown values, `STARTING`, four reciprocal assignment lines, and `ACTIVE` appear in order.
2. Confirm all four clients occupy separate pillars. Compare assignment lines across later rounds; a repeated individual pillar is allowed because each shuffle is unbiased.
3. From the Server Command Bar, directly set Player1's current Humanoid health to zero without requiring `RoundService` or `PlayerSpawnService`.
4. Confirm Player1 remains dead and the gameplay-context log reports one elimination and the reduced alive count.
5. Repeat for Player2 and Player3. Confirm Player4 is logged as winner and the state enters `ENDING`.
6. Confirm the remaining recorded character is destroyed after the ending delay, cleanup is logged, and connected players remain characterless in `WAITING`/`COUNTDOWN`.
7. Confirm another countdown and round begin without restarting Studio, all connected players participate again, and a new shuffle is executed.
8. Optionally join another client during `ACTIVE` and confirm it remains characterless and unassigned until the next round.

Safe death command example:

```luau
local player = game.Players:FindFirstChild("Player1")
local humanoid = player and player.Character and player.Character:FindFirstChildOfClass("Humanoid")

if humanoid then
	humanoid.Health = 0
end
```

The Server Command Bar is used only to mutate the real Humanoid for test input. Authoritative state verification comes from diagnostics emitted inside the gameplay server context.

## Assumptions

- Every directly connected Player is eligible until a future lobby/readiness system exists.
- `Players:GetPlayers()` order is acceptable for the temporary pre-shuffle selection cap.
- Participant selection occurs once on entry to `STARTING`; late joiners never enter that snapshot.
- Sequential character loading is acceptable for a maximum of eight prototype participants.
- Failed participants are not replaced mid-setup by unselected or newly joined players.
- Eliminated players retain no automatic character respawn and wait characterless for the next round.
- Death does not release a pillar for reuse during the same round; normal cleanup clears all assignments.
- A player may receive the same pillar in consecutive rounds by chance.
