-- Handles the BUILD-phase remotes. Every handler re-validates role, phase and
-- limits -- the client sends intent only. Grid occupancy lives here and is
-- authoritative: one entry per covered cell, keyed by "col,row". A block
-- covers every cell of its shape, rotated 0-3 quarter-turns.

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

local function typeDefByName(name)
	for _, def in Config.BlockTypes do
		if def.Name == name then
			return def
		end
	end
	return nil
end

-- Drop every occupancy entry that points at this block.
local function releaseCells(blockId)
	for cellKey, id in occupancy do
		if id == blockId then
			occupancy[cellKey] = nil
		end
	end
end

local function notify()
	MatchController.notifyBlocksRemaining(BlockManager.remainingByType())
end

-- payload: { blockId: number, cell: Vector2 (bottom-left anchor), rotation: number (0-3) }
local function onPlaceBlock(player, payload)
	if not canBuild(player) then
		return
	end
	if typeof(payload) ~= "table" then
		return
	end
	local blockId = payload.blockId
	local cell = payload.cell
	if typeof(blockId) ~= "number" or typeof(cell) ~= "Vector2" then
		return
	end

	local entry = BlockManager.get(blockId)
	if not entry then
		return
	end
	local typeDef = typeDefByName(entry.typeName)
	if not typeDef then
		return
	end

	local rotation = tonumber(payload.rotation) or 0
	rotation = math.floor(rotation) % 4
	local anchor = Vector2.new(math.floor(cell.X), math.floor(cell.Y))
	local cells = GridUtil.coveredCells(typeDef.Shape, anchor, rotation)

	for _, c in cells do
		if not GridUtil.isInside(c) then
			return
		end
		local occupant = occupancy[key(c)]
		if occupant and occupant ~= blockId then
			return
		end
	end

	releaseCells(blockId)
	for _, c in cells do
		occupancy[key(c)] = blockId
	end

	local span = GridUtil.rotatedSpan(typeDef.Shape, rotation)
	local centre = GridUtil.cellToWorld(Config.BuildZoneOrigin, GridUtil.footprintCentre(anchor, span))
	BlockManager.moveToWall(blockId, centre, rotation)
	notify()
end

local function onPickupBlock(player, blockId)
	if not canBuild(player) then
		return
	end
	if typeof(blockId) ~= "number" then
		return
	end
	local entry = BlockManager.get(blockId)
	if not entry or not entry.placed then
		return
	end
	releaseCells(blockId)
	BlockManager.returnToPile(blockId)
	notify()
end

local function onConfirmBuild(player)
	MatchController.confirmBuild(player)
end

-- Blocks get fresh, reused ids each round (BlockManager.spawnAll() resets its
-- own counter), so stale cell->blockId entries from the previous round would
-- otherwise misjudge occupancy. Registered as a round-reset hook.
function BuildManager.resetOccupancy()
	occupancy = {}
end

function BuildManager.start()
	Remotes.PlaceBlock.OnServerEvent:Connect(onPlaceBlock)
	Remotes.PickupBlock.OnServerEvent:Connect(onPickupBlock)
	Remotes.ConfirmBuild.OnServerEvent:Connect(onConfirmBuild)
	MatchController.onRoundReset(BuildManager.resetOccupancy)
end

return BuildManager
