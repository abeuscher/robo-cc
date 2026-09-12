-- Watches the Princess for the win condition: once armed, checks her own
-- tilt against world up every Heartbeat and calls her dead the moment that
-- angle passes Config.PrincessTopplingAngle. She's a real unanchored body now
-- (session 009) -- this replaces both of the prior kill paths (a raycast-
-- reported direct hit from WeaponManager, and Touched by a fast-moving
-- BlockId part) outright, not generalized: a block landing on her, a wall
-- collapsing onto her (including the Builder's own), or a projectile strike
-- all funnel through this one physical check, and none of them matter except
-- whether she ends up tipped over. Armed only while a kill should count
-- (ATTACK through the RESOLVE settle beat); MatchController arms/disarms
-- around each round.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Config = require(ReplicatedStorage.Shared.Config)
local Arena = require(script.Parent.Arena)

local PrincessMonitor = {}

local dead = false
local armed = false
local deathCallback = nil
local princess = nil

local function killPrincess()
	if dead or not armed then
		return
	end
	dead = true
	if deathCallback then
		deathCallback("toppled")
	end
end

-- MatchController registers once at start() to hear about a kill the instant
-- it happens, rather than polling between shots.
function PrincessMonitor.onDeath(callback)
	deathCallback = callback
end

-- ATTACK-phase transition. Unanchor first, then SetNetworkOwner(nil) (it
-- errors on an anchored part) -- same ordering BlockManager.releaseAll() uses
-- for blocks. She becomes a real physical target the moment ATTACK begins.
function PrincessMonitor.arm()
	dead = false
	armed = true
	princess.Anchored = false
	princess:SetNetworkOwner(nil)
end

function PrincessMonitor.disarm()
	armed = false
end

function PrincessMonitor.isDead()
	return dead
end

function PrincessMonitor.reason()
	return if dead then "toppled" else nil
end

local function checkTilt()
	if dead or not armed then
		return
	end
	local upDot = princess.CFrame.UpVector:Dot(Vector3.yAxis)
	local tiltAngle = math.deg(math.acos(math.clamp(upDot, -1, 1)))
	if tiltAngle > Config.PrincessTopplingAngle then
		killPrincess()
	end
end

function PrincessMonitor.start()
	princess = Arena.root():WaitForChild("Princess")
	RunService.Heartbeat:Connect(checkTilt)
end

return PrincessMonitor
