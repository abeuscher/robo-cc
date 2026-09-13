-- Round-result / match-result banner, centered top of screen. Tracks
-- StateChanged only to know the local player's role at the moment a
-- RoundResult arrives -- roles flip on SWAP, which broadcasts its own
-- StateChanged right after.
--
-- Session 009: the server now holds the round outcome on screen for
-- Config.RoundEndHoldTime (camera included -- AttackCamera stays engaged
-- through RESOLVE) instead of cutting straight to the next round, so neither
-- banner auto-fades anymore; a "Continue" button lets either player skip the
-- wait early via ContinueRequested. update() hides the whole banner once the
-- next StateChanged moves the phase off RESOLVE -- which, for a MatchResult,
-- never happens (the match loop stops advancing), so that banner stays up
-- exactly as it always did. The button itself is only ever shown for a round
-- result -- a MatchResult has nothing left to continue past.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Remotes = require(ReplicatedStorage.Shared.Remotes)

local player = Players.LocalPlayer

local ResultBanner = {}

local REASON_TEXT = {
	survived = "the Princess survived",
	toppled = "knocked off her feet",
}

local gui, container, title, subtitle, continueButton
local lastRoles = nil

local function onContinueClicked()
	continueButton.Visible = false
	Remotes.ContinueRequested:FireServer()
end

local function build()
	if gui then
		return
	end

	gui = Instance.new("ScreenGui")
	gui.Name = "ResultBanner"
	gui.ResetOnSpawn = false

	container = Instance.new("Frame")
	container.Size = UDim2.fromOffset(560, 160)
	container.AnchorPoint = Vector2.new(0.5, 0)
	container.Position = UDim2.new(0.5, 0, 0, 40)
	container.BackgroundTransparency = 1
	container.Visible = false
	container.Parent = gui

	title = Instance.new("TextLabel")
	title.Size = UDim2.new(1, 0, 0, 56)
	title.BackgroundTransparency = 1
	title.Font = Enum.Font.GothamBold
	title.TextSize = 44
	title.TextColor3 = Color3.fromRGB(255, 235, 200)
	title.Text = ""
	title.Parent = container

	subtitle = Instance.new("TextLabel")
	subtitle.Size = UDim2.new(1, 0, 0, 48)
	subtitle.Position = UDim2.new(0, 0, 0, 58)
	subtitle.BackgroundTransparency = 1
	subtitle.Font = Enum.Font.Gotham
	subtitle.TextSize = 18
	subtitle.TextWrapped = true
	subtitle.TextYAlignment = Enum.TextYAlignment.Top
	subtitle.TextColor3 = Color3.fromRGB(220, 220, 225)
	subtitle.Text = ""
	subtitle.Parent = container

	continueButton = Instance.new("TextButton")
	continueButton.Name = "Continue"
	continueButton.Size = UDim2.fromOffset(160, 36)
	continueButton.AnchorPoint = Vector2.new(0.5, 0)
	continueButton.Position = UDim2.new(0.5, 0, 0, 116)
	continueButton.BackgroundColor3 = Color3.fromRGB(60, 90, 130)
	continueButton.Font = Enum.Font.GothamBold
	continueButton.TextSize = 20
	continueButton.TextColor3 = Color3.fromRGB(240, 240, 245)
	continueButton.Text = "Continue"
	continueButton.Visible = false
	continueButton.Parent = container
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 6)
	corner.Parent = continueButton
	continueButton.MouseButton1Click:Connect(onContinueClicked)

	gui.Parent = player:WaitForChild("PlayerGui")
end

local function show(titleText, subtitleText, showContinue)
	build()
	container.Visible = true
	title.Text = titleText
	subtitle.Text = subtitleText
	continueButton.Visible = showContinue
end

local function myRole()
	if not lastRoles then
		return nil
	end
	if lastRoles.builder == player.UserId then
		return "Builder"
	elseif lastRoles.attacker == player.UserId then
		return "Attacker"
	end
	return nil
end

local function onRoundResult(result)
	local headline
	if result.winner == nil then
		headline = "Round tied"
	elseif myRole() == result.winner then
		headline = "You win the round"
	else
		headline = result.winner .. " wins the round"
	end

	local subtitleText = string.format(
		"Builder %d pts (%d/%d pieces survived)  ·  Attacker %d pts (%s)",
		result.builderPoints,
		result.piecesSurvived,
		result.piecesTotal,
		result.attackerPoints,
		REASON_TEXT[result.reason] or result.reason
	)
	show(headline, subtitleText, true)
end

local function onMatchResult(result)
	local headline
	if result.winner == nil then
		headline = "Match tied"
	elseif result.winner == player.UserId then
		headline = "You win the match!"
	else
		headline = "Match over"
	end

	local myScore = (result.score and result.score[player.UserId]) or 0
	local otherScore = 0
	for userId, wins in result.score or {} do
		if userId ~= player.UserId then
			otherScore = wins
		end
	end
	show(headline, string.format("Final score  —  You: %d pts   Opponent: %d pts", myScore, otherScore), false)
end

function ResultBanner.start()
	build()
	Remotes.RoundResult.OnClientEvent:Connect(onRoundResult)
	Remotes.MatchResult.OnClientEvent:Connect(onMatchResult)
end

function ResultBanner.update(state)
	lastRoles = state.roles
	if state.phase ~= "RESOLVE" and container then
		container.Visible = false
	end
end

return ResultBanner
