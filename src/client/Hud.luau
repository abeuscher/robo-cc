-- Screen-corner readouts. Driven by StateChanged for role / phase / counts,
-- AttackInput.setAttackReadout for the live weapon + angle, and
-- BuildInput.setBuildReadout for the held piece's shape/rotation/flip. Two
-- panels, both a translucent rounded backdrop for legibility over the arena:
-- the info block (bottom-right) shows round/phase/progress plus whichever of
-- "Current Block" (BUILD, a small oriented shape preview) or "Current Weapon"
-- (ATTACK) applies; the score panel (top-right) is a fixed Player 1 / Player 2
-- readout by join order -- unlike role, which flips every SWAP -- with the
-- viewer's own row highlighted. The round-result / match-result banner itself
-- is ResultBanner.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local GridUtil = require(Shared:WaitForChild("GridUtil"))

local player = Players.LocalPlayer

local Hud = {}

local PANEL_BG = Color3.fromRGB(0, 0, 0)
local PANEL_TRANSPARENCY = 0.5
local TEXT_COLOR = Color3.fromRGB(238, 238, 238)
local DIM_TEXT_COLOR = Color3.fromRGB(200, 205, 215)
local ACCENT_COLOR = Color3.fromRGB(255, 210, 120)
local HIGHLIGHT_BG = Color3.fromRGB(255, 210, 120)

local PHASE_NAMES = {
	BUILD = "Build Phase",
	POSITION = "Positioning Flag",
	ATTACK = "Attack Phase",
	RESOLVE = "Resolving…",
	SWAP = "Swapping…",
}

local PREVIEW_GRID = Config.PieceGridSize
local PREVIEW_CELL_PX = 14
local PREVIEW_GAP_PX = 2

local gui
local roleLabel, roundLabel, phaseLabel, countLabel, hintLabel, shieldLabel, waitingLabel
local blockRow, weaponRow, weaponAngleLabel
local previewCells = {}
local weaponIconCells = {}
local scoreRows = {} -- { one = {frame, label}, two = {frame, label} }

local lastState = nil
local attackReadout = { weapon = "Ballista", angle = 0 }
local buildReadout = { shape = {}, rotation = 0, flipped = false }

-- A translucent rounded backdrop, positioned/anchored by the caller, with a
-- vertical list layout and inner padding ready for labels to be parented into.
local function makePanel(size, position, anchorPoint)
	local panel = Instance.new("Frame")
	panel.BackgroundColor3 = PANEL_BG
	panel.BackgroundTransparency = PANEL_TRANSPARENCY
	panel.BorderSizePixel = 0
	panel.AnchorPoint = anchorPoint
	panel.Position = position
	panel.Size = size
	panel.AutomaticSize = Enum.AutomaticSize.Y
	panel.Parent = gui

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 10)
	corner.Parent = panel

	local padding = Instance.new("UIPadding")
	padding.PaddingLeft = UDim.new(0, 14)
	padding.PaddingRight = UDim.new(0, 14)
	padding.PaddingTop = UDim.new(0, 10)
	padding.PaddingBottom = UDim.new(0, 10)
	padding.Parent = panel

	local layout = Instance.new("UIListLayout")
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Padding = UDim.new(0, 4)
	layout.Parent = panel

	return panel
end

local function label(parent, size, color, order)
	local l = Instance.new("TextLabel")
	l.Size = UDim2.new(1, 0, 0, size)
	l.BackgroundTransparency = 1
	l.TextXAlignment = Enum.TextXAlignment.Left
	l.Font = Enum.Font.GothamBold
	l.TextColor3 = color
	l.TextSize = size
	l.Text = ""
	l.LayoutOrder = order
	l.Parent = parent
	return l
end

-- A fixed PREVIEW_GRID x PREVIEW_GRID square grid, one cell Frame per grid
-- position, transparent until a filled cell lights it up. Shared visual
-- language for both the Current Block shape preview and the Current Weapon
-- icon -- same size, same style, so the two read as the same kind of thing.
-- Cells are keyed "col,uiRow" in screen space (uiRow 0 = top row). Built once
-- per box; setGridFilled toggles which cells show.
local function makeCellGrid(parent)
	local side = PREVIEW_GRID * PREVIEW_CELL_PX + (PREVIEW_GRID - 1) * PREVIEW_GAP_PX
	local box = Instance.new("Frame")
	box.Size = UDim2.fromOffset(side, side)
	box.BackgroundTransparency = 1
	box.Parent = parent

	local cells = {}
	for uiRow = 0, PREVIEW_GRID - 1 do
		for col = 0, PREVIEW_GRID - 1 do
			local cell = Instance.new("Frame")
			cell.Size = UDim2.fromOffset(PREVIEW_CELL_PX, PREVIEW_CELL_PX)
			cell.Position = UDim2.fromOffset(
				col * (PREVIEW_CELL_PX + PREVIEW_GAP_PX),
				uiRow * (PREVIEW_CELL_PX + PREVIEW_GAP_PX)
			)
			cell.BackgroundColor3 = ACCENT_COLOR
			cell.BackgroundTransparency = 1
			cell.BorderSizePixel = 0
			cell.Parent = box
			local cellCorner = Instance.new("UICorner")
			cellCorner.CornerRadius = UDim.new(0, 2)
			cellCorner.Parent = cell
			cells[string.format("%d,%d", col, uiRow)] = cell
		end
	end
	return box, cells
end

-- Lights up exactly the cells at `uiCoords` (a list of Vector2(col, uiRow),
-- screen space) and hides every other cell in `cells`.
local function setGridFilled(cells, uiCoords)
	for _, cell in cells do
		cell.BackgroundTransparency = 1
	end
	for _, coord in uiCoords do
		local cell = cells[string.format("%d,%d", coord.X, coord.Y)]
		if cell then
			cell.BackgroundTransparency = 0.1
		end
	end
end

-- The held piece's actual footprint right now: shape mirrored (if flipped)
-- then rotated -- identical math to BuildInput's own baseShape() + the
-- rotation coveredCells applies, just without an anchor since this only needs
-- relative cells. Converted from grid space (row 0 = bottom, matching the
-- build plane) to screen space (uiRow 0 = top) for the shared grid widget.
local function renderBlockPreview()
	local shape = if buildReadout.flipped then GridUtil.mirrorShape(buildReadout.shape) else buildReadout.shape
	local rotated = GridUtil.rotateShape(shape, buildReadout.rotation)
	local uiCoords = {}
	for _, c in rotated do
		table.insert(uiCoords, Vector2.new(c.X, PREVIEW_GRID - 1 - c.Y))
	end
	setGridFilled(previewCells, uiCoords)
end

-- Fixed pixel-art glyphs for the two weapons, drawn on the same grid widget
-- as the block preview so "Current Weapon" reads as the same kind of thing as
-- "Current Block" -- a flat 3-across line for the ballista's straight shot, a
-- low-high-low hump for the catapult's arc.
local WEAPON_ICON_CELLS = {
	Ballista = { Vector2.new(0, 1), Vector2.new(1, 1), Vector2.new(2, 1) },
	Catapult = { Vector2.new(0, 2), Vector2.new(1, 0), Vector2.new(2, 2) },
}

local function renderWeaponIcon()
	setGridFilled(weaponIconCells, WEAPON_ICON_CELLS[attackReadout.weapon] or {})
end

local function makeScoreRow(parent, order)
	local row = Instance.new("Frame")
	row.Size = UDim2.new(1, 0, 0, 26)
	row.BackgroundColor3 = HIGHLIGHT_BG
	row.BackgroundTransparency = 1
	row.BorderSizePixel = 0
	row.LayoutOrder = order
	row.Parent = parent

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 6)
	corner.Parent = row

	local padding = Instance.new("UIPadding")
	padding.PaddingLeft = UDim.new(0, 8)
	padding.PaddingRight = UDim.new(0, 8)
	padding.Parent = row

	local text = label(row, 18, TEXT_COLOR, order)
	text.Size = UDim2.new(1, 0, 1, 0)

	return row, text
end

function Hud.start()
	if gui then
		return
	end

	gui = Instance.new("ScreenGui")
	gui.Name = "Hud"
	gui.ResetOnSpawn = false

	-- Info block, bottom-right.
	local infoPanel = makePanel(UDim2.fromOffset(340, 0), UDim2.new(1, -16, 1, -16), Vector2.new(1, 1))

	roleLabel = label(infoPanel, 24, TEXT_COLOR, 1)
	roundLabel = label(infoPanel, 18, DIM_TEXT_COLOR, 2)
	phaseLabel = label(infoPanel, 18, DIM_TEXT_COLOR, 3)
	countLabel = label(infoPanel, 18, DIM_TEXT_COLOR, 4)

	blockRow = Instance.new("Frame")
	blockRow.Size = UDim2.new(1, 0, 0, PREVIEW_GRID * PREVIEW_CELL_PX + (PREVIEW_GRID - 1) * PREVIEW_GAP_PX)
	blockRow.BackgroundTransparency = 1
	blockRow.LayoutOrder = 5
	blockRow.Parent = infoPanel
	local blockRowLayout = Instance.new("UIListLayout")
	blockRowLayout.SortOrder = Enum.SortOrder.LayoutOrder
	blockRowLayout.FillDirection = Enum.FillDirection.Horizontal
	blockRowLayout.VerticalAlignment = Enum.VerticalAlignment.Center
	blockRowLayout.Padding = UDim.new(0, 10)
	blockRowLayout.Parent = blockRow
	local blockLabelText = label(blockRow, 18, ACCENT_COLOR, 1)
	blockLabelText.Size = UDim2.fromOffset(120, PREVIEW_GRID * PREVIEW_CELL_PX)
	blockLabelText.TextYAlignment = Enum.TextYAlignment.Center
	blockLabelText.Text = "Current Block:"
	local preview
	preview, previewCells = makeCellGrid(blockRow)
	preview.LayoutOrder = 2

	weaponRow = Instance.new("Frame")
	weaponRow.Size = UDim2.new(1, 0, 0, PREVIEW_GRID * PREVIEW_CELL_PX + (PREVIEW_GRID - 1) * PREVIEW_GAP_PX)
	weaponRow.BackgroundTransparency = 1
	weaponRow.LayoutOrder = 5
	weaponRow.Parent = infoPanel
	local weaponRowLayout = Instance.new("UIListLayout")
	weaponRowLayout.SortOrder = Enum.SortOrder.LayoutOrder
	weaponRowLayout.FillDirection = Enum.FillDirection.Horizontal
	weaponRowLayout.VerticalAlignment = Enum.VerticalAlignment.Center
	weaponRowLayout.Padding = UDim.new(0, 10)
	weaponRowLayout.Parent = weaponRow
	local weaponLabelText = label(weaponRow, 18, ACCENT_COLOR, 1)
	weaponLabelText.Size = UDim2.fromOffset(150, PREVIEW_GRID * PREVIEW_CELL_PX)
	weaponLabelText.TextYAlignment = Enum.TextYAlignment.Center
	weaponLabelText.Text = "Current Weapon:"
	local weaponIcon
	weaponIcon, weaponIconCells = makeCellGrid(weaponRow)
	weaponIcon.LayoutOrder = 2
	weaponAngleLabel = label(weaponRow, 18, ACCENT_COLOR, 3)
	weaponAngleLabel.Size = UDim2.fromOffset(50, PREVIEW_GRID * PREVIEW_CELL_PX)
	weaponAngleLabel.TextYAlignment = Enum.TextYAlignment.Center

	shieldLabel = label(infoPanel, 18, Color3.fromRGB(120, 190, 255), 6)
	hintLabel = label(infoPanel, 15, Color3.fromRGB(150, 155, 165), 7)
	hintLabel.Size = UDim2.new(1, 0, 0, 36)
	hintLabel.TextWrapped = true
	hintLabel.TextYAlignment = Enum.TextYAlignment.Top

	waitingLabel = label(infoPanel, 18, Color3.fromRGB(230, 200, 120), 8)

	-- Score panel, top-right: a stable Player 1 / Player 2 readout by join
	-- order, independent of the Builder/Attacker roles that flip every round.
	local scorePanel = makePanel(UDim2.fromOffset(220, 0), UDim2.new(1, -16, 0, 16), Vector2.new(1, 0))
	local oneRow, oneText = makeScoreRow(scorePanel, 1)
	local twoRow, twoText = makeScoreRow(scorePanel, 2)
	scoreRows.one = { frame = oneRow, text = oneText }
	scoreRows.two = { frame = twoRow, text = twoText }

	gui.Parent = player:WaitForChild("PlayerGui")
end

local function renderScoreRow(seat, label_, userId)
	local score = (userId and lastState and lastState.score and lastState.score[userId]) or 0
	local text = if userId then string.format("Player %s: %d", label_, score) else string.format("Player %s: —", label_)
	seat.text.Text = text
	local isMe = userId ~= nil and userId == player.UserId
	seat.frame.BackgroundTransparency = if isMe then 0.25 else 1
	seat.text.TextColor3 = if isMe then Color3.fromRGB(30, 24, 10) else TEXT_COLOR
end

-- Redraws every label from lastState + the two readouts. Safe to call before
-- any state has arrived.
local function render()
	Hud.start()
	if not lastState then
		return
	end
	local state = lastState

	local players = state.players or {}
	renderScoreRow(scoreRows.one, "1", players.one)
	renderScoreRow(scoreRows.two, "2", players.two)

	local myRole
	if state.roles then
		if state.roles.builder == player.UserId then
			myRole = "Builder"
		elseif state.roles.attacker == player.UserId then
			myRole = "Attacker"
		end
	end

	roleLabel.Text = myRole and ("You are the " .. myRole) or "You are a spectator"

	roundLabel.Visible = state.roles ~= nil
	local round = state.round or 1
	if round > Config.RoundsPerMatch then
		roundLabel.Text = string.format("Sudden death  —  round %d", round)
	else
		roundLabel.Text = string.format("Round %d of %d", round, Config.RoundsPerMatch)
	end

	local inBuild = state.phase == "BUILD"
	local inPosition = state.phase == "POSITION"
	local inAttack = state.phase == "ATTACK"

	phaseLabel.Text = PHASE_NAMES[state.phase] or state.phase

	countLabel.Visible = inBuild or inAttack
	if inBuild then
		local current = math.clamp(Config.PieceCount - (state.blocksRemaining or 0) + 1, 1, Config.PieceCount)
		countLabel.Text = string.format("Placing Block %d of %d", current, Config.PieceCount)
	elseif inAttack then
		local current = math.clamp(Config.ShotsPerTurn - (state.shotsRemaining or 0) + 1, 1, Config.ShotsPerTurn)
		countLabel.Text = string.format("Shot %d of %d", current, Config.ShotsPerTurn)
	end

	local hintForBuilderBuild = inBuild and myRole == "Builder"
	local hintForBuilderPosition = inPosition and myRole == "Builder"
	local hintForBuilderAttack = inAttack and myRole == "Builder"
	local hintForAttacker = inAttack and myRole == "Attacker"

	blockRow.Visible = hintForBuilderBuild
	if blockRow.Visible then
		renderBlockPreview()
	end

	weaponRow.Visible = hintForAttacker
	if weaponRow.Visible then
		renderWeaponIcon()
	end
	weaponAngleLabel.Visible = attackReadout.weapon == "Catapult"
	weaponAngleLabel.Text = string.format("%d°", attackReadout.angle)

	shieldLabel.Visible = hintForBuilderAttack
	shieldLabel.Text = if state.shieldAvailable ~= false then "Shield ready  ·  press F" else "Shield used"

	hintLabel.Visible = hintForBuilderBuild or hintForBuilderPosition or hintForBuilderAttack or hintForAttacker
	if hintForAttacker then
		hintLabel.Text = "mouse aim · Q/E angle (catapult) · C camera · click, click at meter target to launch"
	elseif hintForBuilderAttack then
		hintLabel.Text = "F to raise your shield — time it against the incoming shot"
	elseif hintForBuilderPosition then
		hintLabel.Text = "click the ground behind your wall to place the Flag — this is your only chance to move it"
	else
		hintLabel.Text = "click cell to place · R rotate · Z flip · Confirm Wall when done"
	end

	local waiting = state.roles == nil or state.roles.attacker == nil
	waitingLabel.Visible = waiting
	waitingLabel.Text = waiting and "Waiting for the other player…" or ""
end

function Hud.update(state)
	lastState = state
	render()
end

-- Called by AttackInput whenever the weapon / angle changes.
function Hud.setAttackReadout(values)
	attackReadout = values
	render()
end

-- Called by BuildInput whenever the held piece's shape, rotation, or flip
-- changes -- keeps the Current Block preview tracking the same footprint the
-- build-plane ghost shows.
function Hud.setBuildReadout(values)
	buildReadout = values
	render()
end

return Hud
