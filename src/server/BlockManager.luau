-- Owns the block parts. Each round's queue is a list of freshly randomized
-- shapes (Config.PieceCount of them, each 3-6 cells of a 3x3 area);
-- BuildManager reads the current one via currentShape() and calls
-- placeCurrent() once it validates a placement. A shape's cells are split
-- into edge-connected components at generation time -- rotation and mirroring
-- both preserve adjacency, so this only needs computing once per shape, not
-- once per placement. Each component of 2+ cells becomes its own
-- UnionOperation, exactly as session 005 established for the (always fully
-- connected) L-piece; a component of exactly 1 cell is a plain Part instead,
-- since a UnionOperation of one part has no reason to exist. Placing a piece
-- can therefore drop several independent rigid bodies at once -- the
-- invariant every prior BUILD pass relied on (one piece = one body) no longer
-- holds, on purpose.
--
-- One density for all blocks, so a bigger component weighs more at equal
-- density. Blocks stay anchored through BUILD; releaseAll() unanchors the
-- wall into server-owned physics at ATTACK start.
--
-- A UnionOperation's own CFrame after UnionAsync doesn't necessarily sit at
-- its shape's bounding-box centre, and Roblox doesn't document exactly where
-- it lands -- so each body's pivot offset is measured once at build time
-- (shape space == world space, identity rotation) and applied when placing it
-- by the piece's actual footprint centre: `part.CFrame = desiredPose *
-- pivotDelta`. A plain Part's CFrame has no such ambiguity (it's whatever it
-- was built with), but measuring it the same way costs nothing and keeps both
-- body kinds on one code path.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage.Shared.Config)
local GridUtil = require(ReplicatedStorage.Shared.GridUtil)
local Arena = require(script.Parent.Arena)

local BlockManager = {}

-- Density from one sub-cube's mass and volume, applied to every block.
local DENSITY = Config.BlockMass / (Config.BlockSize.X * Config.BlockSize.Y * Config.BlockSize.Z)
local PROPS = PhysicalProperties.new(DENSITY, Config.BlockFriction, Config.BlockRestitution)

local NEIGHBOR_OFFSETS = { Vector2.new(1, 0), Vector2.new(-1, 0), Vector2.new(0, 1), Vector2.new(0, -1) }

-- Every block placed so far this round, for releaseAll()/resetQueue() to walk.
local placedParts = {}
local nextId = 1

-- This round's pieces still to come, in issue order; queue[queuePos] is the
-- one the Builder currently holds. Each entry is { components = {{Vector2}} }.
local queue = {}
local queuePos = 1

local function cellKey(cell)
	return string.format("%d,%d", cell.X, cell.Y)
end

-- Splits `cells` into groups of edge-adjacent cells (4-connectivity: up,
-- down, left, right -- not diagonal) via flood fill. Two cells in the same
-- group end up fused into one rigid body; a group of one stays independent.
local function connectedComponents(cells)
	local byKey = {}
	for _, c in cells do
		byKey[cellKey(c)] = c
	end

	local visited = {}
	local components = {}
	for _, cell in cells do
		local key = cellKey(cell)
		if not visited[key] then
			visited[key] = true
			local component = { cell }
			local frontier = { cell }
			while #frontier > 0 do
				local current = table.remove(frontier)
				for _, offset in NEIGHBOR_OFFSETS do
					local neighborKey = cellKey(current + offset)
					local neighbor = byKey[neighborKey]
					if neighbor and not visited[neighborKey] then
						visited[neighborKey] = true
						table.insert(component, neighbor)
						table.insert(frontier, neighbor)
					end
				end
			end
			table.insert(components, component)
		end
	end
	return components
end

-- Picks a random cell count in [PieceMinCells, PieceMaxCells], then that many
-- distinct cells from the PieceGridSize x PieceGridSize area (a partial
-- shuffle of every candidate cell), and splits the result into components.
local function randomComponents()
	local candidates = {}
	for x = 0, Config.PieceGridSize - 1 do
		for y = 0, Config.PieceGridSize - 1 do
			table.insert(candidates, Vector2.new(x, y))
		end
	end
	for i = #candidates, 2, -1 do
		local j = math.random(i)
		candidates[i], candidates[j] = candidates[j], candidates[i]
	end

	local count = math.random(Config.PieceMinCells, Config.PieceMaxCells)
	local chosen = {}
	for i = 1, count do
		chosen[i] = candidates[i]
	end
	return connectedComponents(GridUtil.normalizeShape(chosen))
end

-- Flattens a piece's components into one cell list, in component order.
local function flattenComponents(components)
	local flat = {}
	for _, component in components do
		for _, cell in component do
			table.insert(flat, cell)
		end
	end
	return flat
end

-- Re-splits a flat cell list into groups the same sizes as `components`, in
-- the same order -- valid because GridUtil.mirrorShape preserves each cell's
-- position in the list, only moving where it sits on the grid.
local function resliceComponents(flatCells, components)
	local resliced = {}
	local i = 1
	for ci, component in components do
		local group = {}
		for _ = 1, #component do
			table.insert(group, flatCells[i])
			i += 1
		end
		resliced[ci] = group
	end
	return resliced
end

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

-- Builds one body from `cells` (a single component), positioned in "shape
-- space" -- the whole piece's bounding-box centre at the world origin,
-- identity rotation, per `halfWidth`/`halfHeight` (the piece's, not this
-- component's own, so a component lands at its correct offset within the
-- piece once placed). A single cell is a plain Part; 2+ cells are unioned
-- into one. Temp parts (union case) are cleaned up before returning.
local function buildBody(cells, halfWidth, halfHeight)
	local function cubeAt(cell)
		local cube = Instance.new("Part")
		cube.Size = Config.BlockSize
		cube.Anchored = true
		cube.CFrame = CFrame.new(
			(cell.X + 0.5) * Config.BlockSize.X - halfWidth,
			(cell.Y + 0.5) * Config.BlockSize.Y - halfHeight,
			0
		)
		return cube
	end

	if #cells == 1 then
		return cubeAt(cells[1])
	end

	local temp = Instance.new("Folder")
	temp.Name = "BlockBuildTemp"
	temp.Parent = Workspace

	local cubes = {}
	for _, cell in cells do
		local cube = cubeAt(cell)
		cube.Parent = temp
		table.insert(cubes, cube)
	end

	local first = table.remove(cubes, 1)
	local union = first:UnionAsync(cubes)
	temp:Destroy()
	return union
end

-- Round reset: destroys every block placed last round and rebuilds the issue
-- queue with Config.PieceCount freshly randomized shapes.
function BlockManager.resetQueue()
	for _, part in placedParts do
		part:Destroy()
	end
	placedParts = {}
	nextId = 1

	queue = {}
	for _ = 1, Config.PieceCount do
		table.insert(queue, { components = randomComponents() })
	end
	queuePos = 1
end

-- The flat cell list of the piece the Builder currently holds, or nil once
-- the queue is exhausted.
function BlockManager.currentShape()
	local entry = queue[queuePos]
	return entry and flattenComponents(entry.components)
end

-- How many pieces are still left in the queue (including the current one).
function BlockManager.remainingCount()
	return math.max(0, #queue - queuePos + 1)
end

-- Builds and places the current queued piece at `centre` (the footprint's
-- bounding-box centre in world space), mirrored left-right if `flipped`,
-- rotated by `rotation` quarter-turns, advancing the queue. Returns false if
-- the queue is already empty. The mirror has to happen at the geometry level
-- (which cells buildBody actually fills) -- rotation alone, being a rigid
-- CFrame transform, can never produce a shape's mirror image -- so it's
-- applied here and the resulting cells re-split back into components;
-- rotation is deferred to the CFrame below, same as it always has been.
function BlockManager.placeCurrent(centre, rotation, flipped)
	local entry = queue[queuePos]
	if not entry then
		return false
	end

	local flat = flattenComponents(entry.components)
	local shape = if flipped then GridUtil.mirrorShape(flat) else flat
	local components = if flipped then resliceComponents(shape, entry.components) else entry.components

	local span = GridUtil.shapeSpan(shape)
	local halfWidth = span.X * Config.BlockSize.X / 2
	local halfHeight = span.Y * Config.BlockSize.Y / 2

	-- Rainbow wall (session 015): every cell of this placement shares one
	-- color from the generated palette, keyed by placement order -- not by
	-- body, so a piece that fractures into several independent bodies
	-- (session 008) still reads as one placement.
	local placementColor = Config.wallColor(queuePos)

	for _, cells in components do
		local body = buildBody(cells, halfWidth, halfHeight)
		local pivotDelta = body.CFrame

		body.Anchored = true
		if body:IsA("UnionOperation") then
			body.UsePartColor = true
		end
		body.Color = placementColor
		body.Material = Enum.Material.Concrete
		body.CustomPhysicalProperties = PROPS
		body.CFrame = CFrame.new(centre) * CFrame.Angles(0, 0, math.rad(90 * rotation)) * pivotDelta
		body:SetAttribute("BlockId", nextId)
		body:SetAttribute("PlacedCFrame", body.CFrame)
		body.Parent = blocksFolder()

		nextId += 1
		table.insert(placedParts, body)
	end

	queuePos += 1
	return true
end

-- ATTACK-phase transition. Every body on the wall becomes server-owned
-- physics: unanchor first, then SetNetworkOwner(nil) (it errors on an
-- anchored part). Everything here was placed through placeCurrent(), so
-- there's nothing unplaced left over to clean up instead.
function BlockManager.releaseAll()
	for _, part in placedParts do
		part.Anchored = false
		part:SetNetworkOwner(nil)
	end
end

-- Every body placed this round, regardless of whether it's still standing --
-- the round's maximum possible piece score (session 012).
function BlockManager.totalCount()
	return #placedParts
end

-- How many placed bodies are still "standing" at round end (session 012):
-- within Config.BlockTopplingAngle of the orientation they were placed in.
-- Compared against each body's own placement CFrame, not world up -- a
-- piece's placement rotation (quarter turns about Z) is a deliberate BUILD-
-- phase choice, not a topple, so only rotation picked up since placement
-- counts. Body-level, matching totalCount() -- one Builder placement can
-- already be several independent bodies (session 008) with no shared fate.
function BlockManager.survivingCount()
	local count = 0
	for _, part in placedParts do
		local placedCFrame = part:GetAttribute("PlacedCFrame")
		local _, angle = placedCFrame:ToObjectSpace(part.CFrame):ToAxisAngle()
		if math.deg(angle) <= Config.BlockTopplingAngle then
			count += 1
		end
	end
	return count
end

return BlockManager
