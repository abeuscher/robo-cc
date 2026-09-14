-- Builder-only. Active only during POSITION (session 015): the one chance,
-- after ConfirmBuild and before ATTACK, to relocate the Flag. A single click
-- on the ground behind the wall both chooses the spot and confirms it -- no
-- drag, no separate confirm step, matching the game's existing click-to-place
-- feel (BuildInput's own click-to-place, Confirm Wall). The server re-clamps
-- into Config.FlagPlacementMaxOffsetX/MinDistance/MaxDistance regardless of
-- what the client thought was valid; this module's own bounds check only
-- decides whether to show the ghost and let the click fire at all.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Remotes = require(Shared:WaitForChild("Remotes"))

local player = Players.LocalPlayer

local FlagPositionInput = {}

local GHOST_COLOR = Color3.fromRGB(255, 105, 180)

local active = false
local ghost
local renderConn, clickConn

local function ensureGhost()
	if ghost then
		return
	end
	ghost = Instance.new("Part")
	ghost.Name = "FlagGhost"
	ghost.Anchored = true
	ghost.CanCollide = false
	ghost.CanQuery = false
	ghost.CastShadow = false
	ghost.Color = GHOST_COLOR
	-- Starts hidden. Every client creates this part (FlagPositionInput.start()
	-- runs for both roles), but onRender only ever reveals it while this
	-- client is actively the Builder placing during POSITION -- a visible
	-- default transparency here previously left it sitting at the world
	-- origin for everyone else to see, looking like a second flag.
	ghost.Transparency = 1
	ghost.Size = Config.FlagSize
	ghost.Parent = Workspace
end

local function hideGhost()
	if ghost then
		ghost.Transparency = 1
	end
end

-- World-space ray from the camera through the current mouse pixel, or nil.
local function cameraRay()
	local camera = Workspace.CurrentCamera
	if not camera then
		return nil
	end
	local mouse = UserInputService:GetMouseLocation()
	return camera:ViewportPointToRay(mouse.X, mouse.Y)
end

-- Intersects the ray with the flat ground plane (world Y = GroundLevel).
-- Returns nil if the ray is parallel to it or points away from it.
local function groundPointUnderRay(ray)
	local dy = ray.Direction.Y
	if math.abs(dy) < 1e-4 then
		return nil
	end
	local t = (Config.GroundLevel - ray.Origin.Y) / dy
	if t <= 0 then
		return nil
	end
	return ray.Origin + ray.Direction * t
end

-- Mirrors the server-side clamp in MatchController.relocateFlag -- this is
-- just the client's own check for whether to show the ghost / send the
-- request at all; the server is the one that actually enforces it.
local function withinPlacementBounds(point)
	local distance = point.Z - Config.BuildZoneOrigin.Z
	return math.abs(point.X) <= Config.FlagPlacementMaxOffsetX
		and distance >= Config.FlagPlacementMinDistance
		and distance <= Config.FlagPlacementMaxDistance
end

local function onRender()
	local ray = cameraRay()
	local point = ray and groundPointUnderRay(ray)
	if not point or not withinPlacementBounds(point) then
		hideGhost()
		return
	end
	ghost.CFrame = CFrame.new(point.X, Config.GroundLevel + Config.FlagSize.Y / 2, point.Z)
	ghost.Transparency = 0.5
end

local function onInput(inputObject, gameProcessed)
	if gameProcessed or inputObject.UserInputType ~= Enum.UserInputType.MouseButton1 then
		return
	end
	local ray = cameraRay()
	local point = ray and groundPointUnderRay(ray)
	if not point or not withinPlacementBounds(point) then
		return
	end
	Remotes.RelocateFlag:FireServer({ position = point })
end

function FlagPositionInput.start()
	ensureGhost()
end

-- Called on every StateChanged. Live only while phase == "POSITION" and the
-- local player is the Builder.
function FlagPositionInput.update(state)
	local shouldBeActive = state.phase == "POSITION" and state.roles ~= nil and state.roles.builder == player.UserId

	if shouldBeActive == active then
		return
	end
	active = shouldBeActive

	if active then
		ensureGhost()
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
		hideGhost()
	end
end

return FlagPositionInput
