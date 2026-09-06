local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local ArenaConfig = require(script.Parent.Parent.Arena.ArenaConfig)
local StudioAssignmentDiagnostics = require(script.Parent.Parent.Players.StudioAssignmentDiagnostics)
local RoundShuffle = require(script.Parent.RoundShuffle)
local RoundState = require(script.Parent.RoundState)

local RoundController = {}
RoundController.__index = RoundController

local function countEntries(entries): number
	local count = 0

	for _ in entries do
		count += 1
	end

	return count
end

function RoundController.new(dependencies)
	assert(dependencies, "RoundController dependencies are required")
	assert(dependencies.Config, "RoundController Config is required")
	assert(dependencies.GetEligiblePlayers, "RoundController GetEligiblePlayers is required")
	assert(dependencies.Wait, "RoundController Wait is required")
	assert(dependencies.Random, "RoundController Random is required")
	assert(dependencies.PlayerSpawnService, "RoundController PlayerSpawnService is required")
	assert(dependencies.CoverService, "RoundController CoverService is required")

	local self = setmetatable({}, RoundController)
	self._config = dependencies.Config
	self._getEligiblePlayers = dependencies.GetEligiblePlayers
	self._wait = dependencies.Wait
	self._random = dependencies.Random
	self._playerSpawnService = dependencies.PlayerSpawnService
	self._coverService = dependencies.CoverService
	self._connectHumanoidDied = dependencies.ConnectHumanoidDied or function(humanoid, callback)
		return humanoid.Died:Connect(callback)
	end
	self._state = RoundState.WAITING
	self._running = false
	self._sessionToken = 0
	self._generation = 0
	self._lastCleanedGeneration = nil
	self._participants = {}
	self._alive = {}
	self._expectedPillars = {}
	self._characters = {}
	self._humanoids = {}
	self._deathConnections = {}
	self._winner = nil
	self._roundEnded = Instance.new("BindableEvent")
	return self
end

function RoundController:_log(message: string)
	if RunService:IsStudio() then
		print(message)
	end
end

function RoundController:_transition(nextState: string)
	assert(
		RoundState.CanTransition(self._state, nextState),
		string.format("invalid round transition: %s -> %s", self._state, nextState)
	)

	self._state = nextState
	self:_log("PILLARS round state: " .. nextState)
end

function RoundController:_connectedEligiblePlayers()
	local connected = {}

	for _, player in self._getEligiblePlayers() do
		if player.Parent == Players then
			table.insert(connected, player)
		end
	end

	return connected
end

function RoundController:_isExpectedLivingCharacter(player): boolean
	local character = self._characters[player]
	local humanoid = self._humanoids[player]
	local expectedPillar = self._expectedPillars[player]

	return player.Parent == Players
		and character ~= nil
		and character.Parent ~= nil
		and player.Character == character
		and humanoid ~= nil
		and humanoid.Parent ~= nil
		and humanoid.Health > 0
		and expectedPillar ~= nil
		and self._playerSpawnService.GetPillarIndex(player) == expectedPillar
		and self._playerSpawnService.GetPlayerForPillar(expectedPillar) == player
end

function RoundController:_removeAlive(player, reason: string): boolean
	if not self._alive[player] then
		return false
	end

	self._alive[player] = nil

	if self._state == RoundState.STARTING then
		self:_log(string.format(
			"PILLARS setup participant lost: %s (%s); %d pending",
			player.Name,
			reason,
			self:GetAliveCount()
		))
	else
		self:_log(string.format("PILLARS eliminated: %s (%s); %d alive", player.Name, reason, self:GetAliveCount()))
	end

	return true
end

function RoundController:_evaluateWinCondition()
	if self._state ~= RoundState.ACTIVE then
		return
	end

	for player in self._alive do
		if not self:_isExpectedLivingCharacter(player) then
			self:_removeAlive(player, "no longer valid")
			self._playerSpawnService.ReleasePlayer(player)
		end
	end

	local aliveCount = self:GetAliveCount()

	if aliveCount > 1 then
		return
	end

	local winner = nil

	if aliveCount == 1 then
		winner = next(self._alive)
	end

	self._winner = winner

	if winner then
		self:_log("PILLARS winner: " .. winner.Name)
	else
		self:_log("PILLARS round ended with no winner")
	end

	self:_transition(RoundState.ENDING)
	self._roundEnded:Fire()
end

function RoundController:_handleCharacterDeath(player, generation: number, character)
	if generation ~= self._generation or self._characters[player] ~= character then
		return
	end

	if self._state == RoundState.STARTING then
		self:_removeAlive(player, "died during setup")
	elseif self._state == RoundState.ACTIVE and self:_removeAlive(player, "died") then
		self:_evaluateWinCondition()
	end
end

function RoundController:_disconnectDeathListeners()
	for player, connection in self._deathConnections do
		connection:Disconnect()
		self._deathConnections[player] = nil
	end
end

function RoundController:_clearRoundTables()
	table.clear(self._participants)
	table.clear(self._alive)
	table.clear(self._expectedPillars)
	table.clear(self._characters)
	table.clear(self._humanoids)
	self._winner = nil
end

function RoundController:_cleanupRound(generation: number)
	if self._lastCleanedGeneration == generation then
		return
	end

	self._lastCleanedGeneration = generation
	self:_disconnectDeathListeners()

	for _, character in self._characters do
		if character.Parent then
			character:Destroy()
		end
	end

	self._playerSpawnService.ClearAssignments()
	self._coverService.ClearRoundCover()
	self:_clearRoundTables()
	self:_log("PILLARS round cleanup complete")
end

function RoundController:_isSessionCurrent(sessionToken): boolean
	return sessionToken == nil or (self._running and self._sessionToken == sessionToken)
end

function RoundController:_beginStarting(sessionToken)
	self._generation += 1
	local generation = self._generation
	self._lastCleanedGeneration = nil
	self:_disconnectDeathListeners()
	self:_clearRoundTables()
	self._playerSpawnService.ClearAssignments()
	self._coverService.ClearRoundCover()

	local coverCallSucceeded, coverOrError, generationError = pcall(self._coverService.GenerateRoundCover)
	local cover = if coverCallSucceeded then coverOrError else nil
	local coverError = if coverCallSucceeded then generationError else coverOrError

	if not cover then
		self:_log("PILLARS round setup aborted: cover generation failed: " .. tostring(coverError))
		self:_cleanupRound(generation)

		if self._state == RoundState.STARTING and self:_isSessionCurrent(sessionToken) then
			self:_transition(RoundState.WAITING)
		end

		return
	end

	if not self:_isSessionCurrent(sessionToken) then
		self:_cleanupRound(generation)
		return
	end

	local eligible = self:_connectedEligiblePlayers()
	local selected = {}

	for index = 1, math.min(#eligible, ArenaConfig.PLAYER_COUNT) do
		selected[index] = eligible[index]
	end

	local shuffled = RoundShuffle.ShuffledCopy(selected, self._random)
	self:_log(string.format("PILLARS round starting with %d participants", #shuffled))

	for _, player in shuffled do
		if self._state ~= RoundState.STARTING
			or generation ~= self._generation
			or not self:_isSessionCurrent(sessionToken)
		then
			break
		end

		if player.Parent ~= Players then
			continue
		end

		local pillarIndex = self._playerSpawnService.AssignPlayer(player)

		if not pillarIndex then
			self:_log("PILLARS round setup skipped " .. player.Name .. ": no pillar available")
			continue
		end

		if RunService:IsStudio() then
			StudioAssignmentDiagnostics.Log(self._playerSpawnService, player, pillarIndex)
		end

		local character, spawnError = self._playerSpawnService.SpawnPlayer(player)

		if not self:_isSessionCurrent(sessionToken) then
			self._playerSpawnService.ReleasePlayer(player)
			if character and character.Parent then
				character:Destroy()
			end
			return
		end

		if not character then
			self._playerSpawnService.ReleasePlayer(player)
			self:_log(string.format("PILLARS round setup skipped %s: %s", player.Name, tostring(spawnError)))
			continue
		end

		local humanoid = character:FindFirstChildOfClass("Humanoid")
		self._expectedPillars[player] = pillarIndex
		self._characters[player] = character
		self._humanoids[player] = humanoid

		if player.Parent == Players and player.Character == character and humanoid and humanoid.Health > 0 then
			self._participants[player] = true
			self._alive[player] = true
			self._deathConnections[player] = self._connectHumanoidDied(humanoid, function()
				self:_handleCharacterDeath(player, generation, character)
			end)
		else
			self._playerSpawnService.ReleasePlayer(player)
		end
	end

	for player in self._alive do
		if not self:_isExpectedLivingCharacter(player) then
			self:_removeAlive(player, "invalid at activation")
			self._playerSpawnService.ReleasePlayer(player)
		end
	end

	if not self:_isSessionCurrent(sessionToken) then
		return
	end

	if self:GetAliveCount() < self._config.MIN_PLAYERS then
		self:_log("PILLARS round setup aborted: too few valid participants")
		self:_cleanupRound(generation)
		self:_transition(RoundState.WAITING)
		return
	end

	self:_transition(RoundState.ACTIVE)
	self:_evaluateWinCondition()
end

function RoundController:Advance(sessionToken)
	if self._state == RoundState.WAITING then
		if #self:_connectedEligiblePlayers() < self._config.MIN_PLAYERS then
			self._wait(self._config.WAITING_CHECK_INTERVAL)
			return
		end

		self:_transition(RoundState.COUNTDOWN)
		return
	end

	if self._state == RoundState.COUNTDOWN then
		local remaining = self._config.COUNTDOWN_DURATION

		while remaining > 0 and self._state == RoundState.COUNTDOWN do
			self:_log(string.format("PILLARS round countdown: %d", math.ceil(remaining)))
			local duration = math.min(1, remaining)
			self._wait(duration)
			remaining -= duration

			if not self:_isSessionCurrent(sessionToken) then
				return
			end

			if #self:_connectedEligiblePlayers() < self._config.MIN_PLAYERS then
				self:_log("PILLARS round countdown cancelled: too few players")
				self:_transition(RoundState.WAITING)
				return
			end
		end

		if self._state == RoundState.COUNTDOWN then
			self:_transition(RoundState.STARTING)
		end

		return
	end

	if self._state == RoundState.STARTING then
		self:_beginStarting(sessionToken)
		return
	end

	if self._state == RoundState.ACTIVE then
		if self._running then
			self._roundEnded.Event:Wait()
		end

		return
	end

	if self._state == RoundState.ENDING then
		self._wait(self._config.END_ROUND_DELAY)

		if not self:_isSessionCurrent(sessionToken) then
			return
		end

		if self._state == RoundState.ENDING then
			self:_cleanupRound(self._generation)
			self:_transition(RoundState.WAITING)
		end
	end
end

function RoundController:Start(): boolean
	if self._running then
		return false
	end

	self._running = true
	self._sessionToken += 1
	local sessionToken = self._sessionToken
	self:_log("PILLARS round state: " .. self._state)

	task.spawn(function()
		while self._running and self._sessionToken == sessionToken do
			self:Advance(sessionToken)
		end
	end)

	return true
end

function RoundController:Stop()
	self._running = false
	self._sessionToken += 1
	self._roundEnded:Fire()
	self:_cleanupRound(self._generation)
	self._state = RoundState.WAITING
end

function RoundController:HandlePlayerRemoving(player)
	self._playerSpawnService.ReleasePlayer(player)

	if self._state == RoundState.STARTING then
		self:_removeAlive(player, "left during setup")
	elseif self._state == RoundState.ACTIVE and self:_removeAlive(player, "left") then
		self:_evaluateWinCondition()
	end
end

function RoundController:GetState(): string
	return self._state
end

function RoundController:GetAliveCount(): number
	return countEntries(self._alive)
end

function RoundController:IsParticipant(player): boolean
	return self._participants[player] == true
end

function RoundController:IsAlive(player): boolean
	return self._alive[player] == true
end

function RoundController:GetWinner()
	return self._winner
end

return RoundController
