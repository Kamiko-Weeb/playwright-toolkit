-- Abbreviates big numbers for display: 1500 -> "1.5K", 2_300_000 -> "2.3M".
local Format = {}

local SUFFIXES = { "", "K", "M", "B", "T", "Qa", "Qi", "Sx", "Sp", "Oc", "No", "Dc" }

function Format.abbreviate(n: number): string
	if n < 0 then
		n = 0
	end
	if n < 1000 then
		return tostring(math.floor(n))
	end

	local index = 0
	local value = n
	while value >= 1000 and index < #SUFFIXES - 1 do
		value = value / 1000
		index += 1
	end

	local text = string.format("%.1f", value)
	text = (text:gsub("%.0$", ""))
	return text .. SUFFIXES[index + 1]
end

return Format
