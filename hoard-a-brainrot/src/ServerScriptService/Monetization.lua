-- ============================================================================
--  Monetization — Game Pass ownership + Developer Product receipts.
--  Kept generic: Main injects what actually happens on a purchase.
-- ============================================================================
local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Config = require(ReplicatedStorage.Shared.Config)

local Monetization = {}

local passOwnership: { [Player]: { [string]: boolean } } = {}

-- Injected by Main.
local getData: (Player) -> any = function()
	return nil
end
local saveData: (Player) -> boolean = function()
	return false
end
-- onProduct(player, productKey, data) -> boolean granted
local onProduct: (Player, string, any) -> boolean = function()
	return false
end

function Monetization.wire(getDataFn, saveFn, onProductFn)
	getData = getDataFn
	saveData = saveFn
	onProduct = onProductFn
end

function Monetization.owns(player: Player, passKey: string): boolean
	local t = passOwnership[player]
	return t ~= nil and t[passKey] == true
end

-- Income multiplier from owned passes (2x Cash, VIP, ...).
function Monetization.multiplier(player: Player): number
	local mult = 1
	for key, factor in Config.Multipliers do
		if Monetization.owns(player, key) then
			mult *= factor
		end
	end
	return mult
end

local function checkPass(player: Player, passKey: string)
	local pass = Config.GamePasses[passKey]
	if not pass or pass.id == 0 then
		return
	end
	local ok, owns = pcall(function()
		return MarketplaceService:UserOwnsGamePassAsync(player.UserId, pass.id)
	end)
	if ok then
		passOwnership[player][passKey] = owns
	end
end

function Monetization.loadPasses(player: Player)
	passOwnership[player] = {}
	for _, passKey in Config.GamePassOrder do
		checkPass(player, passKey)
	end
end

function Monetization.clear(player: Player)
	passOwnership[player] = nil
end

function Monetization.markOwned(player: Player, gamePassId: number): string?
	for passKey, pass in Config.GamePasses do
		if pass.id == gamePassId and passOwnership[player] then
			passOwnership[player][passKey] = true
			return passKey
		end
	end
	return nil
end

local function productKeyFromId(productId: number): string?
	for key, product in Config.Products do
		if product.id == productId then
			return key
		end
	end
	return nil
end

function Monetization.setupReceipts()
	MarketplaceService.ProcessReceipt = function(receiptInfo)
		local player = Players:GetPlayerByUserId(receiptInfo.PlayerId)
		if not player then
			return Enum.ProductPurchaseDecision.NotProcessedYet
		end

		local key = productKeyFromId(receiptInfo.ProductId)
		if not key then
			return Enum.ProductPurchaseDecision.NotProcessedYet
		end

		local data = getData(player)
		if not data then
			return Enum.ProductPurchaseDecision.NotProcessedYet
		end

		data.purchaseHistory = data.purchaseHistory or {}
		if data.purchaseHistory[receiptInfo.PurchaseId] then
			return Enum.ProductPurchaseDecision.PurchaseGranted
		end

		-- Let Main apply the effect. It must not fail after this point except
		-- for persistence, which we handle below.
		local granted = onProduct(player, key, data)
		if not granted then
			return Enum.ProductPurchaseDecision.NotProcessedYet
		end

		data.purchaseHistory[receiptInfo.PurchaseId] = true

		-- Persist before confirming so a crash can't erase the purchase.
		if not saveData(player) then
			data.purchaseHistory[receiptInfo.PurchaseId] = nil
			return Enum.ProductPurchaseDecision.NotProcessedYet
		end

		return Enum.ProductPurchaseDecision.PurchaseGranted
	end
end

-- Fires when a player finishes a Game Pass prompt in-experience.
function Monetization.setupPassListener(onPassPurchased: (Player, string) -> ())
	MarketplaceService.PromptGamePassPurchaseFinished:Connect(function(player, gamePassId, purchased)
		if purchased then
			local passKey = Monetization.markOwned(player, gamePassId)
			if passKey then
				onPassPurchased(player, passKey)
			end
		end
	end)
end

return Monetization
