-- ============================================================================
--  Monetization — Game Pass ownership + Developer Product receipt handling.
--  This is the code that turns purchases into in-game value (and Robux for you).
-- ============================================================================
local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Config = require(ReplicatedStorage.Shared.Config)

local Monetization = {}

-- passOwnership[player][passKey] = boolean
local passOwnership: { [Player]: { [string]: boolean } } = {}

-- Wired by Main.
local getData: (Player) -> any = function()
	return nil
end
local onCoinsGranted: (Player) -> () = function() end
local saveData: (Player) -> boolean = function()
	return false
end

function Monetization.wire(getDataFn, onCoinsGrantedFn, saveFn)
	getData = getDataFn
	onCoinsGranted = onCoinsGrantedFn
	saveData = saveFn
end

function Monetization.owns(player: Player, passKey: string): boolean
	local t = passOwnership[player]
	return t ~= nil and t[passKey] == true
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

-- Flip a pass to "owned" immediately after an in-experience purchase.
function Monetization.markOwned(player: Player, gamePassId: number)
	for passKey, pass in Config.GamePasses do
		if pass.id == gamePassId and passOwnership[player] then
			passOwnership[player][passKey] = true
		end
	end
end

local function productKeyFromId(productId: number): string?
	for key, product in Config.Products do
		if product.id == productId then
			return key
		end
	end
	return nil
end

-- Developer Products: grant coins, idempotently, and persist before we tell
-- Roblox the purchase was granted.
function Monetization.setupReceipts()
	MarketplaceService.ProcessReceipt = function(receiptInfo)
		local player = Players:GetPlayerByUserId(receiptInfo.PlayerId)
		if not player then
			return Enum.ProductPurchaseDecision.NotProcessedYet
		end

		local key = productKeyFromId(receiptInfo.ProductId)
		if not key then
			-- Unknown product id (maybe not configured yet); don't consume it.
			return Enum.ProductPurchaseDecision.NotProcessedYet
		end

		local data = getData(player)
		if not data then
			return Enum.ProductPurchaseDecision.NotProcessedYet
		end

		data.purchaseHistory = data.purchaseHistory or {}
		if data.purchaseHistory[receiptInfo.PurchaseId] then
			-- Already granted in a previous call — safe to confirm.
			return Enum.ProductPurchaseDecision.PurchaseGranted
		end

		local amount = Config.Products[key].coins
		data.coins += amount
		data.purchaseHistory[receiptInfo.PurchaseId] = true

		-- Persist NOW so the grant survives a crash. If the save fails, roll
		-- back and ask Roblox to retry later rather than lose the purchase.
		if not saveData(player) then
			data.coins -= amount
			data.purchaseHistory[receiptInfo.PurchaseId] = nil
			return Enum.ProductPurchaseDecision.NotProcessedYet
		end

		onCoinsGranted(player)
		return Enum.ProductPurchaseDecision.PurchaseGranted
	end
end

function Monetization.setupPassListener(onOwnershipChanged: (Player) -> ())
	MarketplaceService.PromptGamePassPurchaseFinished:Connect(function(player, gamePassId, purchased)
		if purchased then
			Monetization.markOwned(player, gamePassId)
			onOwnershipChanged(player)
		end
	end)
end

return Monetization
