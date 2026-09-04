local Arena = require(script.Arena)
local BlockManager = require(script.BlockManager)
local BuildManager = require(script.BuildManager)
local MatchController = require(script.MatchController)

Arena.build()
BlockManager.spawnAll()
MatchController.start()
BuildManager.start()

print("[server] Siege prototype booted")
