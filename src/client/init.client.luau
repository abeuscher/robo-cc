local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Remotes = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Remotes"))
local TitleScreen = require(script:WaitForChild("TitleScreen"))
local Hud = require(script:WaitForChild("Hud"))
local BuildInput = require(script:WaitForChild("BuildInput"))
local CameraIntro = require(script:WaitForChild("CameraIntro"))

local live = false
local latestState = nil

Remotes.StateChanged.OnClientEvent:Connect(function(state)
	latestState = state
	if live then
		Hud.update(state)
		BuildInput.update(state)
	end
end)

local function begin()
	if live then
		return
	end
	live = true

	Hud.start()
	BuildInput.start()

	if latestState then
		Hud.update(latestState)
		BuildInput.update(latestState)
	end
end

TitleScreen.show(function()
	print("[client] Start pressed")
	Remotes.StartRequested:FireServer()
	CameraIntro.playAndRelease()
	begin()
end)

CameraIntro.start()
