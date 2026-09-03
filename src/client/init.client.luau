local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Remotes = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Remotes"))
local TitleScreen = require(script:WaitForChild("TitleScreen"))

TitleScreen.show(function()
	print("[client] Start pressed")
	Remotes.StartRequested:FireServer()
end)
