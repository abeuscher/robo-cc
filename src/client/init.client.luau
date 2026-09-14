local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Remotes = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Remotes"))
local TitleScreen = require(script:WaitForChild("TitleScreen"))
local Hud = require(script:WaitForChild("Hud"))
local ResultBanner = require(script:WaitForChild("ResultBanner"))
local BuildInput = require(script:WaitForChild("BuildInput"))
local FlagPositionInput = require(script:WaitForChild("FlagPositionInput"))
local FlagRevealEffect = require(script:WaitForChild("FlagRevealEffect"))
local AttackInput = require(script:WaitForChild("AttackInput"))
local ShieldInput = require(script:WaitForChild("ShieldInput"))
local AttackCamera = require(script:WaitForChild("AttackCamera"))
local BuildCamera = require(script:WaitForChild("BuildCamera"))
local PositionCamera = require(script:WaitForChild("PositionCamera"))

local live = false
local latestState = nil

Remotes.StateChanged.OnClientEvent:Connect(function(state)
	latestState = state
	if live then
		Hud.update(state)
		ResultBanner.update(state)
		BuildInput.update(state)
		FlagPositionInput.update(state)
		FlagRevealEffect.update(state)
		AttackInput.update(state)
		ShieldInput.update(state)
		AttackCamera.update(state)
		BuildCamera.update(state)
		PositionCamera.update(state)
	end
end)

local function begin()
	if live then
		return
	end
	live = true

	Hud.start()
	ResultBanner.start()
	BuildInput.start()
	FlagPositionInput.start()
	FlagRevealEffect.start()
	AttackInput.start()
	ShieldInput.start()
	AttackCamera.start()
	BuildCamera.start()
	PositionCamera.start()

	if latestState then
		Hud.update(latestState)
		ResultBanner.update(latestState)
		BuildInput.update(latestState)
		FlagPositionInput.update(latestState)
		FlagRevealEffect.update(latestState)
		AttackInput.update(latestState)
		ShieldInput.update(latestState)
		AttackCamera.update(latestState)
		BuildCamera.update(latestState)
		PositionCamera.update(latestState)
	end
end

-- No animated intro (session 016 -- removed the overhead swoop): the moment
-- Start is pressed, whichever fixed camera applies (BuildCamera for round 1's
-- Builder) just engages immediately via the normal update() path below.
TitleScreen.show(function()
	print("[client] Start pressed")
	Remotes.StartRequested:FireServer()
	begin()
end)
