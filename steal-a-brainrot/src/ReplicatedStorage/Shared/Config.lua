-- ============================================================================
--  Steal a Brainrot — central configuration (shared by server + clients).
--
--  MONETIZATION: create the Game Passes / Developer Products in Roblox, then
--  paste their numeric IDs below. Any id left as 0 is simply ignored (no error).
-- ============================================================================
local Config = {}

Config.CurrencyName = "Cash"

-- Server pushes an authoritative snapshot this often (seconds). Between
-- snapshots the client predicts locally for smooth number-go-up.
Config.SyncInterval = 3

-- World -----------------------------------------------------------------------
-- Keep PlotCount >= your experience's Max Players (set that in Studio →
-- Game Settings → so everyone gets a base).
Config.PlotCount = 8
Config.SlotsPerPlot = 9 -- podiums per base

-- Economy ---------------------------------------------------------------------
Config.StartingCash = 100
-- Each brainrot you own makes your next roll pricier — which is exactly why
-- stealing (free brainrots) is the meta.
Config.BaseRollCost = 50
Config.RollCostGrowth = 1.18 -- ^ (number of brainrots you own)

-- Steal ------------------------------------------------------------------------
Config.StealHoldSeconds = 4 -- how long a thief must hold the prompt
Config.StealRange = 12

-- Perks -----------------------------------------------------------------------
Config.DefaultWalkSpeed = 16
Config.SpeedPassWalkSpeed = 26

-- ----------------------------------------------------------------------------
--  MONETIZATION — paste your real IDs here.
-- ----------------------------------------------------------------------------
Config.GamePasses = {
	DoubleCash = { id = 0, name = "2x Cash", desc = "Double all income" },
	AutoCollect = { id = 0, name = "Auto Collect", desc = "Bank income automatically" },
	BaseLock = { id = 0, name = "Base Lock", desc = "Nobody can steal from you" },
	Speed = { id = 0, name = "Super Speed", desc = "Run faster to steal & escape" },
	VIP = { id = 0, name = "VIP", desc = "+25% income & a golden glow" },
}
Config.GamePassOrder = { "DoubleCash", "AutoCollect", "BaseLock", "Speed", "VIP" }

-- Income multipliers granted by passes (used by the economy).
Config.Multipliers = {
	DoubleCash = 2,
	VIP = 1.25,
}

Config.Products = {
	Cash10k = { id = 0, name = "10,000 Cash", cash = 10000 },
	Cash100k = { id = 0, name = "100,000 Cash", cash = 100000 },
	Cash1m = { id = 0, name = "1,000,000 Cash", cash = 1000000 },
	LuckyRoll = { id = 0, name = "Lucky Roll", desc = "Guaranteed Legendary or better" },
}
Config.ProductOrder = { "Cash10k", "Cash100k", "Cash1m", "LuckyRoll" }

-- If a Lucky Roll is bought but the buyer's base is full, grant this much cash
-- instead so the purchase is never wasted.
Config.LuckyRollFullFallbackCash = 250000

return Config
