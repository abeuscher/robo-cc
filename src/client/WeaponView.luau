-- Crude part-built props for the two weapons, parked just behind the muzzle at
-- the firing position so the Attacker can see which one is active. Purely
-- cosmetic and client-only: anchored, non-colliding, excluded from raycasts,
-- never replicated. AttackInput toggles the active one on the F key.

local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"))

local WeaponView = {}

local WOOD = Color3.fromRGB(94, 66, 41)
local IRON = Color3.fromRGB(70, 74, 82)
-- Two fixed emplacements on the firing pad, a stud in front of where the
-- Attacker stands, offset either side of centre to match Config.muzzleOrigin.
-- +Z is downrange, toward the wall.
local BASE_Z = -(Config.GapWidth / 2) - 1
local BASE = {
	Ballista = CFrame.new(-Config.MuzzleOffsetX, Config.GroundLevel + 0.5, BASE_Z),
	Catapult = CFrame.new(Config.MuzzleOffsetX, Config.GroundLevel + 0.5, BASE_Z),
}

local folder
local models = {}
local visible = false
local current = "Ballista"

local function piece(model, size, offset, color, base)
	local p = Instance.new("Part")
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CastShadow = false
	p.Material = Enum.Material.Wood
	p.Size = size
	p.CFrame = base * offset
	p.Color = color
	p.Parent = model
	return p
end

local function buildBallista()
	local model = Instance.new("Model")
	model.Name = "BallistaView"
	local base = BASE.Ballista
	piece(model, Vector3.new(1.4, 0.5, 4), CFrame.new(0, 0, 0), WOOD, base) -- stock
	piece(model, Vector3.new(5, 0.35, 0.35), CFrame.new(0, 0.3, 1.4), WOOD, base) -- bow limbs
	piece(model, Vector3.new(0.2, 0.2, 3.2), CFrame.new(0, 0.35, 0.2), IRON, base) -- rail / bolt
	piece(model, Vector3.new(2, 1.1, 0.4), CFrame.new(0, -0.1, -1.6) * CFrame.Angles(math.rad(20), 0, 0), WOOD, base) -- rear brace
	model.Parent = folder
	return model
end

local function buildCatapult()
	local model = Instance.new("Model")
	model.Name = "CatapultView"
	local base = BASE.Catapult
	piece(model, Vector3.new(2.6, 0.5, 3.4), CFrame.new(0, 0, 0), WOOD, base) -- frame
	piece(model, Vector3.new(0.4, 2, 0.4), CFrame.new(-0.9, 1, 0.2), WOOD, base) -- left post
	piece(model, Vector3.new(0.4, 2, 0.4), CFrame.new(0.9, 1, 0.2), WOOD, base) -- right post
	piece(model, Vector3.new(0.4, 0.4, 4), CFrame.new(0, 1.4, 0.1) * CFrame.Angles(math.rad(-35), 0, 0), WOOD, base) -- throwing arm
	local bucket = piece(model, Vector3.new(1, 0.8, 1), CFrame.new(0, 2.4, 1.8), IRON, base) -- bucket
	bucket.Material = Enum.Material.Metal
	model.Parent = folder
	return model
end

-- Shows only `current` when `visible`, hides everything otherwise.
local function apply()
	for name, model in models do
		local show = visible and name == current
		for _, part in model:GetChildren() do
			part.Transparency = show and 0 or 1
		end
	end
end

-- Builds both props once (hidden). Called from AttackInput.start().
function WeaponView.start()
	if folder then
		return
	end
	folder = Instance.new("Folder")
	folder.Name = "WeaponView"
	folder.Parent = Workspace
	models.Ballista = buildBallista()
	models.Catapult = buildCatapult()
	apply()
end

function WeaponView.setActive(weapon)
	current = weapon
	apply()
end

function WeaponView.setVisible(isVisible)
	visible = isVisible
	apply()
end

return WeaponView
