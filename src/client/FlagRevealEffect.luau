-- A brief visual pulse on the Flag the instant it's revealed (session 015
-- follow-up): playtesting found the reveal was easy to miss entirely, even
-- though the server scored it correctly -- this is purely the "something just
-- happened" cue, with no bearing on scoring itself. Driven off the shared
-- StateChanged.flagRevealed field, so every client (both roles) plays the
-- same effect at the same moment, not just the Attacker whose concealment
-- actually changes.

local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local FlagRevealEffect = {}

local FLASH_COLOR = Color3.fromRGB(255, 255, 255)
local FLASH_UP_TIME = 0.12
local FLASH_DOWN_TIME = 0.28
local GLOW_FADE_TIME = 1

local wasRevealed = false
local initialized = false -- see update(): the first broadcast is a sync, not a transition

local function flagPart()
	local root = Workspace:FindFirstChild("ActiveRound")
	return root and root:FindFirstChild("Flag")
end

-- Flashes the Flag's own color to white and back (readable even at a glance),
-- plus a glowing Highlight outline that fades out over a second (readable at
-- any camera distance/angle, unlike the color change alone).
local function playRevealEffect()
	local flag = flagPart()
	if not flag then
		return
	end

	local originalColor = flag.Color
	local flashUp = TweenService:Create(
		flag,
		TweenInfo.new(FLASH_UP_TIME, Enum.EasingStyle.Sine, Enum.EasingDirection.Out),
		{ Color = FLASH_COLOR }
	)
	flashUp.Completed:Connect(function()
		TweenService:Create(
			flag,
			TweenInfo.new(FLASH_DOWN_TIME, Enum.EasingStyle.Sine, Enum.EasingDirection.In),
			{ Color = originalColor }
		):Play()
	end)
	flashUp:Play()

	local highlight = Instance.new("Highlight")
	highlight.FillColor = FLASH_COLOR
	highlight.OutlineColor = FLASH_COLOR
	highlight.FillTransparency = 0.3
	highlight.OutlineTransparency = 0
	highlight.Parent = flag

	local fade = TweenService:Create(
		highlight,
		TweenInfo.new(GLOW_FADE_TIME, Enum.EasingStyle.Quad, Enum.EasingDirection.In),
		{ FillTransparency = 1, OutlineTransparency = 1 }
	)
	fade.Completed:Connect(function()
		highlight:Destroy()
	end)
	fade:Play()
end

function FlagRevealEffect.start() end

-- Called on every StateChanged. Only fires on the false -> true edge, so it
-- plays exactly once per round regardless of how many broadcasts follow. The
-- very first call (init.client.luau replays whatever state already arrived
-- as soon as the local scripts start up) is treated as a baseline sync rather
-- than a transition -- otherwise joining or respawning mid-round with the
-- Flag already revealed would incorrectly play the effect.
function FlagRevealEffect.update(state)
	local revealed = state.flagRevealed == true
	if initialized and revealed and not wasRevealed then
		playRevealEffect()
	end
	wasRevealed = revealed
	initialized = true
end

return FlagRevealEffect
