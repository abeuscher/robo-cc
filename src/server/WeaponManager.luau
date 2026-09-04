-- Handles FireWeapon. Validates the request (Attacker, ATTACK phase, a shot
-- available via MatchController.consumeShot), then spawns a server-simulated
-- projectile and steps it on Heartbeat: integrate its own velocity with a
-- per-weapon gravity scale, raycast last position -> new position against blocks
-- and the Princess, act on the first hit, despawn after ProjectileLifetime.
--
-- The projectile Part is anchored and CanQuery/CanCollide false -- it is a
-- deterministic hit probe, not a physics body. It never touches blocks itself;
-- a hit applies an impulse and the projectile despawns. (The brief sketched an
-- unanchored, network-owned projectile; a manually stepped anchored part gives
-- the same server-authoritative raycast hits without an integrator to fight.)

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage.Shared.Config)
local Remotes = require(ReplicatedStorage.Shared.Remotes)

local Arena = require(script.Parent.Arena)
local MatchController = require(script.Parent.MatchController)

local WeaponManager = {}

local PROJECTILE_SIZE = Vector3.new(1.3, 1.3, 1.3)
local PROJECTILE_COLOR = Color3.fromRGB(255, 170, 80)
local MUZZLE_ORIGIN = Vector3.new(0, Config.GroundLevel + Config.MuzzleHeight, -(Config.GapWidth / 2))

-- [proj] = true. proj = { part, velocity, gravityScale, weapon, elapsed, params }
local active = {}

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

-- Raycast filter: only blocks and the Princess matter this session. A standing
-- block in the lane is hit before the Princess, which is how the ballista
-- "cannot arc over". Anything else (platforms, markers) is ignored.
local function hitParams()
	local root = Arena.root()
	local include = {}
	local blocks = root:FindFirstChild("Blocks")
	if blocks then
		table.insert(include, blocks)
	end
	local princess = root:FindFirstChild("Princess")
	if princess then
		table.insert(include, princess)
	end
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Include
	params.FilterDescendantsInstances = include
	return params
end

local function makeProjectile()
	local part = Instance.new("Part")
	part.Name = "Projectile"
	part.Shape = Enum.PartType.Ball
	part.Size = PROJECTILE_SIZE
	part.Color = PROJECTILE_COLOR
	part.Material = Enum.Material.Neon
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CastShadow = false
	part.Position = MUZZLE_ORIGIN

	local a0 = Instance.new("Attachment")
	a0.Position = Vector3.new(0, 0.45, 0)
	a0.Parent = part
	local a1 = Instance.new("Attachment")
	a1.Position = Vector3.new(0, -0.45, 0)
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
-- it into range. Ballista: dead flat along the horizontal aim, speed between
-- BallistaMinVelocity and BallistaMuzzleVelocity -- fired low it rakes the base
-- and cannot arc over a wall regardless of power. Catapult: horizontal heading
-- from the aim, pitched up by `angle`, scaled by `force`. The client value is a
-- request either way.
local function launchVelocity(weapon, direction, force, angle)
	local flat = Vector3.new(direction.X, 0, direction.Z)
	local heading = if flat.Magnitude > 1e-3 then flat.Unit else Vector3.zAxis
	if weapon == "Ballista" then
		local speed = math.clamp(force, Config.BallistaMinVelocity, Config.BallistaMuzzleVelocity)
		return heading * speed
	end
	local f = math.clamp(force, Config.CatapultMinForce, Config.CatapultMaxForce)
	local a = math.rad(math.clamp(angle, Config.CatapultMinAngle, Config.CatapultMaxAngle))
	return heading * (f * math.cos(a)) + Vector3.yAxis * (f * math.sin(a))
end

-- First hit along the step. A struck block takes an impulse along the
-- projectile's travel direction, scaled by the weapon's impact constant and the
-- block's mass so heavier (Wide) blocks get the same shove. The Princess is
-- inert this session -- the projectile just despawns on her.
local function onHit(proj, result)
	local part = result.Instance
	if part:GetAttribute("BlockId") then
		local impact = if proj.weapon == "Ballista" then Config.BallistaImpact else Config.CatapultImpact
		local dir = proj.velocity.Magnitude > 0 and proj.velocity.Unit or Vector3.zAxis
		part:ApplyImpulse(dir * impact * part.AssemblyMass)
	end
end

local function despawn(proj)
	proj.part:Destroy()
	active[proj] = nil
end

local function step(dt)
	for proj in active do
		proj.elapsed += dt
		proj.velocity -= Vector3.yAxis * (Workspace.Gravity * proj.gravityScale * dt)

		local from = proj.part.Position
		local delta = proj.velocity * dt
		local result = Workspace:Raycast(from, delta, proj.params)
		if result then
			onHit(proj, result)
			despawn(proj)
		else
			proj.part.Position = from + delta
			if proj.elapsed >= Config.ProjectileLifetime then
				despawn(proj)
			end
		end
	end
end

-- Spawn and register a projectile. Caller has already validated and consumed the
-- shot.
function WeaponManager.fire(weapon, direction, force, angle)
	local proj = {
		part = makeProjectile(),
		velocity = launchVelocity(weapon, direction, force, angle),
		gravityScale = if weapon == "Ballista" then Config.BallistaGravityScale else 1,
		weapon = weapon,
		elapsed = 0,
		params = hitParams(),
	}
	active[proj] = true
end

local function onFireWeapon(player, payload)
	if MatchController.getPhase() ~= "ATTACK" or not MatchController.isAttacker(player) then
		return
	end
	if typeof(payload) ~= "table" then
		return
	end
	local weapon = payload.weapon
	if weapon ~= "Ballista" and weapon ~= "Catapult" then
		return
	end
	local direction = payload.direction
	if typeof(direction) ~= "Vector3" or direction.Magnitude < 1e-3 then
		return
	end
	local force = tonumber(payload.force) or 0
	local angle = tonumber(payload.angle) or 0

	if not MatchController.consumeShot() then
		return
	end
	WeaponManager.fire(weapon, direction.Unit, force, angle)
end

function WeaponManager.start()
	Remotes.FireWeapon.OnServerEvent:Connect(onFireWeapon)
	RunService.Heartbeat:Connect(step)
end

return WeaponManager
