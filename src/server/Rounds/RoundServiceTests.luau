local Players = game:GetService("Players")

local RoundService = require(script.Parent.RoundService)
local RoundState = require(script.Parent.RoundState)

local RoundServiceTests = {}

function RoundServiceTests.Run()
	RoundService.Stop()

	assert(RoundService.Start(), "RoundService must start its one production controller")
	assert(not RoundService.Start(), "RoundService must reject an overlapping second start")
	assert(Players.CharacterAutoLoads == false, "RoundService must retain controlled character loading")
	assert(RoundService.GetState() == RoundState.WAITING, "production controller must begin waiting")
	assert(RoundService.GetAliveCount() == 0, "production controller must begin without alive participants")
	assert(RoundService.GetWinner() == nil, "production controller must begin without a winner")

	RoundService.Stop()
	assert(RoundService.GetState() == RoundState.WAITING, "stopping the service must leave it waiting")
end

return RoundServiceTests
