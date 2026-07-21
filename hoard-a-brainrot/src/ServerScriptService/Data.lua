-- ============================================================================
--  Data — per-player save/load (DataStoreService) with a session cache and a
--  guard that disables saving when a load fails (so we never wipe real data).
-- ============================================================================
local DataStoreService = game:GetService("DataStoreService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Config = require(ReplicatedStorage.Shared.Config)

local store = DataStoreService:GetDataStore("HoardABrainrot_PlayerData_v1")

local Data = {}

local cache: { [Player]: any } = {}
local canSave: { [Player]: boolean } = {}

local function defaultData()
	return {
		cash = Config.StartingCash, -- "Loot" (kept as `cash` internally)
		rebirths = 0, -- ascension tier
		creatures = {}, -- array of { id = string, golden = boolean } on the Vault
		purchaseHistory = {}, -- [PurchaseId] = true, blocks double-granting products
	}
end

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
		local def = defaultData()
		d.cash = d.cash or def.cash
		d.rebirths = d.rebirths or 0
		d.creatures = d.creatures or {}
		d.purchaseHistory = d.purchaseHistory or {}
		cache[player] = d
		canSave[player] = true
	else
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
