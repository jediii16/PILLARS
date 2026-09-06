# PILLARS Prompt 003 Round Lifecycle Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a repeatable, server-authoritative PILLARS round lifecycle that selects, shuffles, spawns, tracks, eliminates, declares, cleans, and restarts rounds.

**Architecture:** Domain-specific `RoundController` owns one state machine and per-round data while accepting only timing, player-provider, randomness, configuration, and spawning dependencies needed by deterministic tests. Thin `RoundService` wires Roblox services and starts one controller; `PlayerSpawnService` remains unchanged.

**Tech Stack:** Roblox Luau, Rojo, Roblox Studio `RunScript` tests, basic Roblox Instances and signals.

**Spec:** `docs/superpowers/specs/2026-09-06-round-lifecycle-design.md`

## Global Constraints

- Preserve the existing arena and `PlayerSpawnService` behavior.
- Keep `Players.CharacterAutoLoads = false`.
- Maximum participants come from `ArenaConfig.PLAYER_COUNT`; never duplicate `8` in round logic.
- Use `MIN_PLAYERS = 2`, `COUNTDOWN_DURATION = 5`, and `END_ROUND_DELAY = 3` in production config.
- Perform a fresh unbiased Fisher–Yates shuffle each round; repeats are allowed.
- Add no lobby, spectators, UI, remotes, combat, items, or Prompt 004 systems.
- Do not modify `default.project.json` unless Rojo cannot map the planned files.

---

### Task 1: Round configuration, states, and shuffle

**Files:**
- Create: `src/server/Rounds/RoundConfig.luau`
- Create: `src/server/Rounds/RoundState.luau`
- Create: `src/server/Rounds/RoundShuffle.luau`
- Create: `src/server/Rounds/RoundFoundationTests.luau`
- Create: `tests/run-round-tests.luau`

**Interfaces:**
- Produces: `RoundState.WAITING|COUNTDOWN|STARTING|ACTIVE|ENDING` and `RoundState.CanTransition(from, to) -> boolean`.
- Produces: `RoundShuffle.ShuffledCopy<T>(values: {T}, random) -> {T}` where `random:NextInteger(min, max)` is called once per Fisher–Yates step.
- Produces: frozen `RoundConfig` values used by production.

- [ ] **Step 1: Write foundation tests before the modules exist**

Test literal transition outcomes, including both cancellation paths and rejected skips. Test that a deterministic random sequence turns `{ "A", "B", "C", "D" }` into a hand-derived order, leaves the input unchanged, and receives fresh calls on a second shuffle.

```luau
assert(RoundState.CanTransition(RoundState.COUNTDOWN, RoundState.WAITING))
assert(RoundState.CanTransition(RoundState.STARTING, RoundState.WAITING))
assert(not RoundState.CanTransition(RoundState.WAITING, RoundState.ACTIVE))

local choices = { 1, 1, 1 }
local choiceIndex = 0
local deterministicRandom = {}
function deterministicRandom:NextInteger(_minimum, _maximum)
	choiceIndex += 1
	return choices[choiceIndex]
end

local input = { "A", "B", "C", "D" }
local output = RoundShuffle.ShuffledCopy(input, deterministicRandom)
assert(table.concat(input, "") == "ABCD")
assert(table.concat(output, "") == "BCDA")
```

- [ ] **Step 2: Build and run the runner; verify missing modules fail**

Run `rojo build default.project.json --output "$env:TEMP\PILLARS-round-red.rbxlx"`, then execute `tests/run-round-tests.luau` with Studio `--task RunScript`. Expected: missing `RoundState` or `RoundShuffle` failure.

- [ ] **Step 3: Implement the minimal foundation modules**

Use a frozen transition adjacency table and a copied Fisher–Yates loop:

```luau
for index = #copy, 2, -1 do
	local swapIndex = random:NextInteger(1, index)
	copy[index], copy[swapIndex] = copy[swapIndex], copy[index]
end
```

- [ ] **Step 4: Run the foundation tests and confirm the pass marker**

Expected: `PILLARS_ROUND_TESTS_PASSED` after the foundation module tests.

---

### Task 2: RoundController waiting, countdown, and setup

**Files:**
- Create: `src/server/Rounds/RoundController.luau`
- Create: `src/server/Rounds/RoundControllerTests.luau`
- Modify: `tests/run-round-tests.luau`

**Interfaces:**
- Consumes: `RoundState`, `RoundShuffle`, `ArenaConfig.PLAYER_COUNT`, and injected `{ Config, GetEligiblePlayers, Wait, Random, PlayerSpawnService }`.
- Produces: `RoundController.new(dependencies)`, `:Start()`, `:Stop()`, `:GetState()`, `:GetAliveCount()`, `:IsParticipant(player)`, `:GetWinner()`, and `:HandlePlayerRemoving(player)`.

- [ ] **Step 1: Add failing lifecycle tests for waiting and countdown**

Use a mutable eligible-player list and scripted wait function. Verify below-minimum waiting creates no assignments, reaching minimum enters countdown, and removing a player during a countdown wait returns to `WAITING` without spawning.

- [ ] **Step 2: Run the Prompt 003 runner and verify `RoundController` is missing**

Expected: a focused missing-module failure rather than a syntax or fixture error.

- [ ] **Step 3: Implement state transitions and one guarded lifecycle loop**

`Start()` sets `_running` before spawning one coroutine. `_transition(nextState)` asserts `RoundState.CanTransition`. `Stop()` invalidates the session token, cleans current round data, and prevents additional cycles; it exists as normal controller lifecycle ownership and enables deterministic test cleanup.

- [ ] **Step 4: Add failing setup tests**

Generate the real arena and use fake connected player-like tables whose `LoadCharacterAsync` creates real Models containing a `HumanoidRootPart` and living `Humanoid`. Verify selection caps at `ArenaConfig.PLAYER_COUNT`, deterministic shuffled order controls sequential pillar ownership, unique assignments spawn at matching markers, and `ACTIVE` is reached only with `MIN_PLAYERS` successful living participants.

- [ ] **Step 5: Implement STARTING setup and final validation**

Record selected snapshot, participant, alive, expected pillar, exact character, and death connection separately. After sequential spawns, revalidate:

```luau
player.Parent == Players
	and player.Character == recordedCharacter
	and recordedCharacter.Parent ~= nil
	and humanoid.Health > 0
	and spawnService.GetPillarIndex(player) == expectedPillar
```

Release failed/disconnected setup assignments. Abort via shared cleanup and `STARTING → WAITING` when fewer than `MIN_PLAYERS` remain.

- [ ] **Step 6: Run the Prompt 003 tests**

Expected: waiting, countdown cancellation, cap, shuffle, spawn integration, and active-entry assertions pass.

---

### Task 3: Elimination, winner, late joiners, and repeated cleanup

**Files:**
- Modify: `src/server/Rounds/RoundController.luau`
- Modify: `src/server/Rounds/RoundControllerTests.luau`

**Interfaces:**
- Extends the controller with generation-scoped STARTING/ACTIVE death processing, event-driven round completion, guarded cleanup, and player-removal handling.

- [ ] **Step 1: Add failing STARTING failure and late-join tests**

Script one loader to fail or disconnect while later participants spawn. Assert the failed assignment is released and setup continues with at least `MIN_PLAYERS`; repeat with fewer valid players and assert `WAITING`, destroyed partial characters, disconnected listeners, cleared assignments, and empty round state. Add a player during `STARTING`, `ACTIVE`, and `ENDING`; assert no current-round assignment, spawn, participant, or alive entry, then confirm eligibility in the next cycle.

- [ ] **Step 2: Add failing death/winner tests**

Verify STARTING death removes pending alive state without ending. During ACTIVE, set Humanoid health to zero and verify one elimination. Cover sole-survivor winner and simultaneous zero-survivor no-winner behavior.

- [ ] **Step 3: Add the explicit two-player disconnect test**

With exactly two alive players in `ACTIVE`, call `HandlePlayerRemoving(leaver)` after setting its parent disconnected. Assert:

```luau
assert(controller:GetAliveCount() == 1)
assert(PlayerSpawnService.GetPillarIndex(leaver) == nil)
assert(controller:GetWinner() == survivor)
assert(controller:GetState() == RoundState.ENDING)
```

Call removal/death again and verify alive count and winner do not change.

- [ ] **Step 4: Implement idempotent elimination and event-driven ending**

Alive membership is the gate. STARTING removes without winner evaluation. ACTIVE removes, counts, records winner only at exactly one, records nil at zero, transitions once to ENDING, and wakes the lifecycle loop.

- [ ] **Step 5: Implement guarded cleanup and repeated rounds**

Disconnect death listeners before destroying recorded characters, clear spawn assignments, then clear all round tables and winner. Use generation and cleanup guards so stale callbacks and repeated cleanup calls do nothing. Ensure each next STARTING recollects players and invokes `RoundShuffle.ShuffledCopy` again.

- [ ] **Step 6: Run all Prompt 003 tests**

Expected: all setup failure, join timing, death, disconnect, winner, no-winner, cleanup, repeat, and overlap assertions pass.

---

### Task 4: Thin RoundService, diagnostics, and bootstrap removal

**Files:**
- Create: `src/server/Rounds/RoundService.luau`
- Create: `src/server/Rounds/RoundServiceTests.luau`
- Create: `src/server/Players/StudioAssignmentDiagnosticsTests.luau`
- Modify: `src/server/init.server.luau`
- Modify: `tests/run-player-spawn-tests.luau`
- Modify: `tests/run-round-tests.luau`
- Delete: `src/server/Players/DevelopmentSpawnBootstrap.luau`
- Delete: `src/server/Players/DevelopmentSpawnBootstrapTests.luau`

**Interfaces:**
- Produces: `RoundService.Start()` as idempotent production startup and read-only delegation methods to the single controller.
- Consumes: `Players`, `RoundConfig`, `PlayerSpawnService`, `RoundController`, and `StudioAssignmentDiagnostics` through the controller's authoritative setup path.

- [ ] **Step 1: Move diagnostics coverage before deleting the bootstrap test**

Create a focused diagnostics test that assigns a fake connected participant through the real `PlayerSpawnService`, calls `StudioAssignmentDiagnostics.Log` with that same service reference, and asserts reciprocal and inconsistent snapshots.

- [ ] **Step 2: Add failing RoundService tests**

Verify calling production `Start()` twice remains idempotent through its existing startup guard, delegates the same controller state, and leaves `Players.CharacterAutoLoads` false without assigning or spawning on `PlayerAdded` directly. The controller's focused test proves that repeated `Start()` calls create only one lifecycle loop; do not add another dependency-injection seam to the thin wrapper.

- [ ] **Step 3: Implement thin production wiring**

Construct one controller, connect `PlayerRemoving` once, and delegate. Keep transitions and round tables exclusively in `RoundController`.

- [ ] **Step 4: Remove DevelopmentSpawnBootstrap and update startup**

Delete both temporary bootstrap files. Update `init.server.luau` to retain Prompt 001 Studio checks, call `ArenaService.Generate()`, then `RoundService.Start()`.

- [ ] **Step 5: Add Studio-only meaningful logging**

Guard transition, countdown, setup size, reciprocal assignment, setup loss, elimination/alive count, winner/no-winner, ending, and cleanup logs with `RunService:IsStudio()`. Reuse `StudioAssignmentDiagnostics` directly; store no diagnostic snapshot.

- [ ] **Step 6: Run Prompt 002 and Prompt 003 suites**

Expected: `PILLARS_PLAYER_SPAWN_TESTS_PASSED` and `PILLARS_ROUND_TESTS_PASSED` with no bootstrap assignment behavior.

---

### Task 5: Full verification and handoff

**Files:**
- Modify: `docs/superpowers/plans/2026-09-07-round-lifecycle.md` only to mark completed checkboxes if useful.

**Interfaces:**
- Verifies all Prompt 001–003 behavior; introduces no runtime interface.

- [ ] **Step 1: Build one fresh place**

Run:

```powershell
rojo build default.project.json --output "$env:TEMP\PILLARS-prompt-003-final.rbxlx"
git diff --check
```

- [ ] **Step 2: Run all Studio harnesses against the fresh place**

Run `tests/run-arena-tests.luau`, `tests/run-arena-runtime-tests.luau`, `tests/run-player-spawn-tests.luau`, and `tests/run-round-tests.luau`. Require the four pass markers and distinguish unrelated Studio/plugin warnings from project failures.

- [ ] **Step 3: Inspect scope and mappings**

Confirm `default.project.json` is unchanged, no `SpawnLocation` or RemoteEvent creation was added, `DevelopmentSpawnBootstrap` is absent, and no prohibited Prompt 004 systems exist.

- [ ] **Step 4: Report Prompt 003**

List every changed file, state transitions, selection/shuffle, PlayerSpawnService integration, alive/death/leave/winner behavior, cleanup safeguards, exact four-client Studio steps, test evidence, and visual edge cases. Stop without starting Prompt 004.
