-- Static arena geometry, built from Config into Workspace.ActiveRound: one
-- flat green ground spanning the whole play area (attacker side, the gap,
-- builder side) ringed by grey boundary walls, marker parts a muted blue.
-- reset() empties the folder; build() fills it. This session calls build()
-- once at server start; the per-round reset loop comes later.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage.Shared.Config)

local FOLDER_NAME = "ActiveRound"
local STONE = Color3.fromRGB(128, 128, 128)
local GRASS = Color3.fromRGB(76, 153, 51)
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

-- The baseplate template drops a SpawnLocation at the world origin, which lands
-- right in the middle of the ground. Remove any that aren't ours and add a
-- single invisible, non-colliding spawn on the builder's side -- MatchController
-- repositions characters onto their marks either way.
local function resetSpawns(root)
	for _, inst in Workspace:GetDescendants() do
		if inst:IsA("SpawnLocation") and not inst:IsDescendantOf(root) then
			inst:Destroy()
		end
	end
	local spawn = Instance.new("SpawnLocation")
	spawn.Name = "PlayerSpawn"
	spawn.Anchored = true
	spawn.CanCollide = false
	spawn.Transparency = 1
	spawn.Size = Vector3.new(4, 1, 4)
	spawn.Neutral = true
	spawn.Duration = 0
	spawn.Position = Vector3.new(0, Config.GroundLevel + 0.5, Config.BuildZoneOrigin.Z + 8)
	spawn.Parent = root
end

function Arena.build()
	Arena.reset()
	local root = Arena.root()
	resetSpawns(root)

	local platformY = Config.GroundLevel - Config.PlatformSize.Y / 2
	local halfGap = Config.GapWidth / 2

	-- One continuous flat ground: attacker side, the gap, and builder side all
	-- at the same elevation (spec: "roughly the same ground elevation"), ringed
	-- by walls so a missed shot hits something. Both folded into a Boundary
	-- folder that WeaponManager includes in its projectile raycast filter.
	local boundary = Instance.new("Folder")
	boundary.Name = "Boundary"
	boundary.Parent = root

	local groundHalfX = Config.PlatformSize.X / 2
	local groundMinZ = -(halfGap + Config.PlatformSize.Z)
	local groundMaxZ = halfGap + Config.PlatformSize.Z
	local groundSize = Vector3.new(Config.PlatformSize.X, Config.PlatformSize.Y, groundMaxZ - groundMinZ)

	part("Ground", groundSize, Vector3.new(0, platformY, (groundMinZ + groundMaxZ) / 2), GRASS).Parent = boundary

	local wallHeight = Config.BoundaryWallHeight
	local wallThickness = Config.BoundaryWallThickness
	local wallY = Config.GroundLevel + wallHeight / 2

	part(
		"WallNear",
		Vector3.new(groundSize.X + wallThickness * 2, wallHeight, wallThickness),
		Vector3.new(0, wallY, groundMinZ - wallThickness / 2),
		STONE
	).Parent = boundary
	part(
		"WallFar",
		Vector3.new(groundSize.X + wallThickness * 2, wallHeight, wallThickness),
		Vector3.new(0, wallY, groundMaxZ + wallThickness / 2),
		STONE
	).Parent = boundary
	part(
		"WallLeft",
		Vector3.new(wallThickness, wallHeight, groundSize.Z + wallThickness * 2),
		Vector3.new(-groundHalfX - wallThickness / 2, wallY, 0),
		STONE
	).Parent = boundary
	part(
		"WallRight",
		Vector3.new(wallThickness, wallHeight, groundSize.Z + wallThickness * 2),
		Vector3.new(groundHalfX + wallThickness / 2, wallY, 0),
		STONE
	).Parent = boundary

	part(
		"BuildZone",
		Vector3.new(Config.BuildZoneSize.X, 0.1, Config.BlockSize.Z),
		Vector3.new(0, Config.GroundLevel + 0.05, Config.BuildZoneOrigin.Z),
		MARK,
		0.35
	).Parent = root

	for _, weapon in { "Ballista", "Catapult" } do
		local sign = if weapon == "Ballista" then -1 else 1
		part(
			weapon .. "FiringPosition",
			Vector3.new(4, 0.1, 4),
			Vector3.new(sign * Config.MuzzleOffsetX, Config.GroundLevel + 0.05, -(halfGap + 2)),
			MARK,
			0.35
		).Parent = root
	end

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
