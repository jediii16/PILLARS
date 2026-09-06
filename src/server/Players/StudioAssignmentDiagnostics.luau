local StudioAssignmentDiagnostics = {}

function StudioAssignmentDiagnostics.Log(playerSpawnService, player, pillarIndex: number)
	local playerPillarIndex = playerSpawnService.GetPillarIndex(player)
	local pillarPlayer = playerSpawnService.GetPlayerForPillar(pillarIndex)
	local isConsistent = playerPillarIndex == pillarIndex and pillarPlayer == player
	local playerPillarLabel = if playerPillarIndex then tostring(playerPillarIndex) else "nil"
	local pillarPlayerLabel = if pillarPlayer then pillarPlayer.Name else "nil"
	local message = string.format(
		"PILLARS Studio assignment: %s -> Pillar %s | Pillar %d -> %s",
		player.Name,
		playerPillarLabel,
		pillarIndex,
		pillarPlayerLabel
	)

	if isConsistent then
		print(message)
	else
		warn("PILLARS Studio assignment inconsistency: " .. message)
	end

	return table.freeze({
		PlayerPillarIndex = playerPillarIndex,
		PillarPlayer = pillarPlayer,
		IsConsistent = isConsistent,
	})
end

return StudioAssignmentDiagnostics
