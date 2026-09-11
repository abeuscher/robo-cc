-- Watches the Princess part for the spec's two kill paths: a direct projectile
-- hit (reported by WeaponManager, which already raycasts against her) and
-- contact from any block moving faster than Config.MovingBlockKillSpeed --
-- no owner check, so a Builder's own wall counts. Armed only while a kill
-- should count (ATTACK through the RESOLVE settle beat); MatchController
-- arms/disarms around each round.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Arena = require(script.Parent.Arena)

local PrincessMonitor = {}

local dead = false
local deathReason = nil
local armed = false
local deathCallback = nil

local function killPrincess(reason)
	if dead or not armed then
		return
	end
	dead = true
	deathReason = reason
	if deathCallback then
		deathCallback(reason)
	end
end

-- MatchController registers once at start() to hear about a kill the instant
-- it happens, rather than polling between shots.
function PrincessMonitor.onDeath(callback)
	deathCallback = callback
end

function PrincessMonitor.arm()
	dead = false
	deathReason = nil
	armed = true
end

function PrincessMonitor.disarm()
	armed = false
end

function PrincessMonitor.isDead()
	return dead
end

function PrincessMonitor.reason()
	return deathReason
end

-- Called by WeaponManager when a projectile's raycast lands on the Princess.
function PrincessMonitor.reportDirectHit()
	killPrincess("direct")
end

local function onTouched(otherPart)
	if dead or not armed then
		return
	end
	if not otherPart:GetAttribute("BlockId") then
		return
	end
	if otherPart.AssemblyLinearVelocity.Magnitude > Config.MovingBlockKillSpeed then
		killPrincess("crushed")
	end
end

function PrincessMonitor.start()
	local princess = Arena.root():WaitForChild("Princess")
	princess.Touched:Connect(onTouched)
end

return PrincessMonitor
