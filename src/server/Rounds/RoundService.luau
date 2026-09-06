local Players = game:GetService("Players")

local PlayerSpawnService = require(script.Parent.Parent.Players.PlayerSpawnService)
local RoundConfig = require(script.Parent.RoundConfig)
local RoundController = require(script.Parent.RoundController)

local controller = RoundController.new({
	Config = RoundConfig,
	GetEligiblePlayers = function()
		return Players:GetPlayers()
	end,
	Wait = task.wait,
	Random = Random.new(),
	PlayerSpawnService = PlayerSpawnService,
})

local started = false
local playerRemovingConnection = nil

local RoundService = {}

function RoundService.Start(): boolean
	if started then
		return false
	end

	started = true
	Players.CharacterAutoLoads = false
	playerRemovingConnection = Players.PlayerRemoving:Connect(function(player)
		controller:HandlePlayerRemoving(player)
	end)
	controller:Start()
	return true
end

function RoundService.Stop()
	if playerRemovingConnection then
		playerRemovingConnection:Disconnect()
		playerRemovingConnection = nil
	end

	controller:Stop()
	started = false
end

function RoundService.GetState(): string
	return controller:GetState()
end

function RoundService.GetAliveCount(): number
	return controller:GetAliveCount()
end

function RoundService.GetWinner()
	return controller:GetWinner()
end

return RoundService
