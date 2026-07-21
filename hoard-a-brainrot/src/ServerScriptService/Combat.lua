-- ============================================================================
--  Combat — everyone spawns with a MALLET. Bonking nearby players knocks them
--  back (cancelling a raider's snatch) and, via the onHit callback, wipes their
--  Snatch Streak. Server-authoritative: the client only asks to swing.
-- ============================================================================
local Players = game:GetService("Players")
local Debris = game:GetService("Debris")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Config = require(ReplicatedStorage.Shared.Config)

local Combat = {}

local lastSwing: { [Player]: number } = {}

-- onHit(victimPlayer) — injected by Main so combat can break snatch streaks.
local onHit: (Player) -> () = function() end
function Combat.setOnHit(fn: (Player) -> ())
	onHit = fn
end

-- Cosmetic mallet welded to the player's right hand on spawn.
function Combat.equip(character: Model)
	if character:FindFirstChild("Mallet") then
		return
	end
	local hand = character:FindFirstChild("RightHand") or character:FindFirstChild("Right Arm")
	if not hand or not hand:IsA("BasePart") then
		return
	end

	-- handle
	local handle = Instance.new("Part")
	handle.Name = "Mallet"
	handle.Size = Vector3.new(0.3, 3, 0.3)
	handle.Color = Color3.fromRGB(120, 90, 40)
	handle.Material = Enum.Material.Wood
	handle.CanCollide = false
	handle.Massless = true
	handle.CFrame = hand.CFrame * CFrame.new(0, 1.5, 0)
	handle.Parent = character
	local handleWeld = Instance.new("Weld")
	handleWeld.Part0 = hand
	handleWeld.Part1 = handle
	handleWeld.C0 = CFrame.new(0, 1.5, 0)
	handleWeld.Parent = handle

	-- head
	local head = Instance.new("Part")
	head.Name = "MalletHead"
	head.Size = Vector3.new(1.4, 1.1, 1.1)
	head.Color = Color3.fromRGB(90, 95, 110)
	head.Material = Enum.Material.Metal
	head.CanCollide = false
	head.Massless = true
	head.CFrame = hand.CFrame * CFrame.new(0, 2.9, 0)
	head.Parent = character
	local headWeld = Instance.new("Weld")
	headWeld.Part0 = hand
	headWeld.Part1 = head
	headWeld.C0 = CFrame.new(0, 2.9, 0)
	headWeld.Parent = head
end

-- A quick shockwave in front of the attacker so the bonk reads visually.
local function bonkEffect(hrp: BasePart)
	local fx = Instance.new("Part")
	fx.Anchored = true
	fx.CanCollide = false
	fx.Shape = Enum.PartType.Ball
	fx.Size = Vector3.new(6, 6, 6)
	fx.Color = Color3.fromRGB(255, 240, 180)
	fx.Material = Enum.Material.Neon
	fx.Transparency = 0.45
	fx.CFrame = hrp.CFrame * CFrame.new(0, 0, -3)
	fx.Parent = workspace
	Debris:AddItem(fx, 0.15)
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

		bonkEffect(hrp)

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
						-- Knockback cancels their snatch hold (they leave prompt range).
						otherHrp.AssemblyLinearVelocity = delta.Unit * Config.Combat.knockback
							+ Vector3.new(0, 25, 0)
						onHit(other) -- breaks their snatch streak
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
