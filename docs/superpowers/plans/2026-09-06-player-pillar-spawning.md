# PILLARS Player-to-Pillar Spawning Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Assign up to eight connected players to unique arena pillars and explicitly spawn each participant at the matching Prompt 001 marker without automatic respawning.

**Architecture:** A reusable `PlayerSpawnService` owns bidirectional assignment state, spawn cancellation revisions, and explicit marker-based character loading. A separate `DevelopmentSpawnBootstrap` connects temporary join/leave behavior and disables Roblox automatic character loading so future `RoundService` can replace the bootstrap without rewriting the service.

**Tech Stack:** Luau, Roblox `Players`/`Player` APIs, existing Prompt 001 arena modules, Rojo 7.7.0

**Spec:** `docs/superpowers/specs/2026-09-06-player-pillar-spawning-design.md`

## Global Constraints

- Use `ArenaConfig.PLAYER_COUNT`; do not duplicate a production capacity literal.
- Use `Workspace.GeneratedArena.SpawnMarkers` and `PillarIndex` attributes as spawn-transform authority.
- Never create or depend on a Roblox `SpawnLocation`.
- Keep assignment and spawning server-authoritative with no RemoteEvents.
- Set `Players.CharacterAutoLoads = false`; death must not trigger automatic or service-driven respawn.
- The ninth player remains connected, unassigned, and characterless; freeing a pillar does not promote them automatically.
- Do not modify Prompt 001 geometry or add rounds, lobby, spectators, combat, inventory, UI, or any Prompt 003 system.
- Use the current asynchronous `Player:LoadCharacterAsync()` API; the deprecated `LoadCharacter()` API is not permitted.

---

### Task 1: Deterministic Bidirectional Assignment State

**Files:**
- Create: `src/server/Players/PlayerSpawnService.luau`
- Create: `src/server/Players/PlayerSpawnServiceTests.luau`
- Create: `tests/run-player-spawn-tests.luau`

**Interfaces:**
- Consumes: `src/server/Arena/ArenaConfig.luau`, connected Player-like keys whose `Parent` is the `Players` service.
- Produces: `AssignPlayer(player) -> number?`, `GetPillarIndex(player) -> number?`, `GetPlayerForPillar(index) -> Player?`, `ReleasePlayer(player) -> number?`, and `ClearAssignments() -> ()`.

- [ ] **Step 1: Write failing assignment tests**

Create a Studio-run test module that uses small fake participant tables with `Parent = Players`, avoiding mocks of the assignment behavior itself. Each test begins from `ClearAssignments()` and asserts literal outcomes:

```luau
local Players = game:GetService("Players")
local ArenaConfig = require(script.Parent.Parent.Arena.ArenaConfig)
local PlayerSpawnService = require(script.Parent.PlayerSpawnService)

local function participant(name)
	return { Name = name, Parent = Players }
end

local PlayerSpawnServiceTests = {}

function PlayerSpawnServiceTests.RunAssignmentTests()
	PlayerSpawnService.ClearAssignments()
	local first = participant("First")
	assert(PlayerSpawnService.AssignPlayer(first) == 1)
	assert(PlayerSpawnService.AssignPlayer(first) == 1)
	assert(PlayerSpawnService.GetPillarIndex(first) == 1)
	assert(PlayerSpawnService.GetPlayerForPillar(1) == first)

	PlayerSpawnService.ClearAssignments()
	local assigned = {}
	for index = 1, ArenaConfig.PLAYER_COUNT do
		local player = participant(string.format("Player%02d", index))
		local pillarIndex = PlayerSpawnService.AssignPlayer(player)
		assert(pillarIndex == index)
		assert(not assigned[pillarIndex])
		assigned[pillarIndex] = true
	end
	assert(PlayerSpawnService.AssignPlayer(participant("Ninth")) == nil)
	assert(PlayerSpawnService.GetPlayerForPillar(0) == nil)
	assert(PlayerSpawnService.GetPlayerForPillar(ArenaConfig.PLAYER_COUNT + 1) == nil)

	PlayerSpawnService.ClearAssignments()
	local a = participant("A")
	local b = participant("B")
	assert(PlayerSpawnService.AssignPlayer(a) == 1)
	assert(PlayerSpawnService.AssignPlayer(b) == 2)
	assert(PlayerSpawnService.ReleasePlayer(a) == 1)
	assert(PlayerSpawnService.GetPillarIndex(a) == nil)
	assert(PlayerSpawnService.GetPlayerForPillar(1) == nil)
	assert(PlayerSpawnService.AssignPlayer(participant("Replacement")) == 1)
	PlayerSpawnService.ClearAssignments()
	assert(PlayerSpawnService.GetPillarIndex(b) == nil)
	for pillarIndex = 1, ArenaConfig.PLAYER_COUNT do
		assert(PlayerSpawnService.GetPlayerForPillar(pillarIndex) == nil)
	end
end

return PlayerSpawnServiceTests
```

Create `tests/run-player-spawn-tests.luau` to generate the arena, require this module, run its assignment tests, and print `PILLARS_PLAYER_SPAWN_TESTS_PASSED` only after all assertions pass.

- [ ] **Step 2: Run the Studio test and verify the missing service fails**

Build with Rojo and run `tests/run-player-spawn-tests.luau` through Roblox Studio `--task RunScript`.

Expected: FAIL because `PlayerSpawnService` does not exist.

- [ ] **Step 3: Implement minimal assignment maps and revision invalidation**

Create `PlayerSpawnService.luau` with server-only maps:

```luau
local Players = game:GetService("Players")
local ArenaConfig = require(script.Parent.Parent.Arena.ArenaConfig)

local playerToPillar = {}
local pillarToPlayer = {}
local assignmentRevisions = setmetatable({}, { __mode = "k" })
local spawnInFlight = setmetatable({}, { __mode = "k" })

local function incrementRevision(player)
	assignmentRevisions[player] = (assignmentRevisions[player] or 0) + 1
	return assignmentRevisions[player]
end
```

`AssignPlayer` returns an existing assignment first, rejects disconnected players, scans `1..ArenaConfig.PLAYER_COUNT`, updates both maps, and increments the player's revision. `ReleasePlayer` removes both directions and increments the revision. `ClearAssignments` increments every currently assigned player's revision before clearing both maps. `GetPlayerForPillar` returns `nil` unless the index is an integer in range.

- [ ] **Step 4: Run assignment tests and confirm they pass**

Run the same Studio command.

Expected: `PILLARS_PLAYER_SPAWN_TESTS_PASSED` and no assertion errors.

### Task 2: Marker-Based Controlled Spawning and Yield Safeguards

**Files:**
- Modify: `src/server/Players/PlayerSpawnService.luau`
- Modify: `src/server/Players/PlayerSpawnServiceTests.luau`
- Modify: `tests/run-player-spawn-tests.luau`

**Interfaces:**
- Consumes: current `Workspace.GeneratedArena.SpawnMarkers`, marker `PillarIndex`, `Player:LoadCharacterAsync()`, `Player.Character`, and `HumanoidRootPart`.
- Produces: `SpawnPlayer(player) -> (Model?, string?)`.

- [ ] **Step 1: Add failing spawn lifecycle tests**

Extend the test module with helpers that create real character Models and fake Player-like tables. Each fake owns a `LoadCharacterAsync` method; this keeps the service's real spawn flow under test while avoiding Roblox account/avatar network loading.

```luau
local function newCharacter(name)
	local character = Instance.new("Model")
	character.Name = name
	local root = Instance.new("Part")
	root.Name = "HumanoidRootPart"
	root.Parent = character
	character.PrimaryPart = root
	character.Parent = workspace
	return character, root
end


local function spawnableParticipant(name, loader)
	local player = { Name = name, Parent = Players, Character = nil }
	function player:LoadCharacterAsync()
		loader(self)
	end
	return player
end
```

Add independent checks for:

- Unassigned spawn returns `nil` without invoking the loader.
- Assigned spawn loads one character and its root reaches the assigned marker CFrame.
- A duplicate `PillarIndex` marker returns a descriptive failure before loading.
- While one loader is blocked on a `BindableEvent`, a concurrent call returns `spawn already in progress` and does not invoke another load.
- If the fake player's `Parent` becomes `nil` during the loader yield, the operation returns failure and destroys the just-created orphan character.
- If `ReleasePlayer` occurs during the loader yield, the captured assignment revision becomes stale, the operation returns failure, and the newly loaded unpositioned character is destroyed.
- The generated arena contains no `SpawnLocation` descendant.

- [ ] **Step 2: Run and verify spawn tests fail for the missing API**

Run the Studio test runner.

Expected: FAIL because `SpawnPlayer` is absent.

- [ ] **Step 3: Implement strict marker resolution**

Add a private resolver that finds the generated arena and marker folder, scans descendants for BaseParts whose `PillarIndex` equals the requested index, and returns exactly one match. Return descriptive failures for missing arena/folder, no match, or duplicate matches. Capture the marker CFrame before character loading.

- [ ] **Step 4: Implement guarded asynchronous spawning**

Use `ROOT_PART_TIMEOUT_SECONDS = 10`. `SpawnPlayer` rejects an existing `spawnInFlight[player]`, captures the pillar index and assignment revision, validates connection and marker state, then marks the operation in flight.

Wrap yielding work in `pcall`:

```luau
local ok, character, failureReason = pcall(function()
	player:LoadCharacterAsync()
	local loadedCharacter = player.Character
	if not loadedCharacter or not loadedCharacter:IsA("Model") then
		return nil, "character load completed without a character"
	end
	if not isSpawnStillCurrent(player, pillarIndex, revision) then
		loadedCharacter:Destroy()
		return nil, "player left or assignment changed while spawning"
	end
	local root = loadedCharacter:WaitForChild("HumanoidRootPart", ROOT_PART_TIMEOUT_SECONDS)
	if not root or not root:IsA("BasePart") then
		loadedCharacter:Destroy()
		return nil, "character did not provide HumanoidRootPart before timeout"
	end
	if not isSpawnStillCurrent(player, pillarIndex, revision) then
		loadedCharacter:Destroy()
		return nil, "player left or assignment changed while spawning"
	end
	loadedCharacter:PivotTo(markerCFrame)
	return loadedCharacter, nil
end)

spawnInFlight[player] = nil
```

Convert a failed `pcall` into `nil` plus a character-loading failure string. Clear the guard unconditionally after the protected call. Do not connect death events or mutate assignment state from `SpawnPlayer`.

- [ ] **Step 5: Run all service tests and confirm they pass**

Expected: assignment, position, duplicate-call, leaving-during-yield, release-during-yield, and no-`SpawnLocation` checks all pass.

### Task 3: Temporary Development Bootstrap and Server Integration

**Files:**
- Create: `src/server/Players/DevelopmentSpawnBootstrap.luau`
- Create: `src/server/Players/DevelopmentSpawnBootstrapTests.luau`
- Modify: `src/server/init.server.luau`
- Modify: `tests/run-player-spawn-tests.luau`

**Interfaces:**
- Consumes: Roblox `Players` lifecycle events and `PlayerSpawnService` APIs.
- Produces: `DevelopmentSpawnBootstrap.Start() -> ()` with idempotent initialization.

- [ ] **Step 1: Write failing bootstrap checks**

Create `DevelopmentSpawnBootstrapTests.luau` that calls `Start()` twice and asserts `CharacterAutoLoads == false`. Run this check only in the standalone RunScript test process, where no real players are connected and the process exits afterward.

Extend the Studio runner to execute bootstrap checks after service state is clear and the arena exists.

- [ ] **Step 2: Run and verify the missing bootstrap fails**

Expected: FAIL because `DevelopmentSpawnBootstrap` does not exist.

- [ ] **Step 3: Implement the temporary lifecycle wiring**

Create an idempotent `Start()`:

```luau
local Players = game:GetService("Players")
local PlayerSpawnService = require(script.Parent.PlayerSpawnService)
local started = false

local function processPlayer(player)
	local pillarIndex = PlayerSpawnService.AssignPlayer(player)
	if not pillarIndex then
		warn(string.format("PILLARS: no pillar is available for %s; player remains unassigned", player.Name))
		return
	end
	task.spawn(function()
		local character, failureReason = PlayerSpawnService.SpawnPlayer(player)
		if not character and player.Parent == Players then
			warn(string.format("PILLARS: failed to spawn %s at pillar %d: %s", player.Name, pillarIndex, failureReason))
		end
	end)
end

function DevelopmentSpawnBootstrap.Start()
	if started then return end
	started = true
	Players.CharacterAutoLoads = false
	Players.PlayerAdded:Connect(processPlayer)
	Players.PlayerRemoving:Connect(function(player)
		PlayerSpawnService.ReleasePlayer(player)
	end)
	for _, player in Players:GetPlayers() do
		processPlayer(player)
	end
end
```

Do not add a listener that reacts to released pillars or character death.

- [ ] **Step 4: Integrate after Prompt 001 arena generation**

Keep existing Prompt 001 Studio tests and `ArenaService.Generate()`. Do not run Prompt 002 fake-player tests automatically in multiplayer Play sessions; execute them through the standalone RunScript harness. Require the reusable service and call `DevelopmentSpawnBootstrap.Start()` exactly once after arena generation.

- [ ] **Step 5: Run Prompt 001 and Prompt 002 test runners**

Run both Studio RunScript harnesses against one fresh Rojo build.

Expected: `PILLARS_ARENA_TESTS_PASSED`, `PILLARS_PLAYER_SPAWN_TESTS_PASSED`, and no project assertion errors.

- [ ] **Step 6: Run the Rojo and source checks**

Run:

```powershell
Get-Content -Raw default.project.json | ConvertFrom-Json | Out-Null
git diff --check
rojo build -o "$env:TEMP\PILLARS-prompt-002-final.rbxlx"
```

Expected: valid JSON, clean diff check, and Rojo exit code 0.

- [ ] **Step 7: Perform multiplayer Studio acceptance**

Use Studio's Server & Clients mode with four local players. In the server Output, verify the gameplay-context diagnostic lines report reciprocal assignments for pillars 1–4, such as `Player1 -> Pillar 1 | Pillar 1 -> Player1`. Do not require `PlayerSpawnService` from Studio's Server Command Bar as an ownership check because that Command Bar has a separate module execution context. Confirm the clients appear on distinct matching markers, killing one Humanoid leaves that player dead beyond the configured respawn time, and closing one client releases its pillar without moving or spawning any unassigned player. Separately test nine clients if the machine supports it; the ninth must remain characterless and produce the capacity warning.
