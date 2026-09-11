-- Every tunable in one table. Nothing in game logic should hardcode a number
-- that belongs here. Values are first-pass guesses; expect to tune by feel.

local BLOCK_SIZE = Vector3.new(2.5, 1.25, 2.5)

-- Block types. Counts sum to BlockCount. Size.X is the long horizontal axis;
-- a Wide block is three Standard blocks across. PileOrigin is filled in below
-- once the piles' X positions are known.
local BLOCK_TYPES = {
	{ Name = "Standard", Size = BLOCK_SIZE, Count = 6, Rotatable = false },
	{ Name = "Wide", Size = Vector3.new(BLOCK_SIZE.X * 3, BLOCK_SIZE.Y, BLOCK_SIZE.Z), Count = 6, Rotatable = true },
}

local BLOCK_COUNT = 0
local TOTAL_BLOCK_HEIGHT = 0 -- every block stacked in one column
local TOTAL_BLOCK_WIDTH = 0 -- every block laid side by side, one row
for _, typeDef in BLOCK_TYPES do
	BLOCK_COUNT += typeDef.Count
	TOTAL_BLOCK_HEIGHT += typeDef.Count * typeDef.Size.Y
	TOTAL_BLOCK_WIDTH += typeDef.Count * typeDef.Size.X
end

-- The trench: the vertical opening the Builder's wall must fill, sized off the
-- block totals so both a single tall stack and a full-width two-high wall are
-- viable strategies (session 003).
local BUILD_ZONE_SIZE = Vector2.new(TOTAL_BLOCK_WIDTH / 2, TOTAL_BLOCK_HEIGHT)

local GAP_WIDTH = 40 -- firing distance across the trench; independently tuned, not block-derived

-- Piles sit clear of the build zone on the builder's right, spaced out one
-- after another; the platform is sized to cover the zone plus every pile.
local PILE_MARGIN = 5
local PILE_GAP = 9
local PILE_Z = 24
do
	local pileX = BUILD_ZONE_SIZE.X / 2 + PILE_MARGIN
	for _, typeDef in BLOCK_TYPES do
		typeDef.PileOrigin = Vector3.new(pileX, 0, PILE_Z)
		pileX += PILE_GAP
	end
end

local platformHalfWidth = BUILD_ZONE_SIZE.X / 2
for _, typeDef in BLOCK_TYPES do
	platformHalfWidth = math.max(platformHalfWidth, typeDef.PileOrigin.X + typeDef.Size.X / 2 + PILE_MARGIN)
end

local Config = {
	-- Blocks
	BlockSize = BLOCK_SIZE, -- the Standard block: width, height, depth
	BlockMass = 25, -- mass of a Standard block; wider blocks scale up at equal density
	BlockFriction = 0.5,
	BlockRestitution = 0.1,
	BlockCount = BLOCK_COUNT, -- total across all types below
	BlockTypes = BLOCK_TYPES,

	-- Arena
	PrincessDistance = 14, -- studs behind the build zone; the single most important tuning value
	GapWidth = GAP_WIDTH,
	PlatformSize = Vector3.new(platformHalfWidth * 2, 1, 30), -- wide enough for the build zone plus both piles
	PrincessSize = Vector3.new(2, 5, 2),
	GroundLevel = 0, -- top surface of both platforms

	-- Build grid (a vertical plane: X = columns, Y = rows, fixed world Z)
	GridSize = Vector2.new(2.5, 1.25), -- column pitch, row pitch
	BuildZoneSize = BUILD_ZONE_SIZE, -- studs, width x height -- the trench, sized off the block totals
	BuildZoneOrigin = Vector3.new(0, BUILD_ZONE_SIZE.Y / 2, GAP_WIDTH / 2 + BLOCK_SIZE.Z / 2), -- plane centre, world space

	-- Weapons (shared)
	MuzzleHeight = 0.75, -- studs above GroundLevel that both weapons fire from; ~bottom-row height so a flat ballista shot rakes the base
	MuzzleOffsetX = 6, -- studs each side of X=0; the two fixed firing emplacements

	-- Boundary: perimeter walls around the flat ground so a missed shot hits
	-- something instead of flying until ProjectileLifetime.
	BoundaryWallHeight = 30,
	BoundaryWallThickness = 1,

	-- Ballista
	BallistaMinVelocity = 190, -- floor for the launch meter; BallistaMuzzleVelocity is the ceiling
	BallistaMuzzleVelocity = 320,
	BallistaGravityScale = 0.05,
	BallistaImpact = 60, -- knockback scale applied to a struck block

	-- Catapult
	CatapultMinForce = 80,
	CatapultMaxForce = 150, -- rough: keeps a mid-range arc landing near the wall at this Princess distance
	CatapultMinAngle = 20, -- degrees
	CatapultMaxAngle = 70,
	CatapultImpact = 60, -- knockback scale applied to a struck block

	-- Match
	ShotsPerTurn = 6,
	RoundsPerMatch = 4,
	ResolveSettleTime = 1.5, -- seconds to let physics settle after the last shot/kill before deciding the round

	-- Physics thresholds
	MovingBlockKillSpeed = 10, -- a block slower than this can't kill the Princess
	ProjectileLifetime = 5, -- seconds before a projectile despawns
}

-- The fixed muzzle point for a weapon's emplacement: same height and firing
-- line for both, offset either side of X=0. Shared by server (projectile
-- spawn) and client (aim ray, trace preview) so there's one formula, not two.
function Config.muzzleOrigin(weapon)
	local x = if weapon == "Ballista" then -Config.MuzzleOffsetX else Config.MuzzleOffsetX
	return Vector3.new(x, Config.GroundLevel + Config.MuzzleHeight, -(Config.GapWidth / 2))
end

return Config
