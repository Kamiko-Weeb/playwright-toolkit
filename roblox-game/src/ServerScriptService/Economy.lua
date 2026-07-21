-- ============================================================================
--  Economy — all earning / upgrade / rebirth math. Pure logic that operates
--  on a player's data table. Server-authoritative.
-- ============================================================================
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Config = require(ReplicatedStorage.Shared.Config)

local Economy = {}

-- Injected by Main so Economy can factor in Game Pass ownership.
local ownsPass: (Player, string) -> boolean = function()
	return false
end
function Economy.setPassChecker(fn: (Player, string) -> boolean)
	ownsPass = fn
end

local function passMultiplier(player: Player): number
	local mult = 1
	if ownsPass(player, "DoubleCoins") then
		mult *= Config.GamePasses.DoubleCoins.multiplier
	end
	if ownsPass(player, "VIP") then
		mult *= Config.GamePasses.VIP.multiplier
	end
	return mult
end

function Economy.rebirthMultiplier(data): number
	return 1 + data.rebirths * Config.Rebirth.multiplierPerRebirth
end

function Economy.perClick(player: Player, data): number
	local base = Config.BaseClickValue + data.upgrades.ClickPower * Config.Upgrades.ClickPower.perLevel
	return math.floor(base * Economy.rebirthMultiplier(data) * passMultiplier(player))
end

function Economy.perSecond(player: Player, data): number
	local auto = data.upgrades.AutoIncome * Config.Upgrades.AutoIncome.perLevel
	local total = auto * Economy.rebirthMultiplier(data) * passMultiplier(player)
	if ownsPass(player, "AutoCollect") then
		total += Economy.perClick(player, data) * Config.AutoCollectClicksPerSecond
	end
	return total
end

function Economy.upgradeCost(upgradeKey: string, level: number): number
	local u = Config.Upgrades[upgradeKey]
	return math.floor(u.baseCost * u.costGrowth ^ level)
end

function Economy.rebirthCost(data): number
	return math.floor(Config.Rebirth.baseCost * Config.Rebirth.costGrowth ^ data.rebirths)
end

function Economy.canRebirth(data): boolean
	return data.coins >= Economy.rebirthCost(data)
end

-- Actions --------------------------------------------------------------------

function Economy.click(player: Player, data)
	data.coins += Economy.perClick(player, data)
end

function Economy.buyUpgrade(player: Player, data, upgradeKey: string): boolean
	local u = Config.Upgrades[upgradeKey]
	if not u then
		return false
	end
	local level = data.upgrades[upgradeKey]
	if level >= u.maxLevel then
		return false
	end
	local cost = Economy.upgradeCost(upgradeKey, level)
	if data.coins < cost then
		return false
	end
	data.coins -= cost
	data.upgrades[upgradeKey] += 1
	return true
end

function Economy.rebirth(player: Player, data): boolean
	if not Economy.canRebirth(data) then
		return false
	end
	data.rebirths += 1
	data.coins = 0
	data.upgrades.ClickPower = 0
	data.upgrades.AutoIncome = 0
	return true
end

return Economy
