-- Shared type definitions. Phase, Role and the BUILD payloads are used this
-- session; the shot payload is defined now and consumed when ATTACK lands.

export type Phase = "BUILD" | "ATTACK" | "RESOLVE" | "SWAP"

export type Role = "Builder" | "Attacker"

export type BlockType = "Standard" | "Wide"

export type Weapon = "Ballista" | "Catapult"

export type PlacePayload = {
	blockId: number,
	cell: Vector2, -- bottom-left anchor cell of the footprint
	rotated: boolean, -- long axis vertical (Wide only)
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
	Standard: number,
	Wide: number,
}

export type StatePayload = {
	phase: Phase,
	roles: Roles?,
	blocksRemaining: BlocksRemaining,
	shotsRemaining: number,
	round: number,
}

return {}
