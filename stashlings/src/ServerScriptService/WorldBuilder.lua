-- ============================================================================
--  WorldBuilder — procedurally builds every base (plot) in code, so no binary
--  map file is needed. Returns descriptors the Plots module drives.
-- ============================================================================
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Config = require(ReplicatedStorage.Shared.Config)

local WorldBuilder = {}

local FLOOR_SIZE = Vector3.new(40, 1, 40)
local PLOT_SPACING = 60
local PODIUM_OFFSETS = { -12, 0, 12 } -- 3x3 grid

local function part(props: { [string]: any }): BasePart
	local p = Instance.new("Part")
	p.Anchored = true
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	for k, v in props do
		(p :: any)[k] = v
	end
	return p
end

-- Build one plot at world X = originX. Returns its descriptor.
local function buildPlot(index: number, originX: number, parent: Instance)
	local model = Instance.new("Model")
	model.Name = "Plot" .. index

	local floor = part({
		Name = "Floor",
		Size = FLOOR_SIZE,
		Position = Vector3.new(originX, 0.5, 0),
		Color = Color3.fromRGB(70, 74, 92),
		Material = Enum.Material.SmoothPlastic,
		Parent = model,
	})

	-- Podiums (3x3)
	local podiums: { BasePart } = {}
	local slot = 0
	for _, dz in PODIUM_OFFSETS do
		for _, dx in PODIUM_OFFSETS do
			slot += 1
			local pad = part({
				Name = "Podium" .. slot,
				Size = Vector3.new(6, 1.5, 6),
				Position = Vector3.new(originX + dx, 1.75, dz), -- top surface at y = 2.5
				Color = Color3.fromRGB(45, 48, 62),
				Material = Enum.Material.Metal,
				Parent = model,
			})
			podiums[slot] = pad
		end
	end

	-- A labeled neon pad the player steps on. Returns the pad part.
	local function makePad(name: string, offsetX: number, color: Color3, text: string): BasePart
		local padPart = part({
			Name = name,
			Size = Vector3.new(12, 1, 8),
			Position = Vector3.new(originX + offsetX, 1.25, 15),
			Color = color,
			Material = Enum.Material.Neon,
			Parent = model,
		})
		local gui = Instance.new("BillboardGui")
		gui.Size = UDim2.fromOffset(180, 40)
		gui.StudsOffsetWorldSpace = Vector3.new(0, 2.5, 0)
		gui.AlwaysOnTop = true
		gui.Parent = padPart
		local label = Instance.new("TextLabel")
		label.Name = "Label"
		label.Size = UDim2.fromScale(1, 1)
		label.BackgroundTransparency = 1
		label.Font = Enum.Font.GothamBold
		label.TextColor3 = Color3.fromRGB(255, 255, 255)
		label.TextStrokeTransparency = 0.4
		label.TextScaled = true
		label.Text = text
		label.Parent = gui
		return padPart
	end

	-- Collect (left) and Lock (right) pads at the front of the base.
	local collectPad = makePad("CollectPad", -8, Color3.fromRGB(80, 200, 120), "COLLECT")
	local lockPad = makePad("LockPad", 8, Color3.fromRGB(90, 150, 255), "LOCK VAULT")
	local lockPadLabel = lockPad:FindFirstChildOfClass("BillboardGui"):FindFirstChild("Label") :: TextLabel

	-- Owner sign on a pole at the back
	local pole = part({
		Name = "SignPole",
		Size = Vector3.new(1, 10, 1),
		Position = Vector3.new(originX, 5, -19),
		Color = Color3.fromRGB(35, 37, 48),
		Parent = model,
	})
	local sign = Instance.new("BillboardGui")
	sign.Name = "Sign"
	sign.Size = UDim2.fromOffset(320, 110)
	sign.StudsOffsetWorldSpace = Vector3.new(0, 6.5, 0)
	sign.AlwaysOnTop = true
	sign.Parent = pole

	local ownerLabel = Instance.new("TextLabel")
	ownerLabel.Name = "Owner"
	ownerLabel.Size = UDim2.new(1, 0, 0.4, 0)
	ownerLabel.BackgroundTransparency = 1
	ownerLabel.Font = Enum.Font.GothamBold
	ownerLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
	ownerLabel.TextStrokeTransparency = 0.4
	ownerLabel.TextScaled = true
	ownerLabel.Text = "Empty Vault"
	ownerLabel.Parent = sign

	local statsLabel = Instance.new("TextLabel")
	statsLabel.Name = "Stats"
	statsLabel.Size = UDim2.new(1, 0, 0.6, 0)
	statsLabel.Position = UDim2.new(0, 0, 0.4, 0)
	statsLabel.BackgroundTransparency = 1
	statsLabel.Font = Enum.Font.Gotham
	statsLabel.TextColor3 = Color3.fromRGB(200, 230, 255)
	statsLabel.TextStrokeTransparency = 0.5
	statsLabel.TextScaled = true
	statsLabel.Text = ""
	statsLabel.Parent = sign

	model.Parent = parent

	return {
		index = index,
		model = model,
		podiums = podiums,
		collectPad = collectPad,
		lockPad = lockPad,
		lockPadLabel = lockPadLabel,
		ownerLabel = ownerLabel,
		statsLabel = statsLabel,
		spawnCFrame = CFrame.lookAt(Vector3.new(originX, 4, 12), Vector3.new(originX, 4, 0)),
	}
end

-- Builds all plots and a ground plane. Returns an array of descriptors.
function WorldBuilder.build(): { any }
	local container = Instance.new("Folder")
	container.Name = "Plots"

	-- Big ground plane so players don't fall off the default baseplate edges.
	local ground = part({
		Name = "Ground",
		Size = Vector3.new(PLOT_SPACING * Config.PlotCount + 80, 1, 120),
		Position = Vector3.new((Config.PlotCount - 1) * PLOT_SPACING / 2, -0.5, 0),
		Color = Color3.fromRGB(60, 120, 70),
		Material = Enum.Material.Grass,
		Parent = container,
	})
	ground:AddTag("GameGround")

	local plots = {}
	for i = 1, Config.PlotCount do
		plots[i] = buildPlot(i, (i - 1) * PLOT_SPACING, container)
	end

	container.Parent = workspace
	return plots
end

return WorldBuilder
