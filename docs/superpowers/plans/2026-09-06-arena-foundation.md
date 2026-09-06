# PILLARS Arena Foundation Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Generate a deterministic, server-authoritative eight-player prototype arena with eight circular starting pillars, one center platform, one spawn marker per pillar, and a touch-based void boundary.

**Architecture:** `ArenaConfig` centralizes tunable values, `ArenaLayout` performs pure geometry calculations, and `ArenaService` owns validation and Workspace construction. The existing server entry point runs Studio-only checks and then generates one clean arena model.

**Tech Stack:** Luau, Roblox server APIs, Rojo 7.7.0

**Spec:** `docs/superpowers/specs/2026-09-06-arena-foundation-design.md`

## Global Constraints

- Keep `PLAYER_COUNT = 8` and expose `PILLAR_SIZE`, `PILLAR_RADIUS`, `PILLAR_HEIGHT`, `CENTER_PLATFORM_SIZE`, and `VOID_KILL_HEIGHT` in one configuration module.
- Use only basic Roblox Parts with neutral prototype styling.
- Use invisible marker Parts, never `SpawnLocation` objects.
- Keep the server authoritative and add no client gameplay logic.
- Remove only the existing `Workspace.Baseplate` entry from `default.project.json`; preserve every other Rojo mapping and property.
- Every Part composing the logical void boundary must use `CanCollide = false`, `CanQuery = false`, and `CanTouch = true`.
- Do not add combat, items, inventory, expansion, cover, Artifacts, storms, rounds, lobby, matchmaking, monetization, cosmetics, UI, or unrelated systems.

---

### Task 1: Pure Arena Configuration and Circular Layout

**Files:**
- Create: `src/server/Arena/ArenaConfig.luau`
- Create: `src/server/Arena/ArenaLayout.luau`
- Create: `src/server/Arena/ArenaLayoutTests.luau`
- Modify: `src/server/init.server.luau`

**Interfaces:**
- Consumes: Roblox `Vector3` and `CFrame` value types.
- Produces: `ArenaConfig` table; `ArenaLayout.Calculate(config) -> {PillarLayout}`; `ArenaLayout.CalculateCenterPlatform(config) -> PlatformLayout`; `ArenaLayout.CalculateVoidBoundary(config) -> PlatformLayout`; `ArenaLayoutTests.Run() -> ()`.

- [x] **Step 1: Write the failing layout checks**

Create `ArenaLayoutTests.luau` with literal, hand-derived expectations. Tests require `ArenaLayout`, clone the config with overrides, and assert these observable behaviors: eight records; 45-degree ordering; radial distance of 80; changed radius of 120; 16-by-16 pillar footprints; marker elevation above a 70-stud top; center position at `(0, 68, 0)` for a four-stud-thick platform; void center at the configured kill height; and an edge-to-edge center gap greater than 20 studs. A realistic mutation such as replacing `2 * math.pi` with `math.pi` must fail the equal-spacing checks. Replace the hello-world server entry point with a temporary Studio-only test bootstrap that requires and runs `ArenaLayoutTests`; this is test scaffolding and contains no arena implementation.

```luau
local ArenaConfig = require(script.Parent.ArenaConfig)
local ArenaLayout = require(script.Parent.ArenaLayout)

local EPSILON = 1e-4

local function expectNear(actual: number, expected: number, message: string)
	assert(math.abs(actual - expected) <= EPSILON, string.format("%s: expected %.4f, got %.4f", message, expected, actual))
end

local function withOverrides(overrides)
	local result = table.clone(ArenaConfig)
	for key, value in overrides do
		result[key] = value
	end
	return result
end

local ArenaLayoutTests = {}

function ArenaLayoutTests.Run()
	local layouts = ArenaLayout.Calculate(ArenaConfig)
	assert(#layouts == 8, "layout must contain exactly eight pillars")
	for index, layout in layouts do
		assert(layout.Index == index, "pillar indices must be stable")
		expectNear(Vector2.new(layout.Position.X, layout.Position.Z).Magnitude, 80, "pillar radius")
		expectNear(layout.Angle, (index - 1) * math.pi / 4, "pillar angle")
		assert(layout.Size == Vector3.new(16, 4, 16), "pillar size must come from config")
		expectNear(layout.SpawnPosition.Y, 73, "spawn marker height")
	end

	local wider = ArenaLayout.Calculate(withOverrides({ PILLAR_RADIUS = 120 }))
	expectNear(Vector2.new(wider[3].Position.X, wider[3].Position.Z).Magnitude, 120, "changed radius")

	local resized = ArenaLayout.Calculate(withOverrides({ PILLAR_SIZE = Vector3.new(20, 8, 20) }))
	assert(resized[1].Size == Vector3.new(20, 8, 20), "changed size must be used")
	expectNear(resized[1].SpawnPosition.Y, 73, "spawn height must derive from the walkable top")

	local center = ArenaLayout.CalculateCenterPlatform(ArenaConfig)
	assert(center.Position == Vector3.new(0, 68, 0), "center platform must be centered")
	local void = ArenaLayout.CalculateVoidBoundary(ArenaConfig)
	expectNear(void.Position.Y, ArenaConfig.VOID_KILL_HEIGHT, "void kill height")
	local edgeGap = ArenaConfig.PILLAR_RADIUS - ArenaConfig.PILLAR_SIZE.Z / 2 - ArenaConfig.CENTER_PLATFORM_SIZE.Z / 2
	assert(edgeGap > 20, "normal movement must not bridge the center gap")
end

return ArenaLayoutTests
```

- [x] **Step 2: Run the checks and verify the missing implementation fails**

Run the Studio test bootstrap in a synced Play session before creating `ArenaLayout.luau`.

Expected: the server reports that `ArenaLayout` is missing; the checks cannot pass before the production module exists.

- [x] **Step 3: Implement centralized configuration**

Create `ArenaConfig.luau` with the approved values plus named supporting constants:

```luau
return table.freeze({
	PLAYER_COUNT = 8,
	PILLAR_SIZE = Vector3.new(16, 4, 16),
	PILLAR_RADIUS = 80,
	PILLAR_HEIGHT = 70,
	CENTER_PLATFORM_SIZE = Vector3.new(24, 4, 24),
	VOID_KILL_HEIGHT = -150,
	ARENA_CENTER = Vector3.new(0, 0, 0),
	SPAWN_MARKER_SIZE = Vector3.new(4, 1, 4),
	SPAWN_MARKER_OFFSET = 3,
	VOID_BOUNDARY_THICKNESS = 2,
	VOID_BOUNDARY_MARGIN = 1024,
	VOID_BOUNDARY_MAX_TILE_SIZE = 2048,
	GENERATED_MODEL_NAME = "GeneratedArena",
	PERMANENT_GEOMETRY_FOLDER_NAME = "PermanentGeometry",
	SPAWN_MARKERS_FOLDER_NAME = "SpawnMarkers",
	PILLAR_COLOR = Color3.fromRGB(105, 110, 120),
	CENTER_PLATFORM_COLOR = Color3.fromRGB(125, 130, 140),
	PLATFORM_MATERIAL = Enum.Material.Concrete,
})
```

- [x] **Step 4: Implement the pure layout calculations**

Create `ArenaLayout.luau`. `Calculate` iterates `1..PLAYER_COUNT`, computes `angle = ((index - 1) / PLAYER_COUNT) * 2 * math.pi`, derives each platform center from the configured walkable-top height, and derives the marker Y coordinate as `PILLAR_HEIGHT + SPAWN_MARKER_OFFSET`. Center and void helpers return size and position records without creating Instances.

- [x] **Step 5: Run the layout checks and confirm they pass**

Run the Studio test bootstrap in a synced Play session.

Expected: every `ArenaLayoutTests.Run()` assertion passes and the server prints one concise success line.

### Task 2: Server-Authoritative Arena Construction

**Files:**
- Create: `src/server/Arena/ArenaService.luau`
- Create: `src/server/Arena/ArenaServiceTests.luau`
- Modify: `src/server/init.server.luau`

**Interfaces:**
- Consumes: `ArenaConfig`, `ArenaLayout`, `Workspace`, `Instance`, and standard character `Humanoid` behavior.
- Produces: `ArenaService.Generate() -> Model`; generated `Workspace.GeneratedArena` model containing `PermanentGeometry`, `SpawnMarkers`, and `VoidBoundary`.

- [x] **Step 1: Write failing service checks**

Create `ArenaServiceTests.luau`. The checks call `Generate()` twice and inspect the real generated Instances. Assert that Workspace contains one owned model; permanent geometry contains exactly eight named starting pillars plus `CenterPlatform`; markers contains exactly eight named Parts with matching `PillarIndex` attributes; no descendant is a `SpawnLocation`; every pillar and center platform is anchored, locked, collidable, and marked permanent; all marker Parts are transparent and non-collidable; and every Part inside the logical `VoidBoundary` is invisible, anchored, non-collidable, non-queryable, and touch-enabled.

The test destroys only the exact generated model between checks. A realistic mutation such as omitting pre-generation cleanup must make the identity/count assertion fail.

- [x] **Step 2: Run the service checks and verify the missing service fails**

Run the Studio test bootstrap before creating `ArenaService.luau`.

Expected: the server reports that `ArenaService` is missing; no construction check passes accidentally.

- [x] **Step 3: Implement config validation and part helpers**

In `ArenaService.luau`, validate the player count, platform dimensions, positive radius, and that `VOID_KILL_HEIGHT < PILLAR_HEIGHT`. Add private helpers for creating permanent Parts and spawn-marker Parts. Keep all styling local to the arena service and all geometry values in configuration/layout records.

- [x] **Step 4: Implement deterministic generation and cleanup**

Implement `ArenaService.Generate()` so it destroys only `Workspace:FindFirstChild(ArenaConfig.GENERATED_MODEL_NAME)`, builds a fresh unparented model, adds exactly eight starting pillars, eight marker Parts, one center platform, and one void boundary, then parents the completed model to Workspace.

Name starting pillars and markers with two-digit one-based suffixes. Give each pillar and marker a `PillarIndex` attribute. Set `PermanentGeometry = true` on starting pillars and the center platform.

- [x] **Step 5: Implement void elimination**

Keep the logical void boundary invisible and tile its configured coverage into engine-safe Parts no larger than `VOID_BOUNDARY_MAX_TILE_SIZE`. Every tile is anchored with `CanCollide = false`, `CanQuery = false`, and `CanTouch = true`. Each tile's `Touched` connection finds a Humanoid from the touching Part's character and sets `Health = 0`. Do not add round, respawn, or out-of-bounds systems.

- [x] **Step 6: Wire Studio checks and server startup**

Replace the hello-world server prints with an entry point that requires the arena modules. When `RunService:IsStudio()` is true, run `ArenaLayoutTests.Run()` and `ArenaServiceTests.Run()` and print a concise success message. Then call `ArenaService.Generate()` once so both Studio and live servers end with one clean arena.

- [x] **Step 7: Run all Studio checks and confirm they pass**

Run a synced Play session.

Expected: all assertions pass, exactly one success line appears, the final generated arena remains visible, and Output contains no warnings or errors.

### Task 3: Rojo Mapping Cleanup and End-to-End Verification

**Files:**
- Modify: `default.project.json`

**Interfaces:**
- Consumes: the existing Rojo DataModel mapping.
- Produces: the same mapping without the `Workspace.Baseplate` child.

- [x] **Step 1: Remove only the mapped Baseplate**

Delete the `Baseplate` object nested under `Workspace` while preserving the `Workspace.$properties` block and all ReplicatedStorage, ServerScriptService, StarterPlayer, Lighting, and SoundService mappings exactly.

- [x] **Step 2: Build the Rojo project**

Run:

```powershell
rojo build -o "$env:TEMP\PILLARS-arena-verification.rbxlx"
```

Expected: Rojo reports a successful build with exit code 0.

- [x] **Step 3: Verify source formatting and changed-file scope**

Run:

```powershell
git diff --check
git status --short
```

Expected: `git diff --check` exits 0. Status lists only the approved arena modules/tests, server entry point, plan, and `default.project.json`, plus the user's pre-existing untracked files.

- [ ] **Step 4: Perform the Studio acceptance playtest**

Automated Studio simulation is complete, including server startup and touch-based Humanoid elimination. The visible camera/player inspection remains the user's final playtest using the steps below.

In a Rojo-synced Studio session, press Play and inspect `Workspace.GeneratedArena`. Confirm eight evenly spaced starting pillars, eight marker Parts under `SpawnMarkers`, one centered platform, and one invisible void boundary. Enable marker visibility temporarily in Studio properties only if needed to inspect their placement; do not save that temporary change.

Move a test character to a pillar and attempt an ordinary unaided jump toward the center; the character must fall short. Fall into the void and confirm there is a visible recovery interval before the character is eliminated at the boundary. Stop and Play again, confirming only one generated arena exists and Output contains no runtime errors.
