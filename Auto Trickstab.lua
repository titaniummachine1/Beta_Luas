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

local function CanBackstabFromPosition(cmd, viewPos)
    local weaponReady = cachedLoadoutSlot2 ~= nil
    if not weaponReady then return false end

    for _, targetPlayer in pairs(cachedPlayers) do
        if targetPlayer.isAlive and not targetPlayer.isDormant and targetPlayer.teamNumber ~= cachedLocalPlayer:GetTeamNumber() then
            local distance = math.abs(viewPos.x - targetPlayer.hitboxPos.x) + math.abs(viewPos.y - targetPlayer.hitboxPos.y) + math.abs(viewPos.z - targetPlayer.hitboxPos.z)
            if distance < 105 then
                local ang = PositionAngles(viewPos, targetPlayer.hitboxPos)
                cmd:SetViewAngles(ang:Unpack())

                if cachedLoadoutSlot2:GetPropInt("m_bReadyToBackstab") == 257 then
                    return true
                end
            end
        end
    end

    return false
end



-- Constants
local NUM_DIRECTIONS = 8  -- Example: 8 directions (N, NE, E, SE, S, SW, W, NW)
local MAX_SPEED = 320  -- Maximum speed
local SIMULATION_TICKS = 24  -- Number of ticks for simulation

local FORWARD_COLLISION_ANGLE = 55
local GROUND_COLLISION_ANGLE_LOW = 45
local GROUND_COLLISION_ANGLE_HIGH = 55

-- Normalizes a vector to a unit vector
local function NormalizeVector(vec)
    local length = math.sqrt(vec.x^2 + vec.y^2 + vec.z^2)
    return Vector3(vec.x / length, vec.y / length, vec.z / length)
end

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
    end

    return lastP
end

-- Simulate walking in multiple directions around a player
local function SimulateWalkingInDirections(player)
    local originalPosition = player:GetAbsOrigin()
    local endPositions = {}

    for direction = 1, NUM_DIRECTIONS do
        local angle = (direction - 1) * (360 / NUM_DIRECTIONS)
        local radianAngle = math.rad(angle)
        local directionVector = NormalizeVector(Vector3(math.cos(radianAngle), math.sin(radianAngle), 0))
        local simulatedVelocity = directionVector * MAX_SPEED

        -- Use the PredictPlayer function to simulate movement in this direction
        local endPosition = PredictPlayer(player, simulatedVelocity)
        endPositions[angle] = endPosition
    end

    return endPositions
end

local warps = {}

local function OnCreateMove(cmd)
    UpdateLocalPlayerCache()  -- Update local player data every tick
    UpdatePlayersCache()  -- Update player data every tick


    warps = SimulateWalkingInDirections(cachedLocalPlayer)
    --for i = 1, 1000 do --crash test
        if CanBackstabFromPosition(cmd, pLocalViewPos) then
            cmd:SetButtons(cmd.buttons | IN_ATTACK)  -- Perform backstab
        end
    --end
end

local consolas = draw.CreateFont("Consolas", 17, 500)
local current_fps = 0
local function doDraw()
    draw.SetFont(consolas)
    draw.Color(255, 255, 255, 255)
    local plocal = entities.GetLocalPlayer()
    local speed = plocal:EstimateAbsVelocity():Length()
    print(speed)
    -- update fps every 100 frames
    if globals.FrameCount() % 100 == 0 then
      current_fps = math.floor(1 / globals.FrameTime())
    end
  
    draw.Text(5, 5, "[lmaobox | fps: " .. current_fps .. "]")

    -- Drawing the threat points on screen
    for i, point in pairs(warps) do
        local screenPos = client.WorldToScreen(Vector3(point.x, point.y, point.z))
        if screenPos then
            draw.Color(0, 255, 0, 255)  -- Green color for points
            local x, y = screenPos[1], screenPos[2]
            draw.FilledRect(x - 2, y - 2, x + 2, y + 2)  -- Draw a small square centered at (x, y)
        end
    end
end

callbacks.Unregister("CreateMove", "OnCreateMove123313")
callbacks.Register("CreateMove", "OnCreateMove12313", OnCreateMove)

callbacks.Unregister("Draw", "AMsadaAT_Draw")                        -- Unregister the "Draw" callback
callbacks.Register("Draw", "AMsadaAT_Draw", doDraw)                               -- Register the "Draw" callback


