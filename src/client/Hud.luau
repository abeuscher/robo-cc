-- Screen-corner readout, driven entirely by StateChanged. Role banner, current
-- phase, blocks-remaining during BUILD, and a "waiting for the other player"
-- line until both roles are filled.

local Players = game:GetService("Players")

local player = Players.LocalPlayer

local Hud = {}

local gui, roleLabel, phaseLabel, blocksLabel, hintLabel, waitingLabel

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
	container.Size = UDim2.fromOffset(460, 170)
	container.Position = UDim2.fromOffset(16, 16)
	container.BackgroundTransparency = 1
	container.Parent = gui

	local layout = Instance.new("UIListLayout")
	layout.Padding = UDim.new(0, 4)
	layout.Parent = container

	roleLabel = label(container, 28, Color3.fromRGB(238, 238, 238))
	phaseLabel = label(container, 20, Color3.fromRGB(200, 205, 215))
	blocksLabel = label(container, 20, Color3.fromRGB(200, 205, 215))
	hintLabel = label(container, 15, Color3.fromRGB(150, 155, 165))
	hintLabel.Size = UDim2.new(1, 0, 0, 36)
	hintLabel.TextWrapped = true
	hintLabel.TextYAlignment = Enum.TextYAlignment.Top

	waitingLabel = label(container, 18, Color3.fromRGB(230, 200, 120))

	gui.Parent = player:WaitForChild("PlayerGui")
end

function Hud.update(state)
	Hud.start()

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

	local buildForMe = state.phase == "BUILD" and myRole == "Builder"
	blocksLabel.Visible = state.phase == "BUILD"
	local remaining = state.blocksRemaining or {}
	blocksLabel.Text = string.format(
		"Blocks left  —  Standard: %d   Wide: %d",
		remaining.Standard or 0,
		remaining.Wide or 0
	)
	hintLabel.Visible = buildForMe
	hintLabel.Text = "click pile to lift · click cell to place · R rotate · Q drop · click a wall block to return it"

	local waiting = state.roles == nil or state.roles.attacker == nil
	waitingLabel.Visible = waiting
	waitingLabel.Text = waiting and "Waiting for the other player…" or ""
end

return Hud
