-- Shared type definitions. Phase, Role and the BUILD payloads are used this
-- session; the shot payload is defined now and consumed when ATTACK lands.

export type Phase = "BUILD" | "ATTACK" | "RESOLVE" | "SWAP"

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

export type Roles = {
	builder: number,
	attacker: number,
}

export type Score = { [number]: number } -- UserId -> cumulative points

export type StatePayload = {
	phase: Phase,
	roles: Roles?,
	blocksRemaining: number,
	shotsRemaining: number,
	currentWeapon: Weapon?, -- mandated weapon for the shot about to fire; nil outside ATTACK
	currentShape: PieceShape?, -- the held piece's shape; nil outside BUILD
	shieldAvailable: boolean, -- whether the Builder's once-per-round shield is still unused
	round: number,
	score: Score,
}

export type RoundResult = {
	reason: "survived" | "toppled",
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
