-- Every tunable in one table. Nothing in game logic should hardcode a number
-- that belongs here. Values are first-pass guesses; expect to tune by feel.

local BLOCK_SIZE = Vector3.new(2.5, 1.25, 2.5)
local BUILD_ZONE_SIZE = Vector2.new(20, 10)
local GAP_WIDTH = 40

local Config = {
	-- Blocks
	BlockSize = BLOCK_SIZE, -- the Standard block: width, height, depth
	BlockMass = 25, -- mass of a Standard block; wider blocks scale up at equal density
	BlockFriction = 0.5,
	BlockRestitution = 0.1,
	BlockCount = 12, -- total across all types below

	-- Block types. Counts sum to BlockCount. Size.X is the long horizontal axis;
	-- a Wide block is three Standard blocks across. Each type spawns stacked at
	-- its PileOrigin (world space, on the builder's right) and blocks return
	-- there when picked off the wall.
	BlockTypes = {
		{
			Name = "Standard",
			Size = BLOCK_SIZE,
			Count = 6,
			Rotatable = false,
			PileOrigin = Vector3.new(15, 0, 24),
		},
		{
			Name = "Wide",
			Size = Vector3.new(BLOCK_SIZE.X * 3, BLOCK_SIZE.Y, BLOCK_SIZE.Z),
			Count = 6,
			Rotatable = true,
			PileOrigin = Vector3.new(24, 0, 24),
		},
	},

	-- Arena
	PrincessDistance = 14, -- studs behind the build zone; the single most important tuning value
	GapWidth = GAP_WIDTH,
	PlatformSize = Vector3.new(56, 1, 30), -- wide enough for the build zone plus both piles
	PrincessSize = Vector3.new(2, 5, 2),
	GroundLevel = 0, -- top surface of both platforms

	-- Build grid (a vertical plane: X = columns, Y = rows, fixed world Z)
	GridSize = Vector2.new(2.5, 1.25), -- column pitch, row pitch
	BuildZoneSize = BUILD_ZONE_SIZE, -- studs, width x height
	BuildZoneOrigin = Vector3.new(0, BUILD_ZONE_SIZE.Y / 2, GAP_WIDTH / 2 + BLOCK_SIZE.Z / 2), -- plane centre, world space

	-- Ballista
	BallistaMuzzleVelocity = 320,
	BallistaGravityScale = 0.05,

	-- Catapult
	CatapultMinForce = 80,
	CatapultMaxForce = 220,
	CatapultMinAngle = 20, -- degrees
	CatapultMaxAngle = 70,
	CatapultImpact = 60, -- impulse scale applied to a struck block

	-- Match
	ShotsPerTurn = 6,
	RoundsPerMatch = 4,

	-- Physics thresholds
	MovingBlockKillSpeed = 10, -- a block slower than this can't kill the Princess
	ProjectileLifetime = 5, -- seconds before a projectile despawns
}

return Config
