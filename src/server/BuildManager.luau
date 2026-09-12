-- Handles the BUILD-phase remotes. Every handler re-validates role, phase and
-- limits -- the client sends intent only. Grid occupancy lives here and is
-- authoritative: one entry per covered cell, keyed by "col,row". The Builder
-- always places the queue's current piece (BlockManager.currentTypeDef()) --
-- there's no client-chosen blockId, and no picking a placed piece back up.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Remotes = require(ReplicatedStorage.Shared.Remotes)
local GridUtil = require(ReplicatedStorage.Shared.GridUtil)

local BlockManager = require(script.Parent.BlockManager)
local MatchController = require(script.Parent.MatchController)

local BuildManager = {}

local occupancy = {}

local function key(cell)
	return string.format("%d,%d", cell.X, cell.Y)
end

local function canBuild(player)
	return MatchController.getPhase() == "BUILD" and MatchController.isBuilder(player)
end

local function notify()
	MatchController.notifyBlocksRemaining(BlockManager.remainingCount())
end

-- payload: { cell: Vector2 (bottom-left anchor), rotation: number (0-3), flipped: boolean }
local function onPlaceBlock(player, payload)
	if not canBuild(player) then
		return
	end
	if typeof(payload) ~= "table" then
		return
	end
	local cell = payload.cell
	if typeof(cell) ~= "Vector2" then
		return
	end

	local typeDef = BlockManager.currentTypeDef()
	if not typeDef then
		return
	end

	local rotation = tonumber(payload.rotation) or 0
	rotation = math.floor(rotation) % 4
	local flipped = payload.flipped == true
	local shape = if flipped then GridUtil.mirrorShape(typeDef.Shape) else typeDef.Shape
	local anchor = Vector2.new(math.floor(cell.X), math.floor(cell.Y))
	local cells = GridUtil.coveredCells(shape, anchor, rotation)

	for _, c in cells do
		if not GridUtil.isInside(c) or occupancy[key(c)] then
			return
		end
	end

	local span = GridUtil.rotatedSpan(shape, rotation)
	local centre = GridUtil.cellToWorld(Config.BuildZoneOrigin, GridUtil.footprintCentre(anchor, span))
	if not BlockManager.placeCurrent(centre, rotation, flipped) then
		return
	end

	for _, c in cells do
		occupancy[key(c)] = true
	end
	notify()
end

local function onConfirmBuild(player)
	MatchController.confirmBuild(player)
end

-- Fresh each round (BlockManager.resetQueue() clears the wall too), so stale
-- entries from the previous round would otherwise misjudge occupancy.
-- Registered as a round-reset hook.
function BuildManager.resetOccupancy()
	occupancy = {}
end

function BuildManager.start()
	Remotes.PlaceBlock.OnServerEvent:Connect(onPlaceBlock)
	Remotes.ConfirmBuild.OnServerEvent:Connect(onConfirmBuild)
	MatchController.onRoundReset(BuildManager.resetOccupancy)
end

return BuildManager
