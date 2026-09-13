-- Attacker-only aiming. Active while phase == "ATTACK" and the local player is
-- the Attacker. Mouse sets aim direction from a fixed muzzle origin, Q/E adjust
-- the catapult angle. Weapon is not a client choice -- state.weapon mirrors
-- whichever weapon the server's fixed shot sequence currently mandates
-- (Config.ShotSequence). A crosshair marks the predicted impact point (traced
-- by stepping the same initial velocity forward under gravity the real
-- projectile launches with) and turns green when that impact is a wall
-- block; a light dashed line sketches the path to it.
--
-- Both weapons fire off the same launch meter (right side of screen), one
-- button pressed in sequence rather than several different ones. First click
-- locks the current aim, hides the 3D targeting, and runs the fill bar
-- linearly from empty to full and back to empty once; a target tick marks the
-- fill to aim for -- the force needed to reach the point you aimed at for the
-- catapult, always the top for the ballista (more power, harder hit). Second
-- click freezes the bar wherever it is. For the ballista that fires
-- immediately; the catapult (session 013) instead moves to a small spin meter
-- above the power one, oscillating left-right faster the harder the power
-- swing was -- a third click freezes it and fires with that spin, curving the
-- shot. Let the power bar run out untouched and it resets to idle with no shot
-- (press again for a fresh attempt); let the spin bar run out instead and it
-- still fires, pinned to full spin on the right -- only power has a safe
-- cancel. Everything sent is intent -- the server clamps force/angle/spin and
-- owns the projectile.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local TweenService = game:GetService("TweenService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Remotes = require(Shared:WaitForChild("Remotes"))
local Hud = require(script.Parent:WaitForChild("Hud"))
local WeaponView = require(script.Parent:WaitForChild("WeaponView"))

local player = Players.LocalPlayer

local AttackInput = {}

-- Q/E increment. UI feel, not gameplay balance, so it lives here rather than
-- in Config.
local ANGLE_STEP = 5

-- Aim ray reach and arc-trace resolution (catapult only -- see traceShot).
local AIM_RANGE = 1000
local TRACE_DT = 1 / 90
local TRACE_MAX_STEPS = 360
local TRACE_RANGE = 140

-- One full ascent or descent of the launch meter: linear, no bounce. A press
-- runs the bar up then back down once and stops -- it does not loop on its own;
-- pressing again starts a fresh up-and-down. 2.4s, 30% faster than the
-- original 3.4s (session 012 playtest feedback).
local METER_LEG_TIME = 2.4

-- Catapult spin stage (session 013): a second, small meter that only appears
-- for the catapult, right after power freezes. It oscillates left-right on a
-- continuous loop (unlike the power meter, which runs once and stops) -- how
-- fast depends on how hard the power swing was, so a big swing is harder to
-- land a clean spin on. Same button as the rest of the sequence: freezing it
-- fires; letting it run out doesn't cancel like the power meter does, it
-- fires pinned to full spin on the right. UI feel, not gameplay balance, so
-- these live here rather than in Config.
local SPIN_OSC_MIN_FREQ = 0.5 -- Hz, at the weakest locked-in power
local SPIN_OSC_MAX_FREQ = 2 -- Hz, at the strongest locked-in power
local SPIN_TIMEOUT = 3 -- seconds before an un-frozen spin stage auto-fires

local CROSSHAIR_COLOR = Color3.fromRGB(255, 230, 120)
local CROSSHAIR_HIT_COLOR = Color3.fromRGB(100, 230, 130)
local DASH_COLOR = Color3.fromRGB(255, 255, 255)
local DASH_THICKNESS = 0.07
local DASH_FILL = 0.55 -- fraction of each traced step drawn, leaving a gap

local active = false
local renderConn, inputConn
local shotsRemaining = 0

local markerFolder
local crosshairPart, crosshairGui
local crosshairFrames = {}
local dashes = {}

local meterGui, meterFill, meterTargetLine
local spinTrack, spinIndicator
local fillTween, fillConn

-- "idle" (aiming, nothing locked yet) -> "power" (first click made, power
-- swinging) -> "spin" (catapult only: second click made, spin oscillating).
-- A third click (or the spin timeout) fires and returns to "idle".
local stage = "idle"
local lockedWeapon, lockedDirection, lockedAngle, lockedForce
local spinStartClock, spinFreq, currentSpinValue = nil, nil, 0

local state = {
	weapon = "Ballista",
	angle = math.floor((Config.CatapultMinAngle + Config.CatapultMaxAngle) / 2),
}

-- Pushes the current weapon / angle to the HUD readout.
local function publish()
	Hud.setAttackReadout({ weapon = state.weapon, angle = state.angle })
end

-- Builds the crosshair: an invisible marker Part carrying a screen-facing
-- BillboardGui drawn from Frames (four ticks around a centre dot). Client-only,
-- non-colliding, excluded from raycasts. Starts hidden.
local function makeCrosshair()
	local part = Instance.new("Part")
	part.Name = "Marker"
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CastShadow = false
	part.Transparency = 1
	part.Size = Vector3.new(0.2, 0.2, 0.2)
	part.Parent = markerFolder

	local gui = Instance.new("BillboardGui")
	gui.Name = "Crosshair"
	gui.Size = UDim2.fromOffset(46, 46)
	gui.AlwaysOnTop = true
	gui.LightInfluence = 0
	gui.Enabled = false
	gui.Parent = part

	local function bar(w, h, anchor, pos)
		local f = Instance.new("Frame")
		f.BorderSizePixel = 0
		f.BackgroundColor3 = CROSSHAIR_COLOR
		f.AnchorPoint = anchor
		f.Position = pos
		f.Size = UDim2.fromOffset(w, h)
		f.Parent = gui
		table.insert(crosshairFrames, f)
	end
	bar(2, 14, Vector2.new(0.5, 0), UDim2.fromScale(0.5, 0.05)) -- top tick
	bar(2, 14, Vector2.new(0.5, 1), UDim2.fromScale(0.5, 0.95)) -- bottom tick
	bar(14, 2, Vector2.new(0, 0.5), UDim2.fromScale(0.05, 0.5)) -- left tick
	bar(14, 2, Vector2.new(1, 0.5), UDim2.fromScale(0.95, 0.5)) -- right tick
	bar(4, 4, Vector2.new(0.5, 0.5), UDim2.fromScale(0.5, 0.5)) -- centre dot

	return part, gui
end

-- Yellow by default; green when the traced shot lands on a wall block.
local function setCrosshairHit(isWallHit)
	local color = isWallHit and CROSSHAIR_HIT_COLOR or CROSSHAIR_COLOR
	for _, frame in crosshairFrames do
		frame.BackgroundColor3 = color
	end
end

-- One reusable thin Part for a dash, created on demand and parked in
-- markerFolder. Client-only, non-colliding, excluded from raycasts.
local function dashPart(index)
	local existing = dashes[index]
	if existing then
		return existing
	end
	local part = Instance.new("Part")
	part.Name = "Dash"
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CastShadow = false
	part.Material = Enum.Material.Neon
	part.Color = DASH_COLOR
	part.Transparency = 1
	part.Size = Vector3.new(DASH_THICKNESS, DASH_THICKNESS, DASH_THICKNESS)
	part.Parent = markerFolder
	dashes[index] = part
	return part
end

-- Hides every dash from `fromIndex` on (inclusive).
local function hideDashesFrom(fromIndex)
	for i = fromIndex, #dashes do
		dashes[i].Transparency = 1
	end
end

-- Lays a light dashed line along the traced path: every other step becomes a
-- dash shrunk to DASH_FILL of its length, leaving a gap before the next.
local function drawDashes(points)
	local shown = 0
	for i = 1, #points - 1, 2 do
		local a, b = points[i], points[i + 1]
		local length = (b - a).Magnitude
		shown += 1
		local part = dashPart(shown)
		part.Size = Vector3.new(DASH_THICKNESS, DASH_THICKNESS, math.max(length * DASH_FILL, 0.05))
		part.CFrame = CFrame.lookAt((a + b) / 2, b)
		part.Transparency = 0.45
	end
	hideDashesFrom(shown + 1)
end

-- Builds the launch meter: a vertical track on the right edge of the screen, a
-- fill bar that grows from the bottom, and a target tick marking the fill the
-- current aim needs. Shared by both weapons. Starts hidden.
local function makeMeter()
	local gui = Instance.new("ScreenGui")
	gui.Name = "LaunchMeter"
	gui.ResetOnSpawn = false
	gui.Enabled = false

	local track = Instance.new("Frame")
	track.Name = "Track"
	track.AnchorPoint = Vector2.new(1, 0.5)
	track.Position = UDim2.new(1, -36, 0.5, 0)
	track.Size = UDim2.fromOffset(28, 320)
	track.BackgroundColor3 = Color3.fromRGB(20, 20, 24)
	track.BackgroundTransparency = 0.25
	track.BorderSizePixel = 0
	track.Parent = gui
	local trackCorner = Instance.new("UICorner")
	trackCorner.CornerRadius = UDim.new(0, 6)
	trackCorner.Parent = track

	local fill = Instance.new("Frame")
	fill.Name = "Fill"
	fill.AnchorPoint = Vector2.new(0, 1)
	fill.Position = UDim2.fromScale(0, 1)
	fill.Size = UDim2.fromScale(1, 0)
	fill.BackgroundColor3 = Color3.fromRGB(255, 170, 80)
	fill.BorderSizePixel = 0
	fill.ZIndex = 1
	fill.Parent = track
	local fillCorner = Instance.new("UICorner")
	fillCorner.CornerRadius = UDim.new(0, 6)
	fillCorner.Parent = fill

	local targetLine = Instance.new("Frame")
	targetLine.Name = "Target"
	targetLine.AnchorPoint = Vector2.new(0.5, 0.5)
	targetLine.Size = UDim2.new(1, 8, 0, 3)
	targetLine.Position = UDim2.fromScale(0.5, 1)
	targetLine.BackgroundColor3 = Color3.fromRGB(120, 230, 255)
	targetLine.BorderSizePixel = 0
	targetLine.ZIndex = 2
	targetLine.Parent = track

	gui.Parent = player:WaitForChild("PlayerGui")
	return gui, fill, targetLine
end

-- The catapult-only spin meter: a small horizontal track sitting just above
-- the power track's top edge, with a thin centre tick (zero spin) and a
-- sliding indicator. Starts hidden -- AttackInput.update / beginSpinStage
-- toggle it.
local function makeSpinMeter(parentGui)
	local track = Instance.new("Frame")
	track.Name = "SpinTrack"
	track.AnchorPoint = Vector2.new(1, 1)
	track.Position = UDim2.new(1, -22, 0.5, -176) -- above the power track's top edge (centre 0.5, half-height 160), plus a gap
	track.Size = UDim2.fromOffset(110, 16)
	track.BackgroundColor3 = Color3.fromRGB(20, 20, 24)
	track.BackgroundTransparency = 0.25
	track.BorderSizePixel = 0
	track.Visible = false
	track.Parent = parentGui
	local trackCorner = Instance.new("UICorner")
	trackCorner.CornerRadius = UDim.new(0, 6)
	trackCorner.Parent = track

	local centreTick = Instance.new("Frame")
	centreTick.Name = "Centre"
	centreTick.AnchorPoint = Vector2.new(0.5, 0.5)
	centreTick.Position = UDim2.fromScale(0.5, 0.5)
	centreTick.Size = UDim2.new(0, 2, 1, 4)
	centreTick.BackgroundColor3 = Color3.fromRGB(120, 230, 255)
	centreTick.BorderSizePixel = 0
	centreTick.Parent = track

	local indicator = Instance.new("Frame")
	indicator.Name = "Indicator"
	indicator.AnchorPoint = Vector2.new(0.5, 0.5)
	indicator.Position = UDim2.fromScale(0.5, 0.5)
	indicator.Size = UDim2.new(0, 8, 1, 8)
	indicator.BackgroundColor3 = Color3.fromRGB(255, 170, 80)
	indicator.BorderSizePixel = 0
	indicator.ZIndex = 2
	indicator.Parent = track
	local indicatorCorner = Instance.new("UICorner")
	indicatorCorner.CornerRadius = UDim.new(0, 4)
	indicatorCorner.Parent = indicator

	return track, indicator
end

-- Moves the spin indicator to `frac` (-1 = farthest left, 1 = farthest
-- right) across the track.
local function updateSpinIndicator(frac)
	spinIndicator.Position = UDim2.fromScale(0.5 + math.clamp(frac, -1, 1) * 0.5, 0.5)
end

-- Linear triangle wave in [-1, 1]: starts at -1, sweeps to 1 at the half
-- period, back to -1 at the full period, and repeats -- same "linear, no
-- bounce" feel as the power meter's own tween, just looping.
local function triangleWave(elapsed, period)
	local phase = (elapsed % period) / period
	if phase < 0.5 then
		return -1 + 4 * phase
	end
	return 3 - 4 * phase
end

-- Each weapon's launch-meter range: catapult force, ballista muzzle speed.
local function forceRange(weapon)
	if weapon == "Ballista" then
		return Config.BallistaMinVelocity, Config.BallistaMuzzleVelocity
	end
	return Config.CatapultMinForce, Config.CatapultMaxForce
end

-- force <-> meter fill fraction, both ways, per weapon.
local function forceFraction(weapon, force)
	local lo, hi = forceRange(weapon)
	return math.clamp((force - lo) / (hi - lo), 0, 1)
end

local function fractionForce(weapon, fraction)
	local lo, hi = forceRange(weapon)
	return lo + math.clamp(fraction, 0, 1) * (hi - lo)
end

-- The catapult force that would land a shot at `range` studs (horizontal,
-- flat-range approximation -- ignores target height) at the given angle,
-- clamped into the Config range so an out-of-reach aim just pins to the top.
local function requiredForce(range, angleDeg)
	local a = math.rad(angleDeg)
	local s = math.sin(2 * a)
	if range <= 0 or s <= 1e-3 then
		return Config.CatapultMinForce
	end
	return math.clamp(math.sqrt(range * Workspace.Gravity / s), Config.CatapultMinForce, Config.CatapultMaxForce)
end

local function updateTargetLine(fraction)
	meterTargetLine.Position = UDim2.fromScale(0.5, 1 - math.clamp(fraction, 0, 1))
end

local function currentFillFraction()
	return meterFill.Size.Y.Scale
end

-- World-space ray from the camera through the current mouse pixel, or nil.
local function cameraRay()
	local camera = Workspace.CurrentCamera
	if not camera then
		return nil
	end
	local mouse = UserInputService:GetMouseLocation()
	return camera:ViewportPointToRay(mouse.X, mouse.Y)
end

-- Filter shared by the aim ray and the impact trace: skip the marker and the
-- local character so they never register as a hit.
local function traceParams()
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { markerFolder, player.Character }
	return params
end

-- The point the player is pointing at: first solid hit under the cursor, or a
-- far point along the ray if nothing is hit.
local function aimPoint()
	local ray = cameraRay()
	if not ray then
		return nil
	end
	local hit = Workspace:Raycast(ray.Origin, ray.Direction * AIM_RANGE, traceParams())
	return hit and hit.Position or ray.Origin + ray.Direction * AIM_RANGE
end

local function blocksFolder()
	local root = Workspace:FindFirstChild("ActiveRound")
	return root and root:FindFirstChild("Blocks")
end

-- Same as aimPoint, but with the wall excluded: the catapult "ignores wall
-- height if aimed well" (spec), so standing close to a tall wall shouldn't let
-- the wall itself block the player from aiming at what's behind it -- pointing
-- roughly at/over the wall now resolves to the ground or Princess beyond it,
-- not the wall's face. This only affects the range used for the target tick;
-- the real simulated arc (traceShot) still raycasts against blocks and will
-- correctly show a hit if the shot doesn't actually clear the wall.
local function catapultAimPoint()
	local ray = cameraRay()
	if not ray then
		return nil
	end
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	local exclude = { markerFolder, player.Character }
	local blocks = blocksFolder()
	if blocks then
		table.insert(exclude, blocks)
	end
	params.FilterDescendantsInstances = exclude
	local hit = Workspace:Raycast(ray.Origin, ray.Direction * AIM_RANGE, params)
	return hit and hit.Position or ray.Origin + ray.Direction * AIM_RANGE
end

-- The aim direction to use for whichever weapon is selected, or nil if there's
-- no camera yet.
local function currentAimDirection()
	local target = if state.weapon == "Catapult" then catapultAimPoint() else aimPoint()
	return target and (target - Config.muzzleOrigin(state.weapon)) or nil
end

-- Initial catapult velocity for a unit aim direction, force and angle. Mirrors
-- WeaponManager.launchVelocity's catapult branch so the arc trace matches the
-- shot; the server still re-clamps force / angle.
local function catapultVelocity(direction, force, angleDeg)
	local flat = Vector3.new(direction.X, 0, direction.Z)
	local heading = if flat.Magnitude > 1e-3 then flat.Unit else Vector3.zAxis
	local a = math.rad(math.clamp(angleDeg, Config.CatapultMinAngle, Config.CatapultMaxAngle))
	local f = math.clamp(force, Config.CatapultMinForce, Config.CatapultMaxForce)
	return heading * (f * math.cos(a)) + Vector3.yAxis * (f * math.sin(a))
end

-- Initial ballista velocity for a unit aim direction and force. Mirrors
-- WeaponManager.launchVelocity's ballista branch -- dead flat along the
-- horizontal aim, speed clamped into the configured range.
local function ballistaVelocity(direction, force)
	local flat = Vector3.new(direction.X, 0, direction.Z)
	local heading = if flat.Magnitude > 1e-3 then flat.Unit else Vector3.zAxis
	local speed = math.clamp(force, Config.BallistaMinVelocity, Config.BallistaMuzzleVelocity)
	return heading * speed
end

-- Steps an initial velocity forward under real gravity, raycasting each step,
-- and returns the traced points (for the dashed line) plus where the shot
-- would land and what it would hit (nil if the trace runs out within
-- TRACE_RANGE without a hit). Both weapons are now real physics bodies under
-- the same gravity (session 009) -- the ballista's shot really does drop,
-- however subtly, so it needs the same stepped treatment the catapult's arc
-- always did; only the initial velocity differs between them. `spinVector`
-- (session 013, catapult only) mirrors WeaponManager's per-frame Magnus force
-- step for step, so the preview curves exactly as the real shot will.
local function stepTrace(origin, velocity, spinVector)
	local gravity = Workspace.Gravity
	local params = traceParams()
	local points = { origin }
	local pos = origin
	for _ = 1, TRACE_MAX_STEPS do
		velocity -= Vector3.yAxis * gravity * TRACE_DT
		if spinVector then
			velocity += spinVector:Cross(velocity) * Config.CatapultMagnusCoefficient * TRACE_DT
		end
		local nextPos = pos + velocity * TRACE_DT
		local hit = Workspace:Raycast(pos, nextPos - pos, params)
		if hit then
			table.insert(points, hit.Position)
			return points, hit.Position, hit.Instance
		end
		pos = nextPos
		table.insert(points, pos)
		if pos.Y <= Config.GroundLevel or (pos - origin).Magnitude > TRACE_RANGE then
			break
		end
	end
	return points, pos, nil
end

local function traceShot(weapon, direction, force, angleDeg, spin)
	local origin = Config.muzzleOrigin(weapon)
	if weapon == "Ballista" then
		return stepTrace(origin, ballistaVelocity(direction, force), nil)
	end
	local spinVector = if spin and spin ~= 0 then Vector3.new(0, spin, 0) else nil
	return stepTrace(origin, catapultVelocity(direction, force, angleDeg), spinVector)
end

-- Traces a shot and updates the crosshair + dashed line from the result.
local function showTrace(weapon, direction, force, angleDeg, spin)
	local points, impact, hitInstance = traceShot(weapon, direction, force, angleDeg, spin)
	crosshairPart.Position = impact
	crosshairGui.Enabled = true
	setCrosshairHit(hitInstance ~= nil and hitInstance:GetAttribute("BlockId") ~= nil)
	drawDashes(points)
end

-- Stops just the power tween/connection, leaving the fill bar wherever it was
-- (so it stays visible, frozen, through the catapult's spin stage) rather than
-- zeroing it. Shared by freezing into the spin stage and by the full reset
-- below.
local function stopPowerTween()
	if fillConn then
		fillConn:Disconnect()
		fillConn = nil
	end
	if fillTween then
		fillTween:Cancel()
		fillTween = nil
	end
end

-- Full stop: any in-progress power or spin stage, bars zeroed/hidden, back to
-- idle. Shared by a natural power-meter timeout (cancels the shot), and by
-- after a shot actually fires.
local function resetMeter()
	stopPowerTween()
	stage = "idle"
	if meterFill then
		meterFill.Size = UDim2.fromScale(1, 0)
	end
	if spinTrack then
		spinTrack.Visible = false
	end
end

-- First click: locks the weapon, aim, and (for the catapult) angle, sets the
-- target tick, hides the 3D targeting (crosshair + dashed line) for the
-- duration of the swing, and runs the fill bar up to the top and back down
-- once, linearly. Click again anywhere in that pass to freeze it; let the bar
-- run out untouched and it resets to idle -- no shot, press again for a fresh
-- attempt (this timeout behaviour is unique to the power stage -- the spin
-- stage below fires instead of cancelling).
local function beginSwing(direction)
	lockedWeapon = state.weapon
	lockedDirection = direction
	lockedAngle = state.angle
	stage = "power"
	crosshairGui.Enabled = false
	hideDashesFrom(1)

	if lockedWeapon == "Catapult" then
		local flat = Vector3.new(direction.X, 0, direction.Z)
		updateTargetLine(forceFraction("Catapult", requiredForce(flat.Magnitude, lockedAngle)))
	else
		updateTargetLine(1) -- ballista: more power always hits harder, aim for the top
	end

	meterFill.Size = UDim2.fromScale(1, 0)
	fillTween = TweenService:Create(
		meterFill,
		TweenInfo.new(METER_LEG_TIME, Enum.EasingStyle.Linear, Enum.EasingDirection.InOut, 0, true),
		{ Size = UDim2.fromScale(1, 1) }
	)
	fillConn = fillTween.Completed:Connect(function(playbackState)
		if playbackState == Enum.PlaybackState.Completed then
			resetMeter()
		end
	end)
	fillTween:Play()
end

-- Sends the locked shot to the server and returns to idle. `spin` is only
-- meaningful for the catapult; the ballista always fires with none.
local function fireLockedShot(spin)
	local weapon, direction, angle, force = lockedWeapon, lockedDirection, lockedAngle, lockedForce
	resetMeter()

	Remotes.FireWeapon:FireServer({
		direction = direction,
		force = force,
		angle = if weapon == "Catapult" then angle else 0,
		spin = if weapon == "Catapult" then spin else 0,
	})
end

-- Third click (catapult only): freezes the spin meter wherever it currently
-- reads and fires at that spin.
local function freezeSpinAndFire()
	fireLockedShot(currentSpinValue * Config.CatapultMaxSpin)
end

-- Starts the spin stage: oscillation speed scales with how hard the just-
-- frozen power swing was, so a full-power swing is harder to time a clean
-- spin on than a soft one.
local function beginSpinStage()
	stage = "spin"
	spinStartClock = os.clock()
	local powerFraction = forceFraction("Catapult", lockedForce)
	spinFreq = SPIN_OSC_MIN_FREQ + (SPIN_OSC_MAX_FREQ - SPIN_OSC_MIN_FREQ) * powerFraction
	currentSpinValue = -1
	spinTrack.Visible = true
	updateSpinIndicator(currentSpinValue)
end

-- Second click: freezes the power bar wherever it is (left visible, not
-- zeroed) and converts that fill to the locked weapon's force/speed. The
-- catapult moves on to the spin stage; the ballista, which never spins,
-- fires immediately -- unchanged from before the spin stage existed.
local function freezePowerAndAdvance()
	stopPowerTween()
	lockedForce = fractionForce(lockedWeapon, currentFillFraction())
	if lockedWeapon == "Catapult" then
		beginSpinStage()
	else
		fireLockedShot(0)
	end
end

-- Every rendered frame while active. Three cases: mid power-swing, nothing to
-- update but the meter's own tween. Mid spin-stage (catapult only), advance
-- the oscillator, move its indicator, and re-show the 3D trace at the live
-- spin value so the curve preview actually sweeps as the meter does -- or
-- auto-fire if the stage has run past SPIN_TIMEOUT unfrozen. Otherwise (idle)
-- preview the shot the current aim would produce: for the catapult that's the
-- force needed to reach the cursor (also what sets the target tick, with no
-- spin yet since it isn't chosen until the swing sequence starts); the
-- ballista previews at full power, matching its always-aim-for-the-top target.
local function onRender()
	if stage == "power" then
		return
	end

	if stage == "spin" then
		local elapsed = os.clock() - spinStartClock
		if elapsed >= SPIN_TIMEOUT then
			currentSpinValue = 1 -- un-frozen: fires pinned to full spin, right side
			freezeSpinAndFire()
			return
		end
		currentSpinValue = triangleWave(elapsed, 1 / spinFreq)
		updateSpinIndicator(currentSpinValue)
		showTrace("Catapult", lockedDirection, lockedForce, lockedAngle, currentSpinValue * Config.CatapultMaxSpin)
		return
	end

	local direction = currentAimDirection() or Vector3.zero
	if direction.Magnitude < 1e-3 then
		crosshairGui.Enabled = false
		hideDashesFrom(1)
		return
	end

	if state.weapon == "Catapult" then
		local flat = Vector3.new(direction.X, 0, direction.Z)
		local req = requiredForce(flat.Magnitude, state.angle)
		updateTargetLine(forceFraction("Catapult", req))
		showTrace("Catapult", direction.Unit, req, state.angle)
	else
		updateTargetLine(1)
		showTrace("Ballista", direction.Unit, Config.BallistaMuzzleVelocity, 0)
	end
end

-- Keyboard and left-click while active. The whole fire sequence is the same
-- button in a row -- click to lock aim and start the power swing, click again
-- to freeze power (and, for the catapult, move on to the spin stage), click a
-- third time to freeze spin and fire. Q/E only nudge the catapult angle before
-- the sequence starts -- once locked, angle can't change mid-shot.
local function onInput(inputObject, gameProcessed)
	if gameProcessed then
		return
	end

	if inputObject.UserInputType ~= Enum.UserInputType.MouseButton1 then
		if stage == "idle" then
			if inputObject.KeyCode == Enum.KeyCode.Q then
				state.angle = math.clamp(state.angle - ANGLE_STEP, Config.CatapultMinAngle, Config.CatapultMaxAngle)
				publish()
			elseif inputObject.KeyCode == Enum.KeyCode.E then
				state.angle = math.clamp(state.angle + ANGLE_STEP, Config.CatapultMinAngle, Config.CatapultMaxAngle)
				publish()
			end
		end
		return
	end

	if stage == "power" then
		freezePowerAndAdvance()
	elseif stage == "spin" then
		freezeSpinAndFire()
	elseif shotsRemaining > 0 then
		local direction = currentAimDirection()
		if direction and direction.Magnitude > 1e-3 then
			beginSwing(direction.Unit)
		end
	end
end

-- One-time setup after the player leaves the title screen. Builds the
-- crosshair, launch meter, and weapon props; update() decides when aiming is
-- live.
function AttackInput.start()
	if not markerFolder then
		markerFolder = Instance.new("Folder")
		markerFolder.Name = "AimMarker"
		markerFolder.Parent = Workspace
		crosshairPart, crosshairGui = makeCrosshair()
	end
	if not meterGui then
		meterGui, meterFill, meterTargetLine = makeMeter()
		spinTrack, spinIndicator = makeSpinMeter(meterGui)
	end
	WeaponView.start()
end

-- Called on every StateChanged. Aiming is live only while phase == "ATTACK" and
-- the local player is the Attacker. state.weapon mirrors the server-mandated
-- currentWeapon -- there's no client choice -- and this has to happen even when
-- `active` doesn't change, since the sequence switches weapon mid-turn (shot 2
-- to shot 3) without a phase transition. On the transition in it connects the
-- render and input handlers and publishes the readout; on the transition out
-- it disconnects them, cancels any in-progress swing, and hides everything.
function AttackInput.update(stateChanged)
	shotsRemaining = stateChanged.shotsRemaining or 0

	if stateChanged.currentWeapon and stateChanged.currentWeapon ~= state.weapon then
		state.weapon = stateChanged.currentWeapon
		if active then
			WeaponView.setActive(state.weapon)
			publish()
		end
	end

	local shouldBeActive = stateChanged.phase == "ATTACK"
		and stateChanged.roles ~= nil
		and stateChanged.roles.attacker == player.UserId

	if shouldBeActive == active then
		return
	end
	active = shouldBeActive

	if active then
		AttackInput.start()
		WeaponView.setActive(state.weapon)
		WeaponView.setVisible(true)
		meterGui.Enabled = true
		publish()
		renderConn = RunService.RenderStepped:Connect(onRender)
		inputConn = UserInputService.InputBegan:Connect(onInput)
	else
		if renderConn then
			renderConn:Disconnect()
			renderConn = nil
		end
		if inputConn then
			inputConn:Disconnect()
			inputConn = nil
		end
		resetMeter()
		if meterGui then
			meterGui.Enabled = false
		end
		WeaponView.setVisible(false)
		if crosshairGui then
			crosshairGui.Enabled = false
		end
		hideDashesFrom(1)
	end
end

return AttackInput
