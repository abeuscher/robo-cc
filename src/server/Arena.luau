-- Static arena geometry, built from Config into Workspace.ActiveRound. Plain
-- grey parts, marker parts a muted blue. reset() empties the folder; build()
-- fills it. This session calls build() once at server start; the per-round
-- reset loop comes later.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage.Shared.Config)

local FOLDER_NAME = "ActiveRound"
local STONE = Color3.fromRGB(128, 128, 128)
local MARK = Color3.fromRGB(90, 110, 140)

local Arena = {}

function Arena.root()
	local existing = Workspace:FindFirstChild(FOLDER_NAME)
	if existing then
		return existing
	end
	local folder = Instance.new("Folder")
	folder.Name = FOLDER_NAME
	folder.Parent = Workspace
	return folder
end

local function part(name, size, position, color, transparency)
	local p = Instance.new("Part")
	p.Name = name
	p.Anchored = true
	p.Size = size
	p.Position = position
	p.Color = color
	p.Transparency = transparency or 0
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	return p
end

function Arena.reset()
	Arena.root():ClearAllChildren()
end

function Arena.build()
	Arena.reset()
	local root = Arena.root()

	local platformY = Config.GroundLevel - Config.PlatformSize.Y / 2
	local halfGap = Config.GapWidth / 2
	local halfDepth = Config.PlatformSize.Z / 2

	part(
		"BuilderPlatform",
		Config.PlatformSize,
		Vector3.new(0, platformY, halfGap + halfDepth),
		STONE
	).Parent = root

	part(
		"AttackerPlatform",
		Config.PlatformSize,
		Vector3.new(0, platformY, -(halfGap + halfDepth)),
		STONE
	).Parent = root

	part(
		"BuildZone",
		Vector3.new(Config.BuildZoneSize.X, 0.1, Config.BlockSize.Z),
		Vector3.new(0, Config.GroundLevel + 0.05, Config.BuildZoneOrigin.Z),
		MARK,
		0.35
	).Parent = root

	part(
		"FiringPosition",
		Vector3.new(6, 0.1, 6),
		Vector3.new(0, Config.GroundLevel + 0.05, -(halfGap + 2)),
		MARK,
		0.35
	).Parent = root

	for _, typeDef in Config.BlockTypes do
		part(
			typeDef.Name .. "Pile",
			Vector3.new(typeDef.Size.X + 1, 0.1, typeDef.Size.Z + 1),
			Vector3.new(typeDef.PileOrigin.X, Config.GroundLevel + 0.05, typeDef.PileOrigin.Z),
			MARK,
			0.35
		).Parent = root
	end

	part(
		"Princess",
		Config.PrincessSize,
		Vector3.new(
			0,
			Config.GroundLevel + Config.PrincessSize.Y / 2,
			Config.BuildZoneOrigin.Z + Config.PrincessDistance
		),
		STONE
	).Parent = root

	return root
end

return Arena
