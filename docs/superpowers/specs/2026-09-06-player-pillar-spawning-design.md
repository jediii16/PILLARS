# PILLARS Player-to-Pillar Assignment and Spawning Design

## Scope

Prompt 002 adds deterministic, server-authoritative pillar assignment and explicit character spawning for up to `ArenaConfig.PLAYER_COUNT` participating players. It uses the arena's existing spawn-marker Parts and introduces no `SpawnLocation`, RemoteEvent, lobby, spectator, round, combat, or other later gameplay system.

## Architecture

### PlayerSpawnService

`PlayerSpawnService` is a reusable server ModuleScript. It owns all session-level assignment state and controlled spawning behavior. It does not connect permanent player lifecycle events itself, so a future `RoundService` can call it without inheriting prototype join behavior.

The service maintains:

- A player-to-pillar map for direct ownership lookup.
- A pillar-to-player map for reverse ownership lookup.
- A monotonically increasing assignment revision per player so a release, clear, or reassignment invalidates an older yielding spawn request.
- An in-flight spawn set that permits at most one active `SpawnPlayer` operation per player.

Assignment keys are server-owned Player instances in production. State is memory-only and is never persisted between servers.

### DevelopmentSpawnBootstrap

`DevelopmentSpawnBootstrap` is the only Prompt 002 component that connects `Players.PlayerAdded` and `Players.PlayerRemoving`. It provides the temporary test behavior that will later be replaced by `RoundService`.

The bootstrap disables automatic Roblox character loading, starts after the arena has generated, assigns and spawns each existing or newly joining player, and releases a leaving player's assignment. If no pillar is available, it emits a clear warning and leaves the player unassigned and characterless. It does not revisit waiting players when a pillar later becomes available.

## Public API

`PlayerSpawnService` exposes:

- `AssignPlayer(player) -> number?`: Returns the player's existing pillar if already assigned; otherwise claims the lowest free index from `1` through `ArenaConfig.PLAYER_COUNT`. Returns `nil` when full.
- `GetPillarIndex(player) -> number?`: Returns the player's current pillar index.
- `GetPlayerForPillar(pillarIndex) -> Player?`: Returns the current owner, or `nil`. Invalid indices also return `nil` rather than accessing unrelated state.
- `SpawnPlayer(player) -> (Model?, string?)`: Explicitly creates and positions the assigned player's character. Returns the character on success or `nil` plus a descriptive reason on failure.
- `ReleasePlayer(player) -> number?`: Releases and returns the prior pillar index, or returns `nil` when the player had no assignment. It invalidates any yielding spawn for that assignment.
- `ClearAssignments() -> ()`: Invalidates current assignment revisions and empties both ownership maps. It does not kill, move, respawn, or promote players.

These operations are server-only. No client-supplied pillar data is accepted.

## Deterministic Assignment

`AssignPlayer` scans pillar indices in ascending order using `ArenaConfig.PLAYER_COUNT`. The first participant receives pillar 1, the second receives pillar 2, and so on. Repeated assignment of the same player is idempotent. A released low-numbered pillar becomes the next available pillar.

The API accepts players individually, allowing a future `RoundService` to shuffle a participant list before calling `AssignPlayer` without changing assignment internals. Randomization is not implemented in Prompt 002.

## Spawn Marker Resolution

Every `SpawnPlayer` call dynamically resolves:

`Workspace.GeneratedArena.SpawnMarkers`

It finds the unique BasePart whose `PillarIndex` attribute matches the player's assigned pillar. The marker's CFrame is the source of truth; marker names are useful for inspection but are not the authoritative lookup key. Resolution rejects missing folders, missing markers, duplicate matching marker attributes, and non-BasePart matches with descriptive failure text.

The service resolves markers at spawn time rather than caching Parts, so arena regeneration does not leave stale marker references.

## Controlled Character Spawning

The temporary bootstrap sets `Players.CharacterAutoLoads = false` before processing players. `SpawnPlayer` follows this sequence:

1. Reject a concurrent spawn already in flight for the same player.
2. Read the player's assigned pillar and assignment revision.
3. Confirm that the player is still parented to `Players`.
4. Resolve the matching current arena marker before loading a character.
5. Mark the player as having one in-flight spawn operation.
6. Call the server-side asynchronous character-loading API inside protected error handling.
7. After loading yields, confirm that the player is still present and the assignment revision is unchanged.
8. Obtain the resulting character and wait for `HumanoidRootPart` with a finite timeout.
9. Recheck player presence and assignment revision after the wait.
10. Pivot the complete character to the marker CFrame, which is already positioned slightly above its pillar by Prompt 001.
11. Clear the in-flight guard on every success or failure path.

If the player leaves or their assignment changes while spawning, the operation exits without positioning an obsolete character. If a character was created for a player who has already left, the service destroys that orphaned model when safe to do so. Concurrent calls return a descriptive `spawn already in progress` result rather than loading a second character.

## Death Behavior

`Players.CharacterAutoLoads = false` prevents Roblox from automatically replacing dead characters. The service does not attach a death listener and the development bootstrap calls `SpawnPlayer` only during initial join processing. Therefore death leaves the player dead until a future system explicitly calls `SpawnPlayer`.

An unmanaged template `SpawnLocation` is not used by this system. Because automatic loading is disabled it cannot choose a spawn during Prompt 002, but it should be manually removed from the Studio place after verification to avoid confusion and future accidental behavior if automatic loading is enabled again. Rojo-managed Workspace content is not silently restructured.

## Temporary Bootstrap Flow

Server startup proceeds in this order:

1. Disable automatic character loading.
2. Run Studio-only Prompt 001 tests.
3. Generate the arena.
4. Run Studio-only focused assignment tests with isolated fake participant keys and clear the test state.
5. Start `DevelopmentSpawnBootstrap`.
6. Process any players who joined during server initialization, then handle later `PlayerAdded` events.

For each prototype participant, the bootstrap calls `AssignPlayer`; on success it calls `SpawnPlayer`. Failures are warned on the server. On `PlayerRemoving`, it calls `ReleasePlayer`. It never automatically retries an unassigned waiting player.

## Failure Handling

Expected capacity and lifecycle conditions return `nil` plus a reason where applicable rather than throwing. Invalid arena state during spawning produces a descriptive spawn failure and no character load if marker resolution fails early. Unexpected failures from character loading are caught, the in-flight guard is cleared, and the error is returned to the caller for logging or round-level policy.

Assignment operations never yield, so their two maps update atomically within one Luau thread. Spawn operations may yield but do not mutate ownership, and their revision checks prevent stale completion.

## Testing Strategy

Focused service tests use opaque server-side participant objects for assignment behavior and validate:

- First assignment receives pillar 1.
- Two participants receive different pillars.
- Exactly `ArenaConfig.PLAYER_COUNT` unique pillars can be occupied.
- A ninth participant receives no assignment.
- Both query directions return reliable ownership.
- Idempotent reassignment preserves ownership.
- Release frees the pillar for reuse.
- Clear removes both directions and makes every pillar available.
- Invalid pillar indices return no owner.

Spawn-focused tests use the real generated arena plus controlled fake player objects whose asynchronous loader returns real character Models. They validate marker-based positioning, missing assignments, no generated `SpawnLocation`, concurrent-call rejection, and cancellation when the player leaves or an assignment is released during a yield.

Runtime Studio verification validates the real `Players` lifecycle: unique multiplayer placement, assignment release after a client leaves, no ninth-player character, and no automatic respawn after Humanoid death. Prompt 001 arena suites and the Rojo build run unchanged as regressions.

## Assumptions

- A Player is considered connected only while its direct parent is the `Players` service.
- The existing spawn-marker CFrame already includes the safe above-platform offset; Prompt 002 adds no second positional offset.
- `ClearAssignments` affects ownership only and deliberately leaves existing characters untouched.
- Releasing an assignment does not automatically destroy the player's current character.
- The ninth player remains connected, unassigned, and characterless until an external system explicitly calls the service after capacity becomes available.
