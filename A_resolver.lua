--credit to https://github.com/daily3014/lbox/blob/main/resolver.lua
--script have been fixed to auto cycle the angles and uses only 3 main ones offsets from direct direction at you
local config = {
	onlyHeadshots = true,
	maxMisses = 3,
	minPriority = 3,
	cycleYawFOV = 60, -- FOV to use when cycling the yaw through keybind

	yawCycle = {
		0,
		90, -90,
	}
}

local lastHits = {}
local usesAntiAim = {}
local lastConsecutiveShots = {}
local customAngleData = {}
local awaitingConfirmation = {}
local misses = {}
local headshotWeapons = {[17] = true, [43] = true}
local cycleKeyState = false

local M_RADPI = 180 / math.pi

local function isNaN(x) return x ~= x end

local function getBool(event, name)
	local bool = event:GetInt(name)
	return bool == 1
end

local function getSteamID(player)
	local playerInfo = client.GetPlayerInfo(player:GetIndex())
	return playerInfo.SteamID
end

local function getMinimumLatency(trueLatency)
	local latency = clientstate.GetLatencyIn() + clientstate.GetLatencyOut()
	if trueLatency == true then return latency end
	return latency <= 0.1 and 0.1 or latency
end

local function setupPlayerAngleData(player)
	local steamID = getSteamID(player)

	if customAngleData[steamID] then
		return
	end

	customAngleData[steamID] = {
		plr = player,
		yawCycleIndex = 0,
		lastYaw = 0,
	}
end

local function isLmaoboxKeybindDown(name)
	if gui.GetValue(name) == 0 then
		return false
	end
	return input.IsButtonDown(gui.GetValue(name))
end

local function resolvePitch(pitch)
	if pitch % 90 == 0 then -- lmaobox fake pitch (up & down)
		return -pitch
	end

	if pitch % 3256 == 0 then -- lmaobox fake pitch (center)
		return 0
	end

	if pitch % 271 == 0 then -- rijin fake pitch? (no idea)
		return pitch / 271 * 89
	end

	return pitch
end

local function isUsingAntiAim(pitch)
	if pitch > 89.4 or pitch < -89.4 then
		return true
	end

	return false
end

local function normalizeAngle(offsetNumber)
    offsetNumber = offsetNumber % 360
    if offsetNumber > 180 then
        offsetNumber = offsetNumber - 360
    elseif offsetNumber < -180 then
        offsetNumber = offsetNumber + 360
    end
    return offsetNumber
end

local function lookAt(from, to, offset)
    offset = offset or 0
    if not from or not to then return end

    local delta = vector.Subtract(to, from)
    local yaw = math.atan(delta.y, delta.x) * 180 / math.pi

    yaw = yaw + offset
    yaw = normalizeAngle(yaw)

    if isNaN(yaw) then yaw = 0 end

    return yaw
end

local function getYaw(currentYaw, data)
	local newYaw = config.yawCycle[math.floor(data.yawCycleIndex)]
		local enemyPosition = data.plr:GetAbsOrigin()
		local localPlayerPosition = entities.GetLocalPlayer():GetAbsOrigin()

		return lookAt(enemyPosition, localPlayerPosition, newYaw)
end

local function getYawText(data)
	local newYaw = config.yawCycle[math.floor(data.yawCycleIndex)]
	if not newYaw then return "" end

	if type(newYaw) == "string" then
		return newYaw
	end

	return newYaw .. "°"
end

local function announceResolve(data)
	local name, yaw = client.GetPlayerInfo(data.plr:GetIndex()).Name, getYawText(data)
	if yaw == "" or data.lastYaw == yaw then return end
	
	data.lastYaw = yaw
	client.ChatPrintf(string.format("\x073475c9[Resolver] \x01Adjusted player \x073475c9'%s'\x01 yaw to \x07f22929%s", name, yaw))
end

local function announceMiss(player)
	local name, steamID = client.GetPlayerInfo(player:GetIndex()).Name, getSteamID(player)
	client.ChatPrintf(string.format("\x073475c9[Resolver] \x01Missed player \x073475c9'%s'\x01. Shots remaining: \x07f22929%s", name, 4 - (misses[steamID] or 1)))
end

local function cycleYaw(data, step)
	data.yawCycleIndex = data.yawCycleIndex + (step or .5)

	if data.yawCycleIndex > #config.yawCycle then
		data.yawCycleIndex = 1
	end

	announceResolve(data)
end

local function tryingToShoot(cmd)
	if cmd and (cmd.buttons ~ IN_ATTACK) == 0 then
		return false
	end

	if gui.GetValue("aim position") == "body" then
		return false
	end

	if gui.GetValue("aim bot") then
		local keyMode = gui.GetValue("aim key mode")

		if keyMode == "press-to-toggle" then
			return true
		elseif keyMode == "hold-to-use" then
			if input.IsButtonDown(gui.GetValue("aim key")) then
				return true
			end
		else
			return true -- automatic aim mode
		end
	end

	return false
end

local function isValidWeapon(weapon)
	if not weapon then return false end
	if not weapon:IsWeapon() then return false end
	if not weapon:IsShootingWeapon() then return false end

	return true
end

local function getHitboxPos(entity, hitboxID)
	local hitbox = entity:GetHitboxes()[hitboxID]
	if not hitbox then return nil end

	return (hitbox[1] + hitbox[2]) * 0.5
end

local function positionAngles(source, dest)
	local delta = source - dest

	local pitch = math.atan(delta.z / delta:Length2D()) * M_RADPI
	local yaw = math.atan(delta.y / delta.x) * M_RADPI

	if delta.x >= 0 then
		yaw = yaw + 180
	end

	if isNaN(pitch) then pitch = 0 end
	if isNaN(yaw) then yaw = 0 end

	return EulerAngles(pitch, yaw, 0)
end

local function angleFov(vFrom, vTo)
	local vSrc = vFrom:Forward()
	local vDst = vTo:Forward()
	
	local fov = math.deg(math.acos(vDst:Dot(vSrc) / vDst:LengthSqr()))
	if isNaN(fov) then fov = 0 end

	return fov
end

local function getEyePos(player)
	return player:GetAbsOrigin() + player:GetPropVector("localdata", "m_vecViewOffset[0]")
end

local function getEyeAngles(player)
	local angles = player:GetPropVector("tfnonlocaldata", "m_angEyeAngles[0]")
	return EulerAngles(angles.x, angles.y, angles.z)
end

local function checkForFakePitch(player, steamID)
	local angles = getEyeAngles(player)

	if isUsingAntiAim(angles.pitch) then
		if not usesAntiAim[steamID] then
			usesAntiAim[steamID] = true
		end

		setupPlayerAngleData(player)
	end
end

local function getBestTarget(customFOV)
	local localPlayer = entities.GetLocalPlayer()
	local players = entities.FindByClass("CTFPlayer")
	local target = nil
	local lastFov = math.huge

	for _, entity in pairs(players) do
		if not entity then goto continue end
		if not entity:IsAlive() then goto continue end
		if entity:GetTeamNumber() == localPlayer:GetTeamNumber() then goto continue end

		local player = entity
		local aimPos = getHitboxPos(player, 1)
		local angles = positionAngles(getEyePos(localPlayer), aimPos)
		local fov = angleFov(angles, engine.GetViewAngles())
		if fov > (customFOV or gui.GetValue("aim fov")) then goto continue end

		if fov < lastFov then
			lastFov = fov
			target = { entity = entity, pos = aimPos, angles = angles, factor = fov }
		end

		::continue::
	end

	return target
end

local function playerShot(cmd, player)
	player = player or entities.GetLocalPlayer()

	local weapon = player:GetPropEntity("m_hActiveWeapon")
	if not isValidWeapon(weapon) then return false end
	if not tryingToShoot(cmd) then return false end

	local id = weapon:GetWeaponID()
	if config.onlyHeadshots and not headshotWeapons[id] then return end

	local shots = weapon:GetPropInt("m_iConsecutiveShots")

	if not lastConsecutiveShots[id] then
		lastConsecutiveShots[id] = shots
	end

	if shots ~= 0 then
		if lastConsecutiveShots[id] < shots then
			lastConsecutiveShots[id] = shots
			return true
		end

		return false
	else
		lastConsecutiveShots[id] = 0
	end
	
	return false
end

local function propUpdate()
	local localPlayer = entities.GetLocalPlayer()
	local players = entities.FindByClass("CTFPlayer")

	for idx, player in pairs(players) do
		if idx == localPlayer:GetIndex() then goto continue end
		if player:IsDormant() or not player:IsAlive() then goto continue end
		
		if playerlist.GetPriority(player) >= config.minPriority then
			setupPlayerAngleData(player)
		end

		local steamID = getSteamID(player)
		local networkAngle = player:GetPropVector("tfnonlocaldata", "m_angEyeAngles[0]") 
		local customAngle = Vector3(networkAngle.x, networkAngle.y, networkAngle.z)
		
		if isUsingAntiAim(networkAngle.x) then
			if not usesAntiAim[steamID] then
				usesAntiAim[steamID] = true
			end 

			setupPlayerAngleData(player)
		end

		if customAngleData[steamID] then
			customAngle.y = getYaw(networkAngle.y, customAngleData[steamID])
			customAngle.x = resolvePitch(networkAngle.x)

			player:SetPropVector(customAngle, "tfnonlocaldata", "m_angEyeAngles[0]");
		end

		::continue::
	end
end

-- Returns if the weapon can shoot
---@param weapon Entity
---@return boolean
local function CanShoot(weapon)
    local lPlayer = entities.GetLocalPlayer()
    if not lPlayer or weapon:IsMeleeWeapon() then return false end

    local nextPrimaryAttack = weapon:GetPropFloat("LocalActiveWeaponData", "m_flNextPrimaryAttack")
    local nextAttack = lPlayer:GetPropFloat("bcc_localdata", "m_flNextAttack")
    if (not nextPrimaryAttack) or (not nextAttack) then return false end

    return (nextPrimaryAttack <= globals.CurTime()) and (nextAttack <= globals.CurTime())
end

local lastCanShoot = true
local lastScoped = false

local function checkForCycleYawKeybind()
    local keyDown = isLmaoboxKeybindDown("toggle yaw key")
    local plocal = entities.GetLocalPlayer()
    if not plocal then return end

    local weapon = plocal:GetPropEntity("m_hActiveWeapon")
    if not weapon then return end

    local canShoot = CanShoot(weapon)
    local scoping = plocal:InCond(1)

    -- Check if the keybind is pressed or if there's a transition from being able to shoot to not being able to shoot
    -- And ensure that scoping state did not change simultaneously
    if (cycleKeyState ~= keyDown and keyDown == true) or (lastCanShoot and not canShoot and lastScoped == scoping and scoping == true) then
        local victimInfo = getBestTarget(config.cycleYawFOV)

        if victimInfo then
            local victim = victimInfo.entity
            if not customAngleData[getSteamID(victim)] then
                setupPlayerAngleData(victim)
            end

            engine.PlaySound("ui/panel_close.wav")
            cycleYaw(customAngleData[getSteamID(victim)], 1)
        end
    end

    cycleKeyState = keyDown
    lastCanShoot = canShoot
    lastScoped = scoping
end




local function processConfirmation(steamID, data)
	local enemy, hitTime, wasHit = data.enemy, data.hitTime, data.wasHit

	if wasHit then
		awaitingConfirmation[steamID] = nil
		goto continue
	end

	if lastHits[steamID] and lastHits[steamID].wasHit then
		local diff = globals.CurTime() - lastHits[steamID].time
		if diff < getMinimumLatency(true) * 2 then
			awaitingConfirmation[steamID] = nil -- we hit the person but the event was fired before awaitingconfirmation was updated
			goto continue
		end
	end

	if globals.CurTime() >= hitTime then
		local usingAntiAim = usesAntiAim[steamID]

		if not usingAntiAim then
			if not misses[steamID] then
				misses[steamID] = 0
			end

			if misses[steamID] < config.maxMisses then
				misses[steamID] = misses[steamID] + 1
				awaitingConfirmation[steamID] = nil
				announceMiss(enemy)
				goto continue
			end
		end

		if not customAngleData[steamID] then
			setupPlayerAngleData(enemy)
		end

		cycleYaw(customAngleData[steamID])
		awaitingConfirmation[steamID] = nil
	end

	::continue::
end

local function handlePlayerShooting(cmd)
	if not cmd then return end
	local playerDidShoot = playerShot(cmd)

	if playerDidShoot then
		local victimInfo = getBestTarget()
	
		if victimInfo then
			local victim = victimInfo.entity

			if awaitingConfirmation[getSteamID(victim)] and awaitingConfirmation[getSteamID(victim)].wasHit then
				goto skip
			end

			awaitingConfirmation[getSteamID(victim)] = {enemy = victim, hitTime = globals.CurTime() + getMinimumLatency(), wasHit = false}
		end
	end

	::skip::
end

local function fireGameEvent(event)
	if event:GetName() == 'player_hurt' then
		local localPlayer = entities.GetLocalPlayer()
		local victim = entities.GetByUserID(event:GetInt("userid"))
		local attacker = entities.GetByUserID(event:GetInt("attacker"))
		local headshot = getBool(event, "crit")

		if (attacker ~= nil and localPlayer:GetIndex() ~= attacker:GetIndex()) then
			local attackerSteamID = getSteamID(attacker)
			checkForFakePitch(attacker, attackerSteamID)
		end

		local steamID = getSteamID(victim)

		if awaitingConfirmation[steamID] then
			awaitingConfirmation[steamID].wasHit = headshot
		else
			lastHits[steamID] = {wasHit = headshot, time = globals.CurTime()} -- could have fired before createmove
		end
	end
end

local function createMove(cmd)
	if not gamerules.IsTruceActive() then
		handlePlayerShooting(cmd)
	end

	checkForCycleYawKeybind()

	for steamID, data in pairs(awaitingConfirmation) do
		processConfirmation(steamID, data)
	end
end

callbacks.Register("CreateMove", "Resolver.CreateMove", createMove)
callbacks.Register("FireGameEvent", "Resolver.FireGameEvent", fireGameEvent)
callbacks.Register("PostPropUpdate", "Resolver.PostPropUpdate", propUpdate)