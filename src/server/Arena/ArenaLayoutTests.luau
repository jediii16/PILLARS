local ArenaConfig = require(script.Parent.ArenaConfig)
local ArenaLayout = require(script.Parent.ArenaLayout)

local EPSILON = 1e-4

local function expectNear(actual: number, expected: number, message: string)
	assert(
		math.abs(actual - expected) <= EPSILON,
		string.format("%s: expected %.4f, got %.4f", message, expected, actual)
	)
end

local function withOverrides(overrides)
	local result = table.clone(ArenaConfig)

	for key, value in overrides do
		result[key] = value
	end

	return result
end

local ArenaLayoutTests = {}

function ArenaLayoutTests.Run()
	local layouts = ArenaLayout.Calculate(ArenaConfig)

	assert(#layouts == 8, "layout must contain exactly eight pillars")

	for index, layout in layouts do
		assert(layout.Index == index, "pillar indices must be stable")
		expectNear(Vector2.new(layout.Position.X, layout.Position.Z).Magnitude, 80, "pillar radius")
		expectNear(layout.Angle, (index - 1) * math.pi / 4, "pillar angle")
		assert(layout.Size == Vector3.new(16, 4, 16), "pillar size must come from config")
		expectNear(layout.SpawnPosition.Y, 73, "spawn marker height")
	end

	local wider = ArenaLayout.Calculate(withOverrides({ PILLAR_RADIUS = 120 }))
	expectNear(Vector2.new(wider[3].Position.X, wider[3].Position.Z).Magnitude, 120, "changed radius")

	local resized = ArenaLayout.Calculate(withOverrides({ PILLAR_SIZE = Vector3.new(20, 8, 20) }))
	assert(resized[1].Size == Vector3.new(20, 8, 20), "changed size must be used")
	expectNear(resized[1].SpawnPosition.Y, 73, "spawn height must derive from the walkable top")

	local center = ArenaLayout.CalculateCenterPlatform(ArenaConfig)
	assert(center.Position == Vector3.new(0, 68, 0), "center platform must be centered")

	local void = ArenaLayout.CalculateVoidBoundary(ArenaConfig)
	expectNear(void.Position.Y, ArenaConfig.VOID_KILL_HEIGHT, "void kill height")
	expectNear(void.Position.Y, -150, "prototype recovery-height boundary")
	assert(
		ArenaConfig.PILLAR_HEIGHT - void.Position.Y == 220,
		"prototype arena must provide 220 studs of vertical recovery distance"
	)
	local pillarOuterEdge = ArenaConfig.PILLAR_RADIUS
		+ math.max(ArenaConfig.PILLAR_SIZE.X, ArenaConfig.PILLAR_SIZE.Z) / 2
	local voidHorizontalMargin = void.Size.X / 2 - pillarOuterEdge
	assert(voidHorizontalMargin >= 1000, "void boundary must extend generously beyond the playable arena")

	local edgeGap = ArenaConfig.PILLAR_RADIUS
		- ArenaConfig.PILLAR_SIZE.Z / 2
		- ArenaConfig.CENTER_PLATFORM_SIZE.Z / 2
	assert(edgeGap > 20, "normal movement must not bridge the center gap")
end

return ArenaLayoutTests
