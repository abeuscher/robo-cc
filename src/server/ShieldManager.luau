-- Handles ActivateShield: spawns the Builder's once-per-round timed physical
-- barrier during ATTACK. MatchController.useShield() owns the one-use flag and
-- validation (role, phase, already-used) -- the same split WeaponManager has
-- with consumeShot() -- this module only owns the physical part itself: where
-- it sits, how long it stays up, and cleaning up a live one at round reset.
-- Unlike the guard piece (session 010) the shield never unanchors; it's a
-- static barrier for its whole life (Config.ShieldDuration), a deliberate,
-- scoped exception to "everything is real physics" settled at this session's
-- Open Gate -- an unanchored shield could itself get shoved into the Princess
-- by a heavy hit and defeat the point.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Remotes = require(ReplicatedStorage.Shared.Remotes)

local Arena = require(script.Parent.Arena)
local MatchController = require(script.Parent.MatchController)

local ShieldManager = {}

local SHIELD_COLOR = Color3.fromRGB(120, 190, 255)

local activePart = nil

local function shieldPosition()
	return Vector3.new(
		0,
		Config.GroundLevel + Config.ShieldSize.Y / 2,
		Config.BuildZoneOrigin.Z + Config.ShieldDistance
	)
end

local function despawn()
	if activePart then
		activePart:Destroy()
		activePart = nil
	end
end

-- Round-reset hook: clears any shield still up (shouldn't normally happen,
-- since ShieldDuration is well under ResolveSettleTime, but hygiene matches
-- WeaponManager.clearAll()).
function ShieldManager.reset()
	despawn()
end

-- Spawns the barrier, replacing any lingering one, and schedules its own
-- despawn after Config.ShieldDuration. Caller (onActivateShield) has already
-- confirmed with MatchController.useShield() that this activation counts.
local function spawnShield()
	despawn()

	local part = Instance.new("Part")
	part.Name = "Shield"
	part.Anchored = true
	part.CanCollide = true
	part.Size = Config.ShieldSize
	part.Position = shieldPosition()
	part.Color = SHIELD_COLOR
	part.Material = Enum.Material.ForceField
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	part.Parent = Arena.root()
	activePart = part

	task.delay(Config.ShieldDuration, function()
		if activePart == part then
			despawn()
		end
	end)
end

local function onActivateShield(player)
	if MatchController.useShield(player) then
		spawnShield()
	end
end

function ShieldManager.start()
	Remotes.ActivateShield.OnServerEvent:Connect(onActivateShield)
	MatchController.onRoundReset(ShieldManager.reset)
end

return ShieldManager
