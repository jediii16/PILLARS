# PILLARS Prompt 004 — Randomized Starting Cover Design

## Scope

Prompt 004 adds one randomized, indestructible starting-cover configuration to every one of the eight existing starting pillars during each round. Cover is generated on the server before participant spawning, remains fixed throughout `ACTIVE`, and is removed by both aborted-setup and normal end-of-round cleanup.

This phase uses only basic Roblox `Part` geometry. It does not add assets, combat, weapons, damage, structure health, inventory, item drops, Blocks, expansions, mobility, Artifacts, storm, lobby behavior, spectators, UI, monetization, cosmetics, or any Prompt 005 system.

## Ownership and Existing-System Integration

Ownership remains deliberately split:

- `RoundController` decides when round cover is generated and cleared.
- `CoverService` decides how cover geometry is selected, constructed, queried, and removed.
- `CoverConfig` owns all tunable archetype dimensions, offsets, colors, spawn-clearance dimensions, and reserved expansion-zone dimensions.
- `ArenaService` continues to own only persistent arena geometry and is not regenerated each round.
- `PlayerSpawnService` remains unchanged and continues to own assignments and controlled character spawning.
- `RoundService` remains the only production owner of player participation and spawning. It supplies the real `CoverService` to its single controller.

No client API, RemoteEvent, SpawnLocation, or separate player-lifecycle owner is introduced.

## Workspace Structure

While a round is being set up or active, cover is organized as:

```text
Workspace
└── GeneratedArena
    ├── PermanentGeometry
    ├── SpawnMarkers
    ├── RoundCover
    │   ├── PillarCover01
    │   │   └── CoverPart
    │   ├── PillarCover02
    │   │   └── CoverPart
    │   └── ... PillarCover08
    └── VoidBoundary
```

`RoundCover` is the only container owned by `CoverService`. Clearing cover destroys only that container. It never destroys or reparents `PermanentGeometry`, `SpawnMarkers`, `VoidBoundary`, the center platform, or unrelated children under `GeneratedArena`.

Each `PillarCoverNN` is a `Model` with:

- `PillarIndex` number attribute;
- `CoverArchetype` string attribute;
- `PermanentCover = true` attribute.

Every generated `CoverPart` repeats those three attributes so future destruction filtering can identify the geometry without depending on ancestry or names alone. Starting-cover Parts do not receive hit points or damage state.

## Cover Configuration

`CoverConfig` is a frozen configuration table. All playtest-sensitive values are centralized so tuning requires no geometry-logic changes.

### Shared placement values

- `ROUND_COVER_FOLDER_NAME = "RoundCover"`
- `LOCAL_REAR_OFFSET_Z = 5.25`
- `SPAWN_CLEARANCE_SIZE = Vector2.new(5, 5)`
- `SPAWN_TO_COVER_GAP = 0.5`
- `REAR_EDGE_INSET = 0.5`
- `RESERVED_ZONE_SIZE = Vector2.new(4, 4)`
- Forward zone center: local `Vector2.new(0, -6)`
- Left zone center: local `Vector2.new(-6, 0)`
- Right zone center: local `Vector2.new(6, 0)`

The central spawn-clearance square therefore covers local X/Z `-2.5` through `+2.5`. Every archetype begins at local `Z = +3`, leaving the approved `0.5`-stud configured gap, and ends at local `Z = +7.5`, leaving the approved `0.5`-stud rear inset on a 16×16 pillar.

### Archetypes

All dimensions use local `X × Y × Z` order:

| Archetype | Part size | Purpose |
| --- | --- | --- |
| `ShortWide` | `Vector3.new(10.5, 3.25, 4.5)` | Wide low barrier that exposes the upper character and is approachable from either side. |
| `TallNarrow` | `Vector3.new(4.5, 7, 4.5)` | Strong vertical protection with deliberately limited horizontal coverage. |
| `LongLow` | `Vector3.new(12, 2.25, 4.5)` | Broadest lateral coverage with the weakest vertical protection. |
| `Chunky` | `Vector3.new(9.5, 5, 4.5)` | Bulky general-purpose cover that does not enclose or roof the player. |

Each archetype also has a neutral prototype color in `CoverConfig`; all use a simple configured material. Shapes are intentionally single rectangular Parts for this phase so tactical dimensions are independent from future art assets.

The literal occupied footprint differs by archetype. `LongLow` is closest to the requested 20–30% guideline; `TallNarrow` is intentionally below it because meeting that target would contradict its narrow tactical profile. Spawn safety and expansion access take priority over making every archetype meet an exact area percentage. `LongLow` lateral coverage and `Chunky` protection strength are explicit manual-playtest targets and are not reduced preemptively.

## Local-Space Placement

The existing starting-pillar CFrames face the arena center. In each pillar's local space:

- `-Z` is Forward/toward the center;
- `+Z` is Rear/away from the center;
- `-X` and `+X` are the two lateral directions.

Every cover is placed in the rear half at local `Z = +5.25`. The cover world transform is derived from the corresponding pillar rather than from hardcoded world directions:

```luau
local coverCFrame = pillar.CFrame * CFrame.new(
    0,
    pillar.Size.Y / 2 + archetype.Size.Y / 2,
    CoverConfig.LOCAL_REAR_OFFSET_Z
)
```

This rests the cover exactly on the pillar's top surface and preserves the same center-facing relationship around all eight circle positions.

## Spawn Safety and Reserved Expansion Access

Cover placement does not intersect the configured central `5×5` spawn-clearance square. It begins another `0.5` stud beyond that square, while the existing invisible spawn marker remains centered on the pillar. This guarantees that generated cover cannot intersect the marker or the character's initial placement transform.

The system reserves three logical `4×4` edge-center rectangles:

- Forward: local center `(0, -6)`;
- Left: local center `(-6, 0)`;
- Right: local center `(6, 0)`.

Because all cover occupies the rear band from local Z `+3` through `+7.5`, it does not overlap any of these zones even when `LongLow` reaches X `±6`. These are access reservations only; no expansion geometry, buttons, prompts, levels, or behavior is created.

Cover tests transform generated Part corners into the matching pillar's local space and verify:

- all horizontal bounds remain inside the 16×16 pillar;
- the Part bottom rests on the pillar top;
- no Part overlaps spawn clearance;
- no Part overlaps Forward, Left, or Right reserved rectangles.

## CoverService

`CoverService` provides this server-side API:

```luau
GenerateRoundCover(randomSource?) -> Folder?, string?
ClearRoundCover() -> boolean
GetCoverForPillar(pillarIndex) -> Model?
GetCoverArchetypeForPillar(pillarIndex) -> string?
```

`GenerateRoundCover` uses a module-owned server `Random` instance when no source is provided. Tests may supply any object implementing compatible `NextInteger(minimum, maximum)` behavior.

Generation performs the following:

1. Resolve `Workspace.GeneratedArena`, `PermanentGeometry`, and `SpawnMarkers`.
2. Discover exactly one starting-pillar Part and one spawn marker for every index from `1` through `ArenaConfig.PLAYER_COUNT`, using `PillarIndex` attributes as the authoritative association.
3. Validate the complete source geometry before publishing new cover.
4. Clear an existing `RoundCover` container.
5. Build a new unparented staging Folder.
6. Independently call `NextInteger(1, 4)` once for each pillar and construct its chosen archetype relative to that pillar.
7. Parent the completed Folder to `GeneratedArena` only after all eight covers are valid.
8. During Studio runs, print one concise diagnostic for each committed cover.

If validation or construction fails, the staging Folder is destroyed, no partial replacement is published, and the method returns an error. Since the previous round container is cleared before staging begins, failure leaves no stale cover.

Each pillar rolls independently. Duplicate archetypes across pillars and identical results for the same pillar in consecutive rounds are valid. There is no anti-repeat state or weighting.

Lookup methods inspect the committed `RoundCover` hierarchy and attributes rather than keeping a mirrored module-local assignment table. This avoids a second cover source of truth and keeps diagnostics tied to actual Workspace geometry.

`ClearRoundCover` returns whether a generated container was removed and is idempotent when no container exists.

## Round Lifecycle Integration

`RoundController` gains a required narrow `CoverService` dependency. Its existing state ownership does not move into the cover service.

On entering `STARTING`, before participant selection, assignment, or character loading, the controller:

1. clears stale round cover;
2. asks `CoverService` to generate all eight covers;
3. aborts to `WAITING` if generation fails;
4. otherwise continues the existing participant selection, shuffle, assignment, and spawn flow unchanged.

This ordering guarantees that no participant sees cover appear around an already spawned character. All eight pillars receive cover even when fewer than eight players participate.

The existing generation-scoped cleanup path calls `ClearRoundCover` for:

- a `STARTING` abort caused by cover generation failure;
- a later assignment, spawn, death, or disconnection failure that leaves too few valid participants;
- normal `ENDING` cleanup;
- controller shutdown.

Cover stays present throughout `ACTIVE` and the configured `ENDING` delay. Cleanup removes it before the transition back to `WAITING`, so both `WAITING` and `COUNTDOWN` remain cover-free.

Cover generation does not consume the participant-shuffle random source. `CoverService` has its own production random source, so pillar-assignment shuffle draws and cover rolls are independently generated.

## Concurrency and Failure Safety

The existing single-lifecycle and session-token safeguards remain in force. Cover generation itself does not yield. The controller validates its session/state before proceeding to participant spawning.

The shared per-generation cleanup guard prevents duplicate cleanup. `ClearRoundCover` is independently idempotent, so a late shutdown or overlapping failure request cannot remove persistent arena geometry or fail because cover was already removed.

No player callbacks are added by `CoverService`.

## Studio Diagnostics

After committing the complete `RoundCover` folder, `CoverService` emits exactly one line per pillar when `RunService:IsStudio()`:

```text
PILLARS cover: Pillar 1 -> TallNarrow
PILLARS cover: Pillar 2 -> Chunky
PILLARS cover: Pillar 3 -> ShortWide
PILLARS cover: Pillar 4 -> LongLow
```

The lines are emitted from the gameplay server context and read the archetypes from the committed Models. No diagnostic snapshot, replicated state, or Command Bar module require is used.

## Testing Strategy

### Cover configuration and service tests

Focused Studio `RunScript` tests will verify:

1. Exactly eight per-pillar cover Models generate.
2. Every index has exactly one model and exactly one basic Part.
3. Every model and Part has a valid configured archetype.
4. A supplied random source is called once per pillar and controls selection.
5. A second and third generation make eight new random calls each.
6. Identical consecutive results remain valid.
7. Duplicate archetypes across pillars remain valid.
8. Persistent arena Parts retain their identity, parent, size, CFrame, and attributes.
9. Cover does not overlap the matching marker's configured clearance area.
10. Every cover remains within its starting-pillar bounds and rests on top.
11. Forward, Left, and Right reserved zones remain unobstructed.
12. Cover Parts are anchored and locked.
13. Cover Parts are collidable.
14. Models and Parts carry `PermanentCover`, `PillarIndex`, and `CoverArchetype` metadata.
15. Both lookup APIs return the committed model/archetype.
16. Clearing removes only `RoundCover` and is idempotent.
17. Regeneration leaves exactly one current folder and one cover per pillar.

### Round integration tests

The injected controller test service records generation and clearing without duplicating production cover state. Tests verify:

18. Cover generation completes before the first participant spawn begins.
19. An aborted `STARTING` removes generated cover.
20. Normal `ENDING` cleanup removes generated cover.
21. Second and third rounds each regenerate once without stale state.
22. Cover-generation failure returns safely to `WAITING` without spawning participants.

### Regression and build verification

The full verification run retains:

- Prompt 001 arena layout, regeneration, and live void-touch elimination tests;
- Prompt 002 assignment, controlled spawning, concurrency, departure, and Studio diagnostics tests;
- Prompt 003 state, shuffle, setup, death, departure, winner, cleanup, and repeated-round tests;
- a complete Rojo build;
- `git diff --check`;
- a production-source scope scan confirming no forbidden Prompt 005 system, SpawnLocation, RemoteEvent, or alternate lifecycle owner was introduced.

## Four-Client Studio Verification

Use Studio's **Server & Clients** test mode with four clients and inspect the Server Output.

1. Start four clients and confirm the normal countdown.
2. During `STARTING`, confirm eight `PILLARS cover` lines appear before the first assignment diagnostic.
3. Inspect `Workspace.GeneratedArena.RoundCover` and verify `PillarCover01` through `PillarCover08` exist.
4. Confirm all four participants spawn at separate markers without intersecting cover.
5. Walk and jump around each occupied pillar. Cover must behave as fixed solid geometry without trapping the player or blocking the Forward/Left/Right approaches.
6. Eliminate three players by setting their real Humanoid health to zero from the Server Command Bar. Do not require a stateful gameplay module.
7. Confirm the survivor is declared the winner and cover remains throughout the ending delay.
8. Confirm all eight cover Models disappear during cleanup before `WAITING`.
9. Confirm the next `STARTING` creates exactly eight new covers and logs eight fresh rolls before players spawn.
10. Compare the two rounds' logs. Repeated archetypes are legitimate; the evidence of rerolling is the new set of eight generation lines and the absence of stale Models.
11. Confirm the center platform and original starting pillars never change across either round.

Safe elimination input:

```luau
local player = game.Players:FindFirstChild("Player1")
local humanoid = player and player.Character
    and player.Character:FindFirstChildOfClass("Humanoid")

if humanoid then
    humanoid.Health = 0
end
```

Authoritative assignment and cover verification comes from diagnostics produced in the gameplay server context, not from requiring stateful modules in the Command Bar.

## Manual Visual-Balance Review

The playtest should answer:

- Does each cover feel too large or too small on a 16×16 pillar?
- Does `TallNarrow` provide useful protection despite its narrow width?
- Does `ShortWide` expose enough of a normal avatar?
- Does `Chunky` feel unfairly strong at the approved initial dimensions?
- Does `LongLow` consume too much lateral movement space at 12 studs wide?
- Is there enough open surface for later dropped items?
- Does the overall pillar feel cramped once cover is present?
- Would Speed Coil and Gravity Coil movement remain feasible around the obstacle?
- Are the Forward, Left, and Right edge-center approaches visibly unobstructed?

These are tuning questions only. The approved initial values are implemented unchanged before the visual playtest.

## Assumptions

- The eight existing starting pillars and spawn markers remain the authoritative geometry and are present before a round starts.
- Starting pillars remain 16×16 for this prototype; bounds tests derive from actual pillar size where possible.
- One basic Part per archetype is sufficient until visual assets replace prototype shapes.
- Cover remains indestructible by metadata and ownership convention; no damage system exists yet.
- All eight pillars receive cover regardless of current participant count.
- A failed participant is not replaced during setup, matching Prompt 003 behavior.
- Cover does not reroll during `ACTIVE`; it rerolls exactly once on every successful entry into `STARTING`.
