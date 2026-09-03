local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Remotes = require(ReplicatedStorage.Shared.Remotes)

Remotes.StartRequested.OnServerEvent:Connect(function(player)
	print(string.format("[server] StartRequested from %s (%d)", player.Name, player.UserId))
end)

print("[server] Siege prototype booted, waiting for Start")
