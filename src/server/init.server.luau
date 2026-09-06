local RunService = game:GetService("RunService")

local ArenaService = require(script.Arena.ArenaService)
local RoundService = require(script.Rounds.RoundService)

if RunService:IsStudio() then
	require(script.Arena.ArenaLayoutTests).Run()
	require(script.Arena.ArenaServiceTests).Run()
	print("PILLARS arena checks passed")
end

ArenaService.Generate()
RoundService.Start()
