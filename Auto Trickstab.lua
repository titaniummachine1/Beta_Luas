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

local cachedLocalPlayer
local cachedPlayers = {}
local cachedLoadoutSlot2
local pLocalViewPos
local tickCount = 0

-- Function to update the cache for the local player and loadout slot
local function UpdateLocalPlayerCache()
    cachedLocalPlayer = entities.GetLocalPlayer()
    cachedLoadoutSlot2 = cachedLocalPlayer and cachedLocalPlayer:GetEntityForLoadoutSlot(2) or nil
    pLocalViewPos = cachedLocalPlayer and (cachedLocalPlayer:GetAbsOrigin() + cachedLocalPlayer:GetPropVector("localdata", "m_vecViewOffset[0]")) or nil
end

-- Function to update the cache for all players
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
                hitboxPos = GetHitboxPos(player, 4)
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

local function CanBackstabFromPosition(cmd, viewPos, real)
    local weaponReady = cachedLoadoutSlot2 ~= nil
    if not weaponReady then return false end

    for _, targetPlayer in pairs(cachedPlayers) do
        if targetPlayer.isAlive and not targetPlayer.isDormant and targetPlayer.teamNumber ~= cachedLocalPlayer:GetTeamNumber() then
            local distance = math.abs(viewPos.x - targetPlayer.hitboxPos.x) + 
                             math.abs(viewPos.y - targetPlayer.hitboxPos.y) + 
                             math.abs(viewPos.z - targetPlayer.hitboxPos.z)
            if distance < BACKSTAB_RANGE then
                local ang = PositionAngles(viewPos, targetPlayer.hitboxPos)
                cmd:SetViewAngles(ang:Unpack())

                if real then
                    return cachedLoadoutSlot2:GetPropInt("m_bReadyToBackstab") == 257
                else
                    local enemy_back_direction = -NormalizeVector(targetPlayer.viewOffset)
                    local spy_to_enemy_direction = NormalizeVector(targetPlayer.hitboxPos - viewPos)
                    local dot_product = spy_to_enemy_direction.x * enemy_back_direction.x +
                                        spy_to_enemy_direction.y * enemy_back_direction.y +
                                        spy_to_enemy_direction.z * enemy_back_direction.z
                    local angle = math.acos(dot_product) * (180 / math.pi)
                    print(angle)
                    return angle <= BACKSTAB_ANGLE / 2
                end
            end
        end
    end

    return false
end

local function GetBestTarget(me)
    local players = entities.FindByClass("CTFPlayer")
    local bestTarget = nil
    local maxDistance = 160  -- 24 ticks into future at speed of 320 units

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


local function SimulateWalkingInDirections(player, target)
    local endPositions = {}
    local playerPos = player:GetAbsOrigin()
    local targetPos = target:GetAbsOrigin()

    -- Calculate the direction towards the target
    local targetDirection = NormalizeVector(targetPos - playerPos)

    -- Calculate the starting angle for the target direction
    local startAngle = math.deg(math.atan(targetDirection.y, targetDirection.x))

    for direction = 1, NUM_DIRECTIONS do
        local angle = (startAngle + (direction - 1) * (360 / NUM_DIRECTIONS)) % 360
        local radianAngle = math.rad(angle)

        local directionVector = NormalizeVector(Vector3(math.cos(radianAngle), math.sin(radianAngle), 0))
        local simulatedVelocity = directionVector * MAX_SPEED

        -- Predict player position based on the simulated direction
        endPositions[angle] = PredictPlayer(player, simulatedVelocity)
    end

    return endPositions
end


local allWarps = {}
local endwarps = {}

local function OnCreateMove(cmd)
    UpdateLocalPlayerCache()  -- Update local player data every tick
    UpdatePlayersCache()  -- Update player data every tick

    allWarps = {}
    endwarps = {}
    BackstabOportunity = Vector3(0, 0, 0)

    -- Store all potential positions in allWarps
    local target = GetBestTarget(cachedLocalPlayer)
    if not target then return end

    local currentWarps = SimulateWalkingInDirections(cachedLocalPlayer, target)

    table.insert(allWarps, currentWarps)

    -- Storing 24th tick positions in endwarps
    for angle, positions in pairs(currentWarps) do
        if positions[24] then
            endwarps[angle] = positions[24]
        end
    end

        -- check if any of warp positions can stab anyone
        for angle, point in pairs(endwarps) do
            if CanBackstabFromPosition(cmd, point + Vector3(0, 0, 75), false) then
                BackstabOportunity = point
            end
        end
    if CanBackstabFromPosition(cmd, pLocalViewPos, true) then
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
            draw.Color(255, 255, 0, 255)
            draw.FilledRect(screenPos[1] - 5, screenPos[2] - 5, screenPos[1] + 5, screenPos[2] + 5)
        end
    end

end

callbacks.Unregister("CreateMove", "OnCreateMove123313")
callbacks.Register("CreateMove", "OnCreateMove12313", OnCreateMove)

callbacks.Unregister("Draw", "AMsadaAT_Draw")                        -- Unregister the "Draw" callback
callbacks.Register("Draw", "AMsadaAT_Draw", doDraw)                               -- Register the "Draw" callback