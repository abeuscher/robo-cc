-- Shared type definitions. Phase, Role and the BUILD payloads are used this
-- session; the shot payload is defined now and consumed when ATTACK lands.

export type Phase = "BUILD" | "ATTACK" | "RESOLVE" | "SWAP"

export type Role = "Builder" | "Attacker"

export type BlockType = "LPiece"

export type Weapon = "Ballista" | "Catapult"

export type PlacePayload = {
	blockId: number,
	cell: Vector2, -- bottom-left anchor cell of the (rotated) footprint's bounding box
	rotation: number, -- 0-3, quarter turns
}

export type ShotPayload = {
	weapon: Weapon,
	direction: Vector3,
	force: number,
	angle: number,
}

export type Roles = {
	builder: number,
	attacker: number,
}

export type BlocksRemaining = {
	LPiece: number,
}

export type Score = { [number]: number } -- UserId -> rounds won

export type StatePayload = {
	phase: Phase,
	roles: Roles?,
	blocksRemaining: BlocksRemaining,
	shotsRemaining: number,
	round: number,
	score: Score,
}

export type RoundResult = {
	winner: Role,
	reason: "survived" | "direct" | "crushed",
}

export type MatchResult = {
	winner: number?, -- UserId; nil on a tie
	score: Score,
}

return {}
