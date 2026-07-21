-- ============================================================================
--  Coin Clicker Simulator — central configuration
--  Shared by both the server and every client.
--
--  MONETIZATION: after you create the Game Passes / Developer Products in
--  Roblox (see roblox-game/README.md), paste the numeric IDs into the
--  GamePasses and Products tables below. Leaving an id as 0 simply disables
--  that item — the game will not error.
-- ============================================================================

local Config = {}

Config.CurrencyName = "Coins"
Config.BaseClickValue = 1

-- How often (seconds) the server pushes an authoritative snapshot to each
-- client. Between snapshots the client predicts locally for a smooth feel.
Config.SyncInterval = 4

-- Anti-spam: maximum manual collects the server accepts per second, per player.
Config.MaxClicksPerSecond = 25

-- ----------------------------------------------------------------------------
--  Upgrades   ->   cost(level) = floor(baseCost * costGrowth ^ level)
-- ----------------------------------------------------------------------------
Config.Upgrades = {
	ClickPower = {
		name = "Click Power",
		description = "+1 coin per click, each level",
		baseCost = 25,
		costGrowth = 1.6,
		maxLevel = 500,
		perLevel = 1,
	},
	AutoIncome = {
		name = "Auto Income",
		description = "+2 coins / sec, each level",
		baseCost = 100,
		costGrowth = 1.75,
		maxLevel = 500,
		perLevel = 2,
	},
}
-- Display order in the shop UI.
Config.UpgradeOrder = { "ClickPower", "AutoIncome" }

-- ----------------------------------------------------------------------------
--  Rebirth (prestige): reset coins + upgrades for a permanent earnings boost.
-- ----------------------------------------------------------------------------
Config.Rebirth = {
	baseCost = 1000, -- coins needed for the first rebirth
	costGrowth = 3, -- cost multiplies each rebirth
	multiplierPerRebirth = 0.5, -- +50% earnings for every rebirth owned
}

-- The Auto Collector pass grants this many "free clicks" per second.
Config.AutoCollectClicksPerSecond = 5

-- ----------------------------------------------------------------------------
--  MONETIZATION — paste your real IDs here after creating them in Roblox.
-- ----------------------------------------------------------------------------
Config.GamePasses = {
	DoubleCoins = { id = 0, name = "2x Coins", multiplier = 2 },
	VIP = { id = 0, name = "VIP (+25%)", multiplier = 1.25 },
	AutoCollect = { id = 0, name = "Auto Collector" },
}
Config.GamePassOrder = { "DoubleCoins", "VIP", "AutoCollect" }

Config.Products = {
	Coins1k = { id = 0, name = "1,000 Coins", coins = 1000 },
	Coins10k = { id = 0, name = "10,000 Coins", coins = 10000 },
	Coins100k = { id = 0, name = "100,000 Coins", coins = 100000 },
}
Config.ProductOrder = { "Coins1k", "Coins10k", "Coins100k" }

return Config
