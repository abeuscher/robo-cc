-- Every tunable in one table. Nothing in game logic should hardcode a number
-- that belongs here. Values are first-pass guesses; expect to tune by feel.

local BLOCK_SIZE = Vector3.new(3.75, 3.75, 3.75) -- 3x the original 1.25 (session 009 balance experiment)

-- Piece generation (session 008): each of a round's pieces fills a random
-- 3-6 cells of a 3x3 area, chosen at random. No two pieces are alike, and
-- there's no roster of named types anymore -- just a shape and a count.
local PIECE_GRID_SIZE = 3 -- the cell area a piece's shape is drawn from (3x3)
local PIECE_MIN_CELLS = 3
local PIECE_MAX_CELLS = 6
local PIECE_COUNT = 10 -- reduced from 9 to 6, then back up to 8 (session 009), then to 10 (session 011 playtest feedback)

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

-- Guard piece (session 010): a second, fixed physical obstacle between the
-- wall and the Princess, so a broken wall doesn't leave her a free target.
-- Sized bigger than her own footprint (below, in Arena) so a shot landing on
-- or near her is likely to meet the guard first. Sits GUARD_CLEARANCE studs
-- in front of her, on the same Z axis PrincessDistance already uses.
local GUARD_SIZE = Vector3.new(BLOCK_SIZE.X * 1.5, BLOCK_SIZE.Y * 1.5, BLOCK_SIZE.Z)
local GUARD_CLEARANCE = 6
local GUARD_DISTANCE = PRINCESS_DISTANCE - GUARD_CLEARANCE

-- Builder's timed shield (session 011): a once-per-round, Builder-activated
-- physical barrier during ATTACK, timed against an incoming shot rather than
-- left up passively. Sits just in front of the Princess -- closer to her than
-- the guard, so it's a last line of defense if the guard's already been
-- knocked aside. Unlike the guard, it never unanchors: an unanchored shield
-- could itself get shoved into the Princess by a heavy hit and defeat the
-- point, so staying anchored for its whole (short) life is a deliberate,
-- scoped exception to "everything is real physics."
local SHIELD_SIZE = Vector3.new(BLOCK_SIZE.X * 3, BLOCK_SIZE.Y * 2.5, BLOCK_SIZE.Z)
local SHIELD_CLEARANCE = 3
local SHIELD_DISTANCE = PRINCESS_DISTANCE - SHIELD_CLEARANCE

-- Fixed, scripted shot order -- the Attacker no longer chooses a weapon
-- (session 007, overrides spec's free choice). ShotsPerTurn derives from this
-- so the two can never drift apart. One more of each added (session 012
-- playtest feedback: still too hard to bring a wall down even after the
-- catapult mass retune) -- kept the original shape (catapults first to break
-- the wall, ballista last to finish off what's exposed), just longer.
local SHOT_SEQUENCE = { "Catapult", "Catapult", "Catapult", "Ballista", "Ballista" }

-- Scoring (session 012): replaces the binary round win/loss with points. The
-- Builder scores per surviving wall piece -- body-level, not by original
-- placement, since one placement can already split into several independent
-- bodies (session 008) and BlockManager already tracks bodies flatly, not
-- grouped by placement. The Attacker scores a fixed bonus for toppling the
-- Princess, tuned to roughly a quarter of the *theoretical* maximum wall
-- score -- worst-case fragmentation, every piece splitting into single-cell
-- bodies (PieceCount * PieceMaxCells) -- not the typical actual body count,
-- which is usually lower once random pieces fuse into fewer, larger bodies.
local POINTS_PER_SURVIVING_BLOCK = 1
local MAX_WALL_SCORE = PIECE_COUNT * PIECE_MAX_CELLS * POINTS_PER_SURVIVING_BLOCK
local PRINCESS_KILL_POINTS = math.round(MAX_WALL_SCORE / 4)

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

	-- Guard piece (session 010): a fixed second obstacle, not a Builder-placed
	-- piece. Reuses BlockFriction/BlockRestitution and the wall's own density
	-- (in Arena) so it behaves exactly like a wall block -- knock it far
	-- enough and it's out of the way, no special-cased "destroyed" state.
	GuardSize = GUARD_SIZE,
	GuardDistance = GUARD_DISTANCE, -- studs behind the build zone, same axis as PrincessDistance

	-- Builder shield (session 011): a timed physical barrier, once per round,
	-- Builder-activated during ATTACK. Stays anchored for its whole duration --
	-- see note above SHIELD_SIZE.
	ShieldSize = SHIELD_SIZE,
	ShieldDistance = SHIELD_DISTANCE, -- studs behind the build zone, same axis as PrincessDistance/GuardDistance
	ShieldDuration = 0.5, -- seconds the shield stays up once activated

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
	-- Angle range shifted down (session 011 playtest feedback: walls couldn't
	-- be built tall enough to matter against the old 20-70 range). For a fixed
	-- target range, arc height scales with tan(angle), so this drops the
	-- default midpoint from 45deg (tan 1.0) to 32.5deg (tan ~0.64) -- roughly
	-- two-thirds the peak height at the same distance.
	CatapultMinAngle = 15, -- degrees
	CatapultMaxAngle = 50,
	CatapultProjectileSize = Vector3.new(1.6, 1.6, 1.6),
	-- 35 -> 43.75 (+25%, session 012 playtest feedback: not knocking down walls
	-- well enough). Mass, not force/velocity -- momentum on impact scales with
	-- mass, and mass doesn't affect trajectory under Roblox's gravity (same
	-- principle as the ballista's speed-only tuning above), so this hits harder
	-- without moving where a given aim/force actually lands.
	CatapultProjectileMass = 43.75,
	CatapultProjectileFriction = 0.5,
	CatapultProjectileRestitution = 0.45,

	-- Scoring (session 012)
	PointsPerSurvivingBlock = POINTS_PER_SURVIVING_BLOCK,
	PrincessKillPoints = PRINCESS_KILL_POINTS, -- ~1/4 of the theoretical max wall score
	BlockTopplingAngle = 60, -- degrees a placed body may drift from how it was placed before it no longer counts as "survived" -- mirrors PrincessTopplingAngle's mechanism (angle vs. a reference orientation), tuned separately since a wall piece leaning partway over reads differently than the Princess needing to go fully flat

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
