local Workspace = game:GetService("Workspace")

local ArenaConfig = require(script.Parent.ArenaConfig)
local ArenaLayout = require(script.Parent.ArenaLayout)

local ArenaService = {}

local function assertPositiveNumber(name: string, value: number)
	assert(type(value) == "number" and value > 0, string.format("%s must be a positive number", name))
end

local function assertPositiveVector3(name: string, value: Vector3)
	assert(typeof(value) == "Vector3", string.format("%s must be a Vector3", name))
	assert(
		value.X > 0 and value.Y > 0 and value.Z > 0,
		string.format("%s components must all be positive", name)
	)
end

local function validateConfig()
	assertPositiveNumber("PLAYER_COUNT", ArenaConfig.PLAYER_COUNT)
	assert(ArenaConfig.PLAYER_COUNT % 1 == 0, "PLAYER_COUNT must be an integer")
	assertPositiveVector3("PILLAR_SIZE", ArenaConfig.PILLAR_SIZE)
	assertPositiveNumber("PILLAR_RADIUS", ArenaConfig.PILLAR_RADIUS)
	assertPositiveNumber("PILLAR_HEIGHT", ArenaConfig.PILLAR_HEIGHT)
	assertPositiveVector3("CENTER_PLATFORM_SIZE", ArenaConfig.CENTER_PLATFORM_SIZE)
	assertPositiveVector3("SPAWN_MARKER_SIZE", ArenaConfig.SPAWN_MARKER_SIZE)
	assertPositiveNumber("SPAWN_MARKER_OFFSET", ArenaConfig.SPAWN_MARKER_OFFSET)
	assertPositiveNumber("VOID_BOUNDARY_THICKNESS", ArenaConfig.VOID_BOUNDARY_THICKNESS)
	assertPositiveNumber("VOID_BOUNDARY_MARGIN", ArenaConfig.VOID_BOUNDARY_MARGIN)
	assertPositiveNumber("VOID_BOUNDARY_MAX_TILE_SIZE", ArenaConfig.VOID_BOUNDARY_MAX_TILE_SIZE)
	assert(
		ArenaConfig.VOID_KILL_HEIGHT < ArenaConfig.ARENA_CENTER.Y + ArenaConfig.PILLAR_HEIGHT,
		"VOID_KILL_HEIGHT must be beneath the arena platforms"
	)
end

local function createPermanentPart(name: string, layout, color: Color3): Part
	local part = Instance.new("Part")
	part.Name = name
	part.Anchored = true
	part.Locked = true
	part.CanCollide = true
	part.CanQuery = true
	part.CanTouch = true
	part.CastShadow = true
	part.Color = color
	part.Material = ArenaConfig.PLATFORM_MATERIAL
	part.Size = layout.Size
	part.CFrame = layout.CFrame
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	part:SetAttribute("PermanentGeometry", true)

	return part
end

local function createSpawnMarker(layout): Part
	local marker = Instance.new("Part")
	marker.Name = string.format("PillarSpawn%02d", layout.Index)
	marker.Anchored = true
	marker.Locked = true
	marker.CanCollide = false
	marker.CanQuery = false
	marker.CanTouch = false
	marker.CastShadow = false
	marker.Transparency = 1
	marker.Size = ArenaConfig.SPAWN_MARKER_SIZE
	marker.CFrame = layout.SpawnCFrame
	marker:SetAttribute("PillarIndex", layout.Index)

	return marker
end

local function eliminateCharacterFromTouch(otherPart: BasePart)
	local character = otherPart:FindFirstAncestorOfClass("Model")

	if not character then
		return
	end

	local humanoid = character:FindFirstChildOfClass("Humanoid")

	if humanoid then
		humanoid.Health = 0
	end
end

local function createVoidBoundary(layout): Model
	local boundary = Instance.new("Model")
	boundary.Name = "VoidBoundary"
	boundary:SetAttribute("KillHeight", ArenaConfig.VOID_KILL_HEIGHT)
	boundary:SetAttribute("CoverageSize", layout.Size)

	local tileCountX = math.ceil(layout.Size.X / ArenaConfig.VOID_BOUNDARY_MAX_TILE_SIZE)
	local tileCountZ = math.ceil(layout.Size.Z / ArenaConfig.VOID_BOUNDARY_MAX_TILE_SIZE)
	local tileSizeX = layout.Size.X / tileCountX
	local tileSizeZ = layout.Size.Z / tileCountZ
	local tileIndex = 0

	for xIndex = 1, tileCountX do
		local xOffset = -layout.Size.X / 2 + tileSizeX / 2 + (xIndex - 1) * tileSizeX

		for zIndex = 1, tileCountZ do
			local zOffset = -layout.Size.Z / 2 + tileSizeZ / 2 + (zIndex - 1) * tileSizeZ
			tileIndex += 1

			local tile = Instance.new("Part")
			tile.Name = string.format("VoidTile%02d", tileIndex)
			tile.Anchored = true
			tile.Locked = true
			tile.CanCollide = false
			tile.CanQuery = false
			tile.CanTouch = true
			tile.CastShadow = false
			tile.Transparency = 1
			tile.Size = Vector3.new(tileSizeX, layout.Size.Y, tileSizeZ)
			tile.CFrame = layout.CFrame * CFrame.new(xOffset, 0, zOffset)
			tile.Touched:Connect(eliminateCharacterFromTouch)
			tile.Parent = boundary
		end
	end

	return boundary
end

function ArenaService.Generate(): Model
	validateConfig()

	local existingArena = Workspace:FindFirstChild(ArenaConfig.GENERATED_MODEL_NAME)

	if existingArena then
		existingArena:Destroy()
	end

	local arena = Instance.new("Model")
	arena.Name = ArenaConfig.GENERATED_MODEL_NAME

	local permanentGeometry = Instance.new("Folder")
	permanentGeometry.Name = ArenaConfig.PERMANENT_GEOMETRY_FOLDER_NAME
	permanentGeometry.Parent = arena

	local spawnMarkers = Instance.new("Folder")
	spawnMarkers.Name = ArenaConfig.SPAWN_MARKERS_FOLDER_NAME
	spawnMarkers.Parent = arena

	for _, layout in ArenaLayout.Calculate(ArenaConfig) do
		local pillar = createPermanentPart(
			string.format("StartingPillar%02d", layout.Index),
			layout,
			ArenaConfig.PILLAR_COLOR
		)
		pillar:SetAttribute("PillarIndex", layout.Index)
		pillar.Parent = permanentGeometry

		local marker = createSpawnMarker(layout)
		marker.Parent = spawnMarkers
	end

	local centerPlatform = createPermanentPart(
		"CenterPlatform",
		ArenaLayout.CalculateCenterPlatform(ArenaConfig),
		ArenaConfig.CENTER_PLATFORM_COLOR
	)
	centerPlatform.Parent = permanentGeometry

	local voidBoundary = createVoidBoundary(ArenaLayout.CalculateVoidBoundary(ArenaConfig))
	voidBoundary.Parent = arena

	arena.Parent = Workspace

	return arena
end

return ArenaService
