-- Static arena geometry, built from Config into Workspace.ActiveRound: one
-- flat green ground spanning the whole play area (attacker side, the gap,
-- builder side) ringed by grey boundary walls, marker parts a muted blue.
-- reset() empties the folder; build() fills it -- called once at server start.
-- resetRound() is the lighter per-round path: it puts the Flag back at its
-- default position (session 015: the Builder can relocate the Flag each
-- round, so this default is also what the Builder starts from before moving
-- it; session 009's earlier note about ATTACK leaving the Princess unanchored
-- no longer applies -- the Flag never unanchors, see below), leaving the
-- static geometry and the Blocks folder untouched (MatchController also runs
-- BlockManager.resetQueue() and clears live projectiles each round).

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage.Shared.Config)

local FOLDER_NAME = "ActiveRound"
local STONE = Color3.fromRGB(128, 128, 128)
local GRASS = Color3.fromRGB(76, 153, 51)
local MARK = Color3.fromRGB(90, 110, 140)
local FLAG_COLOR = Color3.fromRGB(255, 105, 180)

-- Density is irrelevant here -- the ground never moves -- only friction and
-- restitution matter, so a landed projectile settles instead of rolling
-- indefinitely (session 009 feedback: a rolling sphere has nothing to stop it
-- once it's rolling without slipping, unless the surface itself grips it).
local GROUND_PROPS = PhysicalProperties.new(1, Config.GroundFriction, Config.GroundRestitution)

-- The Flag's default position each round, before the Builder relocates it
-- (session 015): centred, at the original PrincessDistance.
local DEFAULT_FLAG_OFFSET_X = 0
local DEFAULT_FLAG_DISTANCE = Config.PrincessDistance

local function computeFlagPosition(offsetX, distance)
	return Vector3.new(offsetX, Config.GroundLevel + Config.FlagSize.Y / 2, Config.BuildZoneOrigin.Z + distance)
end

-- Session 016: the Flag isn't part of the board while the wall is being
-- built -- hidden (and non-colliding/non-queryable, so it can't be bumped
-- into or raycast onto while invisible) from every reset through POSITION,
-- until the Builder actually places it. Safe to toggle freely: FlagMonitor's
-- Touched handler already ignores everything unless armed (ATTACK through
-- the RESOLVE settle beat), so a hidden Flag being touched during
-- BUILD/POSITION was already a no-op even before this.
local function hideFlag(flag)
	flag.Transparency = 1
	flag.CanCollide = false
	flag.CanQuery = false
end

local function revealFlag(flag)
	flag.Transparency = 0
	flag.CanCollide = true
	flag.CanQuery = true
end

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

local function part(name, size, position, color, transparency, material)
	local p = Instance.new("Part")
	p.Name = name
	p.Anchored = true
	p.Size = size
	p.Position = position
	p.Color = color
	p.Material = material or Enum.Material.SmoothPlastic
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
	-- by walls so a missed shot physically collides with something instead of
	-- flying into the void (session 009: a real projectile, so this is now
	-- ordinary collision, not a raycast filter). Both folded into a Boundary
	-- folder the client's aim-trace raycasts also see, since it's never
	-- excluded.
	local boundary = Instance.new("Folder")
	boundary.Name = "Boundary"
	boundary.Parent = root

	local groundHalfX = Config.PlatformSize.X / 2
	local groundMinZ = -(halfGap + Config.PlatformSize.Z)
	local groundMaxZ = halfGap + Config.PlatformSize.Z
	local groundSize = Vector3.new(Config.PlatformSize.X, Config.PlatformSize.Y, groundMaxZ - groundMinZ)

	local ground =
		part("Ground", groundSize, Vector3.new(0, platformY, (groundMinZ + groundMaxZ) / 2), GRASS, nil, Enum.Material.Grass)
	ground.CustomPhysicalProperties = GROUND_PROPS
	ground.Parent = boundary

	local wallHeight = Config.BoundaryWallHeight
	local wallThickness = Config.BoundaryWallThickness
	local wallY = Config.GroundLevel + wallHeight / 2

	part(
		"WallNear",
		Vector3.new(groundSize.X + wallThickness * 2, wallHeight, wallThickness),
		Vector3.new(0, wallY, groundMinZ - wallThickness / 2),
		STONE,
		nil,
		Enum.Material.Cobblestone
	).Parent = boundary
	part(
		"WallFar",
		Vector3.new(groundSize.X + wallThickness * 2, wallHeight, wallThickness),
		Vector3.new(0, wallY, groundMaxZ + wallThickness / 2),
		STONE,
		nil,
		Enum.Material.Cobblestone
	).Parent = boundary
	part(
		"WallLeft",
		Vector3.new(wallThickness, wallHeight, groundSize.Z + wallThickness * 2),
		Vector3.new(-groundHalfX - wallThickness / 2, wallY, 0),
		STONE,
		nil,
		Enum.Material.Cobblestone
	).Parent = boundary
	part(
		"WallRight",
		Vector3.new(wallThickness, wallHeight, groundSize.Z + wallThickness * 2),
		Vector3.new(groundHalfX + wallThickness / 2, wallY, 0),
		STONE,
		nil,
		Enum.Material.Cobblestone
	).Parent = boundary

	part(
		"BuildZone",
		Vector3.new(Config.BuildZoneSize.X, 0.1, Config.BlockSize.Z),
		Vector3.new(0, Config.GroundLevel + 0.05, Config.BuildZoneOrigin.Z),
		MARK,
		0.35,
		Enum.Material.Neon
	).Parent = root

	for _, weapon in { "Ballista", "Catapult" } do
		local sign = if weapon == "Ballista" then -1 else 1
		part(
			weapon .. "FiringPosition",
			Vector3.new(4, 0.1, 4),
			Vector3.new(sign * Config.MuzzleOffsetX, Config.GroundLevel + 0.05, -(halfGap + 2)),
			MARK,
			0.35,
			Enum.Material.Neon
		).Parent = root
	end

	-- The Flag (session 015, replaces the Princess): hit-or-not, not toppled,
	-- so it stays anchored for good -- no PhysicalProperties needed.
	-- FlagMonitor watches it via Touched. Starts hidden (session 016) -- it
	-- isn't placed yet.
	local flag =
		part("Flag", Config.FlagSize, computeFlagPosition(DEFAULT_FLAG_OFFSET_X, DEFAULT_FLAG_DISTANCE), FLAG_COLOR)
	flag.Parent = root
	hideFlag(flag)

	return root
end

-- Per-round reset: puts the Flag back at its default position and hides it
-- again (session 016 -- it stays off the board through the new round's BUILD
-- and POSITION until the Builder re-places it). The Flag never unanchors, so
-- there's no leftover velocity to clear.
function Arena.resetRound()
	local root = Arena.root()
	local flag = root:FindFirstChild("Flag")
	if flag then
		flag.CFrame = CFrame.new(computeFlagPosition(DEFAULT_FLAG_OFFSET_X, DEFAULT_FLAG_DISTANCE))
		hideFlag(flag)
	end
	return root
end

-- Called by the Builder during POSITION (session 015; repeatable as of
-- session 016 -- see MatchController.relocateFlag). `offsetX` and `distance`
-- have already been validated/clamped by the caller against
-- Config.FlagPlacementMaxOffsetX/MinDistance/MaxDistance. Reveals the Flag
-- the first time this is called, same as showFlag() below.
function Arena.relocateFlag(offsetX, distance)
	local flag = Arena.root():FindFirstChild("Flag")
	if not flag then
		return
	end
	flag.CFrame = CFrame.new(computeFlagPosition(offsetX, distance))
	revealFlag(flag)
end

-- Reveals the Flag wherever it currently sits, without moving it (session
-- 016) -- the fallback for confirmFlagPlacement when the Builder advances
-- without ever clicking to relocate it, so it doesn't stay invisible forever
-- at its default spot. A no-op re-reveal if relocateFlag already did this.
function Arena.showFlag()
	local flag = Arena.root():FindFirstChild("Flag")
	if flag then
		revealFlag(flag)
	end
end

-- The Flag's current world position -- ShieldManager reads this to keep the
-- Builder's shield tracking the Flag (session 015), since it can no longer
-- assume a fixed point.
function Arena.flagPosition()
	local flag = Arena.root():FindFirstChild("Flag")
	return flag and flag.Position
end

return Arena
