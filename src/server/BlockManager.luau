-- Owns the block Parts. Every block from Config.BlockTypes is spawned anchored
-- at match start into its pile; placing and picking up just reposition the same
-- Part between its pile and the wall. One density for all blocks, so a Wide
-- block (3x the volume) weighs 3x as much. No unanchor / no SetNetworkOwner
-- this session -- that is ATTACK-phase work.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Arena = require(script.Parent.Arena)

local BlockManager = {}

local BLOCK_COLOR = Color3.fromRGB(150, 150, 150)
-- Density from the Standard block's mass and volume, applied to every block.
local DENSITY = Config.BlockMass / (Config.BlockSize.X * Config.BlockSize.Y * Config.BlockSize.Z)
local PROPS = PhysicalProperties.new(DENSITY, Config.BlockFriction, Config.BlockRestitution)

-- [blockId] = { part = Part, typeName = string, home = CFrame, placed = boolean }
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

local function makeBlock(typeDef, home)
	local id = nextId
	nextId += 1

	local part = Instance.new("Part")
	part.Name = typeDef.Name .. "Block"
	part.Anchored = true
	part.Size = typeDef.Size
	part.CFrame = home
	part.Color = BLOCK_COLOR
	part.CustomPhysicalProperties = PROPS
	part:SetAttribute("BlockId", id)
	part:SetAttribute("BlockType", typeDef.Name)
	part:SetAttribute("Placed", false)
	part.Parent = blocksFolder()

	blocks[id] = { part = part, typeName = typeDef.Name, home = home, placed = false }
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

-- Move a block onto the wall. `centre` is the footprint centre in world space;
-- `rotated` turns it 90deg about Z so the long side runs vertically.
function BlockManager.moveToWall(blockId, centre, rotated)
	local entry = blocks[blockId]
	if not entry then
		return false
	end
	local cf = CFrame.new(centre)
	if rotated then
		cf = cf * CFrame.Angles(0, 0, math.rad(90))
	end
	entry.part.CFrame = cf
	entry.part:SetAttribute("Placed", true)
	entry.placed = true
	return true
end

function BlockManager.returnToPile(blockId)
	local entry = blocks[blockId]
	if not entry then
		return false
	end
	entry.part.CFrame = entry.home
	entry.part:SetAttribute("Placed", false)
	entry.placed = false
	return true
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
