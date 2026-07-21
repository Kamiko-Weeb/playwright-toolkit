-- ============================================================================
--  Main — server entry point. Creates remotes, handles join/leave, runs the
--  economy tick, and pushes authoritative snapshots to clients.
-- ============================================================================
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Config = require(ReplicatedStorage.Shared.Config)
local Data = require(script.Parent.Data)
local Economy = require(script.Parent.Economy)
local Monetization = require(script.Parent.Monetization)
local Leaderboard = require(script.Parent.Leaderboard)

-- Remotes --------------------------------------------------------------------
local Remotes = Instance.new("Folder")
Remotes.Name = "Remotes"

local function makeEvent(name: string): RemoteEvent
	local e = Instance.new("RemoteEvent")
	e.Name = name
	e.Parent = Remotes
	return e
end
local function makeFunction(name: string): RemoteFunction
	local f = Instance.new("RemoteFunction")
	f.Name = name
	f.Parent = Remotes
	return f
end

local SyncEvent = makeEvent("Sync") -- server -> client (full snapshot)
local CollectEvent = makeEvent("Collect") -- client -> server (manual click)
local BuyEvent = makeEvent("Buy") -- client -> server (upgrade key)
local RebirthEvent = makeEvent("Rebirth") -- client -> server
local ReadyEvent = makeEvent("Ready") -- client -> server (request first snapshot)
local LeaderboardFn = makeFunction("GetLeaderboard") -- client -> server (top players)

Remotes.Parent = ReplicatedStorage

-- Snapshot / sync ------------------------------------------------------------
local function buildSnapshot(player: Player)
	local data = Data.get(player)
	if not data then
		return nil
	end

	local snapshot = {
		coins = data.coins,
		rebirths = data.rebirths,
		perClick = Economy.perClick(player, data),
		perSecond = Economy.perSecond(player, data),
		rebirthCost = Economy.rebirthCost(data),
		canRebirth = Economy.canRebirth(data),
		rebirthMultiplier = Economy.rebirthMultiplier(data),
		upgrades = {},
		passes = {},
	}

	for _, key in Config.UpgradeOrder do
		local u = Config.Upgrades[key]
		local level = data.upgrades[key]
		snapshot.upgrades[key] = {
			level = level,
			cost = Economy.upgradeCost(key, level),
			maxed = level >= u.maxLevel,
		}
	end

	for _, key in Config.GamePassOrder do
		snapshot.passes[key] = Monetization.owns(player, key)
	end

	return snapshot
end

local function pushSync(player: Player)
	local snapshot = buildSnapshot(player)
	if snapshot then
		SyncEvent:FireClient(player, snapshot)
	end
end

-- Wiring ---------------------------------------------------------------------
Economy.setPassChecker(function(player, passKey)
	return Monetization.owns(player, passKey)
end)

Monetization.wire(function(player)
	return Data.get(player)
end, pushSync, function(player)
	return Data.save(player)
end)
Monetization.setupReceipts()
Monetization.setupPassListener(pushSync)

-- Click rate limiting (reset every second in the tick loop) ------------------
local clicksThisSecond: { [Player]: number } = {}

-- Remote handlers ------------------------------------------------------------
CollectEvent.OnServerEvent:Connect(function(player)
	local data = Data.get(player)
	if not data then
		return
	end
	local used = clicksThisSecond[player] or 0
	if used >= Config.MaxClicksPerSecond then
		return
	end
	clicksThisSecond[player] = used + 1
	Economy.click(player, data)
end)

BuyEvent.OnServerEvent:Connect(function(player, upgradeKey)
	if typeof(upgradeKey) ~= "string" then
		return
	end
	local data = Data.get(player)
	if not data then
		return
	end
	if Economy.buyUpgrade(player, data, upgradeKey) then
		pushSync(player)
	end
end)

RebirthEvent.OnServerEvent:Connect(function(player)
	local data = Data.get(player)
	if not data then
		return
	end
	if Economy.rebirth(player, data) then
		local ls = player:FindFirstChild("leaderstats")
		local rebirthValue = ls and ls:FindFirstChild("Rebirths")
		if rebirthValue then
			(rebirthValue :: IntValue).Value = data.rebirths
		end
		pushSync(player)
	end
end)

ReadyEvent.OnServerEvent:Connect(function(player)
	pushSync(player)
end)

LeaderboardFn.OnServerInvoke = function()
	return Leaderboard.getTop(10)
end

-- Join / leave ---------------------------------------------------------------
local function onJoin(player: Player)
	local data = Data.load(player)
	Monetization.loadPasses(player)

	-- Default Roblox sidebar shows Rebirths (small, always-safe numbers).
	-- Coins live in the custom top bar to avoid 32-bit overflow.
	local leaderstats = Instance.new("Folder")
	leaderstats.Name = "leaderstats"
	local rebirths = Instance.new("IntValue")
	rebirths.Name = "Rebirths"
	rebirths.Value = data.rebirths
	rebirths.Parent = leaderstats
	leaderstats.Parent = player

	pushSync(player)
end

local function onLeave(player: Player)
	local data = Data.get(player)
	if data then
		Leaderboard.update(player, data.coins)
	end
	Data.save(player)
	Monetization.clear(player)
	clicksThisSecond[player] = nil
	Data.clear(player)
end

Players.PlayerAdded:Connect(onJoin)
Players.PlayerRemoving:Connect(onLeave)
-- Handle anyone already in-game (e.g. the first player in Studio).
for _, player in Players:GetPlayers() do
	task.spawn(onJoin, player)
end

-- Economy tick ---------------------------------------------------------------
local secondAccumulator = 0
local syncAccumulator = 0
RunService.Heartbeat:Connect(function(dt)
	secondAccumulator += dt
	syncAccumulator += dt

	for _, player in Players:GetPlayers() do
		local data = Data.get(player)
		if data then
			data.coins += Economy.perSecond(player, data) * dt
		end
	end

	if secondAccumulator >= 1 then
		secondAccumulator -= 1
		clicksThisSecond = {} -- refill everyone's click budget
	end

	if syncAccumulator >= Config.SyncInterval then
		syncAccumulator -= Config.SyncInterval
		for _, player in Players:GetPlayers() do
			pushSync(player)
			local data = Data.get(player)
			if data then
				Leaderboard.update(player, data.coins)
			end
		end
	end
end)

-- Autosave -------------------------------------------------------------------
task.spawn(function()
	while true do
		task.wait(60)
		for _, player in Players:GetPlayers() do
			Data.save(player)
		end
	end
end)

game:BindToClose(function()
	for _, player in Players:GetPlayers() do
		task.spawn(Data.save, player)
	end
	task.wait(3) -- give async saves a moment to finish before shutdown
end)
