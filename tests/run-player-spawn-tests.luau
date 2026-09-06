local ServerScriptService = game:GetService("ServerScriptService")

local server = ServerScriptService:WaitForChild("Server")
local playerModules = server:WaitForChild("Players")

require(playerModules.PlayerSpawnServiceTests).Run()
require(playerModules.StudioAssignmentDiagnosticsTests).Run()

print("PILLARS_PLAYER_SPAWN_TESTS_PASSED")
