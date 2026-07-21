-- ============================================================================
--  Stashlings — central configuration (shared by server + clients).
--
--  MONETIZATION: create the Game Passes / Developer Products in Roblox, then
--  paste their numeric IDs below. Any id left as 0 is simply ignored (no error).
-- ============================================================================
local Config = {}

Config.CurrencyName = "Loot"

-- Server pushes an authoritative snapshot this often (seconds). Between
-- snapshots the client predicts locally for smooth number-go-up.
Config.SyncInterval = 3

-- World -----------------------------------------------------------------------
-- Keep PlotCount >= your experience's Max Players (Studio → Game Settings) so
-- everyone gets a Vault.
Config.PlotCount = 8
Config.SlotsPerPlot = 9 -- pedestals per Vault

-- Economy ---------------------------------------------------------------------
Config.StartingCash = 100
-- Every Stashling you own makes your next roll pricier — which is exactly why
-- SNATCHING (free Stashlings) is the smart play.
Config.BaseRollCost = 50
Config.RollCostGrowth = 1.18 -- ^ (number of Stashlings you own)

-- Selling ---------------------------------------------------------------------
-- Sell value of a Stashling = its income/sec * this. Lets you clear junk for Loot.
Config.SellMultiplier = 15

-- Fusion ----------------------------------------------------------------------
-- Merge this many identical Stashlings into one GOLDEN Stashling that earns
-- `multiplier` times as much (and glows). Duplicates become valuable.
Config.Fusion = {
	count = 3,
	multiplier = 5,
}

-- Snatch Streak ---------------------------------------------------------------
-- Each successful snatch stacks a temporary income bonus; getting BONKED (taking
-- damage) resets it to zero. Rewards aggression, punishes sloppiness.
Config.Streak = {
	duration = 20, -- seconds a streak lasts / refreshes to
	bonusPerSnatch = 0.1, -- +10% income per stack
	max = 10, -- stack cap
}

-- Snatch (steal) --------------------------------------------------------------
Config.StealHoldSeconds = 4 -- how long a raider must hold the prompt
Config.StealRange = 12

-- Timed Vault lock ------------------------------------------------------------
-- Stepping on your LOCK pad locks your Vault for this many seconds; then it
-- expires and you must return and step on it again. (The Vault Lock GAME PASS
-- makes the lock permanent — no timer, no pad needed.)
Config.LockDuration = 60

-- Ascension (prestige) --------------------------------------------------------
-- Reset your Loot + Stashlings for a permanent income multiplier.
Config.Rebirth = {
	baseCost = 100000, -- banked Loot needed for your first ascension
	costGrowth = 5, -- cost multiplies each ascension
	multiplierPerRebirth = 0.5, -- +50% income per tier, forever
}

-- Combat ----------------------------------------------------------------------
-- Everyone spawns with a mallet. Bonking a raider knocks them back (cancelling
-- their snatch) and wipes their Snatch Streak.
Config.Combat = {
	damage = 30,
	range = 9,
	cooldown = 0.6, -- seconds between swings
	knockback = 55,
}

-- Perks -----------------------------------------------------------------------
Config.DefaultWalkSpeed = 16
Config.SpeedPassWalkSpeed = 26

-- ----------------------------------------------------------------------------
--  MONETIZATION — paste your real IDs here. (Keys are internal; only `name`/
--  `desc` are shown to players, so renaming display text is safe.)
-- ----------------------------------------------------------------------------
Config.GamePasses = {
	DoubleCash = { id = 0, name = "2x Loot", desc = "Double all income" },
	AutoCollect = { id = 0, name = "Auto Collect", desc = "Bank income automatically" },
	BaseLock = { id = 0, name = "Vault Lock", desc = "Nobody can snatch from you" },
	Speed = { id = 0, name = "Zoomies", desc = "Run faster to raid & escape" },
	VIP = { id = 0, name = "VIP", desc = "+25% income & a golden glow" },
}
Config.GamePassOrder = { "DoubleCash", "AutoCollect", "BaseLock", "Speed", "VIP" }

-- Income multipliers granted by passes (used by the economy).
Config.Multipliers = {
	DoubleCash = 2,
	VIP = 1.25,
}

Config.Products = {
	Cash10k = { id = 0, name = "10,000 Loot", cash = 10000 },
	Cash100k = { id = 0, name = "100,000 Loot", cash = 100000 },
	Cash1m = { id = 0, name = "1,000,000 Loot", cash = 1000000 },
	LuckyRoll = { id = 0, name = "Lucky Roll", desc = "Guaranteed Legendary or better" },
}
Config.ProductOrder = { "Cash10k", "Cash100k", "Cash1m", "LuckyRoll" }

-- If a Lucky Roll is bought but the buyer's Vault is full, grant this much Loot
-- instead so the purchase is never wasted.
Config.LuckyRollFullFallbackCash = 250000

return Config
