local Arena = require(script.Arena)
local BuildManager = require(script.BuildManager)
local MatchController = require(script.MatchController)
local PrincessMonitor = require(script.PrincessMonitor)
local WeaponManager = require(script.WeaponManager)

Arena.build()
PrincessMonitor.start()
MatchController.start()
BuildManager.start()
WeaponManager.start()

print("[server] Siege prototype booted")
