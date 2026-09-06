local RoundState = {
	WAITING = "WAITING",
	COUNTDOWN = "COUNTDOWN",
	STARTING = "STARTING",
	ACTIVE = "ACTIVE",
	ENDING = "ENDING",
}

local allowedTransitions = {
	[RoundState.WAITING] = table.freeze({
		[RoundState.COUNTDOWN] = true,
	}),
	[RoundState.COUNTDOWN] = table.freeze({
		[RoundState.STARTING] = true,
		[RoundState.WAITING] = true,
	}),
	[RoundState.STARTING] = table.freeze({
		[RoundState.ACTIVE] = true,
		[RoundState.WAITING] = true,
	}),
	[RoundState.ACTIVE] = table.freeze({
		[RoundState.ENDING] = true,
	}),
	[RoundState.ENDING] = table.freeze({
		[RoundState.WAITING] = true,
	}),
}

function RoundState.CanTransition(fromState: string, toState: string): boolean
	local destinations = allowedTransitions[fromState]
	return destinations ~= nil and destinations[toState] == true
end

return table.freeze(RoundState)
