-- ============================================================================
--  Stashlings — the collectible critters, their rarities, and roll logic.
--
--  Original placeholder critters (simple colored blocks with a name tag) so
--  you can ship today. Swap in real models later by editing WorldBuilder/Plots
--  — just keep the `id`, `rarity`, and `income`.
-- ============================================================================
local Stashlings = {}

local rng = Random.new()

-- Rarity table. `weight` drives roll odds (higher = more common). `color`
-- tints the unit + its glow.
Stashlings.Rarities = {
	Common = { color = Color3.fromRGB(180, 184, 196), weight = 55 },
	Rare = { color = Color3.fromRGB(80, 140, 255), weight = 25 },
	Epic = { color = Color3.fromRGB(170, 90, 255), weight = 12 },
	Legendary = { color = Color3.fromRGB(255, 175, 40), weight = 5 },
	Mythic = { color = Color3.fromRGB(255, 70, 120), weight = 2.5 },
	Secret = { color = Color3.fromRGB(40, 255, 200), weight = 0.5 },
}
Stashlings.RarityOrder = { "Common", "Rare", "Epic", "Legendary", "Mythic", "Secret" }

-- income = cash/sec this unit generates while on a base.
Stashlings.List = {
	{ id = "gloopy_goose", name = "Gloopy Goose", rarity = "Common", income = 5 },
	{ id = "turbo_toad", name = "Turbo Toad", rarity = "Common", income = 8 },
	{ id = "sussy_snail", name = "Sussy Snail", rarity = "Common", income = 12 },
	{ id = "rizzly_bear", name = "Rizzly Bear", rarity = "Rare", income = 30 },
	{ id = "mega_muffin", name = "Mega Muffin", rarity = "Rare", income = 45 },
	{ id = "cosmic_corn", name = "Cosmic Corn", rarity = "Epic", income = 140 },
	{ id = "diamond_duck", name = "Diamond Duck", rarity = "Epic", income = 200 },
	{ id = "galaxy_gorilla", name = "Galaxy Gorilla", rarity = "Legendary", income = 750 },
	{ id = "void_viper", name = "Void Viper", rarity = "Legendary", income = 1000 },
	{ id = "omega_onion", name = "Omega Onion", rarity = "Mythic", income = 3500 },
	{ id = "plasma_penguin", name = "Plasma Penguin", rarity = "Mythic", income = 5000 },
	{ id = "secret_sasquatch", name = "Secret Sasquatch", rarity = "Secret", income = 22000 },
	{ id = "ancient_avocado", name = "Ancient Avocado", rarity = "Secret", income = 30000 },
}

-- Lookups --------------------------------------------------------------------
local byId = {}
local byRarity = {}
for _, def in Stashlings.List do
	byId[def.id] = def
	byRarity[def.rarity] = byRarity[def.rarity] or {}
	table.insert(byRarity[def.rarity], def)
end
Stashlings.byId = byId

function Stashlings.get(id: string)
	return byId[id]
end

function Stashlings.rarityColor(rarity: string): Color3
	local r = Stashlings.Rarities[rarity]
	return r and r.color or Color3.fromRGB(200, 200, 200)
end

-- Pick a rarity by weight. `allowed` (optional) is a set like {Legendary=true}
-- to restrict the pool (used by the Lucky Roll product).
local function rollRarity(allowed: { [string]: boolean }?): string
	local total = 0
	for _, r in Stashlings.RarityOrder do
		if not allowed or allowed[r] then
			total += Stashlings.Rarities[r].weight
		end
	end
	local pick = rng:NextNumber() * total
	for _, r in Stashlings.RarityOrder do
		if not allowed or allowed[r] then
			pick -= Stashlings.Rarities[r].weight
			if pick <= 0 then
				return r
			end
		end
	end
	return "Common"
end

-- Returns a random Stashling def. Pass an `allowed` set to restrict rarities.
function Stashlings.roll(allowed: { [string]: boolean }?)
	local rarity = rollRarity(allowed)
	local pool = byRarity[rarity]
	return pool[rng:NextInteger(1, #pool)]
end

-- Rarities counted as "Legendary or better" for the Lucky Roll product.
Stashlings.HighRarities = { Legendary = true, Mythic = true, Secret = true }

return Stashlings
