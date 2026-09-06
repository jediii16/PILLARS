local ServerScriptService = game:GetService("ServerScriptService")
local server = ServerScriptService:WaitForChild("Server")
local arena = server:WaitForChild("Arena")

require(arena.ArenaLayoutTests).Run()

local arenaServiceTests = arena:FindFirstChild("ArenaServiceTests")

if arenaServiceTests then
	require(arenaServiceTests).Run()
end

print("PILLARS_ARENA_TESTS_PASSED")
