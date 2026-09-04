-- Pure world <-> grid-cell math for the vertical build plane. The plane spans
-- world X (columns) and world Y (rows) at a fixed world Z. Callers pass the
-- plane origin (its centre, world space); pitch and extent come from Config.
-- A cell is a Vector2 of integer (column, row), (0, 0) at the bottom-left.

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

-- Grid-cell span (columns, rows) a block of the given world Size occupies,
-- optionally rotated 90deg so its long axis runs vertically. Rounded to whole
-- cells; never smaller than 1x1.
function GridUtil.spanForSize(size, rotated)
	local horizontal = if rotated then size.Y else size.X
	local vertical = if rotated then size.X else size.Y
	return Vector2.new(
		math.max(1, math.round(horizontal / Config.GridSize.X)),
		math.max(1, math.round(vertical / Config.GridSize.Y))
	)
end

-- Every integer cell covered by a footprint whose bottom-left cell is `anchor`
-- and whose size in cells is `span`.
function GridUtil.coveredCells(anchor, span)
	local cells = {}
	for dx = 0, span.X - 1 do
		for dy = 0, span.Y - 1 do
			table.insert(cells, Vector2.new(anchor.X + dx, anchor.Y + dy))
		end
	end
	return cells
end

-- The (possibly fractional) cell at the centre of a footprint. Feed the result
-- straight to cellToWorld to position the block.
function GridUtil.footprintCentre(anchor, span)
	return Vector2.new(anchor.X + (span.X - 1) / 2, anchor.Y + (span.Y - 1) / 2)
end

return GridUtil
