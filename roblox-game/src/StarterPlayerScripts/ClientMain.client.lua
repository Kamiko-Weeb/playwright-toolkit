-- ============================================================================
--  ClientMain — builds the whole UI in code and runs the client game loop.
--  No image assets required, so it works the moment you press Play.
-- ============================================================================
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local MarketplaceService = game:GetService("MarketplaceService")
local TweenService = game:GetService("TweenService")

local Config = require(ReplicatedStorage.Shared.Config)
local Format = require(ReplicatedStorage.Shared.Format)

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local Remotes = ReplicatedStorage:WaitForChild("Remotes")
local SyncEvent = Remotes:WaitForChild("Sync") :: RemoteEvent
local CollectEvent = Remotes:WaitForChild("Collect") :: RemoteEvent
local BuyEvent = Remotes:WaitForChild("Buy") :: RemoteEvent
local RebirthEvent = Remotes:WaitForChild("Rebirth") :: RemoteEvent
local ReadyEvent = Remotes:WaitForChild("Ready") :: RemoteEvent
local LeaderboardFn = Remotes:WaitForChild("GetLeaderboard") :: RemoteFunction

-- ----------------------------------------------------------------------------
--  Style helpers
-- ----------------------------------------------------------------------------
local COLORS = {
	bg = Color3.fromRGB(28, 30, 40),
	panel = Color3.fromRGB(38, 41, 56),
	row = Color3.fromRGB(48, 52, 70),
	accent = Color3.fromRGB(90, 160, 255),
	gold = Color3.fromRGB(255, 205, 70),
	green = Color3.fromRGB(80, 200, 120),
	red = Color3.fromRGB(230, 90, 90),
	robux = Color3.fromRGB(0, 176, 111),
	text = Color3.fromRGB(240, 242, 250),
	subtext = Color3.fromRGB(170, 176, 195),
}

local function create(className: string, props: { [string]: any }, children: { Instance }?): any
	local inst = Instance.new(className)
	for k, v in props do
		if k ~= "Parent" then
			(inst :: any)[k] = v
		end
	end
	if children then
		for _, child in children do
			child.Parent = inst
		end
	end
	if props.Parent then
		inst.Parent = props.Parent
	end
	return inst
end

local function corner(radius: number): UICorner
	return create("UICorner", { CornerRadius = UDim.new(0, radius) })
end

local function padding(px: number): UIPadding
	return create("UIPadding", {
		PaddingTop = UDim.new(0, px),
		PaddingBottom = UDim.new(0, px),
		PaddingLeft = UDim.new(0, px),
		PaddingRight = UDim.new(0, px),
	})
end

-- ----------------------------------------------------------------------------
--  Root GUI
-- ----------------------------------------------------------------------------
local gui = create("ScreenGui", {
	Name = "CoinClickerUI",
	ResetOnSpawn = false,
	ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
	IgnoreGuiInset = true,
	Parent = playerGui,
})

-- Top bar --------------------------------------------------------------------
local topBar = create("Frame", {
	Name = "TopBar",
	Size = UDim2.new(0, 340, 0, 84),
	Position = UDim2.new(0.5, 0, 0, 12),
	AnchorPoint = Vector2.new(0.5, 0),
	BackgroundColor3 = COLORS.panel,
	BackgroundTransparency = 0.05,
	Parent = gui,
}, { corner(16) })

local coinLabel = create("TextLabel", {
	Name = "Coins",
	Size = UDim2.new(1, -20, 0, 44),
	Position = UDim2.new(0, 10, 0, 6),
	BackgroundTransparency = 1,
	Font = Enum.Font.GothamBold,
	TextColor3 = COLORS.gold,
	TextScaled = true,
	Text = "0 Coins",
	Parent = topBar,
})

local rateLabel = create("TextLabel", {
	Name = "Rates",
	Size = UDim2.new(1, -20, 0, 24),
	Position = UDim2.new(0, 10, 0, 52),
	BackgroundTransparency = 1,
	Font = Enum.Font.Gotham,
	TextColor3 = COLORS.subtext,
	TextScaled = true,
	Text = "+1 / click   •   +0 / sec",
	Parent = topBar,
})

-- Collect button -------------------------------------------------------------
local collectButton = create("TextButton", {
	Name = "Collect",
	Size = UDim2.new(0, 240, 0, 240),
	Position = UDim2.new(0.5, 0, 1, -60),
	AnchorPoint = Vector2.new(0.5, 1),
	BackgroundColor3 = COLORS.gold,
	AutoButtonColor = false,
	Font = Enum.Font.GothamBlack,
	TextColor3 = Color3.fromRGB(60, 45, 0),
	TextScaled = true,
	Text = "COLLECT",
	Parent = gui,
}, { create("UICorner", { CornerRadius = UDim.new(1, 0) }), create("UIStroke", {
	Thickness = 4,
	Color = Color3.fromRGB(255, 230, 150),
}) })

-- Side buttons (open panels) -------------------------------------------------
local function sideButton(text: string, order: number, color: Color3): TextButton
	return create("TextButton", {
		Name = text,
		Size = UDim2.new(0, 120, 0, 52),
		Position = UDim2.new(0, 16, 0.5, (order - 2) * 62),
		AnchorPoint = Vector2.new(0, 0.5),
		BackgroundColor3 = color,
		Font = Enum.Font.GothamBold,
		TextColor3 = COLORS.text,
		TextScaled = true,
		Text = text,
		Parent = gui,
	}, { corner(12), padding(10) })
end

local shopSideBtn = sideButton("Shop", 1, COLORS.accent)
local storeSideBtn = sideButton("Store", 2, COLORS.robux)
local topSideBtn = sideButton("Top 10", 3, COLORS.panel)

-- ----------------------------------------------------------------------------
--  Generic sliding panel
-- ----------------------------------------------------------------------------
local openPanel: Frame? = nil

local function makePanel(titleText: string): (Frame, ScrollingFrame)
	local panel = create("Frame", {
		Name = titleText .. "Panel",
		Size = UDim2.new(0, 420, 0, 460),
		Position = UDim2.new(0.5, 0, 0.5, 0),
		AnchorPoint = Vector2.new(0.5, 0.5),
		BackgroundColor3 = COLORS.bg,
		Visible = false,
		Parent = gui,
	}, { corner(18), create("UIStroke", { Thickness = 2, Color = COLORS.panel }) })

	create("TextLabel", {
		Size = UDim2.new(1, -70, 0, 48),
		Position = UDim2.new(0, 18, 0, 10),
		BackgroundTransparency = 1,
		Font = Enum.Font.GothamBold,
		TextColor3 = COLORS.text,
		TextScaled = true,
		TextXAlignment = Enum.TextXAlignment.Left,
		Text = titleText,
		Parent = panel,
	})

	local closeBtn = create("TextButton", {
		Size = UDim2.new(0, 40, 0, 40),
		Position = UDim2.new(1, -50, 0, 12),
		BackgroundColor3 = COLORS.red,
		Font = Enum.Font.GothamBold,
		TextColor3 = COLORS.text,
		TextScaled = true,
		Text = "X",
		Parent = panel,
	}, { corner(10) })
	closeBtn.Activated:Connect(function()
		panel.Visible = false
		openPanel = nil
	end)

	local scroll = create("ScrollingFrame", {
		Size = UDim2.new(1, -24, 1, -76),
		Position = UDim2.new(0, 12, 0, 66),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ScrollBarThickness = 6,
		CanvasSize = UDim2.new(0, 0, 0, 0),
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		Parent = panel,
	}, {
		create("UIListLayout", {
			Padding = UDim.new(0, 10),
			SortOrder = Enum.SortOrder.LayoutOrder,
		}),
	})

	return panel, scroll
end

local function togglePanel(panel: Frame)
	if openPanel and openPanel ~= panel then
		openPanel.Visible = false
	end
	panel.Visible = not panel.Visible
	openPanel = panel.Visible and panel or nil
end

-- ----------------------------------------------------------------------------
--  Shop panel (upgrades + rebirth)
-- ----------------------------------------------------------------------------
local shopPanel, shopScroll = makePanel("Shop")
shopSideBtn.Activated:Connect(function()
	togglePanel(shopPanel)
end)

-- Rebirth row
local rebirthRow = create("Frame", {
	Size = UDim2.new(1, 0, 0, 92),
	BackgroundColor3 = Color3.fromRGB(70, 55, 90),
	LayoutOrder = 0,
	Parent = shopScroll,
}, { corner(12), padding(10) })

local rebirthInfo = create("TextLabel", {
	Size = UDim2.new(1, -120, 1, 0),
	BackgroundTransparency = 1,
	Font = Enum.Font.Gotham,
	TextColor3 = COLORS.text,
	TextScaled = true,
	TextXAlignment = Enum.TextXAlignment.Left,
	TextYAlignment = Enum.TextYAlignment.Top,
	Text = "Rebirth",
	Parent = rebirthRow,
})

local rebirthBtn = create("TextButton", {
	Size = UDim2.new(0, 100, 0, 60),
	Position = UDim2.new(1, -100, 0.5, 0),
	AnchorPoint = Vector2.new(0, 0.5),
	BackgroundColor3 = COLORS.red,
	Font = Enum.Font.GothamBold,
	TextColor3 = COLORS.text,
	TextScaled = true,
	Text = "Rebirth",
	Parent = rebirthRow,
}, { corner(10), padding(6) })
rebirthBtn.Activated:Connect(function()
	RebirthEvent:FireServer()
end)

-- Upgrade rows
type UpgradeRow = { info: TextLabel, button: TextButton }
local upgradeRows: { [string]: UpgradeRow } = {}

for i, key in Config.UpgradeOrder do
	local cfg = Config.Upgrades[key]

	local row = create("Frame", {
		Size = UDim2.new(1, 0, 0, 84),
		BackgroundColor3 = COLORS.row,
		LayoutOrder = i,
		Parent = shopScroll,
	}, { corner(12), padding(10) })

	local info = create("TextLabel", {
		Size = UDim2.new(1, -120, 1, 0),
		BackgroundTransparency = 1,
		Font = Enum.Font.Gotham,
		TextColor3 = COLORS.text,
		TextScaled = true,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextYAlignment = Enum.TextYAlignment.Top,
		Text = cfg.name .. "\n" .. cfg.description,
		Parent = row,
	})

	local button = create("TextButton", {
		Size = UDim2.new(0, 100, 0, 56),
		Position = UDim2.new(1, -100, 0.5, 0),
		AnchorPoint = Vector2.new(0, 0.5),
		BackgroundColor3 = COLORS.green,
		Font = Enum.Font.GothamBold,
		TextColor3 = COLORS.text,
		TextScaled = true,
		Text = "Buy",
		Parent = row,
	}, { corner(10), padding(6) })

	button.Activated:Connect(function()
		BuyEvent:FireServer(key)
	end)

	upgradeRows[key] = { info = info, button = button }
end

-- ----------------------------------------------------------------------------
--  Store panel (Robux: game passes + coin products)
-- ----------------------------------------------------------------------------
local storePanel, storeScroll = makePanel("Store")
storeSideBtn.Activated:Connect(function()
	togglePanel(storePanel)
end)

type PassRow = { button: TextButton }
local passRows: { [string]: PassRow } = {}

local function storeRow(order: number, title: string, subtitle: string, buttonText: string, onClick: () -> ()): TextButton
	local row = create("Frame", {
		Size = UDim2.new(1, 0, 0, 84),
		BackgroundColor3 = COLORS.row,
		LayoutOrder = order,
		Parent = storeScroll,
	}, { corner(12), padding(10) })

	create("TextLabel", {
		Size = UDim2.new(1, -120, 1, 0),
		BackgroundTransparency = 1,
		Font = Enum.Font.Gotham,
		TextColor3 = COLORS.text,
		TextScaled = true,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextYAlignment = Enum.TextYAlignment.Top,
		Text = title .. "\n" .. subtitle,
		Parent = row,
	})

	local button = create("TextButton", {
		Size = UDim2.new(0, 100, 0, 56),
		Position = UDim2.new(1, -100, 0.5, 0),
		AnchorPoint = Vector2.new(0, 0.5),
		BackgroundColor3 = COLORS.robux,
		Font = Enum.Font.GothamBold,
		TextColor3 = COLORS.text,
		TextScaled = true,
		Text = buttonText,
		Parent = row,
	}, { corner(10), padding(6) })
	button.Activated:Connect(onClick)
	return button
end

local storeOrder = 0
for _, key in Config.GamePassOrder do
	storeOrder += 1
	local pass = Config.GamePasses[key]
	local subtitle = "Game Pass — permanent perk"
	local btn = storeRow(storeOrder, pass.name, subtitle, "Buy", function()
		if pass.id ~= 0 then
			MarketplaceService:PromptGamePassPurchase(player, pass.id)
		else
			warn(("[Store] Game Pass '%s' has no id set in Config."):format(key))
		end
	end)
	passRows[key] = { button = btn }
end

for _, key in Config.ProductOrder do
	storeOrder += 1
	local product = Config.Products[key]
	storeRow(storeOrder, product.name, "Instant coins", "Buy", function()
		if product.id ~= 0 then
			MarketplaceService:PromptProductPurchase(player, product.id)
		else
			warn(("[Store] Product '%s' has no id set in Config."):format(key))
		end
	end)
end

-- ----------------------------------------------------------------------------
--  Top 10 panel
-- ----------------------------------------------------------------------------
local topPanel, topScroll = makePanel("Top 10")
topSideBtn.Activated:Connect(function()
	togglePanel(topPanel)
	if topPanel.Visible then
		for _, child in topScroll:GetChildren() do
			if child:IsA("Frame") then
				child:Destroy()
			end
		end
		task.spawn(function()
			local ok, list = pcall(function()
				return LeaderboardFn:InvokeServer()
			end)
			if not ok or not list then
				return
			end
			for rank, entry in list do
				create("Frame", {
					Size = UDim2.new(1, 0, 0, 48),
					BackgroundColor3 = COLORS.row,
					LayoutOrder = rank,
					Parent = topScroll,
				}, {
					corner(10),
					padding(8),
					create("TextLabel", {
						Size = UDim2.new(1, 0, 1, 0),
						BackgroundTransparency = 1,
						Font = Enum.Font.GothamMedium,
						TextColor3 = COLORS.text,
						TextScaled = true,
						TextXAlignment = Enum.TextXAlignment.Left,
						Text = ("#%d  %s  —  %s"):format(rank, entry.name, Format.abbreviate(entry.coins)),
					}),
				})
			end
		end)
	end
end)

-- ----------------------------------------------------------------------------
--  Sync + client-side prediction
-- ----------------------------------------------------------------------------
local snapshot: any = nil
local displayCoins = 0

local function refresh()
	if not snapshot then
		return
	end
	displayCoins = snapshot.coins
	rateLabel.Text = ("+%s / click   •   +%s / sec"):format(
		Format.abbreviate(snapshot.perClick),
		Format.abbreviate(snapshot.perSecond)
	)

	-- Rebirth row
	rebirthInfo.Text = ("Rebirth  (x%.2f earnings)\nCost: %s coins  →  next x%.2f"):format(
		snapshot.rebirthMultiplier,
		Format.abbreviate(snapshot.rebirthCost),
		snapshot.rebirthMultiplier + Config.Rebirth.multiplierPerRebirth
	)
	rebirthBtn.BackgroundColor3 = snapshot.canRebirth and COLORS.gold or COLORS.row
	rebirthBtn.TextColor3 = snapshot.canRebirth and Color3.fromRGB(60, 45, 0) or COLORS.subtext

	-- Upgrade rows
	for key, row in upgradeRows do
		local u = snapshot.upgrades[key]
		local cfg = Config.Upgrades[key]
		row.info.Text = ("%s  (Lv %d)\n%s"):format(cfg.name, u.level, cfg.description)
		if u.maxed then
			row.button.Text = "MAX"
			row.button.BackgroundColor3 = COLORS.row
		else
			row.button.Text = Format.abbreviate(u.cost)
			local affordable = snapshot.coins >= u.cost
			row.button.BackgroundColor3 = affordable and COLORS.green or COLORS.row
		end
	end

	-- Store: mark owned passes
	for key, row in passRows do
		if snapshot.passes[key] then
			row.button.Text = "Owned"
			row.button.BackgroundColor3 = COLORS.row
		else
			row.button.Text = "Buy"
			row.button.BackgroundColor3 = COLORS.robux
		end
	end
end

SyncEvent.OnClientEvent:Connect(function(snap)
	snapshot = snap
	refresh()
end)

-- Collect: optimistic local add + fire to server (which is authoritative).
local basePop = collectButton.Size
collectButton.Activated:Connect(function()
	if snapshot then
		displayCoins += snapshot.perClick
	end
	CollectEvent:FireServer()

	collectButton.Size = basePop - UDim2.fromOffset(16, 16)
	TweenService:Create(collectButton, TweenInfo.new(0.12, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {
		Size = basePop,
	}):Play()
end)

-- Smoothly tick up displayed coins from passive income between syncs.
RunService.RenderStepped:Connect(function(dt)
	if snapshot then
		displayCoins += snapshot.perSecond * dt
	end
	coinLabel.Text = Format.abbreviate(displayCoins) .. " " .. Config.CurrencyName
end)

-- Ask the server for our first snapshot now that everything is connected.
ReadyEvent:FireServer()
