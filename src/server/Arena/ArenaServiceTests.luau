local Workspace = game:GetService("Workspace")

local ArenaConfig = require(script.Parent.ArenaConfig)
local ArenaLayout = require(script.Parent.ArenaLayout)
local ArenaService = require(script.Parent.ArenaService)

local EPSILON = 1e-4

local function expectNear(actual: number, expected: number, message: string)
	assert(
		math.abs(actual - expected) <= EPSILON,
		string.format("%s: expected %.4f, got %.4f", message, expected, actual)
	)
end

local function expectVectorNear(actual: Vector3, expected: Vector3, message: string)
	assert(
		(actual - expected).Magnitude <= EPSILON,
		string.format("%s: expected %s, got %s", message, tostring(expected), tostring(actual))
	)
end

local function countNamedWorkspaceChildren(name: string): number
	local count = 0

	for _, child in Workspace:GetChildren() do
		if child.Name == name then
			count += 1
		end
	end

	return count
end

local ArenaServiceTests = {}

function ArenaServiceTests.Run()
	local firstArena = ArenaService.Generate()
	local secondArena = ArenaService.Generate()

	assert(firstArena.Parent == nil, "regeneration must remove the previous arena")
	assert(secondArena.Parent == Workspace, "generated arena must be parented to Workspace")
	assert(
		countNamedWorkspaceChildren(ArenaConfig.GENERATED_MODEL_NAME) == 1,
		"regeneration must leave exactly one arena model"
	)

	local permanentGeometry = secondArena:FindFirstChild(ArenaConfig.PERMANENT_GEOMETRY_FOLDER_NAME)
	local spawnMarkers = secondArena:FindFirstChild(ArenaConfig.SPAWN_MARKERS_FOLDER_NAME)
	local voidBoundary = secondArena:FindFirstChild("VoidBoundary")

	assert(permanentGeometry and permanentGeometry:IsA("Folder"), "permanent geometry folder is required")
	assert(spawnMarkers and spawnMarkers:IsA("Folder"), "spawn markers folder is required")
	assert(voidBoundary and voidBoundary:IsA("Model"), "one logical void boundary model is required")
	assert(#permanentGeometry:GetChildren() == 9, "eight pillars and one center platform are required")
	assert(#spawnMarkers:GetChildren() == 8, "exactly eight spawn markers are required")
	assert(secondArena:FindFirstChildWhichIsA("SpawnLocation", true) == nil, "SpawnLocations must not be generated")

	local layouts = ArenaLayout.Calculate(ArenaConfig)

	for index, layout in layouts do
		local pillarName = string.format("StartingPillar%02d", index)
		local markerName = string.format("PillarSpawn%02d", index)
		local pillar = permanentGeometry:FindFirstChild(pillarName)
		local marker = spawnMarkers:FindFirstChild(markerName)

		assert(pillar and pillar:IsA("Part"), pillarName .. " must be a Part")
		assert(marker and marker:IsA("Part"), markerName .. " must be a Part")
		assert(pillar.Anchored and pillar.Locked and pillar.CanCollide, pillarName .. " must be permanent geometry")
		assert(pillar:GetAttribute("PermanentGeometry") == true, pillarName .. " must be marked permanent")
		assert(pillar:GetAttribute("PillarIndex") == index, pillarName .. " must expose its index")
		assert(pillar.Size == ArenaConfig.PILLAR_SIZE, pillarName .. " must use configured size")
		expectVectorNear(pillar.Position, layout.Position, pillarName .. " position")

		assert(marker.Anchored, markerName .. " must be anchored")
		assert(marker.Transparency == 1, markerName .. " must be invisible")
		assert(not marker.CanCollide and not marker.CanQuery and not marker.CanTouch, markerName .. " must be inert")
		assert(marker:GetAttribute("PillarIndex") == index, markerName .. " must expose its index")
		expectVectorNear(marker.Position, layout.SpawnPosition, markerName .. " position")
	end

	local centerPlatform = permanentGeometry:FindFirstChild("CenterPlatform")
	local expectedCenter = ArenaLayout.CalculateCenterPlatform(ArenaConfig)

	assert(centerPlatform and centerPlatform:IsA("Part"), "one center platform Part is required")
	assert(centerPlatform.Anchored and centerPlatform.Locked and centerPlatform.CanCollide, "center must be permanent")
	assert(centerPlatform:GetAttribute("PermanentGeometry") == true, "center must be marked permanent")
	assert(centerPlatform.Size == ArenaConfig.CENTER_PLATFORM_SIZE, "center must use configured size")
	expectVectorNear(centerPlatform.Position, expectedCenter.Position, "center platform position")

	local expectedVoid = ArenaLayout.CalculateVoidBoundary(ArenaConfig)
	assert(
		voidBoundary:GetAttribute("CoverageSize") == expectedVoid.Size,
		"logical void boundary must expose its full configured coverage"
	)
	assert(#voidBoundary:GetChildren() == 4, "prototype void boundary must use four engine-safe tiles")

	local minimumX = math.huge
	local maximumX = -math.huge
	local minimumZ = math.huge
	local maximumZ = -math.huge

	for _, tile in voidBoundary:GetChildren() do
		assert(tile:IsA("Part"), "void boundary tiles must be Parts")
		assert(tile.Anchored, "void boundary tiles must be anchored")
		assert(tile.Transparency == 1, "void boundary tiles must be invisible")
		assert(not tile.CanCollide, "void boundary tiles must be non-collidable")
		assert(tile.CanTouch, "void boundary tiles must keep touch detection enabled")
		assert(not tile.CanQuery, "void boundary tiles must not affect spatial queries")
		expectNear(tile.Position.Y, expectedVoid.Position.Y, "void boundary tile height")

		minimumX = math.min(minimumX, tile.Position.X - tile.Size.X / 2)
		maximumX = math.max(maximumX, tile.Position.X + tile.Size.X / 2)
		minimumZ = math.min(minimumZ, tile.Position.Z - tile.Size.Z / 2)
		maximumZ = math.max(maximumZ, tile.Position.Z + tile.Size.Z / 2)
	end

	expectNear(minimumX, expectedVoid.Position.X - expectedVoid.Size.X / 2, "void minimum X coverage")
	expectNear(maximumX, expectedVoid.Position.X + expectedVoid.Size.X / 2, "void maximum X coverage")
	expectNear(minimumZ, expectedVoid.Position.Z - expectedVoid.Size.Z / 2, "void minimum Z coverage")
	expectNear(maximumZ, expectedVoid.Position.Z + expectedVoid.Size.Z / 2, "void maximum Z coverage")

	secondArena:Destroy()
end

return ArenaServiceTests
