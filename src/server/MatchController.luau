-- The state machine. Tracks connected players in join order, assigns Builder /
-- Attacker, positions their characters, and broadcasts StateChanged. Runs the
-- full round loop: BUILD (ConfirmBuild releases the wall) -> POSITION
-- (session 015: a short beat where the Builder relocates the Flag once, via
-- RelocateFlag) -> ATTACK (each shot consumed through consumeShot(); a Flag
-- hit no longer ends the phase early -- session 015's hit-or-not model has
-- nothing left to end for) -> RESOLVE (a settle beat so the last shot
-- actually lands before deciding the round, then broadcast RoundResult and
-- hold on it -- Config.RoundEndHoldTime, or sooner if a player fires
-- ContinueRequested -- so the outcome and camera stay put instead of cutting
-- straight to the next round) -> SWAP (flip roles, reset the
-- arena/blocks/projectiles, back to BUILD) for Config.RoundsPerMatch rounds,
-- then broadcast MatchResult and hold. Solo-permissive: with one player that
-- player is the Builder and the BUILD loop stays fully usable (ATTACK just
-- never completes without an Attacker to fire).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Remotes = require(ReplicatedStorage.Shared.Remotes)

local Arena = require(script.Parent.Arena)
local BlockManager = require(script.Parent.BlockManager)
local FlagMonitor = require(script.Parent.FlagMonitor)

local MatchController = {}

local joinOrder = {}
local roundResetHooks = {}
local pendingContinue = nil
local state = {
	phase = "BUILD",
	roles = nil,
	blocksRemaining = Config.PieceCount,
	shotsRemaining = 0,
	shieldAvailable = true,
	round = 1,
	score = {}, -- UserId -> cumulative points (session 012)
}

local function rebuildRoles()
	if #joinOrder == 0 then
		state.roles = nil
		return
	end
	state.roles = {
		builder = joinOrder[1].UserId,
		attacker = joinOrder[2] and joinOrder[2].UserId or nil,
	}
end

-- The weapon mandated for the shot about to be fired, derived from
-- Config.ShotSequence and how many shots remain -- nil outside ATTACK. The
-- shot index counts up as shotsRemaining counts down.
local function currentWeapon()
	if state.phase ~= "ATTACK" then
		return nil
	end
	return Config.ShotSequence[#Config.ShotSequence - state.shotsRemaining + 1]
end

-- The shape of the piece the Builder currently holds -- nil outside BUILD.
-- Randomized per piece (session 008), so the client can no longer look this
-- up from a shared Config constant; it has to arrive on every broadcast.
local function currentShape()
	if state.phase ~= "BUILD" then
		return nil
	end
	return BlockManager.currentShape()
end

-- Stable seat identity by join order -- "Player 1" / "Player 2" -- separate
-- from state.roles, which flips every SWAP. Lets the HUD show a fixed score
-- readout per person across the whole match instead of one that swaps labels
-- with their role.
local function seats()
	return {
		one = joinOrder[1] and joinOrder[1].UserId or nil,
		two = joinOrder[2] and joinOrder[2].UserId or nil,
	}
end

local function broadcast()
	Remotes.StateChanged:FireAllClients({
		phase = state.phase,
		roles = state.roles,
		players = seats(),
		blocksRemaining = state.blocksRemaining,
		shotsRemaining = state.shotsRemaining,
		currentWeapon = currentWeapon(),
		currentShape = currentShape(),
		shieldAvailable = state.shieldAvailable,
		flagRevealed = FlagMonitor.isRevealed(),
		round = state.round,
		score = state.score,
	})
end

local function standFor(player)
	local halfGap = Config.GapWidth / 2
	if state.roles and state.roles.builder == player.UserId then
		local pos = Vector3.new(0, Config.GroundLevel + 3, Config.BuildZoneOrigin.Z + 8)
		return CFrame.lookAt(pos, pos - Vector3.zAxis)
	end
	local pos = Vector3.new(0, Config.GroundLevel + 3, -(halfGap + 2))
	return CFrame.lookAt(pos, pos + Vector3.zAxis)
end

local function positionCharacter(player, character)
	character = character or player.Character
	if not character then
		return
	end
	character:WaitForChild("HumanoidRootPart", 5)
	character:PivotTo(standFor(player))
end

local function repositionAll()
	for _, player in joinOrder do
		positionCharacter(player)
	end
end

local function addPlayer(player)
	if table.find(joinOrder, player) then
		return
	end
	table.insert(joinOrder, player)
	player.CharacterAdded:Connect(function(character)
		positionCharacter(player, character)
	end)
	rebuildRoles()
	broadcast()
	positionCharacter(player)
end

local function removePlayer(player)
	local index = table.find(joinOrder, player)
	if not index then
		return
	end
	table.remove(joinOrder, index)
	rebuildRoles()
	broadcast()
end

local function runRoundResetHooks()
	for _, callback in roundResetHooks do
		callback()
	end
end

-- BUILD setup for a round: reposition the Flag back to default, clear any
-- live projectiles, reset the block queue, and grant a fresh block budget.
-- Used both for round 1 (from start()) and after every SWAP.
local function startRound()
	Arena.resetRound()
	runRoundResetHooks()
	BlockManager.resetQueue()
	state.blocksRemaining = Config.PieceCount
	state.shieldAvailable = true
	state.phase = "BUILD"
	broadcast()
	repositionAll()
end

-- Both players' cumulative scores, defaulting to 0 for anyone who hasn't
-- scored yet (or isn't there, in the solo-permissive case).
local function scores()
	local p1, p2 = joinOrder[1], joinOrder[2]
	local s1 = p1 and (state.score[p1.UserId] or 0) or 0
	local s2 = p2 and (state.score[p2.UserId] or 0) or 0
	return s1, s2
end

-- Best of RoundsPerMatch, two players only (same assumption the rest of the
-- module makes). Only ever called once scores() are unequal (see
-- shouldEndMatch) -- sudden death means a genuine tie never reaches here.
local function finishMatch()
	local p1, p2 = joinOrder[1], joinOrder[2]
	local s1, s2 = scores()
	local winnerUserId = nil
	if s1 > s2 then
		winnerUserId = p1.UserId
	elseif s2 > s1 and p2 then
		winnerUserId = p2.UserId
	end
	Remotes.MatchResult:FireAllClients({ winner = winnerUserId, score = state.score })
	print(string.format("[server] MATCH complete -> winner %s", tostring(winnerUserId)))
end

-- The match ends after RoundsPerMatch rounds, unless the score is tied --
-- then it keeps going one round at a time (sudden death) until someone is
-- actually ahead. Below RoundsPerMatch it's always another round regardless
-- of score.
local function shouldEndMatch()
	if state.round < Config.RoundsPerMatch then
		return false
	end
	local s1, s2 = scores()
	return s1 ~= s2
end

local function swapRoles()
	state.roles.builder, state.roles.attacker = state.roles.attacker, state.roles.builder
	state.round += 1
	startRound()
	print(string.format("[server] SWAP -> round %d", state.round))
end

-- Holds `advance` (swapRoles or finishMatch) until Config.RoundEndHoldTime
-- elapses or a player fires ContinueRequested, whichever comes first -- so
-- the outcome stays on screen (camera included, since AttackCamera now stays
-- engaged through RESOLVE) instead of cutting straight to the next round.
-- Guarded so the timer and a click can never both fire it.
local function awaitContinue(advance)
	local firedAlready = false
	local function proceed()
		if firedAlready then
			return
		end
		firedAlready = true
		pendingContinue = nil
		advance()
	end
	pendingContinue = proceed
	task.delay(Config.RoundEndHoldTime, proceed)
end

-- Decide the round once FlagMonitor's state is settled (session 012: points,
-- not a single deterministic winner). The Builder scores per surviving wall
-- piece; the Attacker scores a fixed bonus only for a direct projectile hit
-- on the Flag (session 015) -- a wall-collapse reveal earns nothing. Both add
-- into state.score (cumulative across the match, keyed by UserId --
-- unaffected by the SWAP that follows). Reports the breakdown, then holds
-- (see awaitContinue) before ending the match or swapping roles.
local function finishRound()
	local reason = FlagMonitor.reason()
	local scored = FlagMonitor.scored()
	FlagMonitor.disarm()

	local piecesSurvived = BlockManager.survivingCount()
	local piecesTotal = BlockManager.totalCount()
	local builderPoints = piecesSurvived * Config.PointsPerSurvivingBlock
	local attackerPoints = if scored then Config.FlagKillPoints else 0

	local builderUserId = state.roles.builder
	local attackerUserId = state.roles.attacker
	state.score[builderUserId] = (state.score[builderUserId] or 0) + builderPoints
	state.score[attackerUserId] = (state.score[attackerUserId] or 0) + attackerPoints

	local winnerRole = nil
	if builderPoints > attackerPoints then
		winnerRole = "Builder"
	elseif attackerPoints > builderPoints then
		winnerRole = "Attacker"
	end

	Remotes.RoundResult:FireAllClients({
		reason = reason,
		piecesSurvived = piecesSurvived,
		piecesTotal = piecesTotal,
		builderPoints = builderPoints,
		attackerPoints = attackerPoints,
		winner = winnerRole,
	})
	print(string.format(
		"[server] RESOLVE: round %d -> Builder %d pts (%d/%d pieces), Attacker %d pts (%s)",
		state.round,
		builderPoints,
		piecesSurvived,
		piecesTotal,
		attackerPoints,
		reason
	))

	awaitContinue(if shouldEndMatch() then finishMatch else swapRoles)
end

-- Enters RESOLVE and waits Config.ResolveSettleTime for physics to settle (a
-- last-shot wall collapse can still reach the Flag after the shot itself
-- missed) before finishRound() reads the outcome. Only ever reached by the
-- shot counter hitting zero now (session 015: a Flag hit doesn't end ATTACK
-- early the way a Princess kill used to -- there's no "she's dead" moment
-- left to cut away to, just a hit-or-not scored at RESOLVE).
local function beginResolve()
	if state.phase ~= "ATTACK" then
		return
	end
	state.phase = "RESOLVE"
	broadcast()
	task.delay(Config.ResolveSettleTime, finishRound)
end

local function beginAttack()
	state.phase = "ATTACK"
	state.shotsRemaining = Config.ShotsPerTurn
	BlockManager.releaseAll()
	FlagMonitor.arm()
	broadcast()
	print(string.format("[server] Flag positioned, phase -> ATTACK (%d shots)", state.shotsRemaining))
end

-- BUILD -> POSITION transition (session 015): the wall is confirmed, but
-- ATTACK doesn't start until the Builder relocates the Flag (relocateFlag()
-- below moves straight on to beginAttack() once it does).
local function beginPosition()
	state.phase = "POSITION"
	broadcast()
	print("[server] BUILD confirmed, phase -> POSITION")
end

function MatchController.getPhase()
	return state.phase
end

function MatchController.isBuilder(player)
	return state.roles ~= nil and state.roles.builder == player.UserId
end

function MatchController.isAttacker(player)
	return state.roles ~= nil and state.roles.attacker == player.UserId
end

-- The weapon mandated for the shot about to fire. Callers must read this
-- before consumeShot(), which is what advances the shot index.
function MatchController.currentWeapon()
	return currentWeapon()
end

-- Spend one ATTACK shot. Returns false (no shot fired) outside ATTACK or when
-- none remain. Broadcasts the new count; at zero it moves to RESOLVE.
function MatchController.consumeShot()
	if state.phase ~= "ATTACK" or state.shotsRemaining <= 0 then
		return false
	end
	state.shotsRemaining -= 1
	broadcast()
	if state.shotsRemaining == 0 then
		beginResolve()
	end
	return true
end

-- Spend the Builder's once-per-round shield. Returns false (nothing happens)
-- outside ATTACK, for anyone but the Builder, or once it's already used this
-- round. Callers must check this before actually spawning the shield object --
-- mirrors consumeShot()'s role as the single source of truth on the count.
function MatchController.useShield(player)
	if state.phase ~= "ATTACK" or not MatchController.isBuilder(player) or not state.shieldAvailable then
		return false
	end
	state.shieldAvailable = false
	broadcast()
	return true
end

function MatchController.notifyBlocksRemaining(remaining)
	state.blocksRemaining = remaining
	broadcast()
end

function MatchController.confirmBuild(player)
	if state.phase ~= "BUILD" or not MatchController.isBuilder(player) then
		return
	end
	beginPosition()
end

-- The Builder's once-per-round Flag relocation (session 015). `payload.position`
-- is the world point they clicked on the ground; only its X and Z matter.
-- Clamped into Config.FlagPlacementMaxOffsetX/MinDistance/MaxDistance
-- server-side regardless of what the client thought was valid, then hands
-- straight off to ATTACK -- there's nothing else to wait for once the Flag is
-- placed.
function MatchController.relocateFlag(player, payload)
	if state.phase ~= "POSITION" or not MatchController.isBuilder(player) then
		return
	end
	if typeof(payload) ~= "table" or typeof(payload.position) ~= "Vector3" then
		return
	end
	local offsetX = math.clamp(payload.position.X, -Config.FlagPlacementMaxOffsetX, Config.FlagPlacementMaxOffsetX)
	local distance = math.clamp(
		payload.position.Z - Config.BuildZoneOrigin.Z,
		Config.FlagPlacementMinDistance,
		Config.FlagPlacementMaxDistance
	)
	Arena.relocateFlag(offsetX, distance)
	beginAttack()
end

-- Other services register a callback here to clean up their own live state
-- (e.g. WeaponManager despawning in-flight projectiles) each time a round
-- resets. Avoids MatchController requiring those modules back and cycling.
function MatchController.onRoundReset(callback)
	table.insert(roundResetHooks, callback)
end

function MatchController.start()
	Players.PlayerAdded:Connect(addPlayer)
	Players.PlayerRemoving:Connect(removePlayer)
	for _, player in Players:GetPlayers() do
		addPlayer(player)
	end

	-- Broadcasts the instant the Flag is revealed, mid-turn, rather than
	-- waiting for the next unrelated state change (mirrors the pattern
	-- sessions 007/008 already established for the mandated weapon and the
	-- held shape).
	FlagMonitor.onReveal(broadcast)

	Remotes.StartRequested.OnServerEvent:Connect(function(player)
		print(string.format("[server] StartRequested from %s (%d)", player.Name, player.UserId))
		broadcast()
	end)

	Remotes.RelocateFlag.OnServerEvent:Connect(MatchController.relocateFlag)

	-- Either player can skip the post-round hold early; a stray click once
	-- nothing is pending (already advanced, or too early -- before the settle
	-- delay's finishRound() has even run) is just a no-op.
	Remotes.ContinueRequested.OnServerEvent:Connect(function()
		if pendingContinue then
			pendingContinue()
		end
	end)

	startRound()
end

return MatchController
