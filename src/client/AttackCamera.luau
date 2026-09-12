-- Three selectable views for the Attacker during ATTACK, cycled with C:
-- top-down (default, engaged as soon as the Attacker's turn begins),
-- first-person (LockFirstPerson -- proven in session 002), and a 45-degree
-- side view looking down the trench. The Builder keeps the normal camera.
-- Stays engaged through RESOLVE too (session 009 feedback: the view used to
-- snap back the instant the last shot fired, cutting away before it landed)
-- -- roles don't swap until the round-end hold finishes, so the same player
-- stays "the Attacker" for the whole window. Released back to Custom/Classic
-- once the next round's BUILD phase arrives (or the local player isn't the
-- Attacker at all).

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage.Shared.Config)

local player = Players.LocalPlayer

local AttackCamera = {}

local MODES = { "TopDown", "FirstPerson", "Side45" }

-- World-space framing for the two scripted modes, derived from the trench
-- geometry (not hardcoded) so they stay centred if Config changes. Both look
-- toward the wall rather than straight down/across, which keeps CFrame.lookAt
-- well away from the straight-down singularity.
local FIRING_Z = -(Config.GapWidth / 2)
local WALL_Z = Config.BuildZoneOrigin.Z
local ARENA_MID_Z = (FIRING_Z + WALL_Z) / 2

local TOP_DOWN_HEIGHT = 45
local TOP_DOWN_CFRAME = CFrame.lookAt(
	Vector3.new(0, Config.GroundLevel + TOP_DOWN_HEIGHT, ARENA_MID_Z),
	Vector3.new(0, Config.GroundLevel, WALL_Z)
)

-- Clear of the boundary wall (session 003's later addition) both sideways and
-- vertically, so the view looks down over it rather than into its face.
local SIDE_OFFSET_X = Config.PlatformSize.X / 2 + Config.BoundaryWallThickness + 20
local SIDE_HEIGHT = Config.BoundaryWallHeight + 20
local SIDE_45_CFRAME = CFrame.lookAt(
	Vector3.new(SIDE_OFFSET_X, Config.GroundLevel + SIDE_HEIGHT, ARENA_MID_Z),
	Vector3.new(0, Config.GroundLevel, ARENA_MID_Z)
)

local active = false
local modeIndex = 1
local renderConn, inputConn

local function applyMode()
	local camera = Workspace.CurrentCamera
	if not camera then
		return
	end
	local mode = MODES[modeIndex]
	if mode == "FirstPerson" then
		camera.CameraType = Enum.CameraType.Custom
		player.CameraMode = Enum.CameraMode.LockFirstPerson
	elseif mode == "TopDown" then
		player.CameraMode = Enum.CameraMode.Classic
		camera.CameraType = Enum.CameraType.Scriptable
		camera.CFrame = TOP_DOWN_CFRAME
	else
		player.CameraMode = Enum.CameraMode.Classic
		camera.CameraType = Enum.CameraType.Scriptable
		camera.CFrame = SIDE_45_CFRAME
	end
end

-- The scripted modes set the camera CFrame once, but Scriptable CFrames can
-- get reset (character respawn, focus changes) -- reapply every frame rather
-- than trust it to stick. FirstPerson is Roblox's own follow camera, so it
-- needs no reapplication.
local function onRender()
	if MODES[modeIndex] ~= "FirstPerson" then
		applyMode()
	end
end

local function onInput(inputObject, gameProcessed)
	if gameProcessed then
		return
	end
	if inputObject.KeyCode == Enum.KeyCode.C then
		modeIndex = modeIndex % #MODES + 1
		applyMode()
	end
end

local function enter()
	if active then
		return
	end
	active = true
	modeIndex = 1
	applyMode()
	renderConn = RunService.RenderStepped:Connect(onRender)
	inputConn = UserInputService.InputBegan:Connect(onInput)
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
	if inputConn then
		inputConn:Disconnect()
		inputConn = nil
	end
	local camera = Workspace.CurrentCamera
	if camera then
		camera.CameraType = Enum.CameraType.Custom
	end
	player.CameraMode = Enum.CameraMode.Classic
end

-- Nothing to prime up front; update() owns the transitions.
function AttackCamera.start() end

function AttackCamera.update(state)
	local mine = (state.phase == "ATTACK" or state.phase == "RESOLVE")
		and state.roles ~= nil
		and state.roles.attacker == player.UserId
	if mine then
		enter()
	else
		exit()
	end
end

return AttackCamera
