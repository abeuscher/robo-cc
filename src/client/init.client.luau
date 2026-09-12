local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Remotes = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Remotes"))
local TitleScreen = require(script:WaitForChild("TitleScreen"))
local Hud = require(script:WaitForChild("Hud"))
local ResultBanner = require(script:WaitForChild("ResultBanner"))
local BuildInput = require(script:WaitForChild("BuildInput"))
local AttackInput = require(script:WaitForChild("AttackInput"))
local AttackCamera = require(script:WaitForChild("AttackCamera"))
local BuildCamera = require(script:WaitForChild("BuildCamera"))
local CameraIntro = require(script:WaitForChild("CameraIntro"))

local live = false
local latestState = nil

Remotes.StateChanged.OnClientEvent:Connect(function(state)
	latestState = state
	if live then
		Hud.update(state)
		ResultBanner.update(state)
		BuildInput.update(state)
		AttackInput.update(state)
		AttackCamera.update(state)
		BuildCamera.update(state)
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
	AttackInput.start()
	AttackCamera.start()
	BuildCamera.start()

	if latestState then
		Hud.update(latestState)
		ResultBanner.update(latestState)
		BuildInput.update(latestState)
		AttackInput.update(latestState)
		AttackCamera.update(latestState)
		BuildCamera.update(latestState)
	end
end

TitleScreen.show(function()
	print("[client] Start pressed")
	Remotes.StartRequested:FireServer()
	CameraIntro.playAndRelease()
	begin()
end)

CameraIntro.start()
