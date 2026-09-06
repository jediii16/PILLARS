local CoverConfig = require(script.Parent.CoverConfig)

local CoverConfigTests = {}

function CoverConfigTests.Run()
	local expectedNames = { "ShortWide", "TallNarrow", "LongLow", "Chunky" }
	local expectedSizes = {
		ShortWide = Vector3.new(10.5, 3.25, 4.5),
		TallNarrow = Vector3.new(4.5, 7, 4.5),
		LongLow = Vector3.new(12, 2.25, 4.5),
		Chunky = Vector3.new(9.5, 5, 4.5),
	}

	assert(#CoverConfig.ARCHETYPES == 4, "exactly four starting-cover archetypes are required")

	for index, expectedName in expectedNames do
		local archetype = CoverConfig.ARCHETYPES[index]
		assert(archetype.Name == expectedName, "archetypes must retain their stable configured order")
		assert(archetype.Size == expectedSizes[expectedName], expectedName .. " must use its approved prototype size")
		assert(CoverConfig.ARCHETYPE_BY_NAME[expectedName] == archetype, expectedName .. " must be addressable by name")
		assert(typeof(archetype.Color) == "Color3", expectedName .. " must have a prototype color")
	end

	assert(CoverConfig.ROUND_COVER_FOLDER_NAME == "RoundCover", "round cover must use the approved hierarchy name")
	assert(CoverConfig.ASSET_ROOT_FOLDER_NAME == "PILLARSAssets", "curated assets must use the approved root")
	assert(CoverConfig.STARTING_COVER_FOLDER_NAME == "StartingCover", "curated assets must use the approved catalog")
	assert(CoverConfig.PLACEMENT_BOUNDS_NAME == "PlacementBounds", "variants must use the approved envelope name")
	assert(CoverConfig.PROTOTYPE_VARIANT_ID == "PrototypeFallback", "fallback must have a stable variant id")
	assert(CoverConfig.LOCAL_FORWARD_OFFSET_Z == -5, "cover must use the approved forward offset")
	assert(CoverConfig.LATERAL_OFFSET_X == 1.5, "cover must use the approved lateral bias")
	assert(CoverConfig.SPAWN_CLEARANCE_SIZE == Vector2.new(5, 5), "spawn clearance must remain centralized")
	assert(CoverConfig.SPAWN_TO_COVER_GAP == 0.25, "spawn-to-cover gap must remain centralized")
	assert(CoverConfig.FORWARD_EDGE_INSET == 0.75, "forward inset must remain centralized")
	assert(CoverConfig.MIN_FORWARD_ROUTE_WIDTH == 3.25, "forward route width must remain centralized")
	assert(CoverConfig.LOOT_RESERVE_SIZE == Vector2.new(6, 4), "loot reserve must remain centralized")
	assert(CoverConfig.LOOT_RESERVE_CENTER == Vector2.new(0, 4.5), "loot reserve location must remain centralized")
	assert(CoverConfig.PIVOT_POSITION_TOLERANCE > 0, "pivot position tolerance must be practical")
	assert(CoverConfig.PIVOT_ORIENTATION_TOLERANCE_DEGREES > 0, "pivot orientation tolerance must be practical")
	assert(CoverConfig.BOUNDS_CONTAINMENT_TOLERANCE > 0, "bounds validation tolerance must be practical")
end

return CoverConfigTests
