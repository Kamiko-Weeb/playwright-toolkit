-- ============================================================================
--  Leaderboard — global "top coins" board backed by an OrderedDataStore.
--  Drives competition, which drives play time, which drives purchases.
-- ============================================================================
local DataStoreService = game:GetService("DataStoreService")
local Players = game:GetService("Players")

local ordered = DataStoreService:GetOrderedDataStore("CoinClicker_Leaderboard_v1")

local Leaderboard = {}

local INT_MAX = 2 ^ 31 - 1

function Leaderboard.update(player: Player, coins: number)
	local value = math.clamp(math.floor(coins), 0, INT_MAX)
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
	local page = pages:GetCurrentPage()
	for _, entry in page do
		local userId = tonumber(entry.key)
		if userId then
			table.insert(list, {
				name = nameFor(userId),
				coins = entry.value,
			})
		end
	end
	return list
end

return Leaderboard
