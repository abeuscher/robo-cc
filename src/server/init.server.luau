local Arena = require(script.Arena)
local BlockManager = require(script.BlockManager)
local BuildManager = require(script.BuildManager)
local MatchController = require(script.MatchController)
local WeaponManager = require(script.WeaponManager)

Arena.build()
BlockManager.spawnAll()
MatchController.start()
BuildManager.start()
WeaponManager.start()

print("[server] Siege prototype booted")
