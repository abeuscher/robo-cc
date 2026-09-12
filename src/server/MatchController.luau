-- The state machine. Tracks connected players in join order, assigns Builder /
-- Attacker, positions their characters, and broadcasts StateChanged. Runs the
-- full round loop: BUILD (ConfirmBuild releases the wall and grants
-- ShotsPerTurn) -> ATTACK (each shot consumed through consumeShot(); a
-- PrincessMonitor kill can end the phase early too) -> RESOLVE (a settle beat,
-- then decide the round and broadcast RoundResult) -> SWAP (flip roles, reset
-- the arena/blocks/projectiles, back to BUILD) for Config.RoundsPerMatch
-- rounds, then broadcast MatchResult and hold. Solo-permissive: with one
-- player that player is the Builder and the BUILD loop stays fully usable
-- (ATTACK just never completes without an Attacker to fire).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Remotes = require(ReplicatedStorage.Shared.Remotes)

local Arena = require(script.Parent.Arena)
local BlockManager = require(script.Parent.BlockManager)
local PrincessMonitor = require(script.Parent.PrincessMonitor)

local MatchController = {}

local function initialRemaining()
	local counts = {}
	for _, typeDef in Config.BlockTypes do
		counts[typeDef.Name] = typeDef.Count
	end
	return counts
end

local joinOrder = {}
local roundResetHooks = {}
local state = {
	phase = "BUILD",
	roles = nil,
	blocksRemaining = initialRemaining(),
	shotsRemaining = 0,
	round = 1,
	score = {}, -- UserId -> rounds won
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

local function broadcast()
	Remotes.StateChanged:FireAllClients({
		phase = state.phase,
		roles = state.roles,
		blocksRemaining = state.blocksRemaining,
		shotsRemaining = state.shotsRemaining,
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

-- BUILD setup for a round: reposition the Princess, clear any live
-- projectiles, reset the block queue, and grant a fresh block budget. Used
-- both for round 1 (from start()) and after every SWAP.
local function startRound()
	Arena.resetRound()
	runRoundResetHooks()
	BlockManager.resetQueue()
	state.blocksRemaining = initialRemaining()
	state.phase = "BUILD"
	broadcast()
	repositionAll()
end

-- Best of RoundsPerMatch, two players only (same assumption the rest of the
-- module makes). Higher score wins; equal scores are a tie (winner = nil).
local function finishMatch()
	local p1, p2 = joinOrder[1], joinOrder[2]
	local s1 = p1 and (state.score[p1.UserId] or 0) or 0
	local s2 = p2 and (state.score[p2.UserId] or 0) or 0
	local winnerUserId = nil
	if s1 > s2 then
		winnerUserId = p1.UserId
	elseif s2 > s1 and p2 then
		winnerUserId = p2.UserId
	end
	Remotes.MatchResult:FireAllClients({ winner = winnerUserId, score = state.score })
	print(string.format("[server] MATCH complete -> winner %s", tostring(winnerUserId)))
end

local function swapRoles()
	state.roles.builder, state.roles.attacker = state.roles.attacker, state.roles.builder
	state.round += 1
	startRound()
	print(string.format("[server] SWAP -> round %d", state.round))
end

-- Decide the round once PrincessMonitor's state is settled: dead means the
-- Attacker wins, survived means the Builder does. Tallies the score, then
-- either ends the match or swaps roles into the next round.
local function finishRound()
	local dead = PrincessMonitor.isDead()
	local reason = if dead then PrincessMonitor.reason() else "survived"
	local winnerRole = if dead then "Attacker" else "Builder"
	PrincessMonitor.disarm()

	local winnerUserId = state.roles[string.lower(winnerRole)]
	state.score[winnerUserId] = (state.score[winnerUserId] or 0) + 1

	Remotes.RoundResult:FireAllClients({ winner = winnerRole, reason = reason })
	print(string.format("[server] RESOLVE: round %d -> %s wins (%s)", state.round, winnerRole, reason))

	if state.round >= Config.RoundsPerMatch then
		finishMatch()
	else
		swapRoles()
	end
end

-- Enters RESOLVE and waits Config.ResolveSettleTime for physics to settle
-- (a last-shot topple can still kill the Princess after the shot itself
-- missed) before finishRound() reads the outcome. Guarded so a kill and the
-- last shot landing at the same moment only trigger this once.
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
	PrincessMonitor.arm()
	broadcast()
	print(string.format("[server] BUILD confirmed, phase -> ATTACK (%d shots)", state.shotsRemaining))
end

local function onPrincessDeath()
	beginResolve()
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

function MatchController.notifyBlocksRemaining(remaining)
	state.blocksRemaining = remaining
	broadcast()
end

function MatchController.confirmBuild(player)
	if state.phase ~= "BUILD" or not MatchController.isBuilder(player) then
		return
	end
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

	PrincessMonitor.onDeath(onPrincessDeath)

	Remotes.StartRequested.OnServerEvent:Connect(function(player)
		print(string.format("[server] StartRequested from %s (%d)", player.Name, player.UserId))
		broadcast()
	end)

	startRound()
end

return MatchController
