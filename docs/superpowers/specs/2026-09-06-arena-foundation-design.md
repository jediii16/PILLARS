# PILLARS Arena Foundation Design

## Scope

Build the first server-authoritative gameplay foundation for PILLARS: an eight-player free-for-all arena containing exactly eight starting pillars, one center platform, one designated spawn marker per pillar, and a configurable void boundary. Combat, rounds, spawning logic, expansion, cover, themes, Artifacts, and all other later systems remain out of scope.

## Project Integration

The existing Rojo mappings remain unchanged except for removing the mapped `Workspace.Baseplate`, which would otherwise prevent players from falling into the void. Arena code lives under the already mapped `src/server` directory. No packages, frameworks, external assets, or client-side arena generation are introduced.

The existing server entry point initializes the arena once when the server starts. Generated instances live inside a single named `Workspace` model. Regeneration first destroys that model, if present, and then constructs a fresh arena so stale or duplicate geometry cannot remain.

## Architecture

### ArenaConfig

`ArenaConfig` owns all values that determine arena geometry and behavior. It includes at least:

- `PLAYER_COUNT = 8`
- `PILLAR_SIZE = Vector3.new(16, 4, 16)`
- `PILLAR_RADIUS = 80`
- `PILLAR_HEIGHT = 70`
- `CENTER_PLATFORM_SIZE = Vector3.new(24, 4, 24)`
- `VOID_KILL_HEIGHT = -150`

It also owns focused supporting values such as arena center, spawn-marker offset and size, generated model name, and neutral prototype colors. `VOID_BOUNDARY_MARGIN = 1024` keeps the invisible kill boundary substantially larger than the playable footprint. Geometry modules consume these values rather than duplicating numeric literals.

With platform tops at approximately 70 studs and the kill boundary at -150 studs, a falling player has 220 studs of vertical recovery distance for future mobility items. An 80-stud pillar-center radius leaves approximately 60 studs between the nearest edges of a 16-stud-deep pillar and a 24-stud-deep center platform, well beyond an ordinary Roblox jump.

### ArenaLayout

`ArenaLayout` is a pure calculation module with no Workspace mutations. For pillar index `i` in the inclusive range `1..PLAYER_COUNT`, it computes:

`angle = ((i - 1) / PLAYER_COUNT) * 2 * math.pi`

The pillar center is:

`ARENA_CENTER + Vector3.new(math.cos(angle) * PILLAR_RADIUS, PILLAR_HEIGHT - PILLAR_SIZE.Y / 2, math.sin(angle) * PILLAR_RADIUS)`

This produces equal angular spacing of `2π / 8`, or 45 degrees. The first pillar lies on the positive X axis; subsequent pillars proceed around the XZ plane. Because radius and size are read from configuration, changing either value regenerates the layout correctly without editing the algorithm.

The spawn marker for each pillar is centered horizontally above the platform. Its Y position is derived from the platform top plus a configurable offset. Layout results include stable one-based indices and transforms so future systems can associate players, cover, and expansions with a specific pillar.

### ArenaService

`ArenaService.Generate()` is the sole public construction entry point. It performs these operations:

1. Remove the existing generated arena model by its exact configured name.
2. Create a new arena model in `Workspace`.
3. Create a permanent-geometry folder containing eight anchored starting pillar Parts and one anchored center platform Part.
4. Create a spawn-markers folder containing one invisible, anchored, non-collidable marker Part per pillar.
5. Create one logical void boundary at the configured kill height, tiled from engine-safe invisible, anchored, non-collidable Parts when its configured coverage exceeds Roblox's per-Part size limit.
6. Connect the void boundary touch handler so a character Humanoid crossing it is reduced to zero health.
7. Parent the completed model to `Workspace` and return it.

Starting pillars are named `StartingPillar01` through `StartingPillar08`; markers are named `PillarSpawn01` through `PillarSpawn08`. Each marker also carries a `PillarIndex` attribute. A future `RoundService` can therefore enumerate the spawn-markers folder, use the stable name, or read the attribute without depending on Roblox default spawning.

Permanent geometry is structurally separated from spawn metadata. This leaves clear extension points for future per-pillar cover and expansion folders without building those systems prematurely.

## Instance Properties and Appearance

All visible arena geometry uses basic anchored Roblox Parts with a neutral material and restrained colors. Permanent parts are locked, have `CanCollide` enabled, and carry a `PermanentGeometry` attribute. Spawn markers are fully transparent, anchored, non-collidable, non-queryable, and non-touchable.

The void boundary is one broad logical boundary below the arena. It does not catch falling characters physically. Its only behavior is detecting character contact and killing the character's Humanoid. Its horizontal dimensions are derived from the pillar radius and platform sizes plus the generous configured margin. With the prototype values, it covers approximately `2224 × 2 × 2224` studs using four seamless `1112 × 2 × 1112` trigger Parts so Roblox does not clamp the requested coverage to its per-Part size ceiling.

## Validation and Error Handling

Configuration is validated before generation. Generation rejects invalid player counts, non-positive platform dimensions, a non-positive radius, or a void height that is not beneath the arena platforms. Invalid configuration fails early with a descriptive server error instead of generating a partial arena.

The arena model is assembled before its final Workspace parent assignment. This limits partially visible results if construction fails. Regeneration is deterministic and deletes only the exact generated model owned by `ArenaService`.

## Testing Strategy

Pure layout tests verify:

- Exactly eight layout records are returned.
- Every pillar lies at the configured radius from arena center.
- Adjacent pillar angles are evenly spaced by 45 degrees.
- Each pillar receives exactly one derived spawn-marker position above its surface.
- A changed radius updates every pillar's radial distance.
- A changed pillar size updates platform dimensions and spawn-marker height derivation.
- The configured gap from pillar edge to center edge exceeds a conservative normal-jump threshold.

Service-level Studio verification checks:

- Exactly eight starting pillars, eight markers, one center platform, and one void boundary exist.
- Calling `Generate()` again leaves only one generated arena.
- Falling reaches the kill boundary after a short delay and kills the character.
- Server output contains no runtime errors.
- No Roblox `SpawnLocation` instances are generated.

Rojo build validation confirms the project mapping and Luau files serialize successfully after the Baseplate entry is removed.

## Assumptions

- `PILLAR_HEIGHT` means the Y coordinate of the walkable top surface, not the Part center or the pillar's physical thickness.
- Starting pillars are prototype platforms rather than columns extending down to the void.
- A 60-stud horizontal edge-to-edge gap is safely beyond ordinary unaided Roblox jumping and can be tuned later through configuration.
- Spawn markers represent future teleport destinations only; this phase does not assign or move players.
- The void boundary kills standard player characters that contain a Humanoid. It does not implement out-of-bounds handling for non-character physics objects.
