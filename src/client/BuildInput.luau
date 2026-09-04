-- Builder-only placement. Click a block in its pile to "lift" it (it becomes
-- the ghost); the mouse ray is intersected with the vertical build plane
-- (world Z = BuildZoneOrigin.Z) and the ghost snaps to the hovered cell. Click
-- a cell to place, R to rotate a Wide block, Q to drop the lifted block, click
-- a block already on the wall (empty-handed) to send it back to its pile.
-- Confirm Wall ends BUILD. Active only while phase == "BUILD" and the local
-- player is the Builder; everything is intent -- the server validates.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Remotes = require(Shared:WaitForChild("Remotes"))
local GridUtil = require(Shared:WaitForChild("GridUtil"))

local player = Players.LocalPlayer

local BuildInput = {}

local PLANE_Z = Config.BuildZoneOrigin.Z
local ROTATE_CF = CFrame.Angles(0, 0, math.rad(90))

local active = false
local ghost, confirmGui
local renderConn, clickConn

-- The block currently lifted off a pile, or nil. size is the Part's world Size;
-- rotatable comes from the type; rotated is the player's R toggle.
local held = nil -- { id: number, size: Vector3, rotatable: boolean, rotated: boolean }

-- Looks up a Config.BlockTypes entry by its Name.
local function typeDefByName(name)
	for _, def in Config.BlockTypes do
		if def.Name == name then
			return def
		end
	end
	return nil
end

-- Creates the translucent preview block once and parks it in Workspace. It is
-- client-only (never replicated), non-colliding, and excluded from raycasts
-- (CanQuery = false) so it can't interfere with its own placement checks. Size
-- and CFrame are rewritten every frame by onRender; starts invisible.
local function makeGhost()
	local part = Instance.new("Part")
	part.Name = "BuildGhost"
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CastShadow = false
	part.Transparency = 1
	part.Color = Color3.fromRGB(120, 200, 255)
	part.Size = Config.BlockSize
	part.Parent = Workspace
	return part
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

-- Finds the server-built folder that holds every block, pile and wall alike
-- (Workspace.ActiveRound.Blocks), or nil if the arena isn't up yet.
local function blocksFolder()
	local root = Workspace:FindFirstChild("ActiveRound")
	return root and root:FindFirstChild("Blocks")
end

-- Raycasts along the ray but only against blocks (Include filter). Returns the
-- block Part under the cursor, or nil. Used to lift a pile block or to return a
-- wall block.
local function blockUnderRay(ray)
	local folder = blocksFolder()
	if not folder then
		return nil
	end
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Include
	params.FilterDescendantsInstances = { folder }
	local result = Workspace:Raycast(ray.Origin, ray.Direction * 500, params)
	return result and result.Instance or nil
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

-- True when every cell of the held block's footprint anchored at `anchor` is on
-- the grid. (Occupancy is the server's call; this is just the bounds check that
-- decides whether to show the ghost / send the request.)
local function footprintFits(anchor)
	local span = GridUtil.spanForSize(held.size, held.rotated)
	for _, c in GridUtil.coveredCells(anchor, span) do
		if not GridUtil.isInside(c) then
			return false
		end
	end
	return true
end

-- The world CFrame the ghost (and the placed block) should sit at for a given
-- anchor: footprint centre, turned 90deg if the held block is rotated.
local function placementCFrame(anchor)
	local span = GridUtil.spanForSize(held.size, held.rotated)
	local centre = GridUtil.cellToWorld(Config.BuildZoneOrigin, GridUtil.footprintCentre(anchor, span))
	return if held.rotated then CFrame.new(centre) * ROTATE_CF else CFrame.new(centre)
end

-- Fills `held` from a pile block Part and hides that Part on this client only
-- (LocalTransparencyModifier -- no replication, other players still see it in
-- the stack) so it reads as lifted out. Restores any previously-held Part first.
local function lift(part)
	if held and held.part then
		held.part.LocalTransparencyModifier = 0
	end
	local def = typeDefByName(part:GetAttribute("BlockType"))
	held = {
		id = part:GetAttribute("BlockId"),
		part = part,
		size = part.Size,
		rotatable = def ~= nil and def.Rotatable == true,
		rotated = false,
	}
	part.LocalTransparencyModifier = 1
end

-- Clears the lifted block, un-hides its Part, and hides the ghost.
local function drop()
	if held and held.part then
		held.part.LocalTransparencyModifier = 0
	end
	held = nil
	ghost.Transparency = 1
end

-- Runs every rendered frame while placement is active. With a block lifted,
-- shows the ghost snapped to the hovered footprint; otherwise hides it.
local function onRender()
	if not held then
		ghost.Transparency = 1
		return
	end
	local ray = cameraRay()
	local anchor = ray and anchorUnderRay(ray)
	if not anchor or not footprintFits(anchor) then
		ghost.Transparency = 1
		return
	end
	ghost.Size = held.size
	ghost.CFrame = placementCFrame(anchor)
	ghost.Transparency = 0.6
end

-- Handles keyboard and left-click while placement is active. R rotates a
-- rotatable held block, Q drops it. A left click either places the held block
-- on the hovered cell, lifts a pile block, or returns a wall block to its pile.
-- gameProcessed is true when the UI already consumed the input.
local function onInput(inputObject, gameProcessed)
	if gameProcessed then
		return
	end

	if inputObject.KeyCode == Enum.KeyCode.R then
		if held and held.rotatable then
			held.rotated = not held.rotated
		end
		return
	end
	if inputObject.KeyCode == Enum.KeyCode.Q then
		if held then
			drop()
		end
		return
	end
	if inputObject.UserInputType ~= Enum.UserInputType.MouseButton1 then
		return
	end

	local ray = cameraRay()
	if not ray then
		return
	end

	if held then
		local anchor = anchorUnderRay(ray)
		if anchor and footprintFits(anchor) then
			Remotes.PlaceBlock:FireServer({
				blockId = held.id,
				cell = Vector2.new(anchor.X, anchor.Y),
				rotated = held.rotated,
			})
			drop()
			return
		end
		-- Not a valid cell: allow switching to a different pile block.
		local part = blockUnderRay(ray)
		if part and part:GetAttribute("BlockId") and not part:GetAttribute("Placed") then
			lift(part)
		end
		return
	end

	local part = blockUnderRay(ray)
	if not part or not part:GetAttribute("BlockId") then
		return
	end
	if part:GetAttribute("Placed") then
		Remotes.PickupBlock:FireServer(part:GetAttribute("BlockId"))
	else
		lift(part)
	end
end

-- One-time setup, called once after the player leaves the title screen. Creates
-- the ghost and Confirm button up front and leaves them hidden; update() decides
-- when they appear.
function BuildInput.start()
	ghost = ghost or makeGhost()
	confirmGui = confirmGui or makeConfirmGui()
	confirmGui.Enabled = false
end

-- Called on every StateChanged broadcast. Placement is live only while the
-- phase is BUILD and the local player is the Builder. On the transition in it
-- shows the button and connects onRender and onInput; on the transition out it
-- disconnects them, drops any held block, and hides the ghost and button.
function BuildInput.update(state)
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
		drop()
		confirmGui.Enabled = false
	end
end

return BuildInput
