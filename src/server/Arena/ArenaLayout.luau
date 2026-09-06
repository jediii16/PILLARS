local ArenaLayout = {}

local function platformCenterY(config, platformSize: Vector3): number
	return config.ARENA_CENTER.Y + config.PILLAR_HEIGHT - platformSize.Y / 2
end

function ArenaLayout.Calculate(config)
	local layouts = table.create(config.PLAYER_COUNT)

	for index = 1, config.PLAYER_COUNT do
		local angle = ((index - 1) / config.PLAYER_COUNT) * 2 * math.pi
		local horizontalOffset = Vector3.new(
			math.cos(angle) * config.PILLAR_RADIUS,
			0,
			math.sin(angle) * config.PILLAR_RADIUS
		)
		local position = config.ARENA_CENTER
			+ horizontalOffset
			+ Vector3.new(0, config.PILLAR_HEIGHT - config.PILLAR_SIZE.Y / 2, 0)
		local centerAtPlatformHeight = Vector3.new(
			config.ARENA_CENTER.X,
			position.Y,
			config.ARENA_CENTER.Z
		)
		local pillarCFrame = CFrame.lookAt(position, centerAtPlatformHeight)
		local spawnPosition = Vector3.new(
			position.X,
			config.ARENA_CENTER.Y + config.PILLAR_HEIGHT + config.SPAWN_MARKER_OFFSET,
			position.Z
		)

		layouts[index] = {
			Index = index,
			Angle = angle,
			Position = position,
			CFrame = pillarCFrame,
			Size = config.PILLAR_SIZE,
			SpawnPosition = spawnPosition,
			SpawnCFrame = CFrame.fromMatrix(
				spawnPosition,
				pillarCFrame.XVector,
				pillarCFrame.YVector,
				pillarCFrame.ZVector
			),
		}
	end

	return layouts
end

function ArenaLayout.CalculateCenterPlatform(config)
	local position = Vector3.new(
		config.ARENA_CENTER.X,
		platformCenterY(config, config.CENTER_PLATFORM_SIZE),
		config.ARENA_CENTER.Z
	)

	return {
		Position = position,
		CFrame = CFrame.new(position),
		Size = config.CENTER_PLATFORM_SIZE,
	}
end

function ArenaLayout.CalculateVoidBoundary(config)
	local pillarHalfExtent = math.max(config.PILLAR_SIZE.X, config.PILLAR_SIZE.Z) / 2
	local centerHalfExtent = math.max(config.CENTER_PLATFORM_SIZE.X, config.CENTER_PLATFORM_SIZE.Z) / 2
	local arenaHalfExtent = math.max(config.PILLAR_RADIUS + pillarHalfExtent, centerHalfExtent)
	local boundaryWidth = (arenaHalfExtent + config.VOID_BOUNDARY_MARGIN) * 2
	local position = Vector3.new(
		config.ARENA_CENTER.X,
		config.VOID_KILL_HEIGHT,
		config.ARENA_CENTER.Z
	)

	return {
		Position = position,
		CFrame = CFrame.new(position),
		Size = Vector3.new(boundaryWidth, config.VOID_BOUNDARY_THICKNESS, boundaryWidth),
	}
end

return ArenaLayout
