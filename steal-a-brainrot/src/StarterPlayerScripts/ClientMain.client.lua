-- ============================================================================
--  ClientMain — builds the whole UI in code (no assets) and runs the client
--  loop: predicts cash between syncs, rolls, collects, opens the store, and
--  shows toast notifications (rolls, steals, purchases).
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
local RollEvent = Remotes:WaitForChild("Roll") :: RemoteEvent
local CollectEvent = Remotes:WaitForChild("Collect") :: RemoteEvent
local NotifyEvent = Remotes:WaitForChild("Notify") :: RemoteEvent
local ReadyEvent = Remotes:WaitForChild("Ready") :: RemoteEvent
local LeaderboardFn = Remotes:WaitForChild("GetLeaderboard") :: RemoteFunction

-- Style ----------------------------------------------------------------------
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

local function corner(r: number)
	return create("UICorner", { CornerRadius = UDim.new(0, r) })
end
local function pad(px: number)
	return create("UIPadding", {
		PaddingTop = UDim.new(0, px),
		PaddingBottom = UDim.new(0, px),
		PaddingLeft = UDim.new(0, px),
		PaddingRight = UDim.new(0, px),
	})
end

local gui = create("ScreenGui", {
	Name = "StealBrainrotUI",
	ResetOnSpawn = false,
	ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
	IgnoreGuiInset = true,
	Parent = playerGui,
})

-- Top bar --------------------------------------------------------------------
local topBar = create("Frame", {
	Size = UDim2.new(0, 340, 0, 80),
	Position = UDim2.new(0.5, 0, 0, 12),
	AnchorPoint = Vector2.new(0.5, 0),
	BackgroundColor3 = COLORS.panel,
	BackgroundTransparency = 0.05,
	Parent = gui,
}, { corner(16) })

local cashLabel = create("TextLabel", {
	Size = UDim2.new(1, -20, 0, 44),
	Position = UDim2.new(0, 10, 0, 6),
	BackgroundTransparency = 1,
	Font = Enum.Font.GothamBold,
	TextColor3 = COLORS.gold,
	TextScaled = true,
	Text = "0 Cash",
	Parent = topBar,
})

local incomeLabel = create("TextLabel", {
	Size = UDim2.new(1, -20, 0, 22),
	Position = UDim2.new(0, 10, 0, 50),
	BackgroundTransparency = 1,
	Font = Enum.Font.Gotham,
	TextColor3 = COLORS.green,
	TextScaled = true,
	Text = "+0 / sec",
	Parent = topBar,
})

-- Roll + Collect buttons -----------------------------------------------------
local rollButton = create("TextButton", {
	Size = UDim2.new(0, 260, 0, 90),
	Position = UDim2.new(0.5, 0, 1, -30),
	AnchorPoint = Vector2.new(0.5, 1),
	BackgroundColor3 = COLORS.accent,
	AutoButtonColor = true,
	Font = Enum.Font.GothamBlack,
	TextColor3 = COLORS.text,
	TextScaled = true,
	Text = "ROLL",
	Parent = gui,
}, { corner(16), pad(10), create("UIStroke", { Thickness = 3, Color = Color3.fromRGB(150, 195, 255) }) })

local collectButton = create("TextButton", {
	Size = UDim2.new(0, 150, 0, 64),
	Position = UDim2.new(0.5, -160, 1, -43),
	AnchorPoint = Vector2.new(0.5, 1),
	BackgroundColor3 = COLORS.green,
	Font = Enum.Font.GothamBold,
	TextColor3 = COLORS.text,
	TextScaled = true,
	Text = "COLLECT",
	Parent = gui,
}, { corner(14), pad(8) })

-- Side buttons ---------------------------------------------------------------
local function sideButton(text: string, order: number, color: Color3): TextButton
	return create("TextButton", {
		Size = UDim2.new(0, 120, 0, 52),
		Position = UDim2.new(0, 16, 0.5, (order - 1) * 62),
		AnchorPoint = Vector2.new(0, 0.5),
		BackgroundColor3 = color,
		Font = Enum.Font.GothamBold,
		TextColor3 = COLORS.text,
		TextScaled = true,
		Text = text,
		Parent = gui,
	}, { corner(12), pad(10) })
end
local storeSideBtn = sideButton("Store", 1, COLORS.robux)
local topSideBtn = sideButton("Top 10", 2, COLORS.panel)

-- Panels ---------------------------------------------------------------------
local openPanel: Frame? = nil
local function makePanel(title: string): (Frame, ScrollingFrame)
	local panel = create("Frame", {
		Size = UDim2.new(0, 440, 0, 480),
		Position = UDim2.new(0.5, 0, 0.5, 0),
		AnchorPoint = Vector2.new(0.5, 0.5),
		BackgroundColor3 = COLORS.bg,
		Visible = false,
		Parent = gui,
	}, { corner(18), create("UIStroke", { Thickness = 2, Color = COLORS.panel }) })

	create("TextLabel", {
		Size = UDim2.new(1, -70, 0, 46),
		Position = UDim2.new(0, 18, 0, 12),
		BackgroundTransparency = 1,
		Font = Enum.Font.GothamBold,
		TextColor3 = COLORS.text,
		TextScaled = true,
		TextXAlignment = Enum.TextXAlignment.Left,
		Text = title,
		Parent = panel,
	})
	local closeBtn = create("TextButton", {
		Size = UDim2.new(0, 40, 0, 40),
		Position = UDim2.new(1, -50, 0, 14),
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
	}, { create("UIListLayout", { Padding = UDim.new(0, 10), SortOrder = Enum.SortOrder.LayoutOrder }) })

	return panel, scroll
end

local function togglePanel(panel: Frame)
	if openPanel and openPanel ~= panel then
		openPanel.Visible = false
	end
	panel.Visible = not panel.Visible
	openPanel = panel.Visible and panel or nil
end

-- Store ----------------------------------------------------------------------
local storePanel, storeScroll = makePanel("Store")
storeSideBtn.Activated:Connect(function()
	togglePanel(storePanel)
end)

local passButtons: { [string]: TextButton } = {}

local function storeRow(order: number, title: string, subtitle: string, onClick: () -> ()): TextButton
	local row = create("Frame", {
		Size = UDim2.new(1, 0, 0, 78),
		BackgroundColor3 = COLORS.row,
		LayoutOrder = order,
		Parent = storeScroll,
	}, { corner(12), pad(10) })
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
		Size = UDim2.new(0, 100, 0, 54),
		Position = UDim2.new(1, -100, 0.5, 0),
		AnchorPoint = Vector2.new(0, 0.5),
		BackgroundColor3 = COLORS.robux,
		Font = Enum.Font.GothamBold,
		TextColor3 = COLORS.text,
		TextScaled = true,
		Text = "Buy",
		Parent = row,
	}, { corner(10), pad(6) })
	button.Activated:Connect(onClick)
	return button
end

local storeOrder = 0
for _, key in Config.GamePassOrder do
	storeOrder += 1
	local passInfo = Config.GamePasses[key]
	local btn = storeRow(storeOrder, passInfo.name, passInfo.desc, function()
		if passInfo.id ~= 0 then
			MarketplaceService:PromptGamePassPurchase(player, passInfo.id)
		else
			warn(("[Store] Game Pass '%s' has no id set."):format(key))
		end
	end)
	passButtons[key] = btn
end
for _, key in Config.ProductOrder do
	storeOrder += 1
	local productInfo = Config.Products[key]
	local subtitle = productInfo.desc or "Instant cash"
	storeRow(storeOrder, productInfo.name, subtitle, function()
		if productInfo.id ~= 0 then
			MarketplaceService:PromptProductPurchase(player, productInfo.id)
		else
			warn(("[Store] Product '%s' has no id set."):format(key))
		end
	end)
end

-- Top 10 ---------------------------------------------------------------------
local topPanel, topScroll = makePanel("Top 10 Richest")
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
					Size = UDim2.new(1, 0, 0, 46),
					BackgroundColor3 = COLORS.row,
					LayoutOrder = rank,
					Parent = topScroll,
				}, {
					corner(10),
					pad(8),
					create("TextLabel", {
						Size = UDim2.new(1, 0, 1, 0),
						BackgroundTransparency = 1,
						Font = Enum.Font.GothamMedium,
						TextColor3 = COLORS.text,
						TextScaled = true,
						TextXAlignment = Enum.TextXAlignment.Left,
						Text = ("#%d  %s  —  $%s"):format(rank, entry.name, Format.abbreviate(entry.cash)),
					}),
				})
			end
		end)
	end
end)

-- Toasts ---------------------------------------------------------------------
local toastLayout = create("Frame", {
	Size = UDim2.new(0, 320, 1, -20),
	Position = UDim2.new(1, -16, 0, 10),
	AnchorPoint = Vector2.new(1, 0),
	BackgroundTransparency = 1,
	Parent = gui,
}, {
	create("UIListLayout", {
		Padding = UDim.new(0, 8),
		HorizontalAlignment = Enum.HorizontalAlignment.Right,
		VerticalAlignment = Enum.VerticalAlignment.Top,
		SortOrder = Enum.SortOrder.LayoutOrder,
	}),
})

local function showToast(text: string, color: Color3)
	local toast = create("Frame", {
		Size = UDim2.new(1, 0, 0, 54),
		BackgroundColor3 = COLORS.panel,
		BackgroundTransparency = 0.05,
		Parent = toastLayout,
	}, {
		corner(12),
		pad(8),
		create("UIStroke", { Thickness = 2, Color = color }),
		create("TextLabel", {
			Size = UDim2.new(1, 0, 1, 0),
			BackgroundTransparency = 1,
			Font = Enum.Font.GothamBold,
			TextColor3 = color,
			TextScaled = true,
			TextWrapped = true,
			Text = text,
		}),
	})
	task.delay(3.5, function()
		local tween = TweenService:Create(toast, TweenInfo.new(0.4), { BackgroundTransparency = 1 })
		tween:Play()
		tween.Completed:Wait()
		toast:Destroy()
	end)
end

NotifyEvent.OnClientEvent:Connect(function(text, color)
	showToast(text, color or COLORS.text)
end)

-- Sync + prediction ----------------------------------------------------------
local snapshot: any = nil
local displayCash = 0

local function refresh()
	if not snapshot then
		return
	end
	displayCash = snapshot.cash
	incomeLabel.Text = "+" .. Format.abbreviate(snapshot.income) .. " / sec"
	rollButton.Text = ("ROLL\n$%s   (%d/%d)"):format(
		Format.abbreviate(snapshot.rollCost),
		snapshot.slotsUsed,
		snapshot.slotsTotal
	)
	for key, btn in passButtons do
		if snapshot.passes[key] then
			btn.Text = "Owned"
			btn.BackgroundColor3 = COLORS.row
		else
			btn.Text = "Buy"
			btn.BackgroundColor3 = COLORS.robux
		end
	end
end

SyncEvent.OnClientEvent:Connect(function(snap)
	snapshot = snap
	refresh()
end)

rollButton.Activated:Connect(function()
	RollEvent:FireServer()
end)
collectButton.Activated:Connect(function()
	CollectEvent:FireServer()
end)

RunService.RenderStepped:Connect(function(dt)
	if snapshot then
		displayCash += snapshot.income * dt
	end
	cashLabel.Text = Format.abbreviate(displayCash) .. " " .. Config.CurrencyName
end)

ReadyEvent:FireServer()
