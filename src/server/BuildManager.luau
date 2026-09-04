-- Handles the BUILD-phase remotes. Every handler re-validates role, phase and
-- limits -- the client sends intent only. Grid occupancy lives here and is
-- authoritative: one entry per covered cell, keyed by "col,row". A block can
-- cover several cells (Wide is 3 across, or 6 tall when rotated).

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

-- payload: { blockId: number, cell: Vector2 (bottom-left anchor), rotated: boolean }
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

	local rotated = payload.rotated == true and typeDef.Rotatable == true
	local anchor = Vector2.new(math.floor(cell.X), math.floor(cell.Y))
	local span = GridUtil.spanForSize(typeDef.Size, rotated)
	local cells = GridUtil.coveredCells(anchor, span)

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

	local centre = GridUtil.cellToWorld(Config.BuildZoneOrigin, GridUtil.footprintCentre(anchor, span))
	BlockManager.moveToWall(blockId, centre, rotated)
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

function BuildManager.start()
	Remotes.PlaceBlock.OnServerEvent:Connect(onPlaceBlock)
	Remotes.PickupBlock.OnServerEvent:Connect(onPickupBlock)
	Remotes.ConfirmBuild.OnServerEvent:Connect(onConfirmBuild)
end

return BuildManager
