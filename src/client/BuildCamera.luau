-- Snaps the Builder's camera to a fixed, consistent view the instant each
-- BUILD phase begins for them -- so a round that started as the Attacker
-- (leaving the camera in one of AttackCamera's scripted views, or just
-- wherever the player last looked) doesn't carry that orientation into the
-- next build. Only fires on the BUILD-phase edge, never on every StateChanged
-- during BUILD (placing a block rebroadcasts state too), so it never yanks
-- the view out from under a player actively looking around their wall.

local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")

local player = Players.LocalPlayer

local BuildCamera = {}

-- Same behind-and-above-the-character framing CameraIntro releases into.
-- This reads as "the same view every round" not because it hardcodes an
-- arena position, but because MatchController.standFor() re-teleports the
-- Builder's character to the same pose every round -- anchoring the camera
-- to the character is enough.
local EYE_BACK = 12
local EYE_UP = 6.5

local wasBuilder = false
local primed = false -- see BuildCamera.update

local function resetCFrame(root)
	local eye = (root.CFrame * CFrame.new(0, EYE_UP, EYE_BACK)).Position
	return CFrame.lookAt(eye, root.Position + Vector3.new(0, 1.5, 0))
end

-- Scriptable-then-Custom, exactly like CameraIntro's own release: setting
-- CFrame while Scriptable and then handing back to Custom is what makes
-- Roblox's default camera controller pick up its look angle from that CFrame
-- instead of wherever it last was.
local function resetView()
	local camera = Workspace.CurrentCamera
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not camera or not root then
		return
	end
	camera.CameraType = Enum.CameraType.Scriptable
	camera.CFrame = resetCFrame(root)
	camera.CameraType = Enum.CameraType.Custom
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if humanoid then
		camera.CameraSubject = humanoid
	end
end

-- Nothing to prime up front; update() owns the reset.
function BuildCamera.start() end

function BuildCamera.update(state)
	local isBuilder = state.phase == "BUILD" and state.roles ~= nil and state.roles.builder == player.UserId

	-- Skip the very first call (init.client.luau replays whatever state
	-- already arrived as soon as the local scripts start up): that can land
	-- while CameraIntro's own release tween is still mid-flight, and forcing
	-- CameraType back and forth would fight it. Round 1's Builder gets their
	-- first framing from CameraIntro instead; every real BUILD-phase edge
	-- after that (including the very next one) resets as normal.
	if primed and isBuilder and not wasBuilder then
		resetView()
	end
	wasBuilder = isBuilder
	primed = true
end

return BuildCamera
