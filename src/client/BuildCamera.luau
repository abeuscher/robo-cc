-- Fixed, non-rotatable camera for the Builder during BUILD (session 016).
-- Positioned outside the build zone -- past the grid, toward the gap -- and
-- elevated, looking back down at the grid and the Builder's own character
-- beyond it. The grid is always the nearest thing to the camera this way, so
-- the character's body (which used to sit between the old over-the-shoulder
-- camera and the wall) can never block it. Replaces that one-time "snap to a
-- good starting angle, then free-look" (session 011) with a full lock, the
-- same way AttackCamera locks the Attacker's view during ATTACK. Engages the
-- instant BUILD starts for this player -- there's no more intro swoop to wait
-- out (session 016 also removed CameraIntro outright). A first-pass framing,
-- meant to be iterated on once it's actually seen in Studio -- see
-- CAMERA_BACK/CAMERA_HEIGHT/TARGET_HEIGHT below.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage.Shared.Config)

local player = Players.LocalPlayer

local BuildCamera = {}

-- The grid plane sits at Config.BuildZoneOrigin.Z, but its own Y (half of
-- BuildZoneSize.Y) is the centre of the *theoretical worst-case* grid height
-- -- real walls are built from the ground up and rarely reach anywhere near
-- that tall, so framing on the geometric centre would aim mostly at empty
-- air above a real wall. TARGET_HEIGHT instead picks a modest height a real
-- wall-in-progress actually occupies.
local WALL_Z = Config.BuildZoneOrigin.Z
local TARGET_HEIGHT = Config.GroundLevel + 20
local CAMERA_BACK = 34 -- studs toward the gap (-Z) from the grid plane
local CAMERA_HEIGHT = 22 -- studs above TARGET_HEIGHT
local BUILD_CFRAME = CFrame.lookAt(
	Vector3.new(0, TARGET_HEIGHT + CAMERA_HEIGHT, WALL_Z - CAMERA_BACK),
	Vector3.new(0, TARGET_HEIGHT, WALL_Z)
)

local active = false
local renderConn

local function isBuilderInBuild(state)
	return state ~= nil and state.phase == "BUILD" and state.roles ~= nil and state.roles.builder == player.UserId
end

local function applyView()
	local camera = Workspace.CurrentCamera
	if camera then
		camera.CFrame = BUILD_CFRAME
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
		camera.CFrame = BUILD_CFRAME
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

function BuildCamera.start() end

function BuildCamera.update(state)
	if isBuilderInBuild(state) then
		enter()
	else
		exit()
	end
end

return BuildCamera
