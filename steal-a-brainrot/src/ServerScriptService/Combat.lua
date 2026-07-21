-- ============================================================================
--  Combat — everyone spawns with a sword. Swinging knocks nearby players back
--  (and damages them), which cancels a thief's steal hold. Server-authoritative:
--  the client only asks to swing; the server decides who gets hit.
-- ============================================================================
local Players = game:GetService("Players")
local Debris = game:GetService("Debris")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Config = require(ReplicatedStorage.Shared.Config)

local Combat = {}

local lastSwing: { [Player]: number } = {}

-- Cosmetic sword welded to the player's right hand on spawn.
function Combat.equip(character: Model)
	if character:FindFirstChild("Sword") then
		return
	end
	local hand = character:FindFirstChild("RightHand") or character:FindFirstChild("Right Arm")
	if not hand or not hand:IsA("BasePart") then
		return
	end

	local sword = Instance.new("Part")
	sword.Name = "Sword"
	sword.Size = Vector3.new(0.25, 3, 0.6)
	sword.Color = Color3.fromRGB(210, 215, 225)
	sword.Material = Enum.Material.Metal
	sword.CanCollide = false
	sword.Massless = true
	sword.CFrame = hand.CFrame * CFrame.new(0, 1.6, 0)
	sword.Parent = character

	local weld = Instance.new("Weld")
	weld.Part0 = hand
	weld.Part1 = sword
	weld.C0 = CFrame.new(0, 1.6, 0)
	weld.Parent = sword

	local guard = Instance.new("Part")
	guard.Name = "SwordGuard"
	guard.Size = Vector3.new(0.25, 0.3, 1.4)
	guard.Color = Color3.fromRGB(120, 90, 40)
	guard.Material = Enum.Material.Wood
	guard.CanCollide = false
	guard.Massless = true
	guard.CFrame = hand.CFrame * CFrame.new(0, 0.4, 0)
	guard.Parent = character
	local guardWeld = Instance.new("Weld")
	guardWeld.Part0 = hand
	guardWeld.Part1 = guard
	guardWeld.C0 = CFrame.new(0, 0.4, 0)
	guardWeld.Parent = guard
end

-- A quick slash effect in front of the attacker so the swing reads visually.
local function slashEffect(hrp: BasePart)
	local slash = Instance.new("Part")
	slash.Anchored = true
	slash.CanCollide = false
	slash.Size = Vector3.new(6, 0.2, 4)
	slash.Color = Color3.fromRGB(255, 255, 255)
	slash.Material = Enum.Material.Neon
	slash.Transparency = 0.35
	slash.CFrame = hrp.CFrame * CFrame.new(0, 0.5, -3) * CFrame.Angles(math.rad(90), 0, 0)
	slash.Parent = workspace
	Debris:AddItem(slash, 0.15)
end

function Combat.setup(swingEvent: RemoteEvent)
	swingEvent.OnServerEvent:Connect(function(player)
		local now = os.clock()
		if lastSwing[player] and now - lastSwing[player] < Config.Combat.cooldown then
			return
		end
		lastSwing[player] = now

		local character = player.Character
		local hrp = character and character:FindFirstChild("HumanoidRootPart")
		local humanoid = character and character:FindFirstChildOfClass("Humanoid")
		if not hrp or not humanoid or humanoid.Health <= 0 then
			return
		end

		slashEffect(hrp)

		local origin = hrp.Position
		local look = hrp.CFrame.LookVector
		for _, other in Players:GetPlayers() do
			if other ~= player and other.Character then
				local otherHrp = other.Character:FindFirstChild("HumanoidRootPart")
				local otherHum = other.Character:FindFirstChildOfClass("Humanoid")
				if otherHrp and otherHum and otherHum.Health > 0 then
					local delta = otherHrp.Position - origin
					local dist = delta.Magnitude
					if dist > 0.1 and dist <= Config.Combat.range and look:Dot(delta.Unit) > 0.25 then
						otherHum:TakeDamage(Config.Combat.damage)
						-- Knockback cancels their steal hold (they leave prompt range).
						otherHrp.AssemblyLinearVelocity = delta.Unit * Config.Combat.knockback
							+ Vector3.new(0, 25, 0)
					end
				end
			end
		end
	end)

	Players.PlayerRemoving:Connect(function(player)
		lastSwing[player] = nil
	end)
end

return Combat
