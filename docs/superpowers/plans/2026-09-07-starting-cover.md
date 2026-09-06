# Randomized Starting Cover Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Generate one independently randomized, indestructible prototype cover on every starting pillar before each round's participants spawn, and remove all round cover through normal or aborted cleanup.

**Architecture:** `CoverConfig` centralizes every tunable geometry and appearance value. `CoverService` transactionally constructs and validates an eight-model candidate, commits it as `GeneratedArena.RoundCover`, exposes Workspace-backed lookups, and clears only that hierarchy. `RoundController` decides when the injected service generates or clears cover; `RoundService` injects the production service.

**Tech Stack:** Roblox Luau, Roblox Parts/Models/Folders and attributes, Rojo, Roblox Studio `RunScript` test harnesses.

**Spec:** `docs/superpowers/specs/2026-09-07-starting-cover-design.md`

## Global Constraints

- Preserve the approved archetypes exactly: `ShortWide = Vector3.new(10.5, 3.25, 4.5)`, `TallNarrow = Vector3.new(4.5, 7, 4.5)`, `LongLow = Vector3.new(12, 2.25, 4.5)`, and `Chunky = Vector3.new(9.5, 5, 4.5)`.
- Preserve local rear placement at `Z = +5.25`, central `5×5` spawn clearance, `0.5` spawn-to-cover gap, `0.5` rear inset, and the configured Forward/Left/Right `4×4` zones.
- Build and validate a complete unparented candidate before committing `RoundCover`; on any failure, destroy the candidate and leave no partial round-cover hierarchy.
- Use one independent unbiased random roll per pillar; allow duplicate and consecutive repeated archetypes.
- Generate all cover before the first participant spawn and clear it through both aborted and normal round cleanup.
- Do not change `ArenaService`, `ArenaLayout`, `PlayerSpawnService`, Rojo mappings, or any Prompt 001–003 gameplay behavior beyond the narrow lifecycle integration.
- Do not add packages, RemoteEvents, SpawnLocations, damage/health, assets, UI, or Prompt 005 systems.

---

### Task 1: Centralized Cover Configuration

**Files:**
- Create: `src/server/Cover/CoverConfig.luau`
- Create: `src/server/Cover/CoverConfigTests.luau`
- Create: `tests/run-cover-tests.luau`

**Interfaces:**
- Consumes: Roblox `Vector2`, `Vector3`, `Color3`, and `Enum.Material` values.
- Produces: frozen `CoverConfig` with folder name, local placement, clearance/reserved-zone values, ordered `ARCHETYPES`, and `ARCHETYPE_BY_NAME`.

- [x] **Step 1: Write the failing configuration test and runner**

Create a Studio runner that requires `CoverConfigTests.Run()`. The test must assert the four names in stable order, every approved `Size`, `LOCAL_REAR_OFFSET_Z == 5.25`, `SPAWN_CLEARANCE_SIZE == Vector2.new(5, 5)`, `SPAWN_TO_COVER_GAP == 0.5`, `REAR_EDGE_INSET == 0.5`, and all three reserved zone centers and sizes.

```luau
local expected = {
    ShortWide = Vector3.new(10.5, 3.25, 4.5),
    TallNarrow = Vector3.new(4.5, 7, 4.5),
    LongLow = Vector3.new(12, 2.25, 4.5),
    Chunky = Vector3.new(9.5, 5, 4.5),
}

for _, archetype in CoverConfig.ARCHETYPES do
    assert(archetype.Size == expected[archetype.Name])
    assert(CoverConfig.ARCHETYPE_BY_NAME[archetype.Name] == archetype)
end
```

- [x] **Step 2: Run the cover runner and verify the intended red failure**

Build a temporary place with `rojo build`, copy `tests/run-cover-tests.luau` to a path without spaces, and run Studio `--task RunScript`. Expected: module resolution fails because `CoverConfig` does not exist.

- [x] **Step 3: Implement the frozen configuration**

Create the ordered archetype records with exact sizes, neutral colors, `Enum.Material.Concrete`, and these placement records:

```luau
LOCAL_REAR_OFFSET_Z = 5.25
SPAWN_CLEARANCE_SIZE = Vector2.new(5, 5)
SPAWN_TO_COVER_GAP = 0.5
REAR_EDGE_INSET = 0.5
RESERVED_ZONE_SIZE = Vector2.new(4, 4)
RESERVED_ZONE_CENTERS = {
    Forward = Vector2.new(0, -6),
    Left = Vector2.new(-6, 0),
    Right = Vector2.new(6, 0),
}
```

Freeze archetype records, the ordered array, lookup map, reserved centers, and returned configuration.

- [x] **Step 4: Run the cover runner and verify configuration tests pass**

Expected marker: `PILLARS_COVER_TESTS_PASSED`.

---

### Task 2: Transactional Cover Geometry Service

**Files:**
- Create: `src/server/Cover/CoverService.luau`
- Create: `src/server/Cover/CoverServiceTests.luau`
- Modify: `tests/run-cover-tests.luau`

**Interfaces:**
- Consumes: `ArenaConfig`, `CoverConfig`, `Workspace.GeneratedArena.PermanentGeometry`, and `SpawnMarkers`; optional `randomSource: { NextInteger: (...) -> number }`.
- Produces: `GenerateRoundCover(randomSource?) -> (Folder?, string?)`, `ClearRoundCover() -> boolean`, `GetCoverForPillar(index) -> Model?`, and `GetCoverArchetypeForPillar(index) -> string?`.

- [x] **Step 1: Write failing service tests**

Generate the arena, snapshot every permanent Part's identity/parent/size/CFrame/attributes, then exercise a deterministic random source. Assert:

```luau
local folder, generationError = CoverService.GenerateRoundCover(random)
assert(folder and not generationError)
assert(#folder:GetChildren() == ArenaConfig.PLAYER_COUNT)
assert(random:GetCallCount() == ArenaConfig.PLAYER_COUNT)
```

For every index, assert one `PillarCover%02d` Model and one `CoverPart`; valid matching attributes; anchored, locked, collidable, queryable, and touchable Part; matching lookup results; and unchanged persistent geometry.

Transform each Part's eight corners through `pillar.CFrame:PointToObjectSpace`. Assert local X/Z bounds lie within the pillar half extents, local bottom Y equals `pillar.Size.Y / 2`, and its X/Z rectangle does not overlap the configured spawn or Forward/Left/Right rectangles.

Run repeated all-one selections to prove duplicate and consecutive repeated archetypes are accepted and that each generation performs eight new calls. Add a sentinel child under `GeneratedArena`, clear, and assert only `RoundCover` was removed. Regenerate and assert exactly one committed folder with eight non-stale Models.

Add a transactional failure test using a random source that errors on its fifth call. Assert `GenerateRoundCover` returns `nil, error`, the incomplete candidate is destroyed, and `GeneratedArena` contains no `RoundCover` or candidate hierarchy.

- [x] **Step 2: Run the runner and verify failure because CoverService is missing**

Expected: service module resolution failure.

- [x] **Step 3: Implement discovery and validation helpers**

Discover exactly one BasePart and marker per `PillarIndex` from `1` through `ArenaConfig.PLAYER_COUNT`. Reject missing, duplicate, or incorrectly typed sources before clearing current cover. Validate each configured archetype against actual pillar bounds, spawn clearance, and the three reserved zones.

- [x] **Step 4: Implement candidate construction and transactional commit**

Use an unparented Folder named `RoundCoverCandidate`. For every pillar, roll exactly once, build `PillarCoverNN` and `CoverPart`, apply metadata to both, and place the Part with:

```luau
part.CFrame = pillar.CFrame * CFrame.new(
    0,
    pillar.Size.Y / 2 + archetype.Size.Y / 2,
    CoverConfig.LOCAL_REAR_OFFSET_Z
)
```

Wrap candidate construction and validation with `xpcall`. On failure, destroy the candidate and any old committed `RoundCover`, then return `nil, tostring(error)`. On success, clear the old committed folder, rename the complete candidate to `RoundCover`, parent it to `GeneratedArena`, and only then emit one Studio line per committed Model:

```text
PILLARS cover: Pillar 1 -> TallNarrow
```

No partial candidate is ever parented to the arena.

- [x] **Step 5: Implement Workspace-backed queries and idempotent clearing**

Scan the committed folder and `PillarIndex` attributes. Do not add a mirrored module-local cover map. `ClearRoundCover` destroys only the exact named child and returns `true`, otherwise `false`.

- [x] **Step 6: Run cover tests until the complete service suite is green**

Expected marker: `PILLARS_COVER_TESTS_PASSED` with no unexpected error or warning.

---

### Task 3: Round Lifecycle Integration

**Files:**
- Modify: `src/server/Rounds/RoundController.luau`
- Modify: `src/server/Rounds/RoundControllerTests.luau`
- Modify: `src/server/Rounds/RoundService.luau`
- Modify: `src/server/Rounds/RoundServiceTests.luau`

**Interfaces:**
- Consumes: required controller dependency with `GenerateRoundCover() -> Folder?, string?` and `ClearRoundCover() -> boolean`.
- Produces: cover-before-spawn ordering and generation-scoped clearing without changing existing round queries or player lifecycle ownership.

- [x] **Step 1: Add a fake cover service to the controller harness and write failing lifecycle tests**

The fake records `GenerateCount`, `ClearCount`, and `Exists`. A participant `BeforeLoad` callback must assert `Exists == true`, proving cover committed before the first character load.

Add assertions that:

- successful `STARTING` generates exactly once;
- setup abort clears cover and returns to `WAITING`;
- normal `ENDING` cleanup clears cover;
- second and third rounds each generate a new set;
- a configured generation failure returns directly to `WAITING`, spawns nobody, assigns nobody, and leaves `Exists == false`.

- [x] **Step 2: Run Prompt 003 tests and verify the intended missing-dependency/integration failures**

Expected: assertions fail because RoundController has not called the cover dependency.

- [x] **Step 3: Integrate CoverService into RoundController**

Require `dependencies.CoverService` in the constructor. At the beginning of `_beginStarting`, clear stale cover, call generation before collecting/spawning participants, and abort through the existing cleanup/`STARTING → WAITING` path on failure. Check the session token before participant work.

Add `self._coverService.ClearRoundCover()` to `_cleanupRound` after listeners/characters/assignments are handled and before round tables are cleared. Keep the per-generation cleanup guard unchanged.

- [x] **Step 4: Inject production CoverService in RoundService**

Require `script.Parent.Parent.Cover.CoverService` and add `CoverService = CoverService` to the one production controller's dependencies. Keep the existing thin-service assertions unchanged: they must continue proving one controller starts, overlapping starts are rejected, `CharacterAutoLoads` stays false, and stop returns the service to `WAITING`. Do not duplicate cover state or geometry logic in `RoundServiceTests`.

- [x] **Step 5: Run Prompt 003 and Prompt 004 tests**

Expected markers: `PILLARS_ROUND_TESTS_PASSED` and `PILLARS_COVER_TESTS_PASSED`.

---

### Task 4: Full Compatibility and Completion Verification

**Files:**
- Verify only: all Prompt 001–004 source, tests, spec, and plan files.

**Interfaces:**
- Consumes: all completed implementation artifacts.
- Produces: fresh evidence for every Prompt 004 acceptance requirement and all existing-system compatibility requirements.

- [x] **Step 1: Run the Prompt 001 arena suite**

Expected marker: `PILLARS_ARENA_TESTS_PASSED`.

- [x] **Step 2: Run the Prompt 001 runtime void suite**

Expected marker: `PILLARS_ARENA_RUNTIME_TESTS_PASSED`.

- [x] **Step 3: Run the Prompt 002 suite**

Expected marker: `PILLARS_PLAYER_SPAWN_TESTS_PASSED`.

- [x] **Step 4: Run the Prompt 003 suite**

Expected marker: `PILLARS_ROUND_TESTS_PASSED`.

- [x] **Step 5: Run the Prompt 004 suite**

Expected marker: `PILLARS_COVER_TESTS_PASSED`.

- [x] **Step 6: Run a fresh complete Rojo build**

```powershell
rojo build default.project.json --output "$env:TEMP\PILLARS-prompt004-final.rbxlx"
```

Expected: exit code `0` and `Built project`.

- [x] **Step 7: Run repository and scope checks**

Run `git diff --check` and scan production source for `SpawnLocation`, `RemoteEvent`, `DevelopmentSpawnBootstrap`, damage/health state on cover, and Prompt 005 systems. Confirm `default.project.json`, Arena modules, and `PlayerSpawnService` were not modified.

- [x] **Step 8: Audit all 26 Prompt 004 checks against direct evidence**

Map configuration assertions, geometry/service assertions, controller integration assertions, regression markers, build output, and diff output to every numbered requirement before claiming completion.
