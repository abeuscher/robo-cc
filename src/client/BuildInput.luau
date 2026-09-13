-- Builder-only placement. The Builder always holds exactly one piece --
-- there's no pile to pick from and no picking a placed piece back up. The
-- mouse ray is intersected with the vertical build plane (world Z =
-- BuildZoneOrigin.Z) and the ghost snaps to the hovered cell. Click a cell to
-- place, R to cycle rotation (0-3 quarter turns), Z to mirror it left-right
-- (its chirality flip -- an L-piece's mirror is a J-piece, which no rotation
-- alone can reach). Confirm Wall ends BUILD at any time. Active only while
-- phase == "BUILD" and the local player is the Builder; everything is intent
-- -- the server validates.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Remotes = require(Shared:WaitForChild("Remotes"))
local GridUtil = require(Shared:WaitForChild("GridUtil"))
local Hud = require(script.Parent:WaitForChild("Hud"))

local player = Players.LocalPlayer

local BuildInput = {}

local PLANE_Z = Config.BuildZoneOrigin.Z

local active = false
local piecesRemaining = 0
local pieceShape = {} -- the held piece's shape at rotation 0, unflipped -- mirrors StateChanged.currentShape
local rotation = 0
local flipped = false
local ghostCubes = {} -- pool of translucent per-cell preview parts, grown as needed
local confirmGui
local renderConn, clickConn

-- The held piece's footprint at rotation 0: pieceShape mirrored left-right if
-- `flipped`. Rotation is applied on top of this wherever it's used.
local function baseShape()
	return if flipped then GridUtil.mirrorShape(pieceShape) else pieceShape
end

-- Pushes the held piece's shape/rotation/flip to the HUD so its small preview
-- (Current Block) tracks exactly what the ghost on the build plane shows.
-- Mirrors AttackInput's own setAttackReadout pattern.
local function publish()
	Hud.setBuildReadout({ shape = pieceShape, rotation = rotation, flipped = flipped })
end

-- Grows the ghost-cube pool to at least `count` parts. Each is a translucent
-- preview cube, client-only (never replicated), non-colliding, and excluded
-- from raycasts (CanQuery = false) so it can't interfere with its own
-- placement checks. Starts invisible; onRender repositions and shows the ones
-- it needs each frame.
local function ensureGhostCubes(count)
	for i = #ghostCubes + 1, count do
		local cube = Instance.new("Part")
		cube.Name = "BuildGhostCell"
		cube.Anchored = true
		cube.CanCollide = false
		cube.CanQuery = false
		cube.CastShadow = false
		cube.Transparency = 1
		cube.Color = Color3.fromRGB(120, 200, 255)
		cube.Size = Config.BlockSize
		cube.Parent = Workspace
		ghostCubes[i] = cube
	end
end

local function hideGhost()
	for _, cube in ghostCubes do
		cube.Transparency = 1
	end
end

-- Shows the ghost as one cube per cell of the held piece's actual footprint
-- at `anchor`, rotated by `rotation` -- the real shape, not a bounding box.
local function showGhostAt(anchor)
	local cells = GridUtil.coveredCells(baseShape(), anchor, rotation)
	ensureGhostCubes(#cells)
	for i, cell in cells do
		local cube = ghostCubes[i]
		cube.CFrame = CFrame.new(GridUtil.cellToWorld(Config.BuildZoneOrigin, cell))
		cube.Transparency = 0.4
	end
	for i = #cells + 1, #ghostCubes do
		ghostCubes[i].Transparency = 1
	end
end

-- Builds the single on-screen "Confirm Wall" button and parents it to PlayerGui.
-- Clicking it just fires ConfirmBuild -- the server decides whether to honour it.
-- Created once; BuildInput.update toggles its .Enabled.
local function makeConfirmGui()
	local gui = Instance.new("ScreenGui")
	gui.Name = "BuildConfirm"
	gui.ResetOnSpawn = false

	local button = Instance.new("TextButton")
	button.AnchorPoint = Vector2.new(0.5, 1)
	button.Position = UDim2.fromScale(0.5, 0.95)
	button.Size = UDim2.fromOffset(220, 56)
	button.BackgroundColor3 = Color3.fromRGB(70, 130, 200)
	button.AutoButtonColor = true
	button.Font = Enum.Font.GothamBold
	button.Text = "Confirm Wall"
	button.TextColor3 = Color3.fromRGB(255, 255, 255)
	button.TextScaled = true
	button.Parent = gui

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 8)
	corner.Parent = button

	button.Activated:Connect(function()
		Remotes.ConfirmBuild:FireServer()
	end)

	gui.Parent = player:WaitForChild("PlayerGui")
	return gui
end

-- Returns a world-space ray {Origin, Direction} from the camera through the
-- current mouse pixel, or nil if there is no camera yet.
local function cameraRay()
	local camera = Workspace.CurrentCamera
	if not camera then
		return nil
	end
	local mouse = UserInputService:GetMouseLocation()
	return camera:ViewportPointToRay(mouse.X, mouse.Y)
end

-- Intersects the ray with the vertical build plane (world Z = PLANE_Z) and
-- converts the hit point to an integer (column, row) cell via GridUtil. This
-- cell is the bottom-left anchor of the footprint. Returns nil if the ray is
-- parallel to the plane, points away from it, or the anchor is off the grid.
local function anchorUnderRay(ray)
	local dz = ray.Direction.Z
	if math.abs(dz) < 1e-4 then
		return nil
	end
	local t = (PLANE_Z - ray.Origin.Z) / dz
	if t <= 0 then
		return nil
	end
	local cell = GridUtil.worldToCell(Config.BuildZoneOrigin, ray.Origin + ray.Direction * t)
	if not GridUtil.isInside(cell) then
		return nil
	end
	return cell
end

-- True when every cell of the held piece's footprint anchored at `anchor` is
-- on the grid. (Occupancy is the server's call; this is just the bounds check
-- that decides whether to show the ghost / send the request.)
local function footprintFits(anchor)
	for _, c in GridUtil.coveredCells(baseShape(), anchor, rotation) do
		if not GridUtil.isInside(c) then
			return false
		end
	end
	return true
end

-- Runs every rendered frame while placement is active. Shows the ghost
-- snapped to the hovered footprint while a piece remains to place; hides it
-- once the queue is empty or the cell under the cursor doesn't fit.
local function onRender()
	if piecesRemaining <= 0 then
		hideGhost()
		return
	end
	local ray = cameraRay()
	local anchor = ray and anchorUnderRay(ray)
	if not anchor or not footprintFits(anchor) then
		hideGhost()
		return
	end
	showGhostAt(anchor)
end

-- Handles keyboard and left-click while placement is active. R cycles the held
-- piece's rotation, Z mirrors it left-right. A left click places it on the
-- hovered cell, if one remains and the cell fits. gameProcessed is true when
-- the UI already consumed the input.
local function onInput(inputObject, gameProcessed)
	if gameProcessed then
		return
	end

	if inputObject.KeyCode == Enum.KeyCode.R then
		rotation = (rotation + 1) % 4
		publish()
		return
	end
	if inputObject.KeyCode == Enum.KeyCode.Z then
		flipped = not flipped
		publish()
		return
	end
	if inputObject.UserInputType ~= Enum.UserInputType.MouseButton1 then
		return
	end
	if piecesRemaining <= 0 then
		return
	end

	local ray = cameraRay()
	local anchor = ray and anchorUnderRay(ray)
	if not anchor or not footprintFits(anchor) then
		return
	end

	Remotes.PlaceBlock:FireServer({
		cell = Vector2.new(anchor.X, anchor.Y),
		rotation = rotation,
		flipped = flipped,
	})
	rotation = 0
	flipped = false
	publish()
end

-- One-time setup, called once after the player leaves the title screen. Creates
-- the Confirm button up front and leaves it hidden; the ghost-cube pool grows
-- lazily on first use. update() decides when they appear.
function BuildInput.start()
	confirmGui = confirmGui or makeConfirmGui()
	confirmGui.Enabled = false
end

-- Called on every StateChanged broadcast. Placement is live only while the
-- phase is BUILD and the local player is the Builder. On the transition in it
-- shows the button and connects onRender and onInput; on the transition out it
-- disconnects them and hides the ghost and button.
function BuildInput.update(state)
	piecesRemaining = state.blocksRemaining or 0
	-- A fresh piece arrives after every placement, well inside a single BUILD
	-- phase -- this has to update on every broadcast, not just on the
	-- activation transition (the same lesson session 007 needed for
	-- AttackInput's currentWeapon).
	local previousShape = pieceShape
	pieceShape = state.currentShape or pieceShape
	if pieceShape ~= previousShape then
		publish()
	end

	local shouldBeActive = state.phase == "BUILD"
		and state.roles ~= nil
		and state.roles.builder == player.UserId

	if shouldBeActive == active then
		return
	end
	active = shouldBeActive

	if active then
		confirmGui.Enabled = true
		renderConn = RunService.RenderStepped:Connect(onRender)
		clickConn = UserInputService.InputBegan:Connect(onInput)
	else
		if renderConn then
			renderConn:Disconnect()
			renderConn = nil
		end
		if clickConn then
			clickConn:Disconnect()
			clickConn = nil
		end
		rotation = 0
		flipped = false
		hideGhost()
		confirmGui.Enabled = false
	end
end

return BuildInput
