local ServerScriptService = game:GetService("ServerScriptService")

local server = ServerScriptService:WaitForChild("Server")
local cover = server:WaitForChild("Cover")

require(cover.CoverConfigTests).Run()

local serviceTests = cover:FindFirstChild("CoverServiceTests")

if serviceTests then
	require(serviceTests).Run()
end

print("PILLARS_COVER_TESTS_PASSED")
