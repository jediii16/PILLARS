local RunService = game:GetService("RunService")
local ServerScriptService = game:GetService("ServerScriptService")

local server = ServerScriptService:WaitForChild("Server")
local rounds = server:WaitForChild("Rounds")

RunService:Run()

require(rounds.RoundFoundationTests).Run()

local controllerTests = rounds:FindFirstChild("RoundControllerTests")

if controllerTests then
	require(controllerTests).Run()
end

local serviceTests = rounds:FindFirstChild("RoundServiceTests")

if serviceTests then
	require(serviceTests).Run()
end

RunService:Pause()
print("PILLARS_ROUND_TESTS_PASSED")
