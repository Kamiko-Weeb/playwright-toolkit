-- ============================================================================
--  Leaderboard — global "richest players" board via an OrderedDataStore.
-- ============================================================================
local DataStoreService = game:GetService("DataStoreService")
local Players = game:GetService("Players")

local ordered = DataStoreService:GetOrderedDataStore("HoardABrainrot_Leaderboard_v1")

local Leaderboard = {}

local INT_MAX = 2 ^ 31 - 1

function Leaderboard.update(player: Player, cash: number)
	local value = math.clamp(math.floor(cash), 0, INT_MAX)
	pcall(function()
		ordered:SetAsync(tostring(player.UserId), value)
	end)
end

local nameCache: { [number]: string } = {}
local function nameFor(userId: number): string
	if nameCache[userId] then
		return nameCache[userId]
	end
	local ok, name = pcall(function()
		return Players:GetNameFromUserIdAsync(userId)
	end)
	local result = (ok and name) or ("User" .. userId)
	nameCache[userId] = result
	return result
end

function Leaderboard.getTop(count: number)
	local list = {}
	local ok, pages = pcall(function()
		return ordered:GetSortedAsync(false, count)
	end)
	if not ok then
		return list
	end
	for _, entry in pages:GetCurrentPage() do
		local userId = tonumber(entry.key)
		if userId then
			table.insert(list, { name = nameFor(userId), cash = entry.value })
		end
	end
	return list
end

return Leaderboard
