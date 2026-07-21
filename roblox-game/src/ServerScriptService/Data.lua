-- ============================================================================
--  Data — per-player save/load backed by DataStoreService, with a session
--  cache. Guards against wiping real data when a load fails.
-- ============================================================================
local DataStoreService = game:GetService("DataStoreService")

local store = DataStoreService:GetDataStore("CoinClicker_PlayerData_v1")

local Data = {}

local cache: { [Player]: any } = {}
local canSave: { [Player]: boolean } = {}

local function defaultData()
	return {
		coins = 0,
		rebirths = 0,
		upgrades = { ClickPower = 0, AutoIncome = 0 },
		purchaseHistory = {}, -- [PurchaseId] = true, prevents double-granting products
	}
end

-- Runs `fn` up to `attempts` times with exponential backoff (2s, 4s, 8s...).
local function retry(fn: () -> any, attempts: number): (boolean, any)
	local ok, result
	for i = 1, attempts do
		ok, result = pcall(fn)
		if ok then
			return true, result
		end
		task.wait(2 ^ i)
	end
	return false, result
end

function Data.load(player: Player)
	local key = "player_" .. player.UserId
	local ok, result = retry(function()
		return store:GetAsync(key)
	end, 3)

	if ok then
		local d = result or defaultData()
		-- Forward-compat: fill any fields added in later versions.
		local def = defaultData()
		d.coins = d.coins or def.coins
		d.rebirths = d.rebirths or def.rebirths
		d.upgrades = d.upgrades or def.upgrades
		d.upgrades.ClickPower = d.upgrades.ClickPower or 0
		d.upgrades.AutoIncome = d.upgrades.AutoIncome or 0
		d.purchaseHistory = d.purchaseHistory or {}
		cache[player] = d
		canSave[player] = true
	else
		-- Load failed: hand out a fresh session copy but DO NOT persist it,
		-- so we never overwrite the player's real (unreadable) save.
		cache[player] = defaultData()
		canSave[player] = false
		warn("[Data] Load failed for " .. player.Name .. "; saving disabled this session.")
	end

	return cache[player]
end

function Data.get(player: Player)
	return cache[player]
end

function Data.save(player: Player): boolean
	local d = cache[player]
	if not d or not canSave[player] then
		return false
	end
	local key = "player_" .. player.UserId
	local ok = retry(function()
		store:SetAsync(key, d)
		return true
	end, 3)
	if not ok then
		warn("[Data] Save failed for " .. player.Name)
	end
	return ok
end

function Data.clear(player: Player)
	cache[player] = nil
	canSave[player] = nil
end

return Data
