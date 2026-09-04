-- The state machine. Tracks connected players in join order, assigns Builder /
-- Attacker, positions their characters, and broadcasts StateChanged. This
-- session runs a single BUILD phase; on ConfirmBuild from the Builder it flips
-- to ATTACK and holds. Solo-permissive: with one player that player is the
-- Builder and the BUILD loop stays fully usable.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Remotes = require(ReplicatedStorage.Shared.Remotes)

local MatchController = {}

local function initialRemaining()
	local counts = {}
	for _, typeDef in Config.BlockTypes do
		counts[typeDef.Name] = typeDef.Count
	end
	return counts
end

local joinOrder = {}
local state = {
	phase = "BUILD",
	roles = nil,
	blocksRemaining = initialRemaining(),
	round = 1,
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
		round = state.round,
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

function MatchController.getPhase()
	return state.phase
end

function MatchController.isBuilder(player)
	return state.roles ~= nil and state.roles.builder == player.UserId
end

function MatchController.notifyBlocksRemaining(remaining)
	state.blocksRemaining = remaining
	broadcast()
end

function MatchController.confirmBuild(player)
	if state.phase ~= "BUILD" or not MatchController.isBuilder(player) then
		return
	end
	state.phase = "ATTACK"
	broadcast()
	print("[server] BUILD confirmed, phase -> ATTACK (holding)")
end

function MatchController.start()
	Players.PlayerAdded:Connect(addPlayer)
	Players.PlayerRemoving:Connect(removePlayer)
	for _, player in Players:GetPlayers() do
		addPlayer(player)
	end

	Remotes.StartRequested.OnServerEvent:Connect(function(player)
		print(string.format("[server] StartRequested from %s (%d)", player.Name, player.UserId))
		broadcast()
	end)
end

return MatchController
