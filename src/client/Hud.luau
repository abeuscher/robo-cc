-- Screen-corner readout. Driven by StateChanged for role / phase / counts, plus
-- AttackInput.setAttackReadout for the live weapon + angle line. Shows
-- blocks-remaining during BUILD and shots-remaining + weapon during ATTACK, with
-- a per-phase controls hint and a "waiting for the other player" line until both
-- roles are filled.

local Players = game:GetService("Players")

local player = Players.LocalPlayer

local Hud = {}

local gui, roleLabel, phaseLabel, blocksLabel, shotsLabel, weaponLabel, hintLabel, waitingLabel

local lastState = nil
local readout = { weapon = "Ballista", angle = 0 }

local function label(parent, size, color)
	local l = Instance.new("TextLabel")
	l.Size = UDim2.new(1, 0, 0, size)
	l.BackgroundTransparency = 1
	l.TextXAlignment = Enum.TextXAlignment.Left
	l.Font = Enum.Font.GothamBold
	l.TextColor3 = color
	l.TextSize = size
	l.Text = ""
	l.Parent = parent
	return l
end

function Hud.start()
	if gui then
		return
	end

	gui = Instance.new("ScreenGui")
	gui.Name = "Hud"
	gui.ResetOnSpawn = false

	local container = Instance.new("Frame")
	container.Size = UDim2.fromOffset(460, 210)
	container.AnchorPoint = Vector2.new(1, 1)
	container.Position = UDim2.new(1, -16, 1, -16)
	container.BackgroundTransparency = 1
	container.Parent = gui

	local layout = Instance.new("UIListLayout")
	layout.Padding = UDim.new(0, 4)
	layout.Parent = container

	roleLabel = label(container, 28, Color3.fromRGB(238, 238, 238))
	phaseLabel = label(container, 20, Color3.fromRGB(200, 205, 215))
	blocksLabel = label(container, 20, Color3.fromRGB(200, 205, 215))
	shotsLabel = label(container, 20, Color3.fromRGB(200, 205, 215))
	weaponLabel = label(container, 18, Color3.fromRGB(255, 210, 120))
	hintLabel = label(container, 15, Color3.fromRGB(150, 155, 165))
	hintLabel.Size = UDim2.new(1, 0, 0, 36)
	hintLabel.TextWrapped = true
	hintLabel.TextYAlignment = Enum.TextYAlignment.Top

	waitingLabel = label(container, 18, Color3.fromRGB(230, 200, 120))

	gui.Parent = player:WaitForChild("PlayerGui")
end

-- Redraws every label from lastState + readout. Safe to call before any state
-- has arrived.
local function render()
	Hud.start()
	if not lastState then
		return
	end
	local state = lastState

	local myRole
	if state.roles then
		if state.roles.builder == player.UserId then
			myRole = "Builder"
		elseif state.roles.attacker == player.UserId then
			myRole = "Attacker"
		end
	end

	roleLabel.Text = myRole and ("You are the " .. myRole) or "You are a spectator"
	phaseLabel.Text = "Phase: " .. state.phase

	local inBuild = state.phase == "BUILD"
	local inAttack = state.phase == "ATTACK"

	blocksLabel.Visible = inBuild
	local remaining = state.blocksRemaining or {}
	blocksLabel.Text = string.format(
		"Blocks left  —  Standard: %d   Wide: %d",
		remaining.Standard or 0,
		remaining.Wide or 0
	)

	shotsLabel.Visible = inAttack
	shotsLabel.Text = string.format("Shots left  —  %d", state.shotsRemaining or 0)

	weaponLabel.Visible = inAttack and myRole == "Attacker"
	if readout.weapon == "Catapult" then
		weaponLabel.Text = string.format("Catapult  ·  angle %d°  ·  click, click to launch", readout.angle)
	else
		weaponLabel.Text = "Ballista  ·  click, click to launch"
	end

	local hintForBuilder = inBuild and myRole == "Builder"
	local hintForAttacker = inAttack and myRole == "Attacker"
	hintLabel.Visible = hintForBuilder or hintForAttacker
	if hintForAttacker then
		hintLabel.Text = "mouse aim · Q/E angle (catapult) · F weapon · click, click at meter target to launch"
	else
		hintLabel.Text = "click pile to lift · click cell to place · R rotate · Q drop · click a wall block to return it"
	end

	local waiting = state.roles == nil or state.roles.attacker == nil
	waitingLabel.Visible = waiting
	waitingLabel.Text = waiting and "Waiting for the other player…" or ""
end

function Hud.update(state)
	lastState = state
	render()
end

-- Called by AttackInput whenever the weapon / angle changes.
function Hud.setAttackReadout(values)
	readout = values
	render()
end

return Hud
