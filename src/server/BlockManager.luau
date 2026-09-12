-- Owns the block parts. Every block from Config.BlockTypes is spawned anchored
-- at match start into its pile; placing and picking up just reposition the
-- same part between its pile and the wall. Each block is a UnionOperation
-- built from `typeDef.Shape`'s cells at spawn -- one rigid assembly per piece,
-- no welds. One density for all blocks, so a 4-cell piece weighs 4x a single
-- sub-cube at equal density. Blocks stay anchored through BUILD; releaseAll()
-- unanchors the wall into server-owned physics at ATTACK start.
--
-- A UnionOperation's own CFrame after UnionAsync doesn't necessarily sit at
-- the shape's bounding-box centre, and Roblox doesn't document exactly where
-- it lands -- so each block's `pivotDelta` is measured once at build time
-- (shape space == world space, identity rotation) and reused to place/rotate
-- the block by its actual footprint centre ever after: `entry.part.CFrame =
-- desiredPose * entry.pivotDelta`.

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

-- [blockId] = { part, typeName, home: CFrame, pivotDelta: CFrame, placed: boolean }
local blocks = {}
local nextId = 1

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

local function makeBlock(typeDef, home)
	local id = nextId
	nextId += 1

	local union = buildUnion(typeDef.Shape)
	local pivotDelta = union.CFrame

	union.Name = typeDef.Name .. "Block"
	union.Anchored = true
	union.UsePartColor = true
	union.Color = BLOCK_COLOR
	union.Material = Enum.Material.Plastic
	union.CustomPhysicalProperties = PROPS
	union.CFrame = home * pivotDelta
	union:SetAttribute("BlockId", id)
	union:SetAttribute("BlockType", typeDef.Name)
	union:SetAttribute("Placed", false)
	union.Parent = blocksFolder()

	blocks[id] = { part = union, typeName = typeDef.Name, home = home, pivotDelta = pivotDelta, placed = false }
end

-- Spawns every configured block into its pile, stacked upward from PileOrigin.
-- Clears any existing set first.
function BlockManager.spawnAll()
	BlockManager.clear()
	for _, typeDef in Config.BlockTypes do
		for i = 0, typeDef.Count - 1 do
			local home = CFrame.new(
				typeDef.PileOrigin.X,
				Config.GroundLevel + typeDef.Size.Y * (i + 0.5),
				typeDef.PileOrigin.Z
			)
			makeBlock(typeDef, home)
		end
	end
end

function BlockManager.get(blockId)
	return blocks[blockId]
end

-- Move a block onto the wall. `centre` is the footprint's bounding-box centre
-- in world space; `rotation` turns it about Z by that many quarter-turns.
function BlockManager.moveToWall(blockId, centre, rotation)
	local entry = blocks[blockId]
	if not entry then
		return false
	end
	local pose = CFrame.new(centre) * CFrame.Angles(0, 0, math.rad(90 * rotation))
	entry.part.CFrame = pose * entry.pivotDelta
	entry.part:SetAttribute("Placed", true)
	entry.placed = true
	return true
end

function BlockManager.returnToPile(blockId)
	local entry = blocks[blockId]
	if not entry then
		return false
	end
	entry.part.CFrame = entry.home * entry.pivotDelta
	entry.part:SetAttribute("Placed", false)
	entry.placed = false
	return true
end

-- ATTACK-phase transition. Every placed block becomes server-owned physics:
-- unanchor first, then SetNetworkOwner(nil) (it errors on an anchored part).
-- Blocks never placed aren't part of the wall -- remove them outright rather
-- than leave physics-active clutter on the pile.
function BlockManager.releaseAll()
	for id, entry in blocks do
		if entry.placed then
			entry.part.Anchored = false
			entry.part:SetNetworkOwner(nil)
		else
			entry.part:Destroy()
			blocks[id] = nil
		end
	end
end

-- How many blocks of each type are still in their pile (not on the wall).
function BlockManager.remainingByType()
	local counts = {}
	for _, typeDef in Config.BlockTypes do
		counts[typeDef.Name] = 0
	end
	for _, entry in blocks do
		if not entry.placed then
			counts[entry.typeName] += 1
		end
	end
	return counts
end

function BlockManager.clear()
	for id, entry in blocks do
		entry.part:Destroy()
		blocks[id] = nil
	end
	nextId = 1
end

return BlockManager
