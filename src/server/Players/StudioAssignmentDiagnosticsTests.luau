local Players = game:GetService("Players")

local PlayerSpawnService = require(script.Parent.PlayerSpawnService)
local StudioAssignmentDiagnostics = require(script.Parent.StudioAssignmentDiagnostics)

local StudioAssignmentDiagnosticsTests = {}

function StudioAssignmentDiagnosticsTests.Run()
	PlayerSpawnService.ClearAssignments()

	local player = {
		Name = "DiagnosticPlayer",
		Parent = Players,
	}
	local pillarIndex = PlayerSpawnService.AssignPlayer(player)
	local snapshot = StudioAssignmentDiagnostics.Log(PlayerSpawnService, player, pillarIndex)

	assert(snapshot.PlayerPillarIndex == 1, "diagnostic must read the player-to-pillar mapping")
	assert(snapshot.PillarPlayer == player, "diagnostic must read the pillar-to-player mapping")
	assert(snapshot.IsConsistent, "diagnostic must confirm reciprocal authoritative mappings")

	local inconsistentSnapshot = StudioAssignmentDiagnostics.Log(PlayerSpawnService, player, 2)
	assert(not inconsistentSnapshot.IsConsistent, "diagnostic must report non-reciprocal mappings")

	PlayerSpawnService.ClearAssignments()
end

return StudioAssignmentDiagnosticsTests
