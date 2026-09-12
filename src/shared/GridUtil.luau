-- Pure world <-> grid-cell math for the vertical build plane. The plane spans
-- world X (columns) and world Y (rows) at a fixed world Z. Callers pass the
-- plane origin (its centre, world space); pitch and extent come from Config.
-- A cell is a Vector2 of integer (column, row), (0, 0) at the bottom-left.
--
-- A block's footprint is a "shape": a list of local (column, row) cell
-- offsets at rotation 0, normalized so its minimum column and row are both 0.
-- `anchor` is always the bottom-left cell of the shape's (rotated) bounding
-- box, matching the old rectangular-footprint convention.

local Config = require(script.Parent:WaitForChild("Config"))

local GridUtil = {}

local COLUMNS = math.floor(Config.BuildZoneSize.X / Config.GridSize.X)
local ROWS = math.floor(Config.BuildZoneSize.Y / Config.GridSize.Y)

function GridUtil.columns()
	return COLUMNS
end

function GridUtil.rows()
	return ROWS
end

function GridUtil.isInside(cell)
	return cell.X >= 0 and cell.X < COLUMNS and cell.Y >= 0 and cell.Y < ROWS
end

function GridUtil.cellToWorld(origin, cell)
	local x = origin.X - Config.BuildZoneSize.X / 2 + (cell.X + 0.5) * Config.GridSize.X
	local y = origin.Y - Config.BuildZoneSize.Y / 2 + (cell.Y + 0.5) * Config.GridSize.Y
	return Vector3.new(x, y, origin.Z)
end

function GridUtil.worldToCell(origin, position)
	local col = math.floor((position.X - origin.X + Config.BuildZoneSize.X / 2) / Config.GridSize.X)
	local row = math.floor((position.Y - origin.Y + Config.BuildZoneSize.Y / 2) / Config.GridSize.Y)
	return Vector2.new(col, row)
end

function GridUtil.snapToWorld(origin, position)
	return GridUtil.cellToWorld(origin, GridUtil.worldToCell(origin, position))
end

-- Rotates a shape's local cell offsets by `rotation` quarter-turns (0-3,
-- matching CFrame.Angles(0, 0, math.rad(90 * rotation))'s (x,y) -> (-y,x) per
-- turn), then re-normalizes so the minimum column and row are both 0 again --
-- keeps "anchor" meaning "bottom-left cell of the bounding box" at every
-- rotation.
function GridUtil.rotateShape(shape, rotation)
	local turns = rotation % 4
	local rotated = {}
	for i, offset in shape do
		local x, y = offset.X, offset.Y
		for _ = 1, turns do
			x, y = -y, x
		end
		rotated[i] = Vector2.new(x, y)
	end

	local minX, minY = math.huge, math.huge
	for _, c in rotated do
		minX = math.min(minX, c.X)
		minY = math.min(minY, c.Y)
	end
	for i, c in rotated do
		rotated[i] = Vector2.new(c.X - minX, c.Y - minY)
	end
	return rotated
end

-- The (cols, rows) bounding box of a shape already normalized to min (0, 0).
function GridUtil.shapeSpan(shape)
	local maxX, maxY = 0, 0
	for _, c in shape do
		maxX = math.max(maxX, c.X)
		maxY = math.max(maxY, c.Y)
	end
	return Vector2.new(maxX + 1, maxY + 1)
end

-- The bounding box of `shape` after rotating it by `rotation` quarter-turns.
function GridUtil.rotatedSpan(shape, rotation)
	return GridUtil.shapeSpan(GridUtil.rotateShape(shape, rotation))
end

-- Every integer cell covered by `shape` (local offsets at rotation 0) rotated
-- by `rotation` quarter-turns and placed with its bounding box's bottom-left
-- cell at `anchor`.
function GridUtil.coveredCells(shape, anchor, rotation)
	local rotated = GridUtil.rotateShape(shape, rotation)
	local cells = {}
	for _, c in rotated do
		table.insert(cells, Vector2.new(anchor.X + c.X, anchor.Y + c.Y))
	end
	return cells
end

-- The (possibly fractional) cell at the centre of a footprint. Feed the result
-- straight to cellToWorld to position the block.
function GridUtil.footprintCentre(anchor, span)
	return Vector2.new(anchor.X + (span.X - 1) / 2, anchor.Y + (span.Y - 1) / 2)
end

return GridUtil
