local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")

local ArenaConfig = require(script.Parent.Parent.Arena.ArenaConfig)
local ArenaService = require(script.Parent.Parent.Arena.ArenaService)
local PlayerSpawnService = require(script.Parent.PlayerSpawnService)

local EPSILON = 1e-4

local function newFakePlayer(name: string, loadCharacterAsync)
	return {
		Name = name,
		Parent = Players,
		Character = nil,
		LoadCharacterAsync = loadCharacterAsync,
	}
end

local function newCharacter(name: string): Model
	local character = Instance.new("Model")
	character.Name = name

	local rootPart = Instance.new("Part")
	rootPart.Name = "HumanoidRootPart"
	rootPart.Size = Vector3.new(2, 2, 1)
	rootPart.Parent = character

	character.PrimaryPart = rootPart
	character.Parent = Workspace
	return character
end

local function waitUntil(predicate, message: string)
	local deadline = os.clock() + 5

	while not predicate() and os.clock() < deadline do
		task.wait()
	end

	assert(predicate(), message)
end

local function makeBlockedLoader(player, gate: BindableEvent, state)
	return function()
		state.started = true
		gate.Event:Wait()
		local character = newCharacter(player.Name .. "Character")
		player.Character = character
	end
end

local PlayerSpawnServiceTests = {}

function PlayerSpawnServiceTests.Run()
	ArenaService.Generate()
	PlayerSpawnService.ClearAssignments()

	local players = {}

	for index = 1, ArenaConfig.PLAYER_COUNT + 1 do
		players[index] = newFakePlayer(string.format("Player%02d", index), function() end)
	end

	for index = 1, ArenaConfig.PLAYER_COUNT do
		local player = players[index]
		assert(PlayerSpawnService.AssignPlayer(player) == index, "players must receive sequential pillars")
		assert(PlayerSpawnService.AssignPlayer(player) == index, "assignment must be idempotent")
		assert(PlayerSpawnService.GetPillarIndex(player) == index, "player lookup must return its pillar")
		assert(PlayerSpawnService.GetPlayerForPillar(index) == player, "pillar lookup must return its player")
	end

	local overflowPlayer = players[ArenaConfig.PLAYER_COUNT + 1]
	assert(PlayerSpawnService.AssignPlayer(overflowPlayer) == nil, "an overflow player must remain unassigned")
	assert(PlayerSpawnService.GetPillarIndex(overflowPlayer) == nil, "overflow player must have no assignment")

	assert(PlayerSpawnService.ReleasePlayer(players[4]) == 4, "release must return the freed pillar")
	assert(PlayerSpawnService.GetPillarIndex(players[4]) == nil, "released player lookup must clear")
	assert(PlayerSpawnService.GetPlayerForPillar(4) == nil, "released pillar lookup must clear")
	assert(PlayerSpawnService.AssignPlayer(overflowPlayer) == 4, "lowest available pillar must be reused")

	PlayerSpawnService.ClearAssignments()

	for pillarIndex = 1, ArenaConfig.PLAYER_COUNT do
		assert(PlayerSpawnService.GetPlayerForPillar(pillarIndex) == nil, "clear must free every pillar")
	end

	local disconnectedPlayer = newFakePlayer("Disconnected", function() end)
	disconnectedPlayer.Parent = nil
	assert(PlayerSpawnService.AssignPlayer(disconnectedPlayer) == nil, "disconnected players must not be assigned")

	local spawnPlayer
	spawnPlayer = newFakePlayer("SpawnSuccess", function()
		local character = newCharacter("SpawnSuccessCharacter")
		spawnPlayer.Character = character
	end)
	assert(PlayerSpawnService.AssignPlayer(spawnPlayer) == 1, "spawn test player must receive pillar 1")

	local spawnedCharacter, spawnError = PlayerSpawnService.SpawnPlayer(spawnPlayer)
	assert(spawnedCharacter ~= nil and spawnError == nil, "assigned player must spawn successfully")

	local arena = Workspace:FindFirstChild(ArenaConfig.GENERATED_MODEL_NAME)
	local spawnMarkers = arena and arena:FindFirstChild(ArenaConfig.SPAWN_MARKERS_FOLDER_NAME)
	local marker = spawnMarkers and spawnMarkers:FindFirstChild("PillarSpawn01")
	local rootPart = spawnedCharacter and spawnedCharacter:FindFirstChild("HumanoidRootPart")
	assert(marker and marker:IsA("BasePart"), "pillar 1 marker must exist")
	assert(rootPart and rootPart:IsA("BasePart"), "spawned character root must exist")
	assert((rootPart.CFrame.Position - marker.CFrame.Position).Magnitude <= EPSILON, "character must move to its marker")
	spawnedCharacter:Destroy()
	PlayerSpawnService.ClearAssignments()

	local unassigned = newFakePlayer("Unassigned", function()
		error("unassigned player loader must not run")
	end)
	local unassignedCharacter, unassignedError = PlayerSpawnService.SpawnPlayer(unassigned)
	assert(unassignedCharacter == nil and unassignedError ~= nil, "unassigned players must not spawn")

	local duplicateMarker = marker:Clone()
	duplicateMarker.Name = "DuplicatePillarSpawn01"
	duplicateMarker.Parent = spawnMarkers
	assert(PlayerSpawnService.AssignPlayer(unassigned) == 1, "duplicate marker test player must be assigned")
	local duplicateCharacter, duplicateError = PlayerSpawnService.SpawnPlayer(unassigned)
	assert(duplicateCharacter == nil, "ambiguous spawn markers must prevent spawning")
	assert(string.find(duplicateError, "multiple spawn markers", 1, true), "ambiguous marker error must be clear")
	duplicateMarker:Destroy()
	PlayerSpawnService.ClearAssignments()

	local concurrentGate = Instance.new("BindableEvent")
	local concurrentState = { started = false, finished = false }
	local concurrentPlayer = newFakePlayer("Concurrent", nil)
	concurrentPlayer.LoadCharacterAsync = makeBlockedLoader(concurrentPlayer, concurrentGate, concurrentState)
	assert(PlayerSpawnService.AssignPlayer(concurrentPlayer) == 1, "concurrent test player must be assigned")

	task.spawn(function()
		concurrentState.character, concurrentState.error = PlayerSpawnService.SpawnPlayer(concurrentPlayer)
		concurrentState.finished = true
	end)

	waitUntil(function()
		return concurrentState.started
	end, "first spawn operation must begin")

	local duplicateSpawn, duplicateSpawnError = PlayerSpawnService.SpawnPlayer(concurrentPlayer)
	assert(duplicateSpawn == nil, "concurrent duplicate spawn must be rejected")
	assert(string.find(duplicateSpawnError, "already in progress", 1, true), "concurrent rejection must be clear")
	concurrentGate:Fire()
	waitUntil(function()
		return concurrentState.finished
	end, "first spawn operation must finish")
	assert(concurrentState.character ~= nil and concurrentState.error == nil, "first spawn operation must remain consistent")
	concurrentState.character:Destroy()
	concurrentGate:Destroy()
	PlayerSpawnService.ClearAssignments()

	local leavingGate = Instance.new("BindableEvent")
	local leavingState = { started = false, finished = false }
	local leavingPlayer = newFakePlayer("Leaving", nil)
	leavingPlayer.LoadCharacterAsync = makeBlockedLoader(leavingPlayer, leavingGate, leavingState)
	assert(PlayerSpawnService.AssignPlayer(leavingPlayer) == 1, "leaving test player must be assigned")

	task.spawn(function()
		leavingState.character, leavingState.error = PlayerSpawnService.SpawnPlayer(leavingPlayer)
		leavingState.finished = true
	end)

	waitUntil(function()
		return leavingState.started
	end, "leaving spawn operation must begin")
	leavingPlayer.Parent = nil
	leavingGate:Fire()
	waitUntil(function()
		return leavingState.finished
	end, "leaving spawn operation must finish")
	assert(leavingState.character == nil and leavingState.error ~= nil, "departed player spawn must be cancelled")
	assert(leavingPlayer.Character.Parent == nil, "departed player's unpositioned character must be destroyed")
	leavingGate:Destroy()
	PlayerSpawnService.ReleasePlayer(leavingPlayer)

	local releasedGate = Instance.new("BindableEvent")
	local releasedState = { started = false, finished = false }
	local releasedPlayer = newFakePlayer("Released", nil)
	releasedPlayer.LoadCharacterAsync = makeBlockedLoader(releasedPlayer, releasedGate, releasedState)
	assert(PlayerSpawnService.AssignPlayer(releasedPlayer) == 1, "released test player must be assigned")

	task.spawn(function()
		releasedState.character, releasedState.error = PlayerSpawnService.SpawnPlayer(releasedPlayer)
		releasedState.finished = true
	end)

	waitUntil(function()
		return releasedState.started
	end, "released spawn operation must begin")
	PlayerSpawnService.ReleasePlayer(releasedPlayer)
	releasedGate:Fire()
	waitUntil(function()
		return releasedState.finished
	end, "released spawn operation must finish")
	assert(releasedState.character == nil and releasedState.error ~= nil, "released assignment must cancel spawn")
	assert(releasedPlayer.Character.Parent == nil, "released player's unpositioned character must be destroyed")
	releasedGate:Destroy()

	assert(arena:FindFirstChildWhichIsA("SpawnLocation", true) == nil, "service must not create SpawnLocations")
	PlayerSpawnService.ClearAssignments()
	arena:Destroy()
end

return PlayerSpawnServiceTests
