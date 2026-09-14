-- Handles FireWeapon. Validates the request (Attacker, ATTACK phase, a shot
-- available via MatchController.consumeShot), then spawns a real, unanchored
-- ball per weapon and hands its flight, collision, and bounce entirely to
-- Roblox's own physics engine -- no manual per-frame integration, no raycast
-- hit probe. (Sessions 002-008 stepped an anchored, non-colliding "hit probe"
-- part on Heartbeat instead, by design; session 009 replaces it with a real
-- physics body so projectiles can persist and bounce after landing. A struck
-- block's knockback is now real mass/velocity collision response, not a
-- manual ApplyImpulse -- and a struck Flag is no longer reported here at all:
-- FlagMonitor watches it directly via Touched instead (session 015), reading
-- the "Projectile" attribute every ball gets below to tell a real shot apart
-- from a falling block or anything else.)
--
-- Every projectile fired this round is tracked, not just ones still moving,
-- so a landed, at-rest ball still gets cleared at the next round's reset.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Config = require(ReplicatedStorage.Shared.Config)
local Remotes = require(ReplicatedStorage.Shared.Remotes)

local Arena = require(script.Parent.Arena)
local MatchController = require(script.Parent.MatchController)

local WeaponManager = {}

local PROJECTILE_COLOR = Color3.fromRGB(255, 170, 80)

-- Every projectile spawned this round, for clearAll() to walk.
local spawned = {}

-- Catapult balls currently spinning, keyed by part: { spin = Vector3, force =
-- VectorForce }. A single Heartbeat recomputes each entry's curving force
-- every frame from the ball's *current* velocity (a real Magnus force depends
-- on live velocity, not the launch velocity), until the ball's first contact
-- removes it -- "active only while airborne" per the brief.
local magnusActive = {}

-- Attaches a per-frame curving force to a catapult ball already carrying
-- angular velocity `spin` (about the world Y axis). Removed on first Touched
-- (landed or hit something) rather than a timer, since that's the real
-- boundary between "in flight" and not.
local function attachMagnus(part, spin)
	local attachment = Instance.new("Attachment")
	attachment.Parent = part

	local force = Instance.new("VectorForce")
	force.Attachment0 = attachment
	force.RelativeTo = Enum.ActuatorRelativeTo.World
	force.Force = Vector3.zero
	force.Parent = part

	magnusActive[part] = { spin = spin, force = force }

	local touchedConn
	touchedConn = part.Touched:Connect(function()
		touchedConn:Disconnect()
		magnusActive[part] = nil
	end)
end

local function projectilesFolder()
	local root = Arena.root()
	local existing = root:FindFirstChild("Projectiles")
	if existing then
		return existing
	end
	local folder = Instance.new("Folder")
	folder.Name = "Projectiles"
	folder.Parent = root
	return folder
end

local function projectileProps(weapon)
	if weapon == "Ballista" then
		return Config.BallistaProjectileSize,
			Config.BallistaProjectileMass,
			Config.BallistaProjectileFriction,
			Config.BallistaProjectileRestitution
	end
	return Config.CatapultProjectileSize,
		Config.CatapultProjectileMass,
		Config.CatapultProjectileFriction,
		Config.CatapultProjectileRestitution
end

-- Builds the ball at the muzzle, still anchored -- caller unanchors, hands it
-- server ownership, then sets its initial velocity. Density is derived from
-- the weapon's configured mass and the ball's own volume, the same way
-- BlockManager derives block density from BlockMass.
local function makeProjectile(weapon, origin)
	local size, mass, friction, restitution = projectileProps(weapon)

	local part = Instance.new("Part")
	part.Name = "Projectile"
	part.Shape = Enum.PartType.Ball
	part.Size = size
	part.Color = PROJECTILE_COLOR
	part.Material = Enum.Material.Neon
	part.Anchored = true
	part.CastShadow = false
	part.Position = origin
	local volume = (4 / 3) * math.pi * (size.X / 2) ^ 3
	part.CustomPhysicalProperties = PhysicalProperties.new(mass / volume, friction, restitution)
	part:SetAttribute("Projectile", true) -- lets FlagMonitor tell a real shot apart from a falling block or anything else (session 015)

	local a0 = Instance.new("Attachment")
	a0.Position = Vector3.new(0, size.Y * 0.4, 0)
	a0.Parent = part
	local a1 = Instance.new("Attachment")
	a1.Position = Vector3.new(0, -size.Y * 0.4, 0)
	a1.Parent = part
	local trail = Instance.new("Trail")
	trail.Attachment0 = a0
	trail.Attachment1 = a1
	trail.FaceCamera = true
	trail.Lifetime = 0.6
	trail.LightEmission = 0.8
	trail.Color = ColorSequence.new(PROJECTILE_COLOR)
	trail.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.1),
		NumberSequenceKeypoint.new(1, 1),
	})
	trail.Parent = part

	local light = Instance.new("PointLight")
	light.Color = PROJECTILE_COLOR
	light.Brightness = 3
	light.Range = 12
	light.Parent = part

	part.Parent = projectilesFolder()
	return part
end

-- Initial velocity for a shot. Both weapons take their launch meter's fill
-- (via `force`) from a two-click meter on the client -- the server just clamps
-- it into range. Ballista: horizontal heading from the aim, speed between
-- BallistaMinVelocity and BallistaMuzzleVelocity, pitched up by `angle`
-- clamped into BallistaMinAngle/MaxAngle (session 016 -- previously always
-- dead flat; the range is shallow enough that "cannot arc over" mostly still
-- holds against a wall built to real height). Catapult: horizontal heading
-- from the aim, pitched up by `angle`, scaled by `force`. The client value is
-- a request either way.
local function launchVelocity(weapon, direction, force, angle)
	local flat = Vector3.new(direction.X, 0, direction.Z)
	local heading = if flat.Magnitude > 1e-3 then flat.Unit else Vector3.zAxis
	if weapon == "Ballista" then
		local speed = math.clamp(force, Config.BallistaMinVelocity, Config.BallistaMuzzleVelocity)
		local a = math.rad(math.clamp(angle, Config.BallistaMinAngle, Config.BallistaMaxAngle))
		return heading * (speed * math.cos(a)) + Vector3.yAxis * (speed * math.sin(a))
	end
	local f = math.clamp(force, Config.CatapultMinForce, Config.CatapultMaxForce)
	local a = math.rad(math.clamp(angle, Config.CatapultMinAngle, Config.CatapultMaxAngle))
	return heading * (f * math.cos(a)) + Vector3.yAxis * (f * math.sin(a))
end

-- Destroys every projectile spawned this round, landed or not. Registered
-- with MatchController as a round-reset hook so nothing carries into the next
-- round.
function WeaponManager.clearAll()
	for _, part in spawned do
		part:Destroy()
	end
	spawned = {}
	magnusActive = {}
end

-- Spawn, unanchor, and launch a real projectile. Caller has already validated
-- and consumed the shot. Unanchor before SetNetworkOwner(nil) (it errors on
-- an anchored part) -- same ordering BlockManager.releaseAll() uses -- then
-- set the initial velocity; Roblox's own physics engine owns everything after
-- that. `spin` (rad/s about the vertical axis) only ever applies to the
-- catapult -- the ballista keeps its flat, spin-free identity regardless of
-- what the client sends.
function WeaponManager.fire(weapon, direction, force, angle, spin)
	local part = makeProjectile(weapon, Config.muzzleOrigin(weapon))
	part.Anchored = false
	part:SetNetworkOwner(nil)
	part.AssemblyLinearVelocity = launchVelocity(weapon, direction, force, angle)

	if weapon == "Catapult" then
		local clampedSpin = math.clamp(spin or 0, -Config.CatapultMaxSpin, Config.CatapultMaxSpin)
		if clampedSpin ~= 0 then
			local spinVector = Vector3.new(0, clampedSpin, 0)
			part.AssemblyAngularVelocity = spinVector
			attachMagnus(part, spinVector)
		end
	end

	table.insert(spawned, part)
end

local function onFireWeapon(player, payload)
	if MatchController.getPhase() ~= "ATTACK" or not MatchController.isAttacker(player) then
		return
	end
	if typeof(payload) ~= "table" then
		return
	end
	local direction = payload.direction
	if typeof(direction) ~= "Vector3" or direction.Magnitude < 1e-3 then
		return
	end
	local force = tonumber(payload.force) or 0
	local angle = tonumber(payload.angle) or 0
	local spin = tonumber(payload.spin) or 0

	-- Read before consumeShot(), which advances the shot index.
	local weapon = MatchController.currentWeapon()
	if not weapon then
		return
	end

	if not MatchController.consumeShot() then
		return
	end
	WeaponManager.fire(weapon, direction.Unit, force, angle, spin)
end

-- Recomputes every airborne catapult ball's curving force each frame from its
-- *current* velocity -- a real Magnus force tracks live velocity, not the
-- launch velocity, so this can't be set once at fire() and left alone. Force
-- is mass*acceleration so the tuned curve (Config.CatapultMagnusCoefficient)
-- stays the same regardless of the ball's own mass.
local function updateMagnus()
	for part, entry in magnusActive do
		if part.Parent then
			local accel = entry.spin:Cross(part.AssemblyLinearVelocity) * Config.CatapultMagnusCoefficient
			entry.force.Force = accel * part.AssemblyMass
		else
			magnusActive[part] = nil
		end
	end
end

function WeaponManager.start()
	Remotes.FireWeapon.OnServerEvent:Connect(onFireWeapon)
	MatchController.onRoundReset(WeaponManager.clearAll)
	RunService.Heartbeat:Connect(updateMagnus)
end

return WeaponManager
