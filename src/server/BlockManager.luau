-- Owns the block parts. Each round's queue is built from Config.BlockTypes
-- (one entry per Count, flattened in issue order); BuildManager reads the
-- current one via currentTypeDef() and calls placeCurrent() once it validates
-- a placement. A block is a UnionOperation built from its shape's cells at
-- placement time -- there's no physical part before that, so no pile to
-- manage. One density for all blocks, so a 4-cell piece weighs 4x a single
-- sub-cube at equal density. Blocks stay anchored through BUILD; releaseAll()
-- unanchors the wall into server-owned physics at ATTACK start.
--
-- A UnionOperation's own CFrame after UnionAsync doesn't necessarily sit at
-- the shape's bounding-box centre, and Roblox doesn't document exactly where
-- it lands -- so each block's pivot offset is measured once at build time
-- (shape space == world space, identity rotation) and applied when placing it
-- by its actual footprint centre: `part.CFrame = desiredPose * pivotDelta`.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage.Shared.Config)
local GridUtil = require(ReplicatedStorage.Shared.GridUtil)
local Arena = require(script.Parent.Arena)

local BlockManager = {}

local BLOCK_COLOR = Color3.fromRGB(150, 150, 150)
-- Density from one sub-cube's mass and volume, applied to every block.
local DENSITY = Config.BlockMass / (Config.BlockSize.X * Config.BlockSize.Y * Config.BlockSize.Z)
local PROPS = PhysicalProperties.new(DENSITY, Config.BlockFriction, Config.BlockRestitution)

-- Every block placed so far this round, for releaseAll()/resetQueue() to walk.
local placedParts = {}
local nextId = 1

-- This round's pieces still to come, in issue order; queue[queuePos] is the
-- one the Builder currently holds.
local queue = {}
local queuePos = 1

local function blocksFolder()
	local root = Arena.root()
	local existing = root:FindFirstChild("Blocks")
	if existing then
		return existing
	end
	local folder = Instance.new("Folder")
	folder.Name = "Blocks"
	folder.Parent = root
	return folder
end

-- Builds one sub-cube per shape cell, positioned in "shape space" -- the
-- shape's own bounding-box centre at the world origin, identity rotation --
-- then unions them into a single part. Temp parts are cleaned up before
-- returning; the caller repositions the result.
local function buildUnion(shape)
	local span = GridUtil.shapeSpan(shape)
	local halfWidth = span.X * Config.BlockSize.X / 2
	local halfHeight = span.Y * Config.BlockSize.Y / 2

	local temp = Instance.new("Folder")
	temp.Name = "BlockBuildTemp"
	temp.Parent = Workspace

	local cubes = {}
	for _, cell in shape do
		local cube = Instance.new("Part")
		cube.Size = Config.BlockSize
		cube.Anchored = true
		cube.CFrame = CFrame.new(
			(cell.X + 0.5) * Config.BlockSize.X - halfWidth,
			(cell.Y + 0.5) * Config.BlockSize.Y - halfHeight,
			0
		)
		cube.Parent = temp
		table.insert(cubes, cube)
	end

	local first = table.remove(cubes, 1)
	local union = first:UnionAsync(cubes)
	temp:Destroy()
	return union
end

-- Round reset: destroys every block placed last round and rebuilds the issue
-- queue from Config.BlockTypes.
function BlockManager.resetQueue()
	for _, part in placedParts do
		part:Destroy()
	end
	placedParts = {}
	nextId = 1

	queue = {}
	for _, typeDef in Config.BlockTypes do
		for _ = 1, typeDef.Count do
			table.insert(queue, typeDef)
		end
	end
	queuePos = 1
end

-- The type of the piece the Builder currently holds, or nil once the queue is
-- exhausted.
function BlockManager.currentTypeDef()
	return queue[queuePos]
end

-- How many pieces of each type are still left in the queue (including the
-- current one).
function BlockManager.remainingCount()
	local counts = {}
	for _, typeDef in Config.BlockTypes do
		counts[typeDef.Name] = 0
	end
	for i = queuePos, #queue do
		local name = queue[i].Name
		counts[name] += 1
	end
	return counts
end

-- Builds and places the current queued piece at `centre` (the footprint's
-- bounding-box centre in world space), mirrored left-right if `flipped` and
-- then rotated by `rotation` quarter-turns, advancing the queue. Returns false
-- if the queue is already empty. The mirror has to happen at the geometry
-- level (which cells buildUnion actually fills) -- rotation alone, being a
-- rigid CFrame transform, can never produce a shape's mirror image.
function BlockManager.placeCurrent(centre, rotation, flipped)
	local typeDef = queue[queuePos]
	if not typeDef then
		return false
	end

	local shape = if flipped then GridUtil.mirrorShape(typeDef.Shape) else typeDef.Shape
	local union = buildUnion(shape)
	local pivotDelta = union.CFrame

	union.Name = typeDef.Name .. "Block"
	union.Anchored = true
	union.UsePartColor = true
	union.Color = BLOCK_COLOR
	union.Material = Enum.Material.Plastic
	union.CustomPhysicalProperties = PROPS
	union.CFrame = CFrame.new(centre) * CFrame.Angles(0, 0, math.rad(90 * rotation)) * pivotDelta
	union:SetAttribute("BlockId", nextId)
	union:SetAttribute("BlockType", typeDef.Name)
	union.Parent = blocksFolder()

	nextId += 1
	table.insert(placedParts, union)
	queuePos += 1
	return true
end

-- ATTACK-phase transition. Every block on the wall becomes server-owned
-- physics: unanchor first, then SetNetworkOwner(nil) (it errors on an
-- anchored part). Everything here was placed through placeCurrent(), so
-- there's nothing unplaced left over to clean up instead.
function BlockManager.releaseAll()
	for _, part in placedParts do
		part.Anchored = false
		part:SetNetworkOwner(nil)
	end
end

return BlockManager
