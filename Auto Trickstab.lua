-- Calculate angle between two points
local function PositionAngles(source, dest)
    local M_RADPI = 180 / math.pi
    local delta = source - dest
    local pitch = math.atan(delta.z / delta:Length2D()) * M_RADPI
    local yaw = math.atan(delta.y / delta.x) * M_RADPI
    yaw = delta.x >= 0 and yaw + 180 or yaw
    return EulerAngles(pitch, yaw, 0)
end

-- Get the center position of a player's hitbox
local function GetHitboxPos(player, hitboxID)
    local hitbox = player:GetHitboxes()[hitboxID]
    return hitbox and (hitbox[1] + hitbox[2]) * 0.5 or nil
end

-- Normalizes a vector to a unit vector
local function NormalizeVector(vec)
    local length = math.sqrt(vec.x^2 + vec.y^2 + vec.z^2)
    return Vector3(vec.x / length, vec.y / length, vec.z / length)
end

local function calculateYaw(y, x)
    local angle = math.atan(y / x)
    if x < 0 then
        angle = angle + math.pi -- adjust for 2nd and 3rd quadrants
    elseif y < 0 then
        angle = angle + 2 * math.pi -- adjust for 4th quadrant
    end
    return angle * (180 / math.pi) -- convert to degrees
end

local cachedLocalPlayer
local cachedPlayers = {}
local cachedLoadoutSlot2
local pLocalViewPos
local tickCount = 0
local pLocal = entities.GetLocalPlayer()

-- Function to update the cache for the local player and loadout slot
local function UpdateLocalPlayerCache()
    cachedLocalPlayer = entities.GetLocalPlayer()
    cachedLoadoutSlot2 = cachedLocalPlayer and cachedLocalPlayer:GetEntityForLoadoutSlot(2) or nil
    pLocalViewPos = cachedLocalPlayer and (cachedLocalPlayer:GetAbsOrigin() + cachedLocalPlayer:GetPropVector("localdata", "m_vecViewOffset[0]")) or nil
end

local function UpdatePlayersCache()
    local allPlayers = entities.FindByClass("CTFPlayer")
    for i, player in pairs(allPlayers) do
        if player:GetIndex() ~= cachedLocalPlayer:GetIndex() then
            cachedPlayers[player:GetIndex()] = {
                entity = player,
                isAlive = player:IsAlive(),
                isDormant = player:IsDormant(),
                teamNumber = player:GetTeamNumber(),
                absOrigin = player:GetAbsOrigin(),
                viewOffset = player:GetPropVector("localdata", "m_vecViewOffset[0]"),
                hitboxPos = GetHitboxPos(player, 4),
                viewAngles = player:GetPropVector("tfnonlocaldata", "m_angEyeAngles[0]") -- Store view angles
            }
        end
    end
end

-- Initialize cache
UpdateLocalPlayerCache()
UpdatePlayersCache()

-- Constants
local NUM_DIRECTIONS = 8  -- Example: 8 directions (N, NE, E, SE, S, SW, W, NW)
local MAX_SPEED = 320  -- Maximum speed
local SIMULATION_TICKS = 24  -- Number of ticks for simulation
local positions = {}

local FORWARD_COLLISION_ANGLE = 55
local GROUND_COLLISION_ANGLE_LOW = 45
local GROUND_COLLISION_ANGLE_HIGH = 55

-- Helper function for forward collision
local function handleForwardCollision(vel, wallTrace, vUp)
    local normal = wallTrace.plane
    local angle = math.deg(math.acos(normal:Dot(vUp)))
    if angle > FORWARD_COLLISION_ANGLE then
        local dot = vel:Dot(normal)
        vel = vel - normal * dot
    end
    return wallTrace.endpos.x, wallTrace.endpos.y
end

-- Helper function for ground collision
local function handleGroundCollision(vel, groundTrace, vUp)
    local normal = groundTrace.plane
    local angle = math.deg(math.acos(normal:Dot(vUp)))
    local onGround = false
    if angle < GROUND_COLLISION_ANGLE_LOW then
        onGround = true
    elseif angle < GROUND_COLLISION_ANGLE_HIGH then
        vel.x, vel.y, vel.z = 0, 0, 0
    else
        local dot = vel:Dot(normal)
        vel = vel - normal * dot
        onGround = true
    end
    if onGround then vel.z = 0 end
    return groundTrace.endpos, onGround
end

-- Simulates movement in a specified direction vector for a player over a given number of ticks
local function PredictPlayer(player, simulatedVelocity)
    local tick_interval = globals.TickInterval()
    local gravity = client.GetConVar("sv_gravity")
    local stepSize = player:GetPropFloat("localdata", "m_flStepSize")
    local vUp = Vector3(0, 0, 1)
    local vHitbox = { Vector3(-20, -20, 0), Vector3(20, 20, 80) }
    local vStep = Vector3(0, 0, stepSize / 2)

    positions = {}  -- Store positions for each tick
    local lastP = player:GetAbsOrigin()
    local lastV = simulatedVelocity
    local flags = player:GetPropInt("m_fFlags")
    local lastG = (flags & FL_ONGROUND == 1)

    for i = 1, SIMULATION_TICKS do
        
        local pos = lastP + lastV * tick_interval
        local vel = lastV
        local onGround = lastG

        -- Forward collision
        local wallTrace = engine.TraceHull(lastP + vStep, pos + vStep, vHitbox[1], vHitbox[2], MASK_PLAYERSOLID)
        if wallTrace.fraction < 1 then
            pos.x, pos.y = handleForwardCollision(vel, wallTrace, vUp)
        end

        -- Ground collision
        local downStep = onGround and vStep or Vector3()
        local groundTrace = engine.TraceHull(pos + vStep, pos - downStep, vHitbox[1], vHitbox[2], MASK_PLAYERSOLID)
        if groundTrace.fraction < 1 then
            pos, onGround = handleGroundCollision(vel, groundTrace, vUp)
        else
            onGround = false
        end

        -- Apply gravity if not on ground
        if not onGround then
            vel.z = vel.z - gravity * tick_interval
        end

        lastP, lastV, lastG = pos, vel, onGround
        positions[i] = lastP  -- Store position for this tick
    end

    return positions
end



-- Constants
local BACKSTAB_RANGE = 105  -- Hammer units
local BACKSTAB_ANGLE = 180  -- Degrees in radians for dot product calculation

local BestYawDifference = 0
local BestPosition

local function CanBackstabFromPosition(cmd, viewPos, real, targetPlayerGlobal)
    local weaponReady = cachedLoadoutSlot2 ~= nil
    if not weaponReady then return false end

    if real then
        for _, targetPlayer in pairs(cachedPlayers) do
            if targetPlayer.isAlive and not targetPlayer.isDormant and targetPlayer.teamNumber ~= cachedLocalPlayer:GetTeamNumber() then
                local distance = vector.Distance(viewPos, targetPlayer.hitboxPos)
                if distance < BACKSTAB_RANGE then
                    local ang = PositionAngles(viewPos, targetPlayer.hitboxPos)
                    cmd:SetViewAngles(ang:Unpack())
                    if cachedLoadoutSlot2:GetPropInt("m_bReadyToBackstab") == 257 then
                        return true
                    end
                end
            end
        end
    else
        local targetPlayer = cachedPlayers[targetPlayerGlobal:GetIndex()]
        if targetPlayer and targetPlayer.isAlive and not targetPlayer.isDormant and targetPlayer.teamNumber ~= cachedLocalPlayer:GetTeamNumber() then
            local distance = vector.Distance(viewPos, targetPlayer.hitboxPos)
            if distance < BACKSTAB_RANGE then

                local enemyYaw = calculateYaw(targetPlayer.viewAngles.y, targetPlayer.viewAngles.x)
                local spyYaw = calculateYaw(viewPos.y - targetPlayer.hitboxPos.y, viewPos.x - targetPlayer.hitboxPos.x)

                local yawDifference = math.abs(enemyYaw - spyYaw)

                if yawDifference > BestYawDifference then
                    BestYawDifference = yawDifference
                    BestPosition = viewPos
                end

                return yawDifference > 100
            end
        end
    end

    return false
end




local function GetBestTarget(me)
    local players = entities.FindByClass("CTFPlayer")
    local bestTarget = nil
    local maxDistance = 1200  -- 24 ticks into future at speed of 320 units

    for _, player in pairs(players) do
        if player ~= nil and player:IsAlive() and not player:IsDormant()
        and player ~= me and player:GetTeamNumber() ~= me:GetTeamNumber() then
            local distance = vector.Distance(me:GetAbsOrigin(), player:GetAbsOrigin())

            if distance <= maxDistance then
                if bestTarget == nil or distance < vector.Distance(me:GetAbsOrigin(), bestTarget:GetAbsOrigin()) then
                    bestTarget = player
                end
            end
        end
    end

    return bestTarget
end


local function SimulateWalkingInDirections(player, target, spread)
    local endPositions = {}
    local playerPos = player:GetAbsOrigin()
    local targetPos = target:GetAbsOrigin()

    -- Calculate the central direction towards the target
    local centralDirection = NormalizeVector(targetPos - playerPos)
    local centralAngle = math.deg(math.atan(centralDirection.y, centralDirection.x))

    -- Check left and right offsets first
    local specialOffsets = {-90, 90}  -- -90 and 90 degrees
    for _, offsetAngle in ipairs(specialOffsets) do
        local angle = (centralAngle + offsetAngle) % 360
        local radianAngle = math.rad(angle)

        local directionVector = NormalizeVector(Vector3(math.cos(radianAngle), math.sin(radianAngle), 0))
        local simulatedVelocity = directionVector * MAX_SPEED

        endPositions[angle] = PredictPlayer(player, simulatedVelocity)
    end

    -- Check remaining angles within spread
    local halfSpread = spread / 2
    local remainingAngles = NUM_DIRECTIONS - #specialOffsets  -- Adjust for special angles already checked
    for i = 1, remainingAngles do
        local offsetAngle = ((i - 1) / (remainingAngles - 1)) * spread - halfSpread
        -- Skip special offsets
        if offsetAngle ~= -90 and offsetAngle ~= 90 then
            local angle = (centralAngle + offsetAngle) % 360
            local radianAngle = math.rad(angle)

            local directionVector = NormalizeVector(Vector3(math.cos(radianAngle), math.sin(radianAngle), 0))
            local simulatedVelocity = directionVector * MAX_SPEED

            endPositions[angle] = PredictPlayer(player, simulatedVelocity)
        end
    end

    return endPositions
end


-- Computes the move vector between two points
---@param userCmd UserCmd
---@param a Vector3
---@param b Vector3
---@return Vector3
local function ComputeMove(userCmd, a, b)
    local diff = (b - a)
    if diff:Length() == 0 then return Vector3(0, 0, 0) end

    local x = diff.x
    local y = diff.y
    local vSilent = Vector3(x, y, 0)

    local ang = vSilent:Angles()
    local cPitch, cYaw, cRoll = userCmd:GetViewAngles()
    local yaw = math.rad(ang.y - cYaw)
    local pitch = math.rad(ang.x - cPitch)
    local move = Vector3(math.cos(yaw) * 320, -math.sin(yaw) * 320, -math.cos(pitch) * 320)

    return move
end

-- Global variable to store the move direction
local movedir = Vector3(0, 0, 0)

-- Walks to the destination and sets the global move direction
---@param userCmd UserCmd
---@param localPlayer Entity
---@param destination Vector3
local function WalkTo(userCmd, localPlayer, destination)
    local localPos = localPlayer:GetAbsOrigin()
    local result = ComputeMove(userCmd, localPos, destination)

    userCmd:SetForwardMove(result.x)
    userCmd:SetSideMove(result.y)

    -- Set the global move direction
    movedir = Vector3(result.x, result.y, 0)
end


local allWarps = {}
local endwarps = {}

local function OnCreateMove(cmd)
    UpdateLocalPlayerCache()  -- Update local player data every tick
    UpdatePlayersCache()  -- Update player data every tick
    BestYawDifference = 0
    pLocal = entities.GetLocalPlayer()
    if not pLocal then return end

    allWarps = {}
    endwarps = {}
    BackstabOportunity = Vector3(0, 0, 0)

    -- Store all potential positions in allWarps
    local target = GetBestTarget(cachedLocalPlayer)
    if not target then return end

    local currentWarps = SimulateWalkingInDirections(pLocal, target, 80)

    table.insert(allWarps, currentWarps)

    -- Storing 24th tick positions in endwarps
    for angle, positions1 in pairs(currentWarps) do
        if positions1[24] then
            endwarps[angle] = positions1[24]
        end
    end

        -- check if any of warp positions can stab anyone
        local lastDistance
        for angle, point in pairs(endwarps) do
            if CanBackstabFromPosition(cmd, point + Vector3(0, 0, 75), false, target) then
                BackstabOportunity = BestPosition - Vector3(0,0,75) --the best point
                WalkTo(cmd, pLocal,  BackstabOportunity)
            end
        end

    if CanBackstabFromPosition(cmd, pLocalViewPos, true, target) then
        cmd:SetButtons(cmd.buttons | IN_ATTACK)  -- Perform backstab
    end
end



local consolas = draw.CreateFont("Consolas", 17, 500)
local current_fps = 0
local function doDraw()
    draw.SetFont(consolas)
    draw.Color(255, 255, 255, 255)

    -- update fps every 100 frames
    if globals.FrameCount() % 100 == 0 then
      current_fps = math.floor(1 / globals.FrameTime())
    end
  
    draw.Text(5, 5, "[lmaobox | fps: " .. current_fps .. "]")

    -- Drawing all simulated positions in green
    for _, warps in ipairs(allWarps) do
        for angle, positions in pairs(warps) do
            for _, point in ipairs(positions) do
                local screenPos = client.WorldToScreen(Vector3(point.x, point.y, point.z))
                if screenPos then
                    draw.Color(0, 255, 0, 255)
                    draw.FilledRect(screenPos[1] - 2, screenPos[2] - 2, screenPos[1] + 2, screenPos[2] + 2)
                end
            end
        end
    end

    -- Drawing the 24th tick positions in red
    for angle, point in pairs(endwarps) do
        local screenPos = client.WorldToScreen(Vector3(point.x, point.y, point.z))
        if screenPos then
            draw.Color(255, 0, 0, 255)
            draw.FilledRect(screenPos[1] - 5, screenPos[2] - 5, screenPos[1] + 5, screenPos[2] + 5)
        end
    end

    -- Drawing backstab Position
    if BackstabOportunity then
        local screenPos = client.WorldToScreen(Vector3(BackstabOportunity.x, BackstabOportunity.y, BackstabOportunity.z))
        if screenPos then
            draw.Color(255, 255, 255, 255)
            draw.FilledRect(screenPos[1] - 5, screenPos[2] - 5, screenPos[1] + 5, screenPos[2] + 5)
        end
    end

    local tartpoint = BestPosition
    if not startPoint or not movedir then return end

    local endPoint = startPoint + movedir
    local screenStart = client.WorldToScreen(startPoint)
    local screenEnd = client.WorldToScreen(endPoint)

    if screenStart and screenEnd then
        draw.Color(255, 0, 0, 255)  -- Red color for line
        draw.Line(screenStart[1], screenStart[2], screenEnd[1], screenEnd[2])
    end
end

callbacks.Unregister("CreateMove", "OnCreateMove123313")
callbacks.Register("CreateMove", "OnCreateMove12313", OnCreateMove)

callbacks.Unregister("Draw", "AMsadaAT_Draw")                        -- Unregister the "Draw" callback
callbacks.Register("Draw", "AMsadaAT_Draw", doDraw)                               -- Register the "Draw" callback