-- ============================================================================
--  Plots (Vaults) — the heart of the game. Owns vault state and every action
--  that touches it: assigning vaults, rolling/placing/selling/fusing Stashlings,
--  accruing Loot, timed locking, ascending, snatch streaks, and SNATCHING.
--
--  A pedestal slot holds an entry: { id = string, golden = boolean }.
-- ============================================================================
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Stashlings = require(ReplicatedStorage.Shared.Stashlings)
local Format = require(ReplicatedStorage.Shared.Format)
local Data = require(script.Parent.Data)
local Monetization = require(script.Parent.Monetization)

local Plots = {}

local world: { any } = {}
local state: { any } = {}
local playerPlot: { [Player]: number } = {}
-- Snatch streaks: streak[player] = { count: number, expire: number }
local streak: { [Player]: { count: number, expire: number } } = {}

-- Injected by Main.
local notify: (Player, string, Color3?) -> () = function() end
local syncPlayer: (Player) -> () = function() end
function Plots.wire(notifyFn, syncFn)
	notify = notifyFn
	syncPlayer = syncFn
end

function Plots.plotIndexOf(player: Player): number?
	return playerPlot[player]
end

-- The Loot/sec a single pedestal entry produces (before player multipliers).
local function slotIncome(entry): number
	local def = Stashlings.get(entry.id)
	if not def then
		return 0
	end
	return def.income * (entry.golden and Config.Fusion.multiplier or 1)
end

-- Locking -------------------------------------------------------------------
function Plots.isLocked(index: number): boolean
	local s = state[index]
	if not s or not s.owner then
		return false
	end
	if Monetization.owns(s.owner, "BaseLock") then
		return true
	end
	return s.lockedUntil ~= nil and os.clock() < s.lockedUntil
end

function Plots.lockRemaining(index: number): number
	local s = state[index]
	if not s or not s.owner then
		return 0
	end
	if Monetization.owns(s.owner, "BaseLock") then
		return math.huge
	end
	if s.lockedUntil and os.clock() < s.lockedUntil then
		return math.ceil(s.lockedUntil - os.clock())
	end
	return 0
end

-- Unit visuals --------------------------------------------------------------
local GOLD = Color3.fromRGB(255, 215, 60)

local function makeUnit(def, podium: BasePart, locked: boolean, golden: boolean): (Model, ProximityPrompt)
	local baseColor = Stashlings.rarityColor(def.rarity)
	local bodyColor = golden and GOLD or baseColor

	local model = Instance.new("Model")
	model.Name = def.id

	local body = Instance.new("Part")
	body.Name = "Body"
	body.Anchored = true
	body.CanCollide = false
	body.Size = Vector3.new(3, 4, 3)
	body.Position = Vector3.new(podium.Position.X, 4.5, podium.Position.Z)
	body.Color = bodyColor
	body.Material = golden and Enum.Material.Foil or Enum.Material.SmoothPlastic
	body.Parent = model
	model.PrimaryPart = body

	for _, side in { -0.7, 0.7 } do
		local eye = Instance.new("Part")
		eye.Anchored = true
		eye.CanCollide = false
		eye.Size = Vector3.new(0.5, 0.5, 0.3)
		eye.Color = Color3.fromRGB(20, 20, 20)
		eye.CFrame = body.CFrame * CFrame.new(side, 0.6, -1.5)
		eye.Parent = model
	end

	local glow = Instance.new("Highlight")
	glow.FillColor = bodyColor
	glow.FillTransparency = golden and 0.35 or 0.6
	glow.OutlineColor = bodyColor
	glow.Adornee = model
	glow.Parent = model

	local tag = Instance.new("BillboardGui")
	tag.Size = UDim2.fromOffset(200, 56)
	tag.StudsOffsetWorldSpace = Vector3.new(0, 3.2, 0)
	tag.AlwaysOnTop = true
	tag.Parent = body

	local nameLabel = Instance.new("TextLabel")
	nameLabel.Size = UDim2.new(1, 0, 0.55, 0)
	nameLabel.BackgroundTransparency = 1
	nameLabel.Font = Enum.Font.GothamBold
	nameLabel.TextColor3 = golden and GOLD or baseColor
	nameLabel.TextStrokeTransparency = 0.3
	nameLabel.TextScaled = true
	nameLabel.Text = (golden and "✨ Golden " or "") .. def.name
	nameLabel.Parent = tag

	local incomeLabel = Instance.new("TextLabel")
	incomeLabel.Size = UDim2.new(1, 0, 0.45, 0)
	incomeLabel.Position = UDim2.new(0, 0, 0.55, 0)
	incomeLabel.BackgroundTransparency = 1
	incomeLabel.Font = Enum.Font.Gotham
	incomeLabel.TextColor3 = Color3.fromRGB(230, 235, 245)
	incomeLabel.TextScaled = true
	incomeLabel.TextStrokeTransparency = 0.4
	local shown = def.income * (golden and Config.Fusion.multiplier or 1)
	incomeLabel.Text = def.rarity .. "  •  $" .. Format.abbreviate(shown) .. "/s"
	incomeLabel.Parent = tag

	local prompt = Instance.new("ProximityPrompt")
	prompt.ActionText = "Snatch"
	prompt.ObjectText = nameLabel.Text
	prompt.HoldDuration = Config.StealHoldSeconds
	prompt.MaxActivationDistance = Config.StealRange
	prompt.RequiresLineOfSight = false
	prompt.Enabled = not locked
	prompt.Parent = body

	model.Parent = podium
	return model, prompt
end

-- Slot helpers --------------------------------------------------------------
local function firstFreeSlot(index: number): number?
	local s = state[index]
	for slot = 1, Config.SlotsPerPlot do
		if not s.slots[slot] then
			return slot
		end
	end
	return nil
end

local function countFilled(index: number): number
	local s = state[index]
	local n = 0
	for slot = 1, Config.SlotsPerPlot do
		if s.slots[slot] then
			n += 1
		end
	end
	return n
end

local function applyLockToPrompts(index: number)
	local locked = Plots.isLocked(index)
	local s = state[index]
	for slot = 1, Config.SlotsPerPlot do
		local unit = s.units[slot]
		if unit then
			local bodyPart = unit:FindFirstChild("Body")
			local prompt = bodyPart and bodyPart:FindFirstChildOfClass("ProximityPrompt")
			if prompt then
				prompt.Enabled = not locked
			end
		end
	end
end

local function placeOnSlot(index: number, slot: number, id: string, golden: boolean)
	local s = state[index]
	local def = Stashlings.get(id)
	if not def then
		return
	end
	local podium = world[index].podiums[slot]
	local model, prompt = makeUnit(def, podium, Plots.isLocked(index), golden)
	s.slots[slot] = { id = id, golden = golden }
	s.units[slot] = model

	prompt.Triggered:Connect(function(triggerPlayer)
		Plots.handleSteal(triggerPlayer, index, slot)
	end)
end

local function removeFromSlot(index: number, slot: number)
	local s = state[index]
	if s.units[slot] then
		s.units[slot]:Destroy()
	end
	s.units[slot] = nil
	s.slots[slot] = nil
end

function Plots.placeCreature(player: Player, id: string, golden: boolean?): boolean
	local index = playerPlot[player]
	if not index then
		return false
	end
	local slot = firstFreeSlot(index)
	if not slot then
		return false
	end
	placeOnSlot(index, slot, id, golden or false)
	return true
end

-- Snatch streak -------------------------------------------------------------
function Plots.registerSnatch(player: Player)
	local now = os.clock()
	local st = streak[player]
	if not st or now > st.expire then
		st = { count = 0, expire = 0 }
	end
	st.count = math.min(st.count + 1, Config.Streak.max)
	st.expire = now + Config.Streak.duration
	streak[player] = st
end

function Plots.streakCount(player: Player): number
	local st = streak[player]
	if not st or os.clock() > st.expire then
		return 0
	end
	return st.count
end

function Plots.streakRemaining(player: Player): number
	local st = streak[player]
	if not st or os.clock() > st.expire then
		return 0
	end
	return math.ceil(st.expire - os.clock())
end

function Plots.streakMultiplier(player: Player): number
	return 1 + Plots.streakCount(player) * Config.Streak.bonusPerSnatch
end

-- Returns true if an active streak was actually broken (for a notification).
function Plots.resetStreak(player: Player): boolean
	local had = Plots.streakCount(player) > 0
	streak[player] = nil
	return had
end

-- Multipliers & income ------------------------------------------------------
function Plots.rebirthMultiplier(player: Player): number
	local data = Data.get(player)
	local rebirths = (data and data.rebirths) or 0
	return 1 + rebirths * Config.Rebirth.multiplierPerRebirth
end

function Plots.totalMultiplier(player: Player): number
	return Monetization.multiplier(player) * Plots.rebirthMultiplier(player) * Plots.streakMultiplier(player)
end

function Plots.baseIncome(index: number): number
	local s = state[index]
	local total = 0
	for slot = 1, Config.SlotsPerPlot do
		local entry = s.slots[slot]
		if entry then
			total += slotIncome(entry)
		end
	end
	return total
end

function Plots.incomePerSecond(player: Player): number
	local index = playerPlot[player]
	if not index then
		return 0
	end
	return Plots.baseIncome(index) * Plots.totalMultiplier(player)
end

function Plots.slotsInfo(player: Player): (number, number)
	local index = playerPlot[player]
	if not index then
		return 0, Config.SlotsPerPlot
	end
	return countFilled(index), Config.SlotsPerPlot
end

function Plots.rollCost(player: Player): number
	local index = playerPlot[player]
	local filled = index and countFilled(index) or 0
	return math.floor(Config.BaseRollCost * Config.RollCostGrowth ^ filled)
end

-- A snapshot of the player's Stashlings for the client's Vault panel.
function Plots.creaturesList(player: Player)
	local index = playerPlot[player]
	if not index then
		return {}
	end
	local s = state[index]
	local list = {}
	for slot = 1, Config.SlotsPerPlot do
		local entry = s.slots[slot]
		if entry then
			local def = Stashlings.get(entry.id)
			if def then
				table.insert(list, {
					slot = slot,
					id = entry.id,
					name = def.name,
					rarity = def.rarity,
					golden = entry.golden or false,
					income = slotIncome(entry),
				})
			end
		end
	end
	return list
end

function Plots.tick(dt: number)
	for index, s in state do
		if s.owner then
			local gain = Plots.baseIncome(index) * Plots.totalMultiplier(s.owner) * dt
			if gain > 0 then
				if Monetization.owns(s.owner, "AutoCollect") then
					local data = Data.get(s.owner)
					if data then
						data.cash += gain
					end
				else
					s.uncollected += gain
				end
			end
		end
	end
end

function Plots.collect(player: Player): number
	local index = playerPlot[player]
	if not index then
		return 0
	end
	local s = state[index]
	local amount = s.uncollected
	if amount <= 0 then
		return 0
	end
	s.uncollected = 0
	local data = Data.get(player)
	if data then
		data.cash += amount
	end
	return amount
end

-- Selling -------------------------------------------------------------------
function Plots.sell(player: Player, slot: number): number
	local index = playerPlot[player]
	if not index then
		return 0
	end
	local s = state[index]
	local entry = s.slots[slot]
	if not entry then
		return 0
	end
	local value = math.floor(slotIncome(entry) * Config.SellMultiplier)
	removeFromSlot(index, slot)
	local data = Data.get(player)
	if data then
		data.cash += value
	end
	Plots.updateSign(index)
	return value
end

function Plots.sellCommons(player: Player): number
	local index = playerPlot[player]
	if not index then
		return 0
	end
	local s = state[index]
	local total = 0
	for slot = 1, Config.SlotsPerPlot do
		local entry = s.slots[slot]
		if entry and not entry.golden then
			local def = Stashlings.get(entry.id)
			if def and def.rarity == "Common" then
				total += math.floor(slotIncome(entry) * Config.SellMultiplier)
				removeFromSlot(index, slot)
			end
		end
	end
	if total > 0 then
		local data = Data.get(player)
		if data then
			data.cash += total
		end
	end
	Plots.updateSign(index)
	return total
end

-- Fusion --------------------------------------------------------------------
-- Merge Config.Fusion.count identical (non-golden) Stashlings into one Golden.
function Plots.fuse(player: Player, id: string): (boolean, any)
	local index = playerPlot[player]
	if not index then
		return false, nil
	end
	local s = state[index]
	local matching = {}
	for slot = 1, Config.SlotsPerPlot do
		local entry = s.slots[slot]
		if entry and entry.id == id and not entry.golden then
			table.insert(matching, slot)
		end
	end
	if #matching < Config.Fusion.count then
		return false, nil
	end
	for i = 1, Config.Fusion.count do
		removeFromSlot(index, matching[i])
	end
	local free = firstFreeSlot(index)
	if free then
		placeOnSlot(index, free, id, true)
	end
	Plots.updateSign(index)
	return true, Stashlings.get(id)
end

-- Rolling -------------------------------------------------------------------
function Plots.roll(player: Player): (boolean, any, string?)
	local index = playerPlot[player]
	if not index then
		return false, nil, "No vault"
	end
	if not firstFreeSlot(index) then
		return false, nil, "Your vault is full"
	end
	local data = Data.get(player)
	if not data then
		return false, nil, "No data"
	end
	local cost = Plots.rollCost(player)
	if data.cash < cost then
		return false, nil, "Not enough Loot"
	end
	data.cash -= cost
	local def = Stashlings.roll(nil)
	Plots.placeCreature(player, def.id, false)
	return true, def, nil
end

-- Lucky Roll product: guaranteed Legendary+. Returns the def, or nil on fallback.
function Plots.luckyRoll(player: Player)
	local index = playerPlot[player]
	if not index or not firstFreeSlot(index) then
		local data = Data.get(player)
		if data then
			data.cash += Config.LuckyRollFullFallbackCash
		end
		notify(player, "Vault full — got $" .. Config.LuckyRollFullFallbackCash .. " instead!", GOLD)
		return nil
	end
	local def = Stashlings.roll(Stashlings.HighRarities)
	Plots.placeCreature(player, def.id, false)
	return def
end

-- Ascension (rebirth) -------------------------------------------------------
function Plots.rebirthCost(player: Player): number
	local data = Data.get(player)
	local rebirths = (data and data.rebirths) or 0
	return math.floor(Config.Rebirth.baseCost * Config.Rebirth.costGrowth ^ rebirths)
end

function Plots.canRebirth(player: Player): boolean
	local data = Data.get(player)
	return data ~= nil and data.cash >= Plots.rebirthCost(player)
end

function Plots.rebirth(player: Player): number?
	local index = playerPlot[player]
	local data = Data.get(player)
	if not index or not data then
		return nil
	end
	if data.cash < Plots.rebirthCost(player) then
		return nil
	end

	data.rebirths = (data.rebirths or 0) + 1
	data.cash = Config.StartingCash
	data.creatures = {}

	local s = state[index]
	s.uncollected = 0
	for slot = 1, Config.SlotsPerPlot do
		removeFromSlot(index, slot)
	end
	Plots.updateSign(index)
	return data.rebirths
end

-- Snatching (steal) ---------------------------------------------------------
function Plots.handleSteal(thief: Player, victimIndex: number, slot: number)
	local vs = state[victimIndex]
	if not vs or not vs.owner then
		return
	end
	local victim = vs.owner
	if victim == thief then
		return
	end
	if Plots.isLocked(victimIndex) then
		notify(thief, victim.Name .. "'s vault is LOCKED!", Color3.fromRGB(230, 90, 90))
		return
	end
	local entry = vs.slots[slot]
	if not entry then
		return
	end

	local thiefIndex = playerPlot[thief]
	if not thiefIndex then
		return
	end
	local freeSlot = firstFreeSlot(thiefIndex)
	if not freeSlot then
		notify(thief, "Your vault is full — sell, fuse or ascend first!", Color3.fromRGB(230, 90, 90))
		return
	end

	local def = Stashlings.get(entry.id)
	local golden = entry.golden or false
	removeFromSlot(victimIndex, slot)
	placeOnSlot(thiefIndex, freeSlot, entry.id, golden)

	Plots.registerSnatch(thief)

	local name = ((golden and "✨ Golden " or "") .. (def and def.name or "a Stashling"))
	local color = def and Stashlings.rarityColor(def.rarity) or nil
	local streakN = Plots.streakCount(thief)
	local thiefMsg = "You snatched " .. name .. " from " .. victim.Name .. "!"
	if streakN > 1 then
		thiefMsg = thiefMsg .. "  🔥x" .. streakN
	end
	notify(thief, thiefMsg, color)
	notify(victim, thief.Name .. " snatched your " .. name .. "!", Color3.fromRGB(230, 90, 90))

	Plots.updateSign(victimIndex)
	Plots.updateSign(thiefIndex)
	syncPlayer(thief)
	syncPlayer(victim)
end

-- Timed lock ----------------------------------------------------------------
function Plots.lockBase(player: Player)
	local index = playerPlot[player]
	if not index then
		return
	end
	if Monetization.owns(player, "BaseLock") then
		notify(player, "Your vault is already permanently locked!", Color3.fromRGB(90, 150, 255))
		return
	end
	local s = state[index]
	s.lockedUntil = os.clock() + Config.LockDuration
	s.lockedApplied = true
	applyLockToPrompts(index)
	Plots.updateSign(index)
	notify(player, ("Vault LOCKED for %ds!"):format(Config.LockDuration), Color3.fromRGB(90, 150, 255))
	syncPlayer(player)
end

function Plots.updateLocks()
	for index, s in state do
		if s.owner then
			local locked = Plots.isLocked(index)
			if locked ~= s.lockedApplied then
				s.lockedApplied = locked
				applyLockToPrompts(index)
				if not locked then
					notify(s.owner, "Your vault is UNLOCKED — re-lock it!", Color3.fromRGB(230, 90, 90))
				end
				syncPlayer(s.owner)
			end
			Plots.updateSign(index)
		end
	end
end

function Plots.refreshLock(player: Player)
	local index = playerPlot[player]
	if not index then
		return
	end
	state[index].lockedApplied = Plots.isLocked(index)
	applyLockToPrompts(index)
	Plots.updateSign(index)
end

-- Signs ---------------------------------------------------------------------
function Plots.updateSign(index: number)
	local w = world[index]
	local s = state[index]
	if s.owner then
		local data = Data.get(s.owner)
		local tier = (data and data.rebirths) or 0
		w.ownerLabel.Text = s.owner.Name .. "'s Vault" .. (tier > 0 and (" ⭐" .. tier) or "")

		local income = Plots.baseIncome(index) * Plots.totalMultiplier(s.owner)
		local lockText, padText
		if Monetization.owns(s.owner, "BaseLock") then
			lockText, padText = "🔒 LOCKED (Pass)", "LOCKED (Pass)"
		elseif Plots.isLocked(index) then
			local remaining = Plots.lockRemaining(index)
			lockText, padText = ("🔒 LOCKED %ds"):format(remaining), ("LOCKED %ds"):format(remaining)
		else
			lockText, padText = "🔓 UNLOCKED", "LOCK VAULT"
		end
		w.statsLabel.Text = ("$%s/s  •  Bank: $%s\n%s"):format(
			Format.abbreviate(income),
			Format.abbreviate(s.uncollected),
			lockText
		)
		if w.lockPadLabel then
			w.lockPadLabel.Text = padText
		end
	else
		w.ownerLabel.Text = "Empty Vault"
		w.statsLabel.Text = ""
		if w.lockPadLabel then
			w.lockPadLabel.Text = "LOCK VAULT"
		end
	end
end

-- Assignment ----------------------------------------------------------------
function Plots.assign(player: Player): number?
	for index = 1, Config.PlotCount do
		if not state[index].owner then
			state[index].owner = player
			playerPlot[player] = index
			state[index].lockedUntil = nil
			state[index].lockedApplied = Plots.isLocked(index)

			local data = Data.get(player)
			if data and data.creatures then
				for _, entry in data.creatures do
					-- tolerate the legacy string format
					local id = type(entry) == "table" and entry.id or entry
					local golden = type(entry) == "table" and entry.golden or false
					if id and Stashlings.get(id) and firstFreeSlot(index) then
						Plots.placeCreature(player, id, golden)
					end
				end
			end

			Plots.updateSign(index)
			return index
		end
	end
	return nil
end

function Plots.snapshotToData(player: Player)
	local index = playerPlot[player]
	if not index then
		return
	end
	local s = state[index]
	local data = Data.get(player)
	if not data then
		return
	end
	data.cash += s.uncollected
	s.uncollected = 0
	local entries = {}
	for slot = 1, Config.SlotsPerPlot do
		local entry = s.slots[slot]
		if entry then
			table.insert(entries, { id = entry.id, golden = entry.golden or false })
		end
	end
	data.creatures = entries
end

function Plots.release(player: Player)
	local index = playerPlot[player]
	if not index then
		streak[player] = nil
		return
	end
	Plots.snapshotToData(player)
	for slot = 1, Config.SlotsPerPlot do
		removeFromSlot(index, slot)
	end
	state[index].owner = nil
	state[index].lockedUntil = nil
	state[index].lockedApplied = false
	playerPlot[player] = nil
	streak[player] = nil
	Plots.updateSign(index)
end

function Plots.spawnCFrame(player: Player): CFrame?
	local index = playerPlot[player]
	return index and world[index].spawnCFrame or nil
end

-- Init ----------------------------------------------------------------------
function Plots.init(worldPlots: { any })
	world = worldPlots
	for i = 1, Config.PlotCount do
		state[i] = { owner = nil, uncollected = 0, slots = {}, units = {}, lockedUntil = nil, lockedApplied = false }
	end

	local collectDebounce: { [number]: number } = {}
	local lockDebounce: { [number]: number } = {}

	for i = 1, Config.PlotCount do
		world[i].collectPad.Touched:Connect(function(hit)
			local plr = hit.Parent and Players:GetPlayerFromCharacter(hit.Parent)
			if not plr or playerPlot[plr] ~= i then
				return
			end
			local now = os.clock()
			if collectDebounce[i] and now - collectDebounce[i] < 0.5 then
				return
			end
			collectDebounce[i] = now
			if Plots.collect(plr) > 0 then
				Plots.updateSign(i)
				syncPlayer(plr)
			end
		end)

		world[i].lockPad.Touched:Connect(function(hit)
			local plr = hit.Parent and Players:GetPlayerFromCharacter(hit.Parent)
			if not plr or playerPlot[plr] ~= i then
				return
			end
			local now = os.clock()
			if lockDebounce[i] and now - lockDebounce[i] < 1 then
				return
			end
			lockDebounce[i] = now
			Plots.lockBase(plr)
		end)
	end
end

return Plots
