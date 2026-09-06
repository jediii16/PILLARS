local RoundShuffle = {}

function RoundShuffle.ShuffledCopy(values, random)
	local shuffled = table.clone(values)

	for index = #shuffled, 2, -1 do
		local swapIndex = random:NextInteger(1, index)
		shuffled[index], shuffled[swapIndex] = shuffled[swapIndex], shuffled[index]
	end

	return shuffled
end

return RoundShuffle
