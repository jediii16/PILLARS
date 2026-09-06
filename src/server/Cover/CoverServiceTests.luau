local ServerStorage = game:GetService("ServerStorage")

local ArenaConfig = require(script.Parent.Parent.Arena.ArenaConfig)
local ArenaService = require(script.Parent.Parent.Arena.ArenaService)
local CoverConfig = require(script.Parent.CoverConfig)
local CoverService = require(script.Parent.CoverService)

local EPSILON = 1e-4
local CoverServiceTests = {}

local function newRandom(choices, failAt)
	local callCount = 0
	local random = {}

	function random:NextInteger(minimum: number, maximum: number): number
		callCount += 1
		if failAt and callCount == failAt then
			error("intentional cover roll failure")
		end
		local choice = choices and choices[((callCount - 1) % #choices) + 1] or minimum
		assert(choice >= minimum and choice <= maximum, "test cover choice must be in range")
		return choice
	end

	function random:GetCallCount(): number
		return callCount
	end

	return random
end

local function resetAssetCatalog(): Folder
	local existing = ServerStorage:FindFirstChild(CoverConfig.ASSET_ROOT_FOLDER_NAME)
	if existing then
		existing:Destroy()
	end

	local root = Instance.new("Folder")
	root.Name = CoverConfig.ASSET_ROOT_FOLDER_NAME
	root.Parent = ServerStorage
	local catalog = Instance.new("Folder")
	catalog.Name = CoverConfig.STARTING_COVER_FOLDER_NAME
	catalog.Parent = root

	for _, archetype in CoverConfig.ARCHETYPES do
		local folder = Instance.new("Folder")
		folder.Name = archetype.Name
		folder.Parent = catalog
	end

	return catalog
end

local function createVariant(catalog: Folder, archetypeName: string, variantName: string, variantId, size: Vector3, pivotOffset: Vector3?, yawDegrees: number?): Model
	local model = Instance.new("Model")
	model.Name = variantName
	model:SetAttribute("CoverVariantId", variantId)
	model.WorldPivot = CFrame.new()
	local deviation = CFrame.new(pivotOffset or Vector3.zero) * CFrame.Angles(0, math.rad(yawDegrees or 0), 0)

	local bounds = Instance.new("Part")
	bounds.Name = CoverConfig.PLACEMENT_BOUNDS_NAME
	bounds.Size = size
	bounds.CFrame = deviation * CFrame.new(0, size.Y / 2, 0)
	bounds.Transparency = 0
	bounds.CanCollide = true
	bounds.CanTouch = true
	bounds.CanQuery = true
	bounds.Parent = model

	local visual = Instance.new("Part")
	visual.Name = "AuthoredGeometry"
	visual.Size = size - Vector3.new(0.2, 0.2, 0.2)
	visual.CFrame = bounds.CFrame
	visual.CanCollide = true
	visual.Parent = model
	model.Parent = assert(catalog:FindFirstChild(archetypeName))
	return model
end

local function getPillar(arena: Model, pillarIndex: number): BasePart
	local geometry = assert(arena:FindFirstChild(ArenaConfig.PERMANENT_GEOMETRY_FOLDER_NAME))
	return assert(geometry:FindFirstChild(string.format("StartingPillar%02d", pillarIndex))) :: BasePart
end

local function getLocalBounds(part: BasePart, reference: BasePart)
	local half = part.Size / 2
	local minimum = Vector3.new(math.huge, math.huge, math.huge)
	local maximum = Vector3.new(-math.huge, -math.huge, -math.huge)
	for _, x in { -1, 1 } do
		for _, y in { -1, 1 } do
			for _, z in { -1, 1 } do
				local point = reference.CFrame:PointToObjectSpace(part.CFrame:PointToWorldSpace(Vector3.new(x * half.X, y * half.Y, z * half.Z)))
				minimum = Vector3.new(math.min(minimum.X, point.X), math.min(minimum.Y, point.Y), math.min(minimum.Z, point.Z))
				maximum = Vector3.new(math.max(maximum.X, point.X), math.max(maximum.Y, point.Y), math.max(maximum.Z, point.Z))
			end
		end
	end
	return minimum, maximum
end

local function assertFallbackSet(arena: Model, folder: Folder, expectedArchetypes, expectedSides)
	assert(#folder:GetChildren() == ArenaConfig.PLAYER_COUNT, "exactly eight cover Models must generate")
	for pillarIndex = 1, ArenaConfig.PLAYER_COUNT do
		local cover = assert(CoverService.GetCoverForPillar(pillarIndex))
		local archetype = CoverConfig.ARCHETYPES[expectedArchetypes[pillarIndex]]
		local side = expectedSides[pillarIndex]
		local sign = if side == "Left" then -1 else 1
		local pillar = getPillar(arena, pillarIndex)
		local bounds = assert(cover:FindFirstChild(CoverConfig.PLACEMENT_BOUNDS_NAME)) :: BasePart
		assert(cover.Parent == folder, "cover lookup must return the committed Model")
		assert(cover:GetAttribute("CoverArchetype") == archetype.Name, "archetype roll must be authoritative")
		assert(cover:GetAttribute("CoverVariantId") == CoverConfig.PROTOTYPE_VARIANT_ID, "missing assets must use fallback")
		assert(cover:GetAttribute("PlacementSide") == side, "side roll must be authoritative")
		assert(cover:GetAttribute("PermanentCover") == true, "cover must be permanent geometry")
		assert(CoverService.GetCoverArchetypeForPillar(pillarIndex) == archetype.Name, "archetype lookup must match")
		assert(CoverService.GetCoverVariantForPillar(pillarIndex) == CoverConfig.PROTOTYPE_VARIANT_ID, "variant lookup must match")
		assert(bounds.Size == archetype.Size, "fallback bounds must use approved dimensions")
		assert(bounds.Transparency == 1, "PlacementBounds must always be invisible")
		assert(not bounds.CanCollide and not bounds.CanTouch and not bounds.CanQuery, "PlacementBounds must be physics-inert")

		local expectedPivot = pillar.CFrame * CFrame.new(sign * CoverConfig.LATERAL_OFFSET_X, pillar.Size.Y / 2, CoverConfig.LOCAL_FORWARD_OFFSET_Z)
		assert((cover:GetPivot().Position - expectedPivot.Position).Magnitude <= EPSILON, "cover pivot must use local front/side placement")
		local minimum, maximum = getLocalBounds(bounds, pillar)
		assert(minimum.Z >= -pillar.Size.Z / 2 + CoverConfig.FORWARD_EDGE_INSET - EPSILON, "cover must preserve forward inset")
		assert(maximum.Z <= -CoverConfig.SPAWN_CLEARANCE_SIZE.Y / 2 - CoverConfig.SPAWN_TO_COVER_GAP + EPSILON, "cover must preserve spawn clearance")
		local openWidth = if side == "Left" then pillar.Size.X / 2 - maximum.X else minimum.X + pillar.Size.X / 2
		assert(openWidth >= CoverConfig.MIN_FORWARD_ROUTE_WIDTH - EPSILON, "cover must leave a forward route")

		for _, descendant in cover:GetDescendants() do
			if descendant:IsA("BasePart") then
				assert(descendant.Anchored and descendant.Locked, "all runtime cover parts must be fixed")
				assert(descendant:GetAttribute("PillarIndex") == pillarIndex, "all parts must carry pillar metadata")
				assert(descendant:GetAttribute("CoverVariantId") == CoverConfig.PROTOTYPE_VARIANT_ID, "all parts must carry variant metadata")
				assert(descendant:GetAttribute("PermanentCover") == true, "all parts must be indestructible")
			end
		end
	end
end

function CoverServiceTests.Run()
	local catalog = resetAssetCatalog()
	local arena = ArenaService.Generate()
	local archetypeRolls = { 1, 2, 3, 4, 1, 2, 3, 4 }
	local expectedSides = { "Left", "Right", "Left", "Right", "Left", "Right", "Left", "Right" }
	local rolls = {}
	for index, archetypeIndex in archetypeRolls do
		table.insert(rolls, archetypeIndex)
		table.insert(rolls, 1)
		table.insert(rolls, if expectedSides[index] == "Left" then 1 else 2)
	end

	local random = newRandom(rolls)
	local folder, generationError = CoverService.GenerateRoundCover(random)
	assert(folder and not generationError, "fallback generation must succeed")
	assert(random:GetCallCount() == ArenaConfig.PLAYER_COUNT * 3, "every pillar must roll archetype, variant, and side")
	assertFallbackSet(arena, folder, archetypeRolls, expectedSides)

	CoverService.ClearRoundCover()
	createVariant(catalog, "ShortWide", "BarrierB", "BarrierB", Vector3.new(9, 3, 4))
	createVariant(catalog, "ShortWide", "BarrierA", "BarrierA", Vector3.new(8, 3, 4))
	local curated = assert(CoverService.GenerateRoundCover(newRandom({ 1, 2, 1 })))
	for pillarIndex = 1, ArenaConfig.PLAYER_COUNT do
		local cover = assert(CoverService.GetCoverForPillar(pillarIndex))
		assert(cover:GetAttribute("CoverVariantId") == "BarrierB", "sorted curated variants must honor the roll")
		local bounds = assert(cover:FindFirstChild(CoverConfig.PLACEMENT_BOUNDS_NAME)) :: BasePart
		assert(bounds.Transparency == 1 and not bounds.CanCollide and not bounds.CanTouch and not bounds.CanQuery, "authored bounds must be forcibly inert")
		assert(cover:FindFirstChild("AuthoredGeometry") ~= nil, "curated geometry must be cloned")
	end
	assert(curated.Parent == arena, "curated set must commit normally")

	CoverService.ClearRoundCover()
	catalog = resetAssetCatalog()
	createVariant(catalog, "TallNarrow", "NearTolerance", "NearTolerance", Vector3.new(4, 6, 4), Vector3.new(CoverConfig.PIVOT_POSITION_TOLERANCE * 0.5, 0, 0), CoverConfig.PIVOT_ORIENTATION_TOLERANCE_DEGREES * 0.5)
	local tolerated = assert(CoverService.GenerateRoundCover(newRandom({ 2, 1, 1 })))
	assert(tolerated:GetChildren()[1]:GetAttribute("CoverVariantId") == "NearTolerance", "small pivot deviations must be accepted")

	CoverService.ClearRoundCover()
	catalog = resetAssetCatalog()
	createVariant(catalog, "Chunky", "DuplicateOne", "Duplicate", Vector3.new(8, 4, 4))
	createVariant(catalog, "Chunky", "DuplicateTwo", "Duplicate", Vector3.new(8, 4, 4))
	createVariant(catalog, "Chunky", "Unique", "Unique", Vector3.new(8, 4, 4))
	local uniqueOnly = assert(CoverService.GenerateRoundCover(newRandom({ 4, 1, 2 })))
	for _, cover in uniqueOnly:GetChildren() do
		assert(cover:GetAttribute("CoverVariantId") == "Unique", "duplicate ids must invalidate every conflicting variant")
	end

	CoverService.ClearRoundCover()
	catalog = resetAssetCatalog()
	createVariant(catalog, "LongLow", "BlankId", "   ", Vector3.new(10, 2, 4))
	createVariant(catalog, "LongLow", "BadPivot", "BadPivot", Vector3.new(10, 2, 4), Vector3.new(CoverConfig.PIVOT_POSITION_TOLERANCE * 4, 0, 0))
	createVariant(catalog, "LongLow", "BadOrientation", "BadOrientation", Vector3.new(10, 2, 4), nil, CoverConfig.PIVOT_ORIENTATION_TOLERANCE_DEGREES * 4)
	createVariant(catalog, "LongLow", "Oversized", "Oversized", Vector3.new(12.5, 2, 4))
	local scripted = createVariant(catalog, "LongLow", "Scripted", "Scripted", Vector3.new(10, 2, 4))
	Instance.new("Script").Parent = scripted
	local outside = createVariant(catalog, "LongLow", "OutsideBounds", "OutsideBounds", Vector3.new(10, 2, 4))
	local outsideGeometry = assert(outside:FindFirstChild("AuthoredGeometry")) :: BasePart
	outsideGeometry.CFrame *= CFrame.new(6, 0, 0)
	local invalidFallback = assert(CoverService.GenerateRoundCover(newRandom({ 3, 1, 1 })))
	for _, cover in invalidFallback:GetChildren() do
		assert(cover:GetAttribute("CoverVariantId") == CoverConfig.PROTOTYPE_VARIANT_ID, "invalid variants must fall back safely")
	end

	local previous = invalidFallback
	local repeated = assert(CoverService.GenerateRoundCover(newRandom({ 1 })))
	assert(previous.Parent == nil and #repeated:GetChildren() == 8, "regeneration must replace the prior complete set")
	assert(CoverService.ClearRoundCover(), "clear must remove generated cover")
	assert(not CoverService.ClearRoundCover(), "clear must be idempotent")

	local failed, failureMessage = CoverService.GenerateRoundCover(newRandom({ 1 }, 10))
	assert(failed == nil and string.find(failureMessage, "intentional cover roll failure", 1, true), "partway failure must be reported")
	assert(arena:FindFirstChild(CoverConfig.ROUND_COVER_FOLDER_NAME) == nil, "failed transaction must leave no committed hierarchy")
	assert(arena:FindFirstChild("RoundCoverCandidate") == nil, "failed transaction must leave no candidate hierarchy")

	local assets = ServerStorage:FindFirstChild(CoverConfig.ASSET_ROOT_FOLDER_NAME)
	if assets then
		assets:Destroy()
	end
	arena:Destroy()
end

return CoverServiceTests
