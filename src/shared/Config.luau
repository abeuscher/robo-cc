-- Every tunable in one table. Nothing in game logic should hardcode a number
-- that belongs here. Values are first-pass guesses; expect to tune by feel.

local BLOCK_SIZE = Vector3.new(1.25, 1.25, 1.25) -- a cube, settled on the original height

-- Piece generation (session 008): each of a round's pieces fills a random
-- 3-6 cells of a 3x3 area, chosen at random. No two pieces are alike, and
-- there's no roster of named types anymore -- just a shape and a count.
local PIECE_GRID_SIZE = 3 -- the cell area a piece's shape is drawn from (3x3)
local PIECE_MIN_CELLS = 3
local PIECE_MAX_CELLS = 6
local PIECE_COUNT = 9

-- The trench: the vertical opening the Builder's wall must fill. Sized off
-- the worst case, since the static geometry can't resize itself round to
-- round: every cell comes from a PIECE_GRID_SIZE x PIECE_GRID_SIZE area, so a
-- piece's bounding box can never exceed that regardless of how many of those
-- cells end up filled -- PieceMinCells/PieceMaxCells affect mass and shape
-- variety, not footprint extent. Treating every piece as if it filled its
-- whole 3x3 box is the tightest true worst case (session 003 established the
-- "size off the totals" approach; sessions 005-007 kept re-deriving it as the
-- roster changed shape).
local PIECE_MAX_SPAN = PIECE_GRID_SIZE * BLOCK_SIZE.X
local TOTAL_BLOCK_HEIGHT = PIECE_COUNT * PIECE_MAX_SPAN -- every piece stacked in one column
local TOTAL_BLOCK_WIDTH = PIECE_COUNT * PIECE_MAX_SPAN -- every piece laid side by side, one row
local BUILD_ZONE_SIZE = Vector2.new(TOTAL_BLOCK_WIDTH / 2, TOTAL_BLOCK_HEIGHT)

local GAP_WIDTH = 40 -- firing distance across the trench; independently tuned, not block-derived

-- Fixed, scripted shot order -- the Attacker no longer chooses a weapon
-- (session 007, overrides spec's free choice). ShotsPerTurn derives from this
-- so the two can never drift apart.
local SHOT_SEQUENCE = { "Catapult", "Catapult", "Ballista" }

-- No physical pile (session 006 -- pieces are issued one at a time, not
-- pre-spawned into a stack) -- the platform just needs to cover the build
-- zone with a little clearance.
local PLATFORM_MARGIN = 5
local platformHalfWidth = BUILD_ZONE_SIZE.X / 2 + PLATFORM_MARGIN

local Config = {
	-- Blocks
	BlockSize = BLOCK_SIZE, -- sub-cube dimensions; every block is built from cells this size
	BlockMass = 25, -- mass of one sub-cube's worth of block; a multi-cell piece scales up at equal density
	BlockFriction = 0.5,
	BlockRestitution = 0.1,
	PieceGridSize = PIECE_GRID_SIZE, -- a piece's shape is a random subset of this x this cells
	PieceMinCells = PIECE_MIN_CELLS,
	PieceMaxCells = PIECE_MAX_CELLS,
	PieceCount = PIECE_COUNT, -- pieces issued per round

	-- Arena
	PrincessDistance = 14, -- studs behind the build zone; the single most important tuning value
	GapWidth = GAP_WIDTH,
	PlatformSize = Vector3.new(platformHalfWidth * 2, 1, 30), -- wide enough for the build zone plus its margin
	PrincessSize = Vector3.new(2, 5, 2),
	GroundLevel = 0, -- top surface of both platforms

	-- Build grid (a vertical plane: X = columns, Y = rows, fixed world Z)
	GridSize = Vector2.new(BLOCK_SIZE.X, BLOCK_SIZE.Y), -- column pitch, row pitch -- always the sub-cube's own footprint
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
	ShotSequence = SHOT_SEQUENCE, -- mandated weapon per shot, in order; no free choice (session 007)
	ShotsPerTurn = #SHOT_SEQUENCE,
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
