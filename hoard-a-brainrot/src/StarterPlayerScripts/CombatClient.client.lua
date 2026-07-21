-- ============================================================================
--  CombatClient — click / tap (or the SWING button on mobile) to swing your
--  sword. Purely a request to the server, which decides who actually gets hit.
-- ============================================================================
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local Config = require(ReplicatedStorage.Shared.Config)

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local Remotes = ReplicatedStorage:WaitForChild("Remotes")
local SwingEvent = Remotes:WaitForChild("Swing") :: RemoteEvent

local cooldown = Config.Combat.cooldown
local lastSwing = 0

local function swing()
	local now = os.clock()
	if now - lastSwing < cooldown then
		return
	end
	lastSwing = now
	SwingEvent:FireServer()
end

-- Mouse click / screen tap anywhere that isn't over UI.
UserInputService.InputBegan:Connect(function(input, gameProcessed)
	if gameProcessed then
		return
	end
	if input.UserInputType == Enum.UserInputType.MouseButton1
		or input.UserInputType == Enum.UserInputType.Touch
	then
		swing()
	end
end)

-- On-screen ATTACK button (handy on mobile).
local gui = Instance.new("ScreenGui")
gui.Name = "CombatUI"
gui.ResetOnSpawn = false
gui.Parent = playerGui

local attackButton = Instance.new("TextButton")
attackButton.Size = UDim2.new(0, 120, 0, 120)
attackButton.Position = UDim2.new(1, -20, 1, -20)
attackButton.AnchorPoint = Vector2.new(1, 1)
attackButton.BackgroundColor3 = Color3.fromRGB(230, 90, 90)
attackButton.Font = Enum.Font.GothamBlack
attackButton.TextColor3 = Color3.fromRGB(255, 255, 255)
attackButton.TextScaled = true
attackButton.Text = "⚔️"
attackButton.Parent = gui

local uiCorner = Instance.new("UICorner")
uiCorner.CornerRadius = UDim.new(1, 0)
uiCorner.Parent = attackButton

attackButton.Activated:Connect(swing)
