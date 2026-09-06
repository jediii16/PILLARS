local archetypes = {
	{
		Name = "ShortWide",
		Size = Vector3.new(10.5, 3.25, 4.5),
		Color = Color3.fromRGB(116, 121, 128),
	},
	{
		Name = "TallNarrow",
		Size = Vector3.new(4.5, 7, 4.5),
		Color = Color3.fromRGB(100, 108, 118),
	},
	{
		Name = "LongLow",
		Size = Vector3.new(12, 2.25, 4.5),
		Color = Color3.fromRGB(126, 126, 121),
	},
	{
		Name = "Chunky",
		Size = Vector3.new(9.5, 5, 4.5),
		Color = Color3.fromRGB(108, 104, 99),
	},
}

local archetypeByName = {}

for _, archetype in archetypes do
	table.freeze(archetype)
	archetypeByName[archetype.Name] = archetype
end

table.freeze(archetypes)
table.freeze(archetypeByName)

local CoverConfig = {
	ROUND_COVER_FOLDER_NAME = "RoundCover",
	ASSET_ROOT_FOLDER_NAME = "PILLARSAssets",
	STARTING_COVER_FOLDER_NAME = "StartingCover",
	PLACEMENT_BOUNDS_NAME = "PlacementBounds",
	PROTOTYPE_VARIANT_ID = "PrototypeFallback",

	LOCAL_FORWARD_OFFSET_Z = -5,
	LATERAL_OFFSET_X = 1.5,
	SPAWN_CLEARANCE_SIZE = Vector2.new(5, 5),
	SPAWN_TO_COVER_GAP = 0.25,
	FORWARD_EDGE_INSET = 0.75,
	MIN_FORWARD_ROUTE_WIDTH = 3.25,
	LOOT_RESERVE_SIZE = Vector2.new(6, 4),
	LOOT_RESERVE_CENTER = Vector2.new(0, 4.5),

	PIVOT_POSITION_TOLERANCE = 0.05,
	PIVOT_ORIENTATION_TOLERANCE_DEGREES = 1,
	BOUNDS_CONTAINMENT_TOLERANCE = 0.05,

	ARCHETYPES = archetypes,
	ARCHETYPE_BY_NAME = archetypeByName,
	MATERIAL = Enum.Material.Concrete,
}

return table.freeze(CoverConfig)
