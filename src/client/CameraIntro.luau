-- Camera intro. While the title screen covers the view, the camera sits high
-- above the local player's spawn point looking down, so the first thing they
-- see when the title clears is where their character is standing in the arena.
-- On Start it tweens from that overhead shot into the normal play camera and
-- hands control back to Roblox. Pure presentation -- no gameplay state here.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local player = Players.LocalPlayer

local CameraIntro = {}

-- Intro shot: camera position relative to the character, up and slightly back.
local OVERHEAD_OFFSET = Vector3.new(0, 32, 10)
-- Handoff pose: studs behind and above the character where the tween ends,
-- roughly where Roblox's default camera would sit.
local RELEASE_BACK = 12
local RELEASE_UP = 6.5
-- Seconds for the swoop from overhead to play camera.
local TWEEN_TIME = 3

local overheadConn = nil
local released = false

-- Waits for the local character and its root part; returns the root, or nil if
-- the character never arrives.
local function waitForRoot()
	local character = player.Character or player.CharacterAdded:Wait()
	return character:WaitForChild("HumanoidRootPart", 10)
end

-- The overhead intro CFrame for a root part: OVERHEAD_OFFSET away from it,
-- looking back at it. The offset isn't vertical, so the default up vector is fine.
local function overheadCFrame(root)
	return CFrame.lookAt(root.Position + OVERHEAD_OFFSET, root.Position)
end

-- The pose the tween ends on: behind and above the character, looking at the
-- upper body -- close to the default camera so the switch to Custom barely moves.
local function releaseCFrame(root)
	local eye = (root.CFrame * CFrame.new(0, RELEASE_UP, RELEASE_BACK)).Position
	return CFrame.lookAt(eye, root.Position + Vector3.new(0, 1.5, 0))
end

-- Takes the camera Scriptable and pins it to the overhead shot every frame, so
-- it tracks the character while MatchController is still positioning it and the
-- title screen is still covering the view. Bails if Start already happened.
function CameraIntro.start()
	local camera = Workspace.CurrentCamera
	local root = waitForRoot()
	if not camera or not root or released then
		return
	end

	camera.CameraType = Enum.CameraType.Scriptable
	camera.CFrame = overheadCFrame(root)

	overheadConn = RunService.RenderStepped:Connect(function()
		local current = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
		if current then
			camera.CFrame = overheadCFrame(current)
		end
	end)
end

-- Called on Start. Stops the overhead tracking, tweens the camera from wherever
-- it is into releaseCFrame, then restores the normal Roblox play camera on
-- completion. Safe to call once; further calls are ignored.
function CameraIntro.playAndRelease()
	if released then
		return
	end
	released = true

	local camera = Workspace.CurrentCamera

	if overheadConn then
		overheadConn:Disconnect()
		overheadConn = nil
	end

	local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
	if not camera or not root then
		if camera then
			camera.CameraType = Enum.CameraType.Custom
		end
		return
	end

	local tween = TweenService:Create(
		camera,
		TweenInfo.new(TWEEN_TIME, Enum.EasingStyle.Back, Enum.EasingDirection.In),
		{ CFrame = releaseCFrame(root) }
	)

	tween.Completed:Connect(function()
		camera.CameraType = Enum.CameraType.Custom
		local humanoid = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
		if humanoid then
			camera.CameraSubject = humanoid
		end
	end)

	tween:Play()
end

return CameraIntro
