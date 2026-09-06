local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")

local ArenaConfig = require(script.Parent.Parent.Arena.ArenaConfig)

local ROOT_PART_TIMEOUT_SECONDS = 10

local playerToPillar = {}
local pillarToPlayer = {}
local assignmentRevisions = setmetatable({}, { __mode = "k" })
local spawnInFlight = setmetatable({}, { __mode = "k" })

local PlayerSpawnService = {}

local function getRevision(player): number
	return assignmentRevisions[player] or 0
end

local function incrementRevision(player)
	assignmentRevisions[player] = getRevision(player) + 1
end

local function isCurrentSpawn(player, pillarIndex: number, revision: number): boolean
	return player.Parent == Players
		and playerToPillar[player] == pillarIndex
		and getRevision(player) == revision
end

local function findSpawnMarker(pillarIndex: number): (BasePart?, string?)
	local arena = Workspace:FindFirstChild(ArenaConfig.GENERATED_MODEL_NAME)

	if not arena then
		return nil, "generated arena is unavailable"
	end

	local spawnMarkers = arena:FindFirstChild(ArenaConfig.SPAWN_MARKERS_FOLDER_NAME)

	if not spawnMarkers then
		return nil, "arena spawn markers are unavailable"
	end

	local matchingMarker = nil

	for _, child in spawnMarkers:GetChildren() do
		if child:IsA("BasePart") and child:GetAttribute("PillarIndex") == pillarIndex then
			if matchingMarker then
				return nil, string.format("multiple spawn markers use PillarIndex %d", pillarIndex)
			end

			matchingMarker = child
		end
	end

	if not matchingMarker then
		return nil, string.format("no spawn marker uses PillarIndex %d", pillarIndex)
	end

	return matchingMarker, nil
end

local function destroyUnpositionedCharacter(character)
	if character and character.Parent then
		character:Destroy()
	end
end

function PlayerSpawnService.AssignPlayer(player): number?
	local existingPillar = playerToPillar[player]

	if existingPillar then
		return existingPillar
	end

	if player.Parent ~= Players then
		return nil
	end

	for pillarIndex = 1, ArenaConfig.PLAYER_COUNT do
		if pillarToPlayer[pillarIndex] == nil then
			playerToPillar[player] = pillarIndex
			pillarToPlayer[pillarIndex] = player
			incrementRevision(player)
			return pillarIndex
		end
	end

	return nil
end

function PlayerSpawnService.GetPillarIndex(player): number?
	return playerToPillar[player]
end

function PlayerSpawnService.GetPlayerForPillar(pillarIndex: number)
	return pillarToPlayer[pillarIndex]
end

function PlayerSpawnService.SpawnPlayer(player): (Model?, string?)
	if spawnInFlight[player] then
		return nil, "a spawn operation is already in progress for this player"
	end

	local pillarIndex = playerToPillar[player]

	if not pillarIndex then
		return nil, "player has no pillar assignment"
	end

	if player.Parent ~= Players then
		return nil, "player left before spawning"
	end

	local spawnMarker, markerError = findSpawnMarker(pillarIndex)

	if not spawnMarker then
		return nil, markerError
	end

	local revision = getRevision(player)
	local spawnCFrame = spawnMarker.CFrame
	local characterBeforeSpawn = player.Character
	spawnInFlight[player] = true

	local succeeded, characterOrError, spawnError = pcall(function()
		player:LoadCharacterAsync()

		local character = player.Character

		if not character or not character:IsA("Model") then
			return nil, "character loading completed without a character Model"
		end

		if not isCurrentSpawn(player, pillarIndex, revision) then
			destroyUnpositionedCharacter(character)
			return nil, "spawn was cancelled while the character was loading"
		end

		local rootPart = character:WaitForChild("HumanoidRootPart", ROOT_PART_TIMEOUT_SECONDS)

		if not rootPart or not rootPart:IsA("BasePart") then
			destroyUnpositionedCharacter(character)
			return nil, "character has no HumanoidRootPart"
		end

		if not isCurrentSpawn(player, pillarIndex, revision) then
			destroyUnpositionedCharacter(character)
			return nil, "spawn was cancelled before character positioning"
		end

		character:PivotTo(spawnCFrame)
		return character, nil
	end)

	spawnInFlight[player] = nil

	if not succeeded then
		local currentCharacter = player.Character

		if currentCharacter ~= characterBeforeSpawn then
			destroyUnpositionedCharacter(currentCharacter)
		end

		return nil, string.format("character spawn failed: %s", tostring(characterOrError))
	end

	return characterOrError, spawnError
end

function PlayerSpawnService.ReleasePlayer(player): number?
	local pillarIndex = playerToPillar[player]

	if not pillarIndex then
		return nil
	end

	playerToPillar[player] = nil

	if pillarToPlayer[pillarIndex] == player then
		pillarToPlayer[pillarIndex] = nil
	end

	incrementRevision(player)
	return pillarIndex
end

function PlayerSpawnService.ClearAssignments()
	for player in playerToPillar do
		incrementRevision(player)
		playerToPillar[player] = nil
	end

	for pillarIndex in pillarToPlayer do
		pillarToPlayer[pillarIndex] = nil
	end
end

return PlayerSpawnService
