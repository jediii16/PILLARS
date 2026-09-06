local RunService = game:GetService("RunService")
local ServerStorage = game:GetService("ServerStorage")
local Workspace = game:GetService("Workspace")

local ArenaConfig = require(script.Parent.Parent.Arena.ArenaConfig)
local CoverConfig = require(script.Parent.CoverConfig)

local defaultRandom = Random.new()
local EPSILON = 1e-4
local PLACEMENT_SIDES = table.freeze({ "Left", "Right" })
local SIDE_SIGNS = table.freeze({ Left = -1, Right = 1 })

local CoverService = {}

local function getArena(): Model?
	local arena = Workspace:FindFirstChild(ArenaConfig.GENERATED_MODEL_NAME)
	return if arena and arena:IsA("Model") then arena else nil
end

local function discoverIndexedParts(folder: Instance, label: string)
	local indexed = {}
	for _, child in folder:GetChildren() do
		local pillarIndex = child:GetAttribute("PillarIndex")
		if pillarIndex ~= nil then
			assert(child:IsA("BasePart"), label .. " with PillarIndex must be a BasePart")
			assert(type(pillarIndex) == "number" and pillarIndex % 1 == 0 and pillarIndex >= 1 and pillarIndex <= ArenaConfig.PLAYER_COUNT, label .. " has an invalid PillarIndex")
			assert(indexed[pillarIndex] == nil, string.format("duplicate %s for PillarIndex %d", label, pillarIndex))
			indexed[pillarIndex] = child
		end
	end

	for pillarIndex = 1, ArenaConfig.PLAYER_COUNT do
		assert(indexed[pillarIndex] ~= nil, string.format("missing %s for PillarIndex %d", label, pillarIndex))
	end
	return indexed
end

local function resolveArenaSources()
	local arena = assert(getArena(), "generated arena is unavailable")
	local geometry = assert(arena:FindFirstChild(ArenaConfig.PERMANENT_GEOMETRY_FOLDER_NAME), "permanent geometry is unavailable")
	local markers = assert(arena:FindFirstChild(ArenaConfig.SPAWN_MARKERS_FOLDER_NAME), "spawn markers are unavailable")
	assert(geometry:IsA("Folder"), "permanent geometry must be a Folder")
	assert(markers:IsA("Folder"), "spawn markers must be a Folder")
	return arena, discoverIndexedParts(geometry, "starting pillar"), discoverIndexedParts(markers, "spawn marker")
end

local function getPartBoundsInReference(part: BasePart, referenceCFrame: CFrame)
	local half = part.Size / 2
	local minimum = Vector3.new(math.huge, math.huge, math.huge)
	local maximum = Vector3.new(-math.huge, -math.huge, -math.huge)
	for _, x in { -1, 1 } do
		for _, y in { -1, 1 } do
			for _, z in { -1, 1 } do
				local point = referenceCFrame:PointToObjectSpace(part.CFrame:PointToWorldSpace(Vector3.new(x * half.X, y * half.Y, z * half.Z)))
				minimum = Vector3.new(math.min(minimum.X, point.X), math.min(minimum.Y, point.Y), math.min(minimum.Z, point.Z))
				maximum = Vector3.new(math.max(maximum.X, point.X), math.max(maximum.Y, point.Y), math.max(maximum.Z, point.Z))
			end
		end
	end
	return minimum, maximum
end

local function rectanglesOverlap(aMin: Vector2, aMax: Vector2, bMin: Vector2, bMax: Vector2): boolean
	return aMin.X < bMax.X - EPSILON and aMax.X > bMin.X + EPSILON and aMin.Y < bMax.Y - EPSILON and aMax.Y > bMin.Y + EPSILON
end

local function trim(value: string): string
	return string.match(value, "^%s*(.-)%s*$")
end

local function rotationDifferenceDegrees(cframe: CFrame): number
	local cosine = math.clamp((cframe.XVector.X + cframe.YVector.Y + cframe.ZVector.Z - 1) / 2, -1, 1)
	return math.deg(math.acos(cosine))
end

local function findPlacementBounds(model: Model): (BasePart?, string?)
	local matches = {}
	for _, child in model:GetChildren() do
		if child.Name == CoverConfig.PLACEMENT_BOUNDS_NAME then
			table.insert(matches, child)
		end
	end
	if #matches ~= 1 or not matches[1]:IsA("BasePart") then
		return nil, "must contain exactly one direct BasePart named PlacementBounds"
	end
	return matches[1], nil
end

local function validateVariant(model: Model, archetype): (boolean, string?)
	for _, descendant in model:GetDescendants() do
		if descendant:IsA("Script") or descendant:IsA("LocalScript") or descendant:IsA("ModuleScript") then
			return false, "contains executable scripts"
		end
	end

	local bounds, boundsError = findPlacementBounds(model)
	if not bounds then
		return false, boundsError
	end
	if bounds.Size.X > archetype.Size.X + EPSILON or bounds.Size.Y > archetype.Size.Y + EPSILON or bounds.Size.Z > archetype.Size.Z + EPSILON then
		return false, "PlacementBounds exceeds the archetype maximum"
	end

	local relative = model:GetPivot():ToObjectSpace(bounds.CFrame)
	local expectedPosition = Vector3.new(0, bounds.Size.Y / 2, 0)
	if (relative.Position - expectedPosition).Magnitude > CoverConfig.PIVOT_POSITION_TOLERANCE then
		return false, "model pivot is not at PlacementBounds bottom-center"
	end
	if rotationDifferenceDegrees(relative.Rotation) > CoverConfig.PIVOT_ORIENTATION_TOLERANCE_DEGREES then
		return false, "model pivot orientation differs from PlacementBounds"
	end

	local half = bounds.Size / 2
	local foundSolidPart = false
	for _, descendant in model:GetDescendants() do
		if descendant:IsA("BasePart") and descendant ~= bounds then
			foundSolidPart = foundSolidPart or descendant.CanCollide
			local minimum, maximum = getPartBoundsInReference(descendant, bounds.CFrame)
			local tolerance = CoverConfig.BOUNDS_CONTAINMENT_TOLERANCE
			if minimum.X < -half.X - tolerance or maximum.X > half.X + tolerance
				or minimum.Y < -half.Y - tolerance or maximum.Y > half.Y + tolerance
				or minimum.Z < -half.Z - tolerance or maximum.Z > half.Z + tolerance then
				return false, descendant:GetFullName() .. " exceeds PlacementBounds"
			end
		end
	end
	if not foundSolidPart then
		return false, "must contain at least one collidable cover part"
	end
	return true, nil
end

local function warnInvalid(archetypeName: string, model: Instance, reason: string)
	if RunService:IsStudio() then
		warn(string.format("PILLARS cover variant rejected: %s/%s (%s)", archetypeName, model.Name, reason))
	end
end

local function buildVariantCatalog()
	local catalogByArchetype = {}
	local root = ServerStorage:FindFirstChild(CoverConfig.ASSET_ROOT_FOLDER_NAME)
	local catalog = root and root:FindFirstChild(CoverConfig.STARTING_COVER_FOLDER_NAME)

	for _, archetype in CoverConfig.ARCHETYPES do
		local valid = {}
		local candidates = {}
		local counts = {}
		local folder = catalog and catalog:FindFirstChild(archetype.Name)
		if folder then
			for _, child in folder:GetChildren() do
				if child:IsA("Model") then
					local rawId = child:GetAttribute("CoverVariantId")
					local variantId = if type(rawId) == "string" then trim(rawId) else ""
					if variantId == "" then
						warnInvalid(archetype.Name, child, "CoverVariantId must be non-empty")
					elseif variantId == CoverConfig.PROTOTYPE_VARIANT_ID then
						warnInvalid(archetype.Name, child, "CoverVariantId is reserved for the prototype fallback")
					else
						table.insert(candidates, { Model = child, Id = variantId })
						counts[variantId] = (counts[variantId] or 0) + 1
					end
				end
			end
		end

		for _, candidate in candidates do
			if counts[candidate.Id] > 1 then
				warnInvalid(archetype.Name, candidate.Model, "duplicate CoverVariantId " .. candidate.Id)
			else
				local isValid, reason = validateVariant(candidate.Model, archetype)
				if isValid then
					table.insert(valid, candidate)
				else
					warnInvalid(archetype.Name, candidate.Model, reason)
				end
			end
		end
		table.sort(valid, function(a, b)
			return a.Id < b.Id
		end)
		catalogByArchetype[archetype.Name] = valid
	end

	return catalogByArchetype
end

local function setCoverAttributes(instance: Instance, pillarIndex: number, archetypeName: string, variantId: string, side: string)
	instance:SetAttribute("PillarIndex", pillarIndex)
	instance:SetAttribute("CoverArchetype", archetypeName)
	instance:SetAttribute("CoverVariantId", variantId)
	instance:SetAttribute("PlacementSide", side)
	instance:SetAttribute("PermanentCover", true)
end

local function createFallback(archetype): Model
	local model = Instance.new("Model")
	model.Name = CoverConfig.PROTOTYPE_VARIANT_ID
	local bounds = Instance.new("Part")
	bounds.Name = CoverConfig.PLACEMENT_BOUNDS_NAME
	bounds.Size = archetype.Size
	bounds.CFrame = CFrame.new(0, archetype.Size.Y / 2, 0)
	bounds.Parent = model

	local part = Instance.new("Part")
	part.Name = "CoverPart"
	part.Size = archetype.Size
	part.CFrame = bounds.CFrame
	part.Color = archetype.Color
	part.Material = CoverConfig.MATERIAL
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	part.CanCollide = true
	part.CanQuery = true
	part.CanTouch = true
	part.Parent = model
	model.WorldPivot = CFrame.new()
	return model
end

local function prepareRuntimeCover(model: Model, pillar: BasePart, pillarIndex: number, archetype, variantId: string, side: string): Model
	model.Name = string.format("PillarCover%02d", pillarIndex)
	local bounds = assert(findPlacementBounds(model))
	model.WorldPivot = bounds.CFrame * CFrame.new(0, -bounds.Size.Y / 2, 0)
	local sign = SIDE_SIGNS[side]
	model:PivotTo(pillar.CFrame * CFrame.new(sign * CoverConfig.LATERAL_OFFSET_X, pillar.Size.Y / 2, CoverConfig.LOCAL_FORWARD_OFFSET_Z))
	setCoverAttributes(model, pillarIndex, archetype.Name, variantId, side)

	for _, descendant in model:GetDescendants() do
		if descendant:IsA("BasePart") then
			descendant.Anchored = true
			descendant.Locked = true
			setCoverAttributes(descendant, pillarIndex, archetype.Name, variantId, side)
		end
	end
	bounds.Transparency = 1
	bounds.CanCollide = false
	bounds.CanTouch = false
	bounds.CanQuery = false
	bounds.CastShadow = false
	return model
end

local function validatePlacement(model: Model, pillar: BasePart, marker: BasePart, side: string)
	local bounds = assert(findPlacementBounds(model))
	local minimum, maximum = getPartBoundsInReference(bounds, pillar.CFrame)
	local halfX, halfZ = pillar.Size.X / 2, pillar.Size.Z / 2
	assert(minimum.X >= -halfX - EPSILON and maximum.X <= halfX + EPSILON, "cover exceeds pillar lateral bounds")
	assert(minimum.Z >= -halfZ + CoverConfig.FORWARD_EDGE_INSET - EPSILON, "cover violates forward edge inset")
	assert(maximum.Z <= halfZ + EPSILON, "cover exceeds pillar rear bound")
	assert(math.abs(minimum.Y - pillar.Size.Y / 2) <= CoverConfig.PIVOT_POSITION_TOLERANCE + EPSILON, "cover does not rest on pillar top")

	local markerLocal = pillar.CFrame:PointToObjectSpace(marker.Position)
	local spawnHalf = CoverConfig.SPAWN_CLEARANCE_SIZE / 2
	local spawnMin = Vector2.new(markerLocal.X, markerLocal.Z) - spawnHalf
	local spawnMax = Vector2.new(markerLocal.X, markerLocal.Z) + spawnHalf
	local coverMin, coverMax = Vector2.new(minimum.X, minimum.Z), Vector2.new(maximum.X, maximum.Z)
	assert(not rectanglesOverlap(coverMin, coverMax, spawnMin, spawnMax), "cover overlaps spawn clearance")
	assert(spawnMin.Y - maximum.Z >= CoverConfig.SPAWN_TO_COVER_GAP - EPSILON, "cover does not preserve spawn gap")

	local openWidth = if side == "Left" then halfX - maximum.X else minimum.X + halfX
	assert(openWidth >= CoverConfig.MIN_FORWARD_ROUTE_WIDTH - EPSILON, "cover does not preserve a practical forward route")
	local lootHalf = CoverConfig.LOOT_RESERVE_SIZE / 2
	assert(not rectanglesOverlap(coverMin, coverMax, CoverConfig.LOOT_RESERVE_CENTER - lootHalf, CoverConfig.LOOT_RESERVE_CENTER + lootHalf), "cover overlaps reserved loot floor")
	assert(bounds.Transparency == 1 and not bounds.CanCollide and not bounds.CanTouch and not bounds.CanQuery, "PlacementBounds must be inert")
end

local function validateCandidate(candidate: Folder, pillars, markers)
	assert(#candidate:GetChildren() == ArenaConfig.PLAYER_COUNT, "candidate must contain exactly one cover per pillar")
	local seen = {}
	for _, child in candidate:GetChildren() do
		assert(child:IsA("Model"), "candidate children must be Models")
		local index = child:GetAttribute("PillarIndex")
		local archetypeName = child:GetAttribute("CoverArchetype")
		local variantId = child:GetAttribute("CoverVariantId")
		local side = child:GetAttribute("PlacementSide")
		assert(type(index) == "number" and pillars[index] and not seen[index], "candidate has invalid or duplicate pillar index")
		assert(CoverConfig.ARCHETYPE_BY_NAME[archetypeName] ~= nil, "candidate has invalid archetype")
		assert(type(variantId) == "string" and trim(variantId) ~= "", "candidate has invalid variant id")
		assert(SIDE_SIGNS[side] ~= nil, "candidate has invalid placement side")
		assert(child:GetAttribute("PermanentCover") == true, "candidate lacks permanent metadata")
		validatePlacement(child, pillars[index], markers[index], side)
		seen[index] = true
	end
	for index = 1, ArenaConfig.PLAYER_COUNT do
		assert(seen[index], string.format("candidate is missing PillarIndex %d", index))
	end
end

function CoverService.ClearRoundCover(): boolean
	local arena = getArena()
	local current = arena and arena:FindFirstChild(CoverConfig.ROUND_COVER_FOLDER_NAME)
	if not current then
		return false
	end
	current:Destroy()
	return true
end

function CoverService.GenerateRoundCover(randomSource): (Folder?, string?)
	local sourceSucceeded, arenaOrError, pillars, markers = pcall(resolveArenaSources)
	if not sourceSucceeded then
		return nil, tostring(arenaOrError)
	end
	local arena = arenaOrError
	local random = randomSource or defaultRandom
	local catalog = buildVariantCatalog()
	CoverService.ClearRoundCover()

	local candidate = Instance.new("Folder")
	candidate.Name = "RoundCoverCandidate"
	local succeeded, generationError = xpcall(function()
		for pillarIndex = 1, ArenaConfig.PLAYER_COUNT do
			local archetype = assert(CoverConfig.ARCHETYPES[random:NextInteger(1, #CoverConfig.ARCHETYPES)], "random source selected invalid archetype")
			local variants = catalog[archetype.Name]
			local variantCount = math.max(1, #variants)
			local variantIndex = random:NextInteger(1, variantCount)
			local source = variants[variantIndex]
			local variantId = if source then source.Id else CoverConfig.PROTOTYPE_VARIANT_ID
			local model = if source then source.Model:Clone() else createFallback(archetype)
			local side = PLACEMENT_SIDES[random:NextInteger(1, #PLACEMENT_SIDES)]
			prepareRuntimeCover(model, pillars[pillarIndex], pillarIndex, archetype, variantId, side).Parent = candidate
		end
		validateCandidate(candidate, pillars, markers)
	end, function(message)
		return debug.traceback(tostring(message), 2)
	end)

	if not succeeded then
		candidate:Destroy()
		CoverService.ClearRoundCover()
		return nil, generationError
	end
	candidate.Name = CoverConfig.ROUND_COVER_FOLDER_NAME
	candidate.Parent = arena

	if RunService:IsStudio() then
		for pillarIndex = 1, ArenaConfig.PLAYER_COUNT do
			local cover = assert(CoverService.GetCoverForPillar(pillarIndex))
			print(string.format("PILLARS cover: Pillar %d -> %s / %s / %s", pillarIndex, cover:GetAttribute("CoverArchetype"), cover:GetAttribute("CoverVariantId"), cover:GetAttribute("PlacementSide")))
		end
	end
	return candidate, nil
end

function CoverService.GetCoverForPillar(pillarIndex: number): Model?
	local arena = getArena()
	local folder = arena and arena:FindFirstChild(CoverConfig.ROUND_COVER_FOLDER_NAME)
	if not folder or not folder:IsA("Folder") then
		return nil
	end
	local match = nil
	for _, child in folder:GetChildren() do
		if child:IsA("Model") and child:GetAttribute("PillarIndex") == pillarIndex then
			if match then
				return nil
			end
			match = child
		end
	end
	return match
end

function CoverService.GetCoverArchetypeForPillar(pillarIndex: number): string?
	local cover = CoverService.GetCoverForPillar(pillarIndex)
	local value = cover and cover:GetAttribute("CoverArchetype")
	return if type(value) == "string" then value else nil
end

function CoverService.GetCoverVariantForPillar(pillarIndex: number): string?
	local cover = CoverService.GetCoverForPillar(pillarIndex)
	local value = cover and cover:GetAttribute("CoverVariantId")
	return if type(value) == "string" then value else nil
end

return CoverService
