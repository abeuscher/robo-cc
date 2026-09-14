-- Fixed, non-rotatable camera for the Builder during POSITION (session 016).
-- Positioned behind and above the Builder's own standing spot -- past the
-- far edge of where the Flag can actually go -- looking back over the whole
-- Flag-placement box (Config.FlagPlacementMinDistance..MaxDistance) so it's
-- fully visible in one shot while choosing where to click, the same locking
-- technique BuildCamera and AttackCamera already use elsewhere. Hands control
-- straight back to Roblox's normal follow camera the moment POSITION ends
-- (either by placing the Flag or -- in principle -- any other phase change),
-- so ATTACK's Builder gets an ordinary view of their own character, same as
-- before this pass existed. A first-pass framing, meant to be iterated on
-- once it's actually seen in Studio.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage.Shared.Config)

local player = Players.LocalPlayer

local PositionCamera = {}

-- The Flag-placement box sits behind the build plane (Config.BuildZoneOrigin.Z
-- + Min..MaxDistance). The camera sits past its far edge, elevated, looking
-- back at its centre -- "outside" the box the same way BuildCamera sits
-- outside the grid, so nothing (the Builder's own character included) can
-- get between the camera and the area they're aiming at.
local WALL_Z = Config.BuildZoneOrigin.Z
local FLAG_NEAR_Z = WALL_Z + Config.FlagPlacementMinDistance
local FLAG_FAR_Z = WALL_Z + Config.FlagPlacementMaxDistance
local FLAG_CENTER_Z = (FLAG_NEAR_Z + FLAG_FAR_Z) / 2

local CAMERA_BACK = 26 -- studs past the placement box's far edge
local CAMERA_HEIGHT = 30 -- studs above ground
local POSITION_CFRAME = CFrame.lookAt(
	Vector3.new(0, Config.GroundLevel + CAMERA_HEIGHT, FLAG_FAR_Z + CAMERA_BACK),
	Vector3.new(0, Config.GroundLevel, FLAG_CENTER_Z)
)

local active = false
local renderConn

local function isBuilderInPosition(state)
	return state ~= nil
		and state.phase == "POSITION"
		and state.roles ~= nil
		and state.roles.builder == player.UserId
end

local function applyView()
	local camera = Workspace.CurrentCamera
	if camera then
		camera.CFrame = POSITION_CFRAME
	end
end

local function enter()
	if active then
		return
	end
	active = true
	local camera = Workspace.CurrentCamera
	if camera then
		camera.CameraType = Enum.CameraType.Scriptable
		camera.CFrame = POSITION_CFRAME
	end
	renderConn = RunService.RenderStepped:Connect(applyView)
end

local function exit()
	if not active then
		return
	end
	active = false
	if renderConn then
		renderConn:Disconnect()
		renderConn = nil
	end
	local camera = Workspace.CurrentCamera
	if camera then
		camera.CameraType = Enum.CameraType.Custom
	end
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if humanoid and camera then
		camera.CameraSubject = humanoid
	end
end

function PositionCamera.start() end

function PositionCamera.update(state)
	if isBuilderInPosition(state) then
		enter()
	else
		exit()
	end
end

return PositionCamera
