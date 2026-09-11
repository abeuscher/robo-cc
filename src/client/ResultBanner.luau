-- Round-result / match-result banner, centered top of screen. A round banner
-- fades out after a few seconds; the match banner stays up. Tracks
-- StateChanged only to know the local player's role at the moment a
-- RoundResult arrives -- roles flip on SWAP, which broadcasts its own
-- StateChanged right after.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Remotes = require(ReplicatedStorage.Shared.Remotes)

local player = Players.LocalPlayer

local ResultBanner = {}

local FADE_DELAY = 3
local FADE_TIME = 1

local REASON_TEXT = {
	survived = "the Princess survived",
	direct = "a direct hit",
	crushed = "a falling block",
}

local gui, container, title, subtitle
local lastRoles = nil
local fadeToken = 0

local function build()
	if gui then
		return
	end

	gui = Instance.new("ScreenGui")
	gui.Name = "ResultBanner"
	gui.ResetOnSpawn = false

	container = Instance.new("Frame")
	container.Size = UDim2.fromOffset(560, 90)
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
	subtitle.Size = UDim2.new(1, 0, 0, 28)
	subtitle.Position = UDim2.new(0, 0, 0, 58)
	subtitle.BackgroundTransparency = 1
	subtitle.Font = Enum.Font.Gotham
	subtitle.TextSize = 22
	subtitle.TextColor3 = Color3.fromRGB(220, 220, 225)
	subtitle.Text = ""
	subtitle.Parent = container

	gui.Parent = player:WaitForChild("PlayerGui")
end

local function show(titleText, subtitleText, autoFade)
	build()
	container.Visible = true
	title.TextTransparency = 0
	subtitle.TextTransparency = 0
	title.Text = titleText
	subtitle.Text = subtitleText

	fadeToken += 1
	local myToken = fadeToken
	if autoFade then
		task.delay(FADE_DELAY, function()
			if myToken ~= fadeToken then
				return
			end
			TweenService:Create(title, TweenInfo.new(FADE_TIME), { TextTransparency = 1 }):Play()
			TweenService:Create(subtitle, TweenInfo.new(FADE_TIME), { TextTransparency = 1 }):Play()
		end)
	end
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
	local youWon = myRole() == result.winner
	local headline = youWon and "You win the round" or (result.winner .. " wins the round")
	show(headline, REASON_TEXT[result.reason] or result.reason, true)
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
	show(headline, string.format("Final score  —  You: %d   Opponent: %d", myScore, otherScore), false)
end

function ResultBanner.start()
	build()
	Remotes.RoundResult.OnClientEvent:Connect(onRoundResult)
	Remotes.MatchResult.OnClientEvent:Connect(onMatchResult)
end

function ResultBanner.update(state)
	lastRoles = state.roles
end

return ResultBanner
