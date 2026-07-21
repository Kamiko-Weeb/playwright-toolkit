-- ============================================================================
--  Plots — the heart of the game. Owns plot state and every action that
--  touches it: assigning bases, placing/rolling brainrots, accruing income,
--  collecting, timed base locking, rebirthing, and STEALING between players.
-- ============================================================================
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Brainrots = require(ReplicatedStorage.Shared.Brainrots)
local Format = require(ReplicatedStorage.Shared.Format)
local Data = require(script.Parent.Data)
local Monetization = require(script.Parent.Monetization)

local Plots = {}

-- Physical descriptors from WorldBuilder, indexed by plot number.
local world: { any } = {}
-- Server-authoritative state per plot index.
-- state[i] = {
--   owner: Player?, uncollected: number,
--   slots: {[slot]=defId}, units: {[slot]=Model},
--   lockedUntil: number?, lockedApplied: boolean,
-- }
local state: { any } = {}
-- Quick reverse lookup.
local playerPlot: { [Player]: number } = {}

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

-- Locking -------------------------------------------------------------------
-- A base is locked while the Base Lock pass is owned (permanent) OR the timed
-- lock from the pad is still active.
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

-- Seconds of timed lock remaining (0 if none). Permanent lock returns math.huge.
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
local function makeUnit(def, podium: BasePart, locked: boolean): (Model, ProximityPrompt)
	local rarityColor = Brainrots.rarityColor(def.rarity)

	local model = Instance.new("Model")
	model.Name = def.id

	local body = Instance.new("Part")
	body.Name = "Body"
	body.Anchored = true
	body.CanCollide = false
	body.Size = Vector3.new(3, 4, 3)
	body.Position = Vector3.new(podium.Position.X, 4.5, podium.Position.Z)
	body.Color = rarityColor
	body.Material = Enum.Material.SmoothPlastic
	body.Parent = model
	model.PrimaryPart = body

	-- eyes: two small dark blocks, purely cosmetic
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
	glow.FillColor = rarityColor
	glow.FillTransparency = 0.6
	glow.OutlineColor = rarityColor
	glow.Adornee = model
	glow.Parent = model

	local tag = Instance.new("BillboardGui")
	tag.Size = UDim2.fromOffset(190, 56)
	tag.StudsOffsetWorldSpace = Vector3.new(0, 3.2, 0)
	tag.AlwaysOnTop = true
	tag.Parent = body

	local nameLabel = Instance.new("TextLabel")
	nameLabel.Size = UDim2.new(1, 0, 0.55, 0)
	nameLabel.BackgroundTransparency = 1
	nameLabel.Font = Enum.Font.GothamBold
	nameLabel.TextColor3 = rarityColor
	nameLabel.TextStrokeTransparency = 0.3
	nameLabel.TextScaled = true
	nameLabel.Text = def.name
	nameLabel.Parent = tag

	local incomeLabel = Instance.new("TextLabel")
	incomeLabel.Size = UDim2.new(1, 0, 0.45, 0)
	incomeLabel.Position = UDim2.new(0, 0, 0.55, 0)
	incomeLabel.BackgroundTransparency = 1
	incomeLabel.Font = Enum.Font.Gotham
	incomeLabel.TextColor3 = Color3.fromRGB(230, 235, 245)
	incomeLabel.TextStrokeTransparency = 0.4
	incomeLabel.TextScaled = true
	incomeLabel.Text = def.rarity .. "  •  $" .. def.income .. "/s"
	incomeLabel.Parent = tag

	-- Steal prompt. Disabled while the base is locked.
	local prompt = Instance.new("ProximityPrompt")
	prompt.ActionText = "Steal"
	prompt.ObjectText = def.name
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

-- Enable/disable every steal prompt on a plot to match its lock state.
local function applyLockToPrompts(index: number)
	local locked = Plots.isLocked(index)
	local s = state[index]
	for slot = 1, Config.SlotsPerPlot do
		local unit = s.units[slot]
		if unit then
			local body = unit:FindFirstChild("Body")
			local prompt = body and body:FindFirstChildOfClass("ProximityPrompt")
			if prompt then
				prompt.Enabled = not locked
			end
		end
	end
end

local function placeOnSlot(index: number, slot: number, defId: string)
	local s = state[index]
	local def = Brainrots.get(defId)
	if not def then
		return
	end
	local podium = world[index].podiums[slot]
	local model, prompt = makeUnit(def, podium, Plots.isLocked(index))
	s.slots[slot] = defId
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

function Plots.placeBrainrot(player: Player, defId: string): boolean
	local index = playerPlot[player]
	if not index then
		return false
	end
	local slot = firstFreeSlot(index)
	if not slot then
		return false
	end
	placeOnSlot(index, slot, defId)
	return true
end

-- Multipliers & income ------------------------------------------------------
function Plots.rebirthMultiplier(player: Player): number
	local data = Data.get(player)
	local rebirths = (data and data.rebirths) or 0
	return 1 + rebirths * Config.Rebirth.multiplierPerRebirth
end

-- Combined income multiplier: game passes (2x, VIP) * rebirth bonus.
function Plots.totalMultiplier(player: Player): number
	return Monetization.multiplier(player) * Plots.rebirthMultiplier(player)
end

function Plots.baseIncome(index: number): number
	local s = state[index]
	local total = 0
	for slot = 1, Config.SlotsPerPlot do
		local defId = s.slots[slot]
		if defId then
			local def = Brainrots.get(defId)
			if def then
				total += def.income
			end
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

-- Accrue income for every owned plot. Called each Heartbeat from Main.
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

-- Timed lock ----------------------------------------------------------------
function Plots.lockBase(player: Player)
	local index = playerPlot[player]
	if not index then
		return
	end
	local s = state[index]
	if Monetization.owns(player, "BaseLock") then
		notify(player, "Your base is already permanently locked!", Color3.fromRGB(90, 150, 255))
		return
	end
	s.lockedUntil = os.clock() + Config.LockDuration
	s.lockedApplied = true
	applyLockToPrompts(index)
	Plots.updateSign(index)
	notify(player, ("Base LOCKED for %ds!"):format(Config.LockDuration), Color3.fromRGB(90, 150, 255))
	syncPlayer(player)
end

-- Called ~once a second from Main: expire timed locks and refresh signs.
function Plots.updateLocks()
	for index, s in state do
		if s.owner then
			local locked = Plots.isLocked(index)
			if locked ~= s.lockedApplied then
				s.lockedApplied = locked
				applyLockToPrompts(index)
				if not locked then
					notify(s.owner, "Your base is UNLOCKED — re-lock it!", Color3.fromRGB(230, 90, 90))
				end
				syncPlayer(s.owner)
			end
			Plots.updateSign(index) -- keep the lock countdown live
		end
	end
end

-- Re-apply lock state after a Base Lock pass purchase.
function Plots.refreshLock(player: Player)
	local index = playerPlot[player]
	if not index then
		return
	end
	state[index].lockedApplied = Plots.isLocked(index)
	applyLockToPrompts(index)
	Plots.updateSign(index)
end

-- Rolling -------------------------------------------------------------------
function Plots.roll(player: Player): (boolean, any, string?)
	local index = playerPlot[player]
	if not index then
		return false, nil, "No base"
	end
	if not firstFreeSlot(index) then
		return false, nil, "Your base is full"
	end
	local data = Data.get(player)
	if not data then
		return false, nil, "No data"
	end
	local cost = Plots.rollCost(player)
	if data.cash < cost then
		return false, nil, "Not enough cash"
	end
	data.cash -= cost
	local def = Brainrots.roll(nil)
	Plots.placeBrainrot(player, def.id)
	return true, def, nil
end

function Plots.luckyRoll(player: Player): boolean
	local index = playerPlot[player]
	if not index or not firstFreeSlot(index) then
		local data = Data.get(player)
		if data then
			data.cash += Config.LuckyRollFullFallbackCash
		end
		notify(player, "Base full — got $" .. Config.LuckyRollFullFallbackCash .. " instead!", Color3.fromRGB(255, 205, 70))
		return true
	end
	local def = Brainrots.roll(Brainrots.HighRarities)
	Plots.placeBrainrot(player, def.id)
	notify(player, "LUCKY ROLL: " .. def.name .. " (" .. def.rarity .. ")!", Brainrots.rarityColor(def.rarity))
	return true
end

-- Rebirth -------------------------------------------------------------------
function Plots.rebirthCost(player: Player): number
	local data = Data.get(player)
	local rebirths = (data and data.rebirths) or 0
	return math.floor(Config.Rebirth.baseCost * Config.Rebirth.costGrowth ^ rebirths)
end

function Plots.canRebirth(player: Player): boolean
	local data = Data.get(player)
	return data ~= nil and data.cash >= Plots.rebirthCost(player)
end

-- Resets cash + brainrots for a permanent income multiplier. Returns the new
-- rebirth count on success, or nil.
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
	data.brainrots = {}

	local s = state[index]
	s.uncollected = 0
	for slot = 1, Config.SlotsPerPlot do
		removeFromSlot(index, slot)
	end
	Plots.updateSign(index)
	return data.rebirths
end

-- Stealing ------------------------------------------------------------------
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
		notify(thief, victim.Name .. "'s base is LOCKED!", Color3.fromRGB(230, 90, 90))
		return
	end
	local defId = vs.slots[slot]
	if not defId then
		return
	end

	local thiefIndex = playerPlot[thief]
	if not thiefIndex then
		return
	end
	local freeSlot = firstFreeSlot(thiefIndex)
	if not freeSlot then
		notify(thief, "Your base is full — collect or rebirth first!", Color3.fromRGB(230, 90, 90))
		return
	end

	local def = Brainrots.get(defId)
	removeFromSlot(victimIndex, slot)
	placeOnSlot(thiefIndex, freeSlot, defId)

	local color = def and Brainrots.rarityColor(def.rarity) or nil
	local name = def and def.name or "a brainrot"
	notify(thief, "You stole " .. name .. " from " .. victim.Name .. "!", color)
	notify(victim, thief.Name .. " stole your " .. name .. "!", Color3.fromRGB(230, 90, 90))

	Plots.updateSign(victimIndex)
	Plots.updateSign(thiefIndex)
	syncPlayer(thief)
	syncPlayer(victim)
end

-- Signs ---------------------------------------------------------------------
function Plots.updateSign(index: number)
	local w = world[index]
	local s = state[index]
	if s.owner then
		local rebirths = Plots.rebirthMultiplier(s.owner)
		local data = Data.get(s.owner)
		local rebirthCount = (data and data.rebirths) or 0
		w.ownerLabel.Text = s.owner.Name .. "'s Base" .. (rebirthCount > 0 and (" ⭐" .. rebirthCount) or "")

		local income = Plots.baseIncome(index) * Plots.totalMultiplier(s.owner)
		local lockText, padText
		if Monetization.owns(s.owner, "BaseLock") then
			lockText, padText = "🔒 LOCKED (Pass)", "LOCKED (Pass)"
		elseif Plots.isLocked(index) then
			local remaining = Plots.lockRemaining(index)
			lockText, padText = ("🔒 LOCKED %ds"):format(remaining), ("LOCKED %ds"):format(remaining)
		else
			lockText, padText = "🔓 UNLOCKED", "LOCK BASE"
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
		w.ownerLabel.Text = "Empty Base"
		w.statsLabel.Text = ""
		if w.lockPadLabel then
			w.lockPadLabel.Text = "LOCK BASE"
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
			if data and data.brainrots then
				for _, defId in data.brainrots do
					if firstFreeSlot(index) then
						Plots.placeBrainrot(player, defId)
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
	local ids = {}
	for slot = 1, Config.SlotsPerPlot do
		if s.slots[slot] then
			table.insert(ids, s.slots[slot])
		end
	end
	data.brainrots = ids
end

function Plots.release(player: Player)
	local index = playerPlot[player]
	if not index then
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
		-- Collect pad: bank your income.
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

		-- Lock pad: (re)lock your base for Config.LockDuration seconds.
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
