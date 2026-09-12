-- Builder-only shield activation during ATTACK: the Builder's first bit of
-- agency after ConfirmBuild. Active only while phase == "ATTACK" and the local
-- player is the Builder; there's no new camera for this (session 011's Open
-- Gate) -- the Builder keeps whatever free-look view BuildCamera last set,
-- from a stand point (MatchController.standFor) that already faces the
-- trench. A single key press fires ActivateShield; the server is authoritative
-- on whether it actually lands (Builder role, ATTACK phase, not already used
-- this round) -- the local shieldAvailable check here only avoids firing a
-- request that can't possibly do anything.

local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Remotes = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Remotes"))

local player = Players.LocalPlayer

local ShieldInput = {}

local SHIELD_KEY = Enum.KeyCode.F

local active = false
local shieldAvailable = true
local inputConn

local function onInput(inputObject, gameProcessed)
	if gameProcessed then
		return
	end
	if inputObject.KeyCode ~= SHIELD_KEY then
		return
	end
	if not shieldAvailable then
		return
	end
	Remotes.ActivateShield:FireServer()
end

-- Nothing to build up front; update() owns the activate/deactivate lifecycle.
function ShieldInput.start() end

-- Called on every StateChanged broadcast. Mirrors AttackInput's
-- activate/deactivate pattern: connect the input handler on the phase+role
-- transition in, disconnect on the way out. shieldAvailable has to track every
-- broadcast, not just the transition, since it flips false mid-ATTACK with no
-- phase or role change to hang the update off of.
function ShieldInput.update(state)
	shieldAvailable = state.shieldAvailable ~= false

	local shouldBeActive = state.phase == "ATTACK" and state.roles ~= nil and state.roles.builder == player.UserId

	if shouldBeActive == active then
		return
	end
	active = shouldBeActive

	if active then
		inputConn = UserInputService.InputBegan:Connect(onInput)
	else
		if inputConn then
			inputConn:Disconnect()
			inputConn = nil
		end
	end
end

return ShieldInput
