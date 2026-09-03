-- Builds the title screen in code and parents it to PlayerGui. No StarterGui
-- assets, no .rbxmx models -- everything is git-visible here.

local Players = game:GetService("Players")

local TitleScreen = {}

-- onStart is called once, when the player clicks Start. The screen hides itself.
function TitleScreen.show(onStart)
	local playerGui = Players.LocalPlayer:WaitForChild("PlayerGui")

	local gui = Instance.new("ScreenGui")
	gui.Name = "TitleScreen"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = true

	local backdrop = Instance.new("Frame")
	backdrop.Size = UDim2.fromScale(1, 1)
	backdrop.BackgroundColor3 = Color3.fromRGB(18, 20, 26)
	backdrop.BorderSizePixel = 0
	backdrop.Parent = gui

	local title = Instance.new("TextLabel")
	title.AnchorPoint = Vector2.new(0.5, 0.5)
	title.Position = UDim2.fromScale(0.5, 0.36)
	title.Size = UDim2.fromScale(0.7, 0.18)
	title.BackgroundTransparency = 1
	title.Font = Enum.Font.GothamBlack
	title.Text = "SIEGE"
	title.TextColor3 = Color3.fromRGB(238, 238, 238)
	title.TextScaled = true
	title.Parent = backdrop

	local subtitle = Instance.new("TextLabel")
	subtitle.AnchorPoint = Vector2.new(0.5, 0.5)
	subtitle.Position = UDim2.fromScale(0.5, 0.5)
	subtitle.Size = UDim2.fromScale(0.6, 0.06)
	subtitle.BackgroundTransparency = 1
	subtitle.Font = Enum.Font.Gotham
	subtitle.Text = "build the wall. break the wall."
	subtitle.TextColor3 = Color3.fromRGB(150, 155, 165)
	subtitle.TextScaled = true
	subtitle.Parent = backdrop

	local button = Instance.new("TextButton")
	button.AnchorPoint = Vector2.new(0.5, 0.5)
	button.Position = UDim2.fromScale(0.5, 0.66)
	button.Size = UDim2.fromScale(0.26, 0.1)
	button.BackgroundColor3 = Color3.fromRGB(70, 130, 200)
	button.AutoButtonColor = true
	button.Font = Enum.Font.GothamBold
	button.Text = "Start"
	button.TextColor3 = Color3.fromRGB(255, 255, 255)
	button.TextScaled = true
	button.Parent = backdrop

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 8)
	corner.Parent = button

	local fired = false
	button.Activated:Connect(function()
		if fired then
			return
		end
		fired = true
		gui.Enabled = false
		onStart()
	end)

	gui.Parent = playerGui
	return gui
end

return TitleScreen
