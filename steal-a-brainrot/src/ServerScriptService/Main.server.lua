-- ============================================================================
--  Main — server entry point. Builds the world, wires the systems, handles
--  join/leave + respawns, runs the economy tick, and syncs clients.
-- ============================================================================
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Config = require(ReplicatedStorage.Shared.Config)
local Brainrots = require(ReplicatedStorage.Shared.Brainrots)
local Data = require(script.Parent.Data)
local Monetization = require(script.Parent.Monetization)
local Leaderboard = require(script.Parent.Leaderboard)
local WorldBuilder = require(script.Parent.WorldBuilder)
local Plots = require(script.Parent.Plots)

-- Players spawn at their base, so we load characters manually after assigning.
Players.CharacterAutoLoads = false

-- Build the world and hand the plots to the Plots system.
Plots.init(WorldBuilder.build())

-- Remotes --------------------------------------------------------------------
local Remotes = Instance.new("Folder")
Remotes.Name = "Remotes"

local function makeEvent(name: string): RemoteEvent
	local e = Instance.new("RemoteEvent")
	e.Name = name
	e.Parent = Remotes
	return e
end

local SyncEvent = makeEvent("Sync")
local RollEvent = makeEvent("Roll")
local CollectEvent = makeEvent("Collect")
local NotifyEvent = makeEvent("Notify")
local ReadyEvent = makeEvent("Ready")

local LeaderboardFn = Instance.new("RemoteFunction")
LeaderboardFn.Name = "GetLeaderboard"
LeaderboardFn.Parent = Remotes

Remotes.Parent = ReplicatedStorage

-- Snapshot / sync ------------------------------------------------------------
local function buildSnapshot(player: Player)
	local data = Data.get(player)
	if not data then
		return nil
	end
	local used, total = Plots.slotsInfo(player)
	local passes = {}
	for _, key in Config.GamePassOrder do
		passes[key] = Monetization.owns(player, key)
	end
	return {
		cash = data.cash,
		income = Plots.incomePerSecond(player),
		rollCost = Plots.rollCost(player),
		slotsUsed = used,
		slotsTotal = total,
		passes = passes,
	}
end

local function pushSync(player: Player)
	local snapshot = buildSnapshot(player)
	if snapshot then
		SyncEvent:FireClient(player, snapshot)
	end
end

local function notify(player: Player, text: string, color: Color3?)
	NotifyEvent:FireClient(player, text, color or Color3.fromRGB(255, 255, 255))
end

Plots.wire(notify, pushSync)

-- Monetization ---------------------------------------------------------------
local function onProduct(player: Player, key: string, data): boolean
	local product = Config.Products[key]
	if product and product.cash then
		data.cash += product.cash
		notify(player, "+$" .. product.cash .. "!", Color3.fromRGB(80, 200, 120))
	elseif key == "LuckyRoll" then
		Plots.luckyRoll(player)
	else
		return false
	end
	pushSync(player)
	return true
end

Monetization.wire(function(player)
	return Data.get(player)
end, function(player)
	return Data.save(player)
end, onProduct)
Monetization.setupReceipts()

-- Character (teleport to base + apply Speed pass) ----------------------------
local function applyWalkSpeed(player: Player)
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if humanoid then
		humanoid.WalkSpeed = Monetization.owns(player, "Speed") and Config.SpeedPassWalkSpeed
			or Config.DefaultWalkSpeed
	end
end

local function onCharacter(player: Player, character: Model)
	local root = character:WaitForChild("HumanoidRootPart", 10) :: BasePart
	local cf = Plots.spawnCFrame(player)
	if root and cf then
		task.wait() -- let the character settle before teleporting
		root.CFrame = cf + Vector3.new(0, 3, 0)
	end
	applyWalkSpeed(player)
end

Monetization.setupPassListener(function(player, passKey)
	if passKey == "BaseLock" then
		Plots.refreshLock(player)
	elseif passKey == "Speed" then
		applyWalkSpeed(player)
	end
	pushSync(player)
end)

-- Remote handlers ------------------------------------------------------------
RollEvent.OnServerEvent:Connect(function(player)
	local ok, def, msg = Plots.roll(player)
	if ok and def then
		notify(player, "You rolled " .. def.name .. " (" .. def.rarity .. ")!", Brainrots.rarityColor(def.rarity))
	elseif msg then
		notify(player, msg, Color3.fromRGB(230, 90, 90))
	end
	pushSync(player)
end)

CollectEvent.OnServerEvent:Connect(function(player)
	local amount = Plots.collect(player)
	if amount > 0 then
		local index = Plots.plotIndexOf(player)
		if index then
			Plots.updateSign(index)
		end
	end
	pushSync(player)
end)

ReadyEvent.OnServerEvent:Connect(function(player)
	pushSync(player)
end)

LeaderboardFn.OnServerInvoke = function()
	return Leaderboard.getTop(10)
end

-- Join / leave ---------------------------------------------------------------
local function onJoin(player: Player)
	Data.load(player)
	Monetization.loadPasses(player)
	Plots.assign(player)

	local leaderstats = Instance.new("Folder")
	leaderstats.Name = "leaderstats"
	local cashValue = Instance.new("StringValue")
	cashValue.Name = "Cash"
	cashValue.Value = "0"
	cashValue.Parent = leaderstats
	leaderstats.Parent = player

	player.CharacterAdded:Connect(function(character)
		onCharacter(player, character)
	end)
	player:LoadCharacter()

	pushSync(player)
end

local function onLeave(player: Player)
	Plots.release(player) -- banks uncollected + writes brainrots into data, clears plot
	local data = Data.get(player)
	if data then
		Leaderboard.update(player, data.cash)
	end
	Data.save(player)
	Monetization.clear(player)
	Data.clear(player)
end

Players.PlayerAdded:Connect(onJoin)
Players.PlayerRemoving:Connect(onLeave)
for _, player in Players:GetPlayers() do
	task.spawn(onJoin, player)
end

-- Economy tick + periodic sync ----------------------------------------------
local Format = require(ReplicatedStorage.Shared.Format)
local syncAccumulator = 0
RunService.Heartbeat:Connect(function(dt)
	Plots.tick(dt)

	syncAccumulator += dt
	if syncAccumulator >= Config.SyncInterval then
		syncAccumulator -= Config.SyncInterval
		for _, player in Players:GetPlayers() do
			pushSync(player)
			local data = Data.get(player)
			if data then
				Leaderboard.update(player, data.cash)
				local ls = player:FindFirstChild("leaderstats")
				local cashValue = ls and ls:FindFirstChild("Cash")
				if cashValue then
					(cashValue :: StringValue).Value = Format.abbreviate(data.cash)
				end
			end
			local index = Plots.plotIndexOf(player)
			if index then
				Plots.updateSign(index)
			end
		end
	end
end)

-- Autosave -------------------------------------------------------------------
task.spawn(function()
	while true do
		task.wait(60)
		for _, player in Players:GetPlayers() do
			Plots.snapshotToData(player) -- keep cash + brainrots current, don't clear the base
			Data.save(player)
		end
	end
end)

game:BindToClose(function()
	for _, player in Players:GetPlayers() do
		task.spawn(function()
			Plots.snapshotToData(player)
			Data.save(player)
		end)
	end
	task.wait(3)
end)
