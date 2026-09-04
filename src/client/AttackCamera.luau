-- Over-the-shoulder camera for the Attacker during ATTACK, locked to a short,
-- fixed distance behind the character (not the scroll wheel) -- true first
-- person (0 studs) was too tight to see by, this backs off just enough. The
-- Builder keeps the normal camera. Released back to the player's own zoom
-- range whenever the local player isn't the ATTACK-phase Attacker.

local Players = game:GetService("Players")

local player = Players.LocalPlayer

local AttackCamera = {}

local ZOOM_DISTANCE = 8 -- studs behind the character; min == max locks the scroll wheel out

local active = false
local savedMinZoom, savedMaxZoom

local function enter()
	if active then
		return
	end
	active = true
	savedMinZoom = player.CameraMinZoomDistance
	savedMaxZoom = player.CameraMaxZoomDistance
	player.CameraMode = Enum.CameraMode.Classic
	player.CameraMinZoomDistance = ZOOM_DISTANCE
	player.CameraMaxZoomDistance = ZOOM_DISTANCE
end

local function exit()
	if not active then
		return
	end
	active = false
	if savedMinZoom then
		player.CameraMinZoomDistance = savedMinZoom
	end
	if savedMaxZoom then
		player.CameraMaxZoomDistance = savedMaxZoom
	end
end

-- Nothing to prime up front; update() owns the transitions.
function AttackCamera.start() end

function AttackCamera.update(state)
	local mine = state.phase == "ATTACK"
		and state.roles ~= nil
		and state.roles.attacker == player.UserId
	if mine then
		enter()
	else
		exit()
	end
end

return AttackCamera
