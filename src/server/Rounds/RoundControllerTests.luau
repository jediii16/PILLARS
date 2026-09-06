local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")

local ArenaConfig = require(script.Parent.Parent.Arena.ArenaConfig)
local ArenaService = require(script.Parent.Parent.Arena.ArenaService)
local PlayerSpawnService = require(script.Parent.Parent.Players.PlayerSpawnService)
local RoundController = require(script.Parent.RoundController)
local RoundState = require(script.Parent.RoundState)

local RoundControllerTests = {}

local function newConfig(overrides)
	local config = {
		MIN_PLAYERS = 2,
		COUNTDOWN_DURATION = 0,
		END_ROUND_DELAY = 0,
		WAITING_CHECK_INTERVAL = 0,
	}

	for key, value in overrides or {} do
		config[key] = value
	end

	return config
end

local function newRandom(choices)
	local index = 0
	local random = {}

	function random:NextInteger(minimum: number, maximum: number): number
		index += 1
		local choice = choices and choices[index] or maximum
		choice = choice or maximum
		assert(choice >= minimum and choice <= maximum, "test random choice must be in range")
		return choice
	end

	function random:GetCallCount(): number
		return index
	end

	return random
end


local function createCharacter(name: string): Model
	local character = Instance.new("Model")
	character.Name = name .. "Character"

	local humanoid = Instance.new("Humanoid")
	humanoid.Parent = character

	local rootPart = Instance.new("Part")
	rootPart.Name = "HumanoidRootPart"
	rootPart.Size = Vector3.new(2, 2, 1)
	rootPart.Parent = character

	character.PrimaryPart = rootPart
	character.Parent = Workspace
	return character
end

local function newPlayer(name: string, options)
	local player = {
		Name = name,
		Parent = Players,
		Character = nil,
		LoadCount = 0,
	}

	function player:LoadCharacterAsync()
		self.LoadCount += 1

		if options and options.BeforeLoad then
			options.BeforeLoad(self)
		end

		if options and options.Fail then
			error("intentional test spawn failure")
		end

		local character = createCharacter(self.Name)
		self.Character = character

		if options and options.AfterCreate then
			options.AfterCreate(self, character)
		end
	end

	return player
end


local function newHarness(initialPlayers, options)
	local eligiblePlayers = table.clone(initialPlayers)
	local waitCount = 0
	local deathCallbacks = {}
	local random = (options and options.Random) or newRandom(nil)
	local config = newConfig(options and options.Config)
	local harness = {}

	function harness.GetEligiblePlayers()
		return table.clone(eligiblePlayers)
	end

	function harness.Wait(duration: number)
		waitCount += 1

		if options and options.OnWait then
			options.OnWait(waitCount, duration, eligiblePlayers)
		end

		task.wait()
	end

	harness.Players = eligiblePlayers
	harness.Random = random
	harness.ConnectHumanoidDied = function(humanoid, callback)
		deathCallbacks[humanoid] = callback
		local connected = true

		return {
			Disconnect = function()
				if connected then
					connected = false
					if deathCallbacks[humanoid] == callback then
						deathCallbacks[humanoid] = nil
					end
				end
			end,
		}
	end
	function harness.Kill(player)
		local humanoid = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
		assert(humanoid, "test participant must have a Humanoid")
		humanoid.Health = 0
		local callback = deathCallbacks[humanoid]

		if callback then
			callback()
		end
	end
	harness.Controller = RoundController.new({
		Config = config,
		GetEligiblePlayers = harness.GetEligiblePlayers,
		Wait = harness.Wait,
		Random = random,
		PlayerSpawnService = PlayerSpawnService,
		ConnectHumanoidDied = harness.ConnectHumanoidDied,
	})

	return harness
end

local function advanceThroughSetup(controller)
	controller:Advance()
	assert(controller:GetState() == RoundState.COUNTDOWN, "eligible waiting must enter countdown")
	controller:Advance()
	assert(controller:GetState() == RoundState.STARTING, "completed countdown must enter starting")
	controller:Advance()
end

local function waitUntil(predicate, message: string)
	local deadline = os.clock() + 5

	while not predicate() and os.clock() < deadline do
		task.wait()
	end

	assert(predicate(), message)
end

local function resetScenario(controller)
	if controller then
		controller:Stop()
	end

	PlayerSpawnService.ClearAssignments()
end

local function getSpawnMarker(pillarIndex: number): BasePart
	local arena = Workspace:FindFirstChild(ArenaConfig.GENERATED_MODEL_NAME)
	local spawnMarkers = arena and arena:FindFirstChild(ArenaConfig.SPAWN_MARKERS_FOLDER_NAME)

	for _, child in spawnMarkers and spawnMarkers:GetChildren() or {} do
		if child:IsA("BasePart") and child:GetAttribute("PillarIndex") == pillarIndex then
			return child
		end
	end

	error(string.format("missing test spawn marker for pillar %d", pillarIndex))
end

function RoundControllerTests.Run()
	ArenaService.Generate()
	PlayerSpawnService.ClearAssignments()

	do
		local lonePlayer = newPlayer("LonePlayer")
		local harness = newHarness({ lonePlayer })
		harness.Controller:Advance()
		assert(harness.Controller:GetState() == RoundState.WAITING, "below minimum must remain waiting")
		assert(PlayerSpawnService.GetPillarIndex(lonePlayer) == nil, "waiting must not assign a pillar")
		assert(lonePlayer.Character == nil, "waiting must not spawn a character")
		resetScenario(harness.Controller)
	end

	do
		local first = newPlayer("CountdownFirst")
		local second = newPlayer("CountdownSecond")
		local harness = newHarness({ first, second }, {
			Config = { COUNTDOWN_DURATION = 1 },
			OnWait = function(_waitCount, _duration, eligiblePlayers)
				table.remove(eligiblePlayers, 2)
				second.Parent = nil
			end,
		})

		harness.Controller:Advance()
		assert(harness.Controller:GetState() == RoundState.COUNTDOWN, "minimum players must begin countdown")
		harness.Controller:Advance()
		assert(harness.Controller:GetState() == RoundState.WAITING, "countdown must cancel below minimum")
		assert(PlayerSpawnService.GetPillarIndex(first) == nil, "cancelled countdown must not assign")
		resetScenario(harness.Controller)
	end

	do
		local players = {}

		for index = 1, ArenaConfig.PLAYER_COUNT + 1 do
			players[index] = newPlayer(string.format("CapPlayer%02d", index))
		end

		local harness = newHarness(players)
		advanceThroughSetup(harness.Controller)
		assert(harness.Controller:GetState() == RoundState.ACTIVE, "successful setup must become active")
		assert(harness.Controller:GetAliveCount() == ArenaConfig.PLAYER_COUNT, "participation must respect arena capacity")

		for index = 1, ArenaConfig.PLAYER_COUNT do
			assert(PlayerSpawnService.GetPillarIndex(players[index]) == index, "selected players must receive unique pillars")
			assert(players[index].Character ~= nil, "selected players must spawn")
			local marker = getSpawnMarker(index)
			local rootPart = players[index].Character:FindFirstChild("HumanoidRootPart")
			assert((rootPart.Position - marker.Position).Magnitude < 0.001, "participant must spawn at the assigned marker")
		end

		local overflow = players[ArenaConfig.PLAYER_COUNT + 1]
		assert(PlayerSpawnService.GetPillarIndex(overflow) == nil, "overflow player must remain unassigned")
		assert(overflow.Character == nil, "overflow player must remain characterless")
		resetScenario(harness.Controller)
	end

	do
		local first = newPlayer("ShuffleA")
		local second = newPlayer("ShuffleB")
		local third = newPlayer("ShuffleC")
		local random = newRandom({ 1, 1 })
		local harness = newHarness({ first, second, third }, { Random = random })
		advanceThroughSetup(harness.Controller)
		assert(PlayerSpawnService.GetPillarIndex(second) == 1, "shuffled first player must receive pillar 1")
		assert(PlayerSpawnService.GetPillarIndex(third) == 2, "shuffled second player must receive pillar 2")
		assert(PlayerSpawnService.GetPillarIndex(first) == 3, "shuffled third player must receive pillar 3")
		assert(random:GetCallCount() == 2, "three participants require two shuffle choices")
		resetScenario(harness.Controller)
	end

	do
		local first = newPlayer("SetupValidA")
		local failed = newPlayer("SetupFailed", { Fail = true })
		local third = newPlayer("SetupValidB")
		local harness = newHarness({ first, failed, third })
		advanceThroughSetup(harness.Controller)
		assert(harness.Controller:GetState() == RoundState.ACTIVE, "setup may continue with the minimum valid players")
		assert(harness.Controller:GetAliveCount() == 2, "failed spawn must not be alive")
		assert(PlayerSpawnService.GetPillarIndex(failed) == nil, "failed setup assignment must be released")
		resetScenario(harness.Controller)
	end

	do
		local first = newPlayer("DisconnectSetupA")
		local disconnected = newPlayer("DisconnectSetupLost", {
			BeforeLoad = function(player)
				player.Parent = nil
			end,
		})
		local third = newPlayer("DisconnectSetupB")
		local harness = newHarness({ first, disconnected, third })
		advanceThroughSetup(harness.Controller)
		assert(harness.Controller:GetState() == RoundState.ACTIVE, "setup may continue after a disconnect with enough valid players")
		assert(harness.Controller:GetAliveCount() == 2, "disconnected setup player must not be alive")
		assert(not harness.Controller:IsParticipant(disconnected), "disconnected setup player must not participate")
		assert(PlayerSpawnService.GetPillarIndex(disconnected) == nil, "disconnected setup assignment must be released")
		assert(disconnected.Character == nil or disconnected.Character.Parent == nil, "disconnected setup character must not remain")
		resetScenario(harness.Controller)
	end

	do
		local first = newPlayer("AbortValid")
		local failed = newPlayer("AbortFailed", { Fail = true })
		local harness = newHarness({ first, failed })
		advanceThroughSetup(harness.Controller)
		assert(harness.Controller:GetState() == RoundState.WAITING, "insufficient setup must abort to waiting")
		assert(harness.Controller:GetAliveCount() == 0, "aborted setup must clear alive state")
		assert(not harness.Controller:IsParticipant(first), "aborted setup must clear participant state")
		assert(first.Character.Parent == nil, "aborted setup must destroy partial characters")
		assert(PlayerSpawnService.GetPillarIndex(first) == nil, "aborted setup must clear assignments")
		resetScenario(harness.Controller)
	end

	do
		local first
		local second
		local third
		local harness
		first = newPlayer("StartingDeathA")
		second = newPlayer("StartingDeathB", {
			BeforeLoad = function()
				harness.Kill(first)
			end,
		})
		third = newPlayer("StartingDeathC")
		harness = newHarness({ first, second, third })
		advanceThroughSetup(harness.Controller)
		waitUntil(function()
			return harness.Controller:GetAliveCount() == 2
		end, "death during starting must remove pending alive player")
		assert(harness.Controller:GetState() == RoundState.ACTIVE, "two surviving setup participants may become active")
		assert(not harness.Controller:IsAlive(first), "starting death must not remain alive")
		assert(harness.Controller:GetWinner() == nil, "starting death must not evaluate a winner")
		resetScenario(harness.Controller)
	end

	do
		local late = newPlayer("LateJoiner")
		local harness
		local first = newPlayer("LateBaseA")
		local second = newPlayer("LateBaseB", {
			BeforeLoad = function()
				table.insert(harness.Players, late)
			end,
		})
		harness = newHarness({ first, second })
		advanceThroughSetup(harness.Controller)
		assert(not harness.Controller:IsParticipant(late), "player joining during starting must not join current round")
		assert(PlayerSpawnService.GetPillarIndex(late) == nil and late.Character == nil, "late starting join must stay unspawned")

		table.insert(harness.Players, newPlayer("ActiveJoiner"))
		local activeJoiner = harness.Players[#harness.Players]
		assert(not harness.Controller:IsParticipant(activeJoiner), "player joining during active must not join current round")
		assert(PlayerSpawnService.GetPillarIndex(activeJoiner) == nil, "active joiner must remain unassigned")

		harness.Kill(first)
		waitUntil(function()
			return harness.Controller:GetState() == RoundState.ENDING
		end, "one survivor must end round")
		local endingJoiner = newPlayer("EndingJoiner")
		table.insert(harness.Players, endingJoiner)
		assert(not harness.Controller:IsParticipant(endingJoiner), "player joining during ending must not join current round")
		harness.Controller:Advance()
		assert(harness.Controller:GetState() == RoundState.WAITING, "ending cleanup must return to waiting")
		advanceThroughSetup(harness.Controller)
		assert(harness.Controller:IsParticipant(late), "late player must be eligible in the next round")
		assert(harness.Controller:IsParticipant(activeJoiner), "active joiner must be eligible in the next round")
		assert(harness.Controller:IsParticipant(endingJoiner), "ending joiner must be eligible in the next round")
		resetScenario(harness.Controller)
	end

	do
		local first = newPlayer("EliminationA")
		local second = newPlayer("EliminationB")
		local third = newPlayer("EliminationC")
		local harness = newHarness({ first, second, third })
		advanceThroughSetup(harness.Controller)
		harness.Kill(first)
		waitUntil(function()
			return harness.Controller:GetAliveCount() == 2
		end, "active death must remove exactly one alive participant")
		assert(harness.Controller:GetState() == RoundState.ACTIVE, "two alive players must keep round active")
		assert(first.LoadCount == 1, "eliminated player must not respawn")
		harness.Kill(second)
		waitUntil(function()
			return harness.Controller:GetState() == RoundState.ENDING
		end, "sole survivor must end the round")
		assert(harness.Controller:GetWinner() == third, "sole survivor must be winner")
		resetScenario(harness.Controller)
	end

	do
		local leaver = newPlayer("DisconnectLeaver")
		local survivor = newPlayer("DisconnectWinner")
		local harness = newHarness({ leaver, survivor })
		advanceThroughSetup(harness.Controller)
		leaver.Parent = nil
		harness.Controller:HandlePlayerRemoving(leaver)
		assert(harness.Controller:GetAliveCount() == 1, "disconnect must remove one alive player")
		assert(PlayerSpawnService.GetPillarIndex(leaver) == nil, "disconnect must release the leaver assignment")
		assert(harness.Controller:GetWinner() == survivor, "remaining player must immediately win")
		assert(harness.Controller:GetState() == RoundState.ENDING, "two-player disconnect must enter ending")
		harness.Controller:HandlePlayerRemoving(leaver)
		harness.Kill(leaver)
		task.wait()
		assert(harness.Controller:GetAliveCount() == 1, "death plus disconnect must not double-process")
		assert(harness.Controller:GetWinner() == survivor, "duplicate removal must not change winner")
		resetScenario(harness.Controller)
	end

	do
		local first = newPlayer("NoWinnerA")
		local second = newPlayer("NoWinnerB")
		local harness = newHarness({ first, second })
		advanceThroughSetup(harness.Controller)
		first.Parent = nil
		second.Parent = nil
		harness.Controller:HandlePlayerRemoving(first)
		waitUntil(function()
			return harness.Controller:GetState() == RoundState.ENDING
		end, "zero valid survivors must end safely")
		assert(harness.Controller:GetAliveCount() == 0, "invalid sole survivor must be removed")
		assert(harness.Controller:GetWinner() == nil, "zero survivors must have no winner")
		resetScenario(harness.Controller)
	end

	do
		local first = newPlayer("CleanupA")
		local second = newPlayer("CleanupB")
		local random = newRandom({ 2, 1 })
		local harness = newHarness({ first, second }, { Random = random })
		advanceThroughSetup(harness.Controller)
		local firstRoundPillar = PlayerSpawnService.GetPillarIndex(first)
		harness.Kill(first)
		waitUntil(function()
			return harness.Controller:GetState() == RoundState.ENDING
		end, "cleanup test round must end")
		local firstRoundCharacter = second.Character
		harness.Controller:Advance()
		assert(harness.Controller:GetState() == RoundState.WAITING, "ending must clean and return to waiting")
		assert(firstRoundCharacter.Parent == nil, "ending cleanup must destroy surviving character")
		assert(PlayerSpawnService.GetPillarIndex(second) == nil, "ending cleanup must clear assignments")
		assert(harness.Controller:GetAliveCount() == 0 and harness.Controller:GetWinner() == nil, "ending cleanup must clear round state")

		first.Parent = Players
		second.Parent = Players
		advanceThroughSetup(harness.Controller)
		assert(harness.Controller:GetState() == RoundState.ACTIVE, "second round must start without restarting")
		assert(random:GetCallCount() == 2, "each two-player round must shuffle independently")
		assert(PlayerSpawnService.GetPillarIndex(first) ~= firstRoundPillar, "scripted second shuffle must affect new assignments")
		resetScenario(harness.Controller)
	end

	do
		local harness = newHarness({})
		assert(harness.Controller:Start(), "first Start call must launch lifecycle")
		assert(not harness.Controller:Start(), "second Start call must not launch another lifecycle")
		harness.Controller:Stop()
	end

	local arena = Workspace:FindFirstChild(ArenaConfig.GENERATED_MODEL_NAME)

	if arena then
		arena:Destroy()
	end
end

return RoundControllerTests
