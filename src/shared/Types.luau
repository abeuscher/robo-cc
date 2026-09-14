-- Shared type definitions. Phase, Role and the BUILD payloads are used this
-- session; the shot payload is defined now and consumed when ATTACK lands.

-- POSITION (session 015): a short beat between BUILD and ATTACK where the
-- Builder relocates the Flag once, after the wall is confirmed.
export type Phase = "BUILD" | "POSITION" | "ATTACK" | "RESOLVE" | "SWAP"

export type Role = "Builder" | "Attacker"

export type Weapon = "Ballista" | "Catapult"

export type PieceShape = { Vector2 } -- local (column, row) cell offsets, normalized to min (0, 0)

export type PlacePayload = {
	cell: Vector2, -- bottom-left anchor cell of the (rotated/flipped) footprint's bounding box
	rotation: number, -- 0-3, quarter turns
	flipped: boolean, -- mirrored left-right before rotation is applied
}

export type ShotPayload = {
	direction: Vector3,
	force: number,
	angle: number,
	spin: number,
}

export type RelocatePayload = {
	position: Vector3, -- world point clicked; only X/Z matter, server clamps into the placement box
}

export type Roles = {
	builder: number,
	attacker: number,
}

export type Seats = {
	one: number?,
	two: number?,
}

export type Score = { [number]: number } -- UserId -> cumulative points

export type StatePayload = {
	phase: Phase,
	roles: Roles?,
	players: Seats, -- stable Player 1 / Player 2 by join order, unlike roles (flips every SWAP)
	blocksRemaining: number,
	shotsRemaining: number,
	currentWeapon: Weapon?, -- mandated weapon for the shot about to fire; nil outside ATTACK
	currentShape: PieceShape?, -- the held piece's shape; nil outside BUILD
	shieldAvailable: boolean, -- whether the Builder's once-per-round shield is still unused
	flagRevealed: boolean, -- session 015: whether the Flag has been struck yet this round (either cause) -- drives the Attacker-only concealment client-side
	round: number,
	score: Score,
}

export type RoundResult = {
	-- collapsed: a wall piece fell onto the Flag -- reveals it, scores nothing.
	-- struck: a direct projectile hit -- reveals it and scores FlagKillPoints.
	reason: "survived" | "collapsed" | "struck",
	piecesSurvived: number,
	piecesTotal: number,
	builderPoints: number,
	attackerPoints: number,
	winner: Role?, -- higher-scoring role this round; nil on a tie
}

export type MatchResult = {
	winner: number?, -- UserId; nil on a tie
	score: Score,
}

return {}
