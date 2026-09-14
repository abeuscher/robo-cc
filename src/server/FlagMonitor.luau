-- Watches the Flag for hits (session 015, replaces PrincessMonitor -- the
-- Flag doesn't topple, it's hit or it isn't, so this reverts to a Touched-
-- based check, the model the Princess herself used before session 009).
-- Distinguishes what touched it by attribute: a projectile (WeaponManager
-- tags every one it spawns) always scores and reveals; a wall piece
-- (BlockManager's own BlockId tag) only reveals, and only if it's actually
-- falling -- Config.FlagCollapseSpeed filters out ordinary resting contact
-- from a settled wall leaning against it. Anything else (the shield, the
-- ground, a player) is ignored. Once revealed, stays revealed; once struck,
-- a later collapse-only touch can never downgrade that. Armed
-- only while a hit should count (ATTACK through the RESOLVE settle beat);
-- MatchController arms/disarms around each round.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Arena = require(script.Parent.Arena)

local FlagMonitor = {}

local armed = false
local outcome = "survived" -- "survived" | "collapsed" | "struck"
local revealCallback = nil
local flag = nil
local touchedConn = nil

-- MatchController registers once at start() to broadcast the reveal the
-- instant it happens, rather than waiting for the next unrelated state change
-- (mirrors the "broadcast it on every relevant change" lesson sessions
-- 007/008 established for the mandated weapon and the held shape).
function FlagMonitor.onReveal(callback)
	revealCallback = callback
end

local function reveal(newOutcome)
	local wasHidden = outcome == "survived"
	-- A projectile always wins (score is permanent once earned); a collapse
	-- only counts if nothing has scored yet.
	if newOutcome == "struck" then
		outcome = "struck"
	elseif outcome == "survived" then
		outcome = "collapsed"
	end
	if wasHidden and outcome ~= "survived" and revealCallback then
		revealCallback()
	end
end

local function onTouched(other)
	if not armed then
		return
	end
	if other:GetAttribute("Projectile") then
		reveal("struck")
		return
	end
	if other:GetAttribute("BlockId") and other.AssemblyLinearVelocity.Magnitude > Config.FlagCollapseSpeed then
		reveal("collapsed")
	end
end

function FlagMonitor.arm()
	armed = true
	outcome = "survived"
end

-- Also clears the latched outcome -- called from finishRound() after it's
-- already read reason()/scored(), so this is safe to do here rather than
-- waiting for the next arm(). Without it, a struck/collapsed Flag would still
-- read as revealed to the next round's Attacker during BUILD/POSITION, before
-- FlagMonitor.arm() runs again.
function FlagMonitor.disarm()
	armed = false
	outcome = "survived"
end

function FlagMonitor.isRevealed()
	return outcome ~= "survived"
end

-- Only a direct projectile hit scores -- an incidental wall-collapse reveal
-- does not (session 015's own design tension: the Attacker gets a real
-- mechanism to force the reveal, separate from what actually scores).
function FlagMonitor.scored()
	return outcome == "struck"
end

function FlagMonitor.reason()
	return outcome
end

function FlagMonitor.start()
	flag = Arena.root():WaitForChild("Flag")
	touchedConn = flag.Touched:Connect(onTouched)
end

return FlagMonitor
