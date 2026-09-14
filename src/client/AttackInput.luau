-- Attacker-only aiming. Active while phase == "ATTACK" and the local player is
-- the Attacker. Mouse sets aim direction from a fixed muzzle origin, Q/E adjust
-- the catapult angle. Weapon is not a client choice -- state.weapon mirrors
-- whichever weapon the server's fixed shot sequence currently mandates
-- (Config.ShotSequence). A crosshair marks the predicted impact point (traced
-- by stepping the same initial velocity forward under gravity the real
-- projectile launches with) and turns green when that impact is a wall
-- block; a light dashed line sketches the path to it.
--
-- Both weapons fire off the same launch meter (left side of screen since
-- session 016), one button pressed in sequence rather than several different
-- ones. First click locks the current aim, hides the 3D targeting, and runs
-- the fill bar linearly from empty to full and back to empty once; a target
-- tick marks the fill to aim for -- the force needed to reach the point you
-- aimed at for the catapult, always the top for the ballista (more power,
-- harder hit). Second click freezes the bar wherever it is and opens a fixed
-- 3-second window (session 016, replaces session 013's power-scaled
-- oscillator) shared by both weapons: held Up/Down (or the scroll wheel, a
-- notch at a time) move a normalized dot continuously off its rest position
-- -- above/below centre for the catapult's spin, lifting off flat for the
-- ballista's new elevation axis. A
-- third click freezes the dot and fires at its current value; letting the
-- window run out instead fires anyway, at whatever the dot currently reads
-- (centre/flat if never touched) -- only the power stage has a safe cancel.
-- Everything sent is intent -- the server clamps force/angle/spin and owns
-- the projectile.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local ContextActionService = game:GetService("ContextActionService")
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

-- The shared timed axis window (session 016, replaces session 013's
-- power-scaled oscillator): a second small meter, right after power freezes,
-- shared by both weapons rather than catapult-only. Held Up/Down move a
-- normalized "dot" level continuously off its rest position for
-- WINDOW_DURATION seconds -- same button as the rest of the sequence:
-- freezing it (a third click) fires at the dot's current value; letting the
-- window run out instead of cancelling also fires, at whatever the dot
-- currently reads (rest/zero if it was never touched) -- no power-scaled
-- difficulty coupling replaces the old oscillator's frequency scaling, per
-- the Open Gate decision to accept that loss. The scroll wheel moves the same
-- dot too (one WHEEL_STEP per notch, added alongside Up/Down rather than
-- replacing them) -- harmless to leave unsunk, since AttackCamera's own
-- Scriptable lock already blocks the default camera-zoom behaviour the wheel
-- would otherwise drive. UI feel, not gameplay balance, so these live here
-- rather than in Config.
local WINDOW_DURATION = 3 -- seconds before an un-frozen window auto-fires
local DOT_RATE = 0.6 -- dot level units/second while Up or Down is held
local WHEEL_STEP = 0.15 -- dot level units per scroll notch
local AXIS_LEVER_MAX_DEGREES = 35 -- visual tilt of the ballista's lever at full elevation

local CROSSHAIR_COLOR = Color3.fromRGB(255, 230, 120)
local CROSSHAIR_HIT_COLOR = Color3.fromRGB(100, 230, 130)
local DASH_COLOR = Color3.fromRGB(255, 255, 255)
local DASH_THICKNESS = 0.07
local DASH_FILL = 0.55 -- fraction of each traced step drawn, leaving a gap

local active = false
local renderConn, inputConn, wheelConn
local shotsRemaining = 0
local flagRevealed = false -- session 015: mirrors StateChanged.flagRevealed

local markerFolder
local crosshairPart, crosshairGui
local crosshairFrames = {}
local dashes = {}

local meterGui, meterFill, meterTargetLine
local axisTrack, axisDot, axisLever, axisFulcrum, axisCountdown, axisTitle
local fillTween, fillConn

-- "idle" (aiming, nothing locked yet) -> "power" (first click made, power
-- swinging) -> "window" (second click made, the shared timed axis window
-- open -- session 016, both weapons). A third click (or the window timing
-- out) fires and returns to "idle".
local stage = "idle"
local lockedWeapon, lockedDirection, lockedAngle, lockedForce
local windowStartClock, dotLevel = nil, 0

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

-- Builds the launch meter: a vertical track on the left edge of the screen
-- (session 016 -- moved from the right, doubled in both dimensions so the
-- bar physically travels twice the distance in the same METER_LEG_TIME,
-- reading as faster without touching that constant), a fill bar that grows
-- from the bottom, and a target tick marking the fill the current aim needs.
-- Shared by both weapons. Enabled for the Attacker's whole turn (session
-- 016), not just mid-swing.
local POWER_TRACK_SIZE = Vector2.new(56, 640)
-- Sits beside the power track (same vertical centre), not stacked above it --
-- a 640px-tall, vertically-centred track already eats most of a short
-- viewport's height, so stacking a second element above it risks clipping
-- off-screen (the brief's own "check against a small viewport" warning).
-- Beside it needs only its own small height, independent of the power
-- track's.
local AXIS_TRACK_GAP = 16 -- px between the power track's right edge and the axis meter

local function makeMeter()
	local gui = Instance.new("ScreenGui")
	gui.Name = "LaunchMeter"
	gui.ResetOnSpawn = false
	gui.Enabled = false

	local track = Instance.new("Frame")
	track.Name = "Track"
	track.AnchorPoint = Vector2.new(0, 0.5)
	track.Position = UDim2.new(0, 36, 0.5, 0)
	track.Size = UDim2.fromOffset(POWER_TRACK_SIZE.X, POWER_TRACK_SIZE.Y)
	track.BackgroundColor3 = Color3.fromRGB(20, 20, 24)
	track.BackgroundTransparency = 0.25
	track.BorderSizePixel = 0
	track.Parent = gui
	local trackCorner = Instance.new("UICorner")
	trackCorner.CornerRadius = UDim.new(0, 6)
	trackCorner.Parent = track

	-- A vertical watermark running the length of the track, behind the fill
	-- (ZIndex 0 < the fill's 1) so it's progressively covered as the bar
	-- rises rather than always fully visible.
	local watermark = Instance.new("TextLabel")
	watermark.Name = "Watermark"
	watermark.AnchorPoint = Vector2.new(0.5, 0.5)
	watermark.Position = UDim2.fromScale(0.5, 0.5)
	-- Sized in pixels off the track's height, not its width -- rotated 90°,
	-- this label's own width becomes the on-screen vertical extent, so it
	-- has to span the track's long axis, not its short one.
	watermark.Size = UDim2.fromOffset(POWER_TRACK_SIZE.Y - 40, 34)
	watermark.Rotation = 90
	watermark.BackgroundTransparency = 1
	watermark.Font = Enum.Font.GothamBold
	watermark.TextColor3 = Color3.fromRGB(255, 255, 255)
	watermark.TextTransparency = 0.55
	watermark.TextSize = 26
	watermark.Text = "POWER METER"
	watermark.ZIndex = 0
	watermark.Parent = track

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

-- The shared axis meter (session 016, replaces the catapult-only spin
-- meter): a small track sitting beside the power track, at the same
-- vertical centre, visible for the Attacker's whole turn at rest (catapult:
-- centred dot; ballista: flat lever) so its final position is never a
-- surprise the first time the window opens. Holds every visual for both
-- weapons at once; updateAxisVisual toggles which set is shown. A countdown
-- label sits to its right, blank outside the window stage.
local function makeAxisMeter(parentGui)
	local track = Instance.new("Frame")
	track.Name = "AxisTrack"
	track.AnchorPoint = Vector2.new(0, 0.5)
	track.Position = UDim2.new(0, 36 + POWER_TRACK_SIZE.X + AXIS_TRACK_GAP, 0.5, 0)
	track.Size = UDim2.fromOffset(160, 60)
	track.BackgroundColor3 = Color3.fromRGB(20, 20, 24)
	track.BackgroundTransparency = 0.25
	track.BorderSizePixel = 0
	track.Parent = parentGui
	local trackCorner = Instance.new("UICorner")
	trackCorner.CornerRadius = UDim.new(0, 6)
	trackCorner.Parent = track

	-- The reference line: a centred horizontal tick for the catapult's dot to
	-- move above/below, and the ballista's flat rest horizon.
	local horizon = Instance.new("Frame")
	horizon.Name = "Horizon"
	horizon.AnchorPoint = Vector2.new(0.5, 0.5)
	horizon.Position = UDim2.fromScale(0.5, 0.5)
	horizon.Size = UDim2.new(1, -20, 0, 2)
	horizon.BackgroundColor3 = Color3.fromRGB(120, 230, 255)
	horizon.BorderSizePixel = 0
	horizon.Parent = track

	-- Catapult: a dot that starts centred on the horizon and moves above or
	-- below it -- above/below stand in for the same left/right curve
	-- direction the session 013 meter produced.
	local dot = Instance.new("Frame")
	dot.Name = "Dot"
	dot.AnchorPoint = Vector2.new(0.5, 0.5)
	dot.Position = UDim2.fromScale(0.5, 0.5)
	dot.Size = UDim2.fromOffset(10, 10)
	dot.BackgroundColor3 = Color3.fromRGB(255, 170, 80)
	dot.BorderSizePixel = 0
	dot.ZIndex = 2
	dot.Parent = track
	local dotCorner = Instance.new("UICorner")
	dotCorner.CornerRadius = UDim.new(1, 0)
	dotCorner.Parent = dot

	-- Ballista: a fulcrum near the horizon's left end with a lever segment
	-- that starts flat (overlapping the horizon) and lifts off it as Up is
	-- held, roughly a "less than" shape once elevated.
	local fulcrum = Instance.new("Frame")
	fulcrum.Name = "Fulcrum"
	fulcrum.AnchorPoint = Vector2.new(0.5, 0.5)
	fulcrum.Position = UDim2.fromScale(0.1, 0.5)
	fulcrum.Size = UDim2.fromOffset(6, 6)
	fulcrum.BackgroundColor3 = Color3.fromRGB(120, 230, 255)
	fulcrum.BorderSizePixel = 0
	fulcrum.ZIndex = 2
	fulcrum.Visible = false
	fulcrum.Parent = track
	local fulcrumCorner = Instance.new("UICorner")
	fulcrumCorner.CornerRadius = UDim.new(1, 0)
	fulcrumCorner.Parent = fulcrum

	local lever = Instance.new("Frame")
	lever.Name = "Lever"
	lever.AnchorPoint = Vector2.new(0, 0.5)
	lever.Position = UDim2.fromScale(0.1, 0.5)
	lever.Size = UDim2.new(0.8, 0, 0, 3)
	lever.BackgroundColor3 = Color3.fromRGB(255, 170, 80)
	lever.BorderSizePixel = 0
	lever.ZIndex = 2
	lever.Visible = false
	lever.Parent = track

	local countdown = Instance.new("TextLabel")
	countdown.Name = "Countdown"
	countdown.AnchorPoint = Vector2.new(0, 0.5)
	countdown.Position = UDim2.new(1, 12, 0.5, 0)
	countdown.Size = UDim2.fromOffset(28, 28)
	countdown.BackgroundTransparency = 1
	countdown.Font = Enum.Font.GothamBold
	countdown.TextColor3 = Color3.fromRGB(255, 230, 120)
	countdown.TextSize = 22
	countdown.Text = ""
	countdown.Parent = track

	-- Horizontal title below the track itself: "SPIN" for the catapult,
	-- "PITCH" for the ballista -- updateAxisVisual keeps it in sync with
	-- whichever weapon the meter is currently showing.
	local title = Instance.new("TextLabel")
	title.Name = "Title"
	title.AnchorPoint = Vector2.new(0.5, 0)
	title.Position = UDim2.new(0.5, 0, 1, 8)
	title.Size = UDim2.new(1, 0, 0, 20)
	title.BackgroundTransparency = 1
	title.Font = Enum.Font.GothamBold
	title.TextColor3 = Color3.fromRGB(230, 230, 235)
	title.TextSize = 16
	title.Text = ""
	title.Parent = track

	return track, dot, lever, fulcrum, countdown, title
end

-- Positions the axis meter at `level` for `weapon`: the catapult's dot above
-- (positive) or below (negative) the horizon within [-1, 1]; the ballista's
-- lever tilted up from flat within [0, 1] (Down only un-lifts back toward
-- flat -- the range has no negative half, per the Open Gate decision). Also
-- keeps the meter's own title in sync -- "SPIN" or "PITCH" -- since the same
-- track shows either weapon depending on what's currently locked/mandated.
local function updateAxisVisual(weapon, level)
	if axisTitle then
		axisTitle.Text = if weapon == "Catapult" then "SPIN" else "PITCH"
	end
	if weapon == "Catapult" then
		axisDot.Visible = true
		axisLever.Visible = false
		axisFulcrum.Visible = false
		local frac = math.clamp(level, -1, 1)
		axisDot.Position = UDim2.fromScale(0.5, 0.5 - frac * 0.4)
	else
		axisDot.Visible = false
		axisLever.Visible = true
		axisFulcrum.Visible = true
		local frac = math.clamp(level, 0, 1)
		axisLever.Rotation = -frac * AXIS_LEVER_MAX_DEGREES
	end
end

-- Clamps a dot level into whichever weapon's range applies -- catapult spins
-- both ways from centre, the ballista only lifts upward from flat.
local function clampDotLevel(weapon, level)
	if weapon == "Catapult" then
		return math.clamp(level, -1, 1)
	end
	return math.clamp(level, 0, 1)
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

local function flagPart()
	local root = Workspace:FindFirstChild("ActiveRound")
	return root and root:FindFirstChild("Flag")
end

-- Filter shared by the aim ray and the impact trace: skip the marker and the
-- local character so they never register as a hit. Session 015: while the
-- Flag is still hidden from this Attacker, it's excluded too -- otherwise the
-- crosshair/dashed-line preview would snap to it and leak its position even
-- though LocalTransparencyModifier keeps it invisible. A real shot can still
-- physically connect either way; this only affects the assist tools.
local function traceParams()
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	local exclude = { markerFolder, player.Character }
	if not flagRevealed then
		local flag = flagPart()
		if flag then
			table.insert(exclude, flag)
		end
	end
	params.FilterDescendantsInstances = exclude
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
-- roughly at/over the wall now resolves to the ground or Flag beyond it, not
-- the wall's face. This only affects the range used for the target tick; the
-- real simulated arc (traceShot) still raycasts against blocks and will
-- correctly show a hit if the shot doesn't actually clear the wall. Also
-- excludes the Flag while it's hidden, same reasoning as traceParams().
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
	if not flagRevealed then
		local flag = flagPart()
		if flag then
			table.insert(exclude, flag)
		end
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

-- Initial ballista velocity for a unit aim direction, force and elevation
-- angle. Mirrors WeaponManager.launchVelocity's ballista branch -- speed
-- clamped into the configured range, pitched up by `angleDeg` (session 016;
-- previously always dead flat) clamped into Config.BallistaMinAngle/MaxAngle.
local function ballistaVelocity(direction, force, angleDeg)
	local flat = Vector3.new(direction.X, 0, direction.Z)
	local heading = if flat.Magnitude > 1e-3 then flat.Unit else Vector3.zAxis
	local speed = math.clamp(force, Config.BallistaMinVelocity, Config.BallistaMuzzleVelocity)
	local a = math.rad(math.clamp(angleDeg or 0, Config.BallistaMinAngle, Config.BallistaMaxAngle))
	return heading * (speed * math.cos(a)) + Vector3.yAxis * (speed * math.sin(a))
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

-- `angleDeg` is the catapult's arc angle or the ballista's elevation
-- (session 016), depending on `weapon`; `spin` only ever applies to the
-- catapult.
local function traceShot(weapon, direction, force, angleDeg, spin)
	local origin = Config.muzzleOrigin(weapon)
	if weapon == "Ballista" then
		return stepTrace(origin, ballistaVelocity(direction, force, angleDeg), nil)
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
-- (so it stays visible, frozen, through the window stage) rather than
-- zeroing it. Shared by freezing into the window stage and by the full reset
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

-- Full stop: any in-progress power or window stage, power bar zeroed, dot
-- level back to rest, back to idle. Shared by a natural power-meter timeout
-- (cancels the shot), and by after a shot actually fires. The axis meter
-- itself is never hidden (session 016: visible the whole turn) -- only its
-- level resets; onRender's idle branch redraws it at rest.
local function resetMeter()
	stopPowerTween()
	stage = "idle"
	dotLevel = 0
	if meterFill then
		meterFill.Size = UDim2.fromScale(1, 0)
	end
	if axisCountdown then
		axisCountdown.Text = ""
	end
end

-- First click: locks the weapon, aim, and (for the catapult) angle, sets the
-- target tick, hides the 3D targeting (crosshair + dashed line) for the
-- duration of the swing, and runs the fill bar up to the top and back down
-- once, linearly. Click again anywhere in that pass to freeze it; let the bar
-- run out untouched and it resets to idle -- no shot, press again for a fresh
-- attempt (this timeout behaviour is unique to the power stage -- the window
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

-- Sends the locked shot to the server and returns to idle. `level` is the
-- dot's final normalized value: for the catapult it scales spin (both
-- directions, via Config.CatapultMaxSpin); for the ballista it scales
-- elevation between Config.BallistaMinAngle and MaxAngle (session 016 --
-- previously the ballista always fired at angle 0).
local function fireLockedShot(level)
	local weapon, direction, angle, force = lockedWeapon, lockedDirection, lockedAngle, lockedForce
	resetMeter()

	local sendAngle, sendSpin
	if weapon == "Catapult" then
		sendAngle = angle
		sendSpin = level * Config.CatapultMaxSpin
	else
		sendAngle = Config.BallistaMinAngle + math.clamp(level, 0, 1) * (Config.BallistaMaxAngle - Config.BallistaMinAngle)
		sendSpin = 0
	end

	Remotes.FireWeapon:FireServer({
		direction = direction,
		force = force,
		angle = sendAngle,
		spin = sendSpin,
	})
end

-- Third click: freezes the axis window wherever the dot currently reads and
-- fires at that level.
local function freezeWindowAndFire()
	fireLockedShot(dotLevel)
end

-- Starts the shared timed axis window (session 016): the dot resets to rest
-- (0) regardless of how hard the just-frozen power swing was -- no
-- power-scaled difficulty coupling replaces session 013's oscillator speed,
-- per the Open Gate decision.
local function beginWindowStage()
	stage = "window"
	windowStartClock = os.clock()
	dotLevel = 0
	updateAxisVisual(lockedWeapon, dotLevel)
	if axisCountdown then
		axisCountdown.Text = tostring(WINDOW_DURATION)
	end
end

-- Second click: freezes the power bar wherever it is (left visible, not
-- zeroed), converts that fill to the locked weapon's force/speed, and opens
-- the axis window -- both weapons now, since the ballista also has an axis
-- (elevation) to set (session 016; previously it fired immediately here).
local function freezePowerAndAdvance()
	stopPowerTween()
	lockedForce = fractionForce(lockedWeapon, currentFillFraction())
	beginWindowStage()
end

-- Every rendered frame while active. Three cases: mid power-swing, nothing to
-- update but the meter's own tween (the axis meter stays at rest,
-- session 016). Mid window-stage, poll Up/Down and move the dot level
-- continuously at DOT_RATE/second, update the axis visual and countdown, and
-- re-show the 3D trace at the live level so the curve/elevation preview
-- actually sweeps as the dot moves -- or auto-fire at whatever the dot
-- currently reads if the window has run past WINDOW_DURATION unfrozen.
-- Otherwise (idle) preview the shot the current aim would produce: for the
-- catapult that's the force needed to reach the cursor (also what sets the
-- target tick, with no spin yet since it isn't chosen until the swing
-- sequence starts); the ballista previews at full power and flat (elevation
-- isn't chosen yet either), matching its always-aim-for-the-top target.
local function onRender(dt)
	if stage == "power" then
		updateAxisVisual(lockedWeapon, 0)
		return
	end

	if stage == "window" then
		local elapsed = os.clock() - windowStartClock
		if elapsed >= WINDOW_DURATION then
			freezeWindowAndFire()
			return
		end
		local delta = 0
		if UserInputService:IsKeyDown(Enum.KeyCode.Up) then
			delta += 1
		end
		if UserInputService:IsKeyDown(Enum.KeyCode.Down) then
			delta -= 1
		end
		dotLevel = clampDotLevel(lockedWeapon, dotLevel + delta * DOT_RATE * dt)
		updateAxisVisual(lockedWeapon, dotLevel)
		axisCountdown.Text = tostring(math.max(1, math.ceil(WINDOW_DURATION - elapsed)))

		if lockedWeapon == "Catapult" then
			showTrace("Catapult", lockedDirection, lockedForce, lockedAngle, dotLevel * Config.CatapultMaxSpin)
		else
			local elevation = Config.BallistaMinAngle + dotLevel * (Config.BallistaMaxAngle - Config.BallistaMinAngle)
			showTrace("Ballista", lockedDirection, lockedForce, elevation)
		end
		return
	end

	updateAxisVisual(state.weapon, 0)

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
-- to freeze power and open the axis window, click a third time to freeze the
-- dot and fire. Q/E only nudge the catapult angle before the sequence starts
-- -- once locked, angle can't change mid-shot. Up/Down are handled
-- separately, polled continuously from onRender rather than here (see the
-- ContextActionService bind in AttackInput.update).
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
	elseif stage == "window" then
		freezeWindowAndFire()
	elseif shotsRemaining > 0 then
		local direction = currentAimDirection()
		if direction and direction.Magnitude > 1e-3 then
			beginSwing(direction.Unit)
		end
	end
end

-- Up/Down are unused anywhere else in this game, but Roblox's default
-- character-movement bindings still claim them -- bound here at high
-- priority with a Sink result so the Attacker's character doesn't walk while
-- the axis window is open (or at any other time while aiming is active; the
-- keys do nothing outside the window stage regardless). The actual
-- continuous movement is polled from onRender via IsKeyDown, not detected
-- here -- ContextActionService only needs to block the default binding.
local ARROW_SINK_ACTION = "AttackInputArrowSink"

local function sinkArrowKeys()
	return Enum.ContextActionResult.Sink
end

-- Alternate input for the same axis window dot Up/Down drives (session 016
-- follow-up): each scroll notch nudges dotLevel by WHEEL_STEP, same clamping
-- as the held-key path. Only acts during the window stage -- harmless the
-- rest of the time, same as Up/Down doing nothing outside it either.
local function onWheelChanged(inputObject, gameProcessed)
	if gameProcessed or stage ~= "window" then
		return
	end
	if inputObject.UserInputType ~= Enum.UserInputType.MouseWheel then
		return
	end
	dotLevel = clampDotLevel(lockedWeapon, dotLevel + inputObject.Position.Z * WHEEL_STEP)
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
		axisTrack, axisDot, axisLever, axisFulcrum, axisCountdown, axisTitle = makeAxisMeter(meterGui)
	end
	WeaponView.start()
end

-- Session 015: hides the Flag on this client alone (Builder's view and the
-- underlying physics are unaffected) for as long as this player is the
-- Attacker and it hasn't been revealed yet -- independent of ATTACK phase,
-- since the Attacker could in principle be looking at the platform during
-- BUILD/POSITION too. Runs on every StateChanged, not just the aiming
-- active/inactive transition below.
local function applyFlagConcealment(stateChanged)
	flagRevealed = stateChanged.flagRevealed == true
	local flag = flagPart()
	if not flag then
		return
	end
	local isAttackerRole = stateChanged.roles ~= nil and stateChanged.roles.attacker == player.UserId
	flag.LocalTransparencyModifier = (isAttackerRole and not flagRevealed) and 1 or 0
end

-- Called on every StateChanged. Aiming is live only while phase == "ATTACK" and
-- the local player is the Attacker. state.weapon mirrors the server-mandated
-- currentWeapon -- there's no client choice -- and this has to happen even when
-- `active` doesn't change, since the sequence switches weapon mid-turn (shot 2
-- to shot 3) without a phase transition. On the transition in it connects the
-- render and input handlers and publishes the readout; on the transition out
-- it disconnects them, cancels any in-progress swing, and hides everything.
function AttackInput.update(stateChanged)
	applyFlagConcealment(stateChanged)
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
		updateAxisVisual(state.weapon, 0)
		publish()
		renderConn = RunService.RenderStepped:Connect(onRender)
		inputConn = UserInputService.InputBegan:Connect(onInput)
		wheelConn = UserInputService.InputChanged:Connect(onWheelChanged)
		ContextActionService:BindActionAtPriority(
			ARROW_SINK_ACTION,
			sinkArrowKeys,
			false,
			Enum.ContextActionPriority.High.Value,
			Enum.KeyCode.Up,
			Enum.KeyCode.Down
		)
	else
		if renderConn then
			renderConn:Disconnect()
			renderConn = nil
		end
		if inputConn then
			inputConn:Disconnect()
			inputConn = nil
		end
		if wheelConn then
			wheelConn:Disconnect()
			wheelConn = nil
		end
		ContextActionService:UnbindAction(ARROW_SINK_ACTION)
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
