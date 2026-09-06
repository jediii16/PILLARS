local RoundConfig = require(script.Parent.RoundConfig)
local RoundShuffle = require(script.Parent.RoundShuffle)
local RoundState = require(script.Parent.RoundState)

local RoundFoundationTests = {}

local function newDeterministicRandom(choices)
	local choiceIndex = 0
	local random = {}

	function random:NextInteger(minimum: number, maximum: number): number
		choiceIndex += 1
		local choice = choices[choiceIndex]
		assert(choice ~= nil, "deterministic random ran out of choices")
		assert(choice >= minimum and choice <= maximum, "deterministic choice is outside the requested range")
		return choice
	end

	function random:GetCallCount(): number
		return choiceIndex
	end

	return random
end

function RoundFoundationTests.Run()
	assert(RoundConfig.MIN_PLAYERS == 2, "prototype minimum must be two players")
	assert(RoundConfig.COUNTDOWN_DURATION == 5, "prototype countdown must be five seconds")
	assert(RoundConfig.END_ROUND_DELAY == 3, "prototype ending delay must be three seconds")

	local allowedTransitions = {
		{ RoundState.WAITING, RoundState.COUNTDOWN },
		{ RoundState.COUNTDOWN, RoundState.STARTING },
		{ RoundState.COUNTDOWN, RoundState.WAITING },
		{ RoundState.STARTING, RoundState.ACTIVE },
		{ RoundState.STARTING, RoundState.WAITING },
		{ RoundState.ACTIVE, RoundState.ENDING },
		{ RoundState.ENDING, RoundState.WAITING },
	}

	for _, transition in allowedTransitions do
		assert(RoundState.CanTransition(transition[1], transition[2]), "required transition must be allowed")
	end

	local states = {
		RoundState.WAITING,
		RoundState.COUNTDOWN,
		RoundState.STARTING,
		RoundState.ACTIVE,
		RoundState.ENDING,
	}

	for _, fromState in states do
		for _, toState in states do
			local expected = false

			for _, transition in allowedTransitions do
				if transition[1] == fromState and transition[2] == toState then
					expected = true
					break
				end
			end

			assert(
				RoundState.CanTransition(fromState, toState) == expected,
				string.format("unexpected transition validation: %s -> %s", fromState, toState)
			)
		end
	end

	local input = { "A", "B", "C", "D" }
	local firstRandom = newDeterministicRandom({ 1, 1, 1 })
	local firstOutput = RoundShuffle.ShuffledCopy(input, firstRandom)

	assert(table.concat(input, "") == "ABCD", "shuffle must not mutate the input")
	assert(table.concat(firstOutput, "") == "BCDA", "shuffle must use Fisher-Yates choices")
	assert(firstRandom:GetCallCount() == 3, "four values require three random choices")

	local secondRandom = newDeterministicRandom({ 4, 3, 2 })
	local secondOutput = RoundShuffle.ShuffledCopy(input, secondRandom)

	assert(table.concat(secondOutput, "") == "ABCD", "a fresh shuffle must consult its own random source")
	assert(secondRandom:GetCallCount() == 3, "each round must perform a fresh shuffle")
end

return RoundFoundationTests
