-- Every tunable in one table. Nothing in game logic should hardcode a number
-- that belongs here. Values are first-pass guesses; expect to tune by feel.

local BLOCK_SIZE = Vector3.new(3.75, 3.75, 3.75) -- 3x the original 1.25 (session 009 balance experiment)

-- Piece generation (session 008): each of a round's pieces fills a random
-- 3-6 cells of a 3x3 area, chosen at random. No two pieces are alike, and
-- there's no roster of named types anymore -- just a shape and a count.
local PIECE_GRID_SIZE = 3 -- the cell area a piece's shape is drawn from (3x3)
local PIECE_MIN_CELLS = 3
local PIECE_MAX_CELLS = 6
local PIECE_COUNT = 8 -- reduced from 9 to 6, then back up 2 (session 009 balance experiments)

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
local BUILD_ZONE_ORIGIN_Z = GAP_WIDTH / 2 + BLOCK_SIZE.Z / 2 -- world Z of the build zone's near edge

-- Session 009 playtest feedback: doubled from the original 14 for balance.
-- The builder platform's own depth derives from this (below) so she keeps
-- clear of the back wall regardless of how far back she sits.
local PRINCESS_DISTANCE = 28
local PRINCESS_CLEARANCE = 10 -- platform kept behind her, before the boundary wall

-- Fixed, scripted shot order -- the Attacker no longer chooses a weapon
-- (session 007, overrides spec's free choice). ShotsPerTurn derives from this
-- so the two can never drift apart.
local SHOT_SEQUENCE = { "Catapult", "Catapult", "Ballista" }

-- The platform is exactly as wide as the build zone -- no side margin
-- (session 009: a narrower build zone left open lanes down both sides of the
-- platform, wide enough for a ballista shot to bounce off the boundary walls
-- and reach the Princess without ever passing through the wall; the Builder
-- had no way to block that since the wall itself couldn't reach that far).
-- The wall can now be built flush against the boundary wall on both sides.
local platformHalfWidth = BUILD_ZONE_SIZE.X / 2
local platformDepth = BUILD_ZONE_ORIGIN_Z + PRINCESS_DISTANCE + PRINCESS_CLEARANCE

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
	PrincessDistance = PRINCESS_DISTANCE, -- studs behind the build zone; the single most important tuning value
	GapWidth = GAP_WIDTH,
	PlatformSize = Vector3.new(platformHalfWidth * 2, 1, platformDepth), -- deep enough to keep the Princess clear of the back wall
	PrincessSize = Vector3.new(2, 5, 2),
	GroundLevel = 0, -- top surface of both platforms
	GroundFriction = 0.8, -- high, so a landed ball settles instead of rolling indefinitely
	GroundRestitution = 0.05,

	-- Princess physics (session 009): she's a real unanchored body now, not a
	-- static target -- these feed a PhysicalProperties the same way BlockMass
	-- does for blocks.
	PrincessMass = 60,
	PrincessFriction = 0.7, -- resists sliding, but nothing here resists tipping
	PrincessRestitution = 0.1,
	PrincessTopplingAngle = 78, -- degrees from upright before she counts as knocked over (raised from 60 -- session 009 balance experiment: one clean hit was enough to finish her the instant the wall was gone)

	-- Build grid (a vertical plane: X = columns, Y = rows, fixed world Z)
	GridSize = Vector2.new(BLOCK_SIZE.X, BLOCK_SIZE.Y), -- column pitch, row pitch -- always the sub-cube's own footprint
	BuildZoneSize = BUILD_ZONE_SIZE, -- studs, width x height -- the trench, sized off the block totals
	BuildZoneOrigin = Vector3.new(0, BUILD_ZONE_SIZE.Y / 2, BUILD_ZONE_ORIGIN_Z), -- plane centre, world space

	-- Weapons (shared)
	MuzzleHeight = 0.75, -- studs above GroundLevel that both weapons fire from; ~bottom-row height so a flat ballista shot rakes the base
	MuzzleOffsetX = 6, -- studs each side of X=0; the two fixed firing emplacements

	-- Boundary: perimeter walls around the flat ground so a missed shot hits
	-- something instead of flying off into the void.
	BoundaryWallHeight = 30,
	BoundaryWallThickness = 1,

	-- Ballista: light and fast. Under Roblox's drag-free gravity, mass never
	-- affects trajectory curvature -- speed alone is what keeps this reading
	-- flat over the trench, so velocity keeps its rough prior magnitude even
	-- though the projectile is now a real, lightweight body (session 009).
	BallistaMinVelocity = 190, -- floor for the launch meter; BallistaMuzzleVelocity is the ceiling
	BallistaMuzzleVelocity = 320,
	BallistaProjectileSize = Vector3.new(1, 1, 1),
	BallistaProjectileMass = 6, -- light: soft momentum on impact even at high speed
	BallistaProjectileFriction = 0.3,
	BallistaProjectileRestitution = 0.2,

	-- Catapult: heavier and slower, with real bounce (above the block's own
	-- 0.1) so it visibly settles instead of sticking dead on impact.
	CatapultMinForce = 70,
	CatapultMaxForce = 120, -- reduced from 150 (session 009) -- less force now real mass carries the impact
	CatapultMinAngle = 20, -- degrees
	CatapultMaxAngle = 70,
	CatapultProjectileSize = Vector3.new(1.6, 1.6, 1.6),
	CatapultProjectileMass = 35, -- heavy relative to the ballista's ball
	CatapultProjectileFriction = 0.5,
	CatapultProjectileRestitution = 0.45,

	-- Match
	ShotSequence = SHOT_SEQUENCE, -- mandated weapon per shot, in order; no free choice (session 007)
	ShotsPerTurn = #SHOT_SEQUENCE,
	RoundsPerMatch = 4,
	ResolveSettleTime = 3, -- seconds to let physics settle (the shot actually land) before deciding the round
	RoundEndHoldTime = 10, -- seconds the camera holds on the outcome before advancing, unless a player skips it
}

-- The fixed muzzle point for a weapon's emplacement: same height and firing
-- line for both, offset either side of X=0. Shared by server (projectile
-- spawn) and client (aim ray, trace preview) so there's one formula, not two.
function Config.muzzleOrigin(weapon)
	local x = if weapon == "Ballista" then -Config.MuzzleOffsetX else Config.MuzzleOffsetX
	return Vector3.new(x, Config.GroundLevel + Config.MuzzleHeight, -(Config.GapWidth / 2))
end

return Config
