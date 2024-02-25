local pLocal = entities.GetLocalPlayer()
---@type boolean, lnxLib
local libLoaded, lnxLib = pcall(require, "lnxLib")
assert(libLoaded, "lnxLib not found, please install it!")

local Math, Conversion = lnxLib.Utils.Math, lnxLib.Utils.Conversion
local WPlayer, WWeapon = lnxLib.TF2.WPlayer, lnxLib.TF2.WWeapon
local Helpers = lnxLib.TF2.Helpers
local Prediction = lnxLib.TF2.Prediction
local Fonts = lnxLib.UI.Fonts

local latency = 0
local lerp = 0
local lastAngle = nil ---@type number
local vHitbox = { Vector3(-24, -24, 0), Vector3(24, 24, 82) }

---@param me WPlayer
local function CalcStrafe(me)
    -- Reset data for dormant or dead players and teammates
        local angle = me:EstimateAbsVelocity():Angles() -- get angle of velocity vector

        -- Calculate the delta angle
        local delta = 0
        if lastAngle then
            delta = angle.y - lastAngle
            delta = Math.NormalizeAngle(delta)
        end

        -- Update the last angle
        lastAngle = angle.y

        -- Calculate the center direction based on recent strafe angles
        local center = angle.y  -- Use the most recent angle as the center
        return delta
end



-- Constants
local SIMULATION_TICKS = 23  -- Number of ticks for simulation
local positions = {}

local FORWARD_COLLISION_ANGLE = 55
local GROUND_COLLISION_ANGLE_LOW = 45
local GROUND_COLLISION_ANGLE_HIGH = 55

-- Helper function for forward collision
local function handleForwardCollision(vel, wallTrace)
    local normal = wallTrace.plane
    local angle = math.deg(math.acos(normal:Dot(Vector3(0, 0, 1))))

     -- Adjust velocity if angle is greater than forward collision angle
    if angle > FORWARD_COLLISION_ANGLE then
        -- The wall is steep, adjust velocity to prevent moving into the wall
        local dot = vel:Dot(normal)
        vel = vel - normal * dot
    end

    return wallTrace.endpos.x, wallTrace.endpos.y, alreadyWithinStep
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

-- Cache structure
local simulationCache = {
    tickInterval = globals.TickInterval(),
    gravity = client.GetConVar("sv_gravity"),
    stepSize = pLocal and pLocal:GetPropFloat("localdata", "m_flStepSize") or 0,
    flags = pLocal and pLocal:GetPropInt("m_fFlags") or 0
}

-- Function to update cache (call this when game environment changes)
local function UpdateSimulationCache()
    simulationCache.tickInterval = globals.TickInterval()
    simulationCache.gravity = client.GetConVar("sv_gravity")
    simulationCache.stepSize = pLocal and pLocal:GetPropFloat("localdata", "m_flStepSize") or 0
    simulationCache.flags = pLocal and pLocal:GetPropInt("m_fFlags") or 0
end

local PredictionTable = {}

-- Simulates movement for a player over a given number of ticks
local function SimulatePlayer(me, ticks, strafeAngle)
    -- Update the simulation cache
    UpdateSimulationCache()
    PredictionTable = {}

    -- Get the player's velocity
    local lastV = me:EstimateAbsVelocity()

    -- Calculate the tick interval based on the server's settings
    local tick_interval = globals.TickInterval()

    local gravity = simulationCache.gravity * tick_interval
    local stepSize = simulationCache.stepSize
    local vUp = Vector3(0, 0, 1)
    local vStep = Vector3(0, 0, stepSize / 2)

    local lastP = me:GetAbsOrigin()
    local flags = simulationCache.flags
    local lastG = (flags & 1 == 1)
    local Endpos = Vector3(0, 0, 0)

    for i = 1, ticks do
        local pos = lastP + lastV * tick_interval
        local vel = lastV
        local onGround = lastG

        -- Apply strafeAngle
        if strafeAngle then
            local ang = vel:Angles()
            ang.y = ang.y + strafeAngle
            vel = ang:Forward() * vel:Length()
        end

        -- Forward collision
        local wallTrace = engine.TraceHull(lastP + vStep, pos + vStep, vHitbox[1], vHitbox[2], MASK_PLAYERSOLID_BRUSHONLY)
        if wallTrace.fraction < 1 then
            pos.x, pos.y = handleForwardCollision(vel, wallTrace)
        end

        -- Ground collision
        local downStep = onGround and vStep or Vector3()
        local groundTrace = engine.TraceHull(pos + vStep, pos - downStep, vHitbox[1], vHitbox[2], MASK_PLAYERSOLID_BRUSHONLY)
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
        Endpos = lastP
        PredictionTable = {pos = pos, vel = vel, onGround = onGround}
    end

    return {pos = Endpos, OnGround = lastG}
end

-- Constants for minimum and maximum speed
local MIN_SPEED = 10  -- Minimum speed to avoid jittery movements
local MAX_SPEED = 650 -- Maximum speed the player can move

local MoveDir = Vector3(0,0,0) -- Variable to store the movement direction

local function NormalizeVector(vector)
    local length = math.sqrt(vector.x * vector.x + vector.y * vector.y + vector.z * vector.z)
    if length == 0 then
        return Vector3(0, 0, 0)
    else
        return Vector3(vector.x / length, vector.y / length, vector.z / length)
    end
end

-- Function to compute the move direction
local function ComputeMove(pCmd, a, b)
    local diff = (b - a)
    if diff:Length() == 0 then return Vector3(0, 0, 0) end

    local x = diff.x
    local y = diff.y
    local vSilent = Vector3(x, y, 0)

    local ang = vSilent:Angles()
    local cPitch, cYaw, cRoll = pCmd:GetViewAngles()
    local yaw = math.rad(ang.y - cYaw)
    local pitch = math.rad(ang.x - cPitch)
    local move = Vector3(math.cos(yaw) * MAX_SPEED, -math.sin(yaw) * MAX_SPEED, 0)

    return move
end

-- Function to make the player walk to a destination smoothly
local function WalkTo(pCmd, pLocal, pDestination)
    local localPos = pLocal:GetAbsOrigin()
    local distVector = pDestination - localPos
    local dist = distVector:Length()

    -- Determine the speed based on the distance
    local speed = math.max(MIN_SPEED, math.min(MAX_SPEED, dist))

    -- If distance is greater than 1, proceed with walking
    if dist > 1 then
        local result = ComputeMove(pCmd, localPos, pDestination)

        -- Scale down the movements based on the calculated speed
        local scaleFactor = speed / MAX_SPEED
        pCmd:SetForwardMove(result.x * scaleFactor)
        pCmd:SetSideMove(result.y * scaleFactor)
    else
        pCmd:SetForwardMove(0)
        pCmd:SetSideMove(0)
    end
end

local function GetMoveDir()
    local moveSpeed = 450 -- Change this to your preferred speed
    -- Handle side movement keys
    if input.IsButtonDown(KEY_A) then
        MoveDir.x = -moveSpeed
    end

    if input.IsButtonDown(KEY_D) then
        MoveDir.x = moveSpeed
    end

    -- Handle forward movement keys
    if input.IsButtonDown(KEY_W) then
        MoveDir.y = moveSpeed
    end

    if input.IsButtonDown(KEY_S) then
        MoveDir.y = -moveSpeed
    end
end

local function FastStop(cmd, OnGround, velocity)
    if not OnGround then return end -- If the player is not on ground, do nothing

    -- If no keys are held, stop movement immediately by moving in the opposite direction of current velocity
    if MoveDir:Length() < 10 and velocity:Length() > 10 then
        local oppositePoint = pLocal:GetAbsOrigin() - velocity
        WalkTo(cmd, pLocal, oppositePoint)
        return
    end
end

local function FastAccel(cmd, OnGround, velocity)
    if not OnGround then return end -- If the player is not on ground, do nothing

    -- If no keys are held, stop movement immediately by moving in the opposite direction of current velocity
    if MoveDir:Length() > 0 then
        local normalizedMoveDir = NormalizeVector(MoveDir) * 450
        cmd.forwardmove = normalizedMoveDir.y
        cmd.sidemove = normalizedMoveDir.x
        return
    end
end

local function isOnGround(player)
    local pFlags = player:GetPropInt("m_fFlags")
    return (pFlags & FL_ONGROUND) == 1
end

local box = {Vector3(), Vector3()}
local PredPos = Vector3(0, 0, 0)
local vHitbox1 = { Vector3(-24, -24, 0), Vector3(24, 24, 82) }
local tickAccel = 800/66.67
local crouchOffset = 45

local function OnCreateMove(cmd)
    pLocal = entities.GetLocalPlayer()
    if not pLocal or not pLocal:IsAlive() then return end

    local onGround = isOnGround(pLocal)
    local m_vecViewOffsetZ = math.floor(pLocal:GetPropVector("m_vecViewOffset[0]").z)

    local vel = pLocal:EstimateAbsVelocity()
    MoveDir = Vector3(0,0,0)
    GetMoveDir()

    FastStop(cmd, OnGround, vel)
    FastAccel(cmd, OnGround, vel)

    if onGround then 
        if input.IsButtonDown(KEY_SPACE) then
            if m_vecViewOffsetZ <= 67 then  -- Fully crouched
                cmd:SetButtons(cmd.buttons & (~IN_DUCK))  -- Uncrouch
                cmd:SetButtons(cmd.buttons | IN_JUMP)     -- Jump
            else
                cmd:SetButtons(cmd.buttons & (~IN_JUMP))
                cmd:SetButtons(cmd.buttons | IN_DUCK)
            end
        end
        return
    end

    -- The rest of your logic when not on ground
    if vel.z < 0 then return end

    local strafeAngle = CalcStrafe(pLocal)

    -- Predict the player's position
    local predData = SimulatePlayer(pLocal, 1, strafeAngle)
    if not predData then return end

    PredPos = predData.pos

    -- Jumpbug logic
    if not predData.OnGround and vel.z < 0 then
        cmd:SetButtons(cmd.buttons & (~IN_DUCK))
        cmd:SetButtons(cmd.buttons | IN_JUMP)
    else
        cmd:SetButtons(cmd.buttons | IN_DUCK)
    end
end



local function OnDraw()
    -- Inside your OnDraw function
    pLocal = entities.GetLocalPlayer()
    if not pLocal then return end
    local pLocalPos = pLocal:GetAbsOrigin()
    draw.Color(255, 0, 0, 255)
    local screenPos = client.WorldToScreen(PredPos)
            if screenPos then
                draw.Color(255, 0, 0, 255)  -- Red color for backstab position
                draw.FilledRect(screenPos[1] - 5, screenPos[2] - 5, screenPos[1] + 5, screenPos[2] + 5)
            end

                -- Calculate min and max points
                local minPoint = box[1]
                local maxPoint = box[2]

                -- Calculate vertices of the AABB
                -- Assuming minPoint and maxPoint are the minimum and maximum points of the AABB:
                local vertices = {
                    Vector3(minPoint.x, minPoint.y, minPoint.z),  -- Bottom-back-left
                    Vector3(minPoint.x, maxPoint.y, minPoint.z),  -- Bottom-front-left
                    Vector3(maxPoint.x, maxPoint.y, minPoint.z),  -- Bottom-front-right
                    Vector3(maxPoint.x, minPoint.y, minPoint.z),  -- Bottom-back-right
                    Vector3(minPoint.x, minPoint.y, maxPoint.z),  -- Top-back-left
                    Vector3(minPoint.x, maxPoint.y, maxPoint.z),  -- Top-front-left
                    Vector3(maxPoint.x, maxPoint.y, maxPoint.z),  -- Top-front-right
                    Vector3(maxPoint.x, minPoint.y, maxPoint.z)   -- Top-back-right
                }



                --[[local vertices = {
                    client.WorldToScreen(vPlayerFuture + Vector3(hitbox_Width, hitbox_Width, 0)),
                    client.WorldToScreen(vPlayerFuture + Vector3(-hitbox_Width, hitbox_Width, 0)),
                    client.WorldToScreen(vPlayerFuture + Vector3(-hitbox_Width, -hitbox_Width, 0)),
                    client.WorldToScreen(vPlayerFuture + Vector3(hitbox_Width, -hitbox_Width, 0)),
                    client.WorldToScreen(vPlayerFuture + Vector3(hitbox_Width, hitbox_Width, hitbox_Height)),
                    client.WorldToScreen(vPlayerFuture + Vector3(-hitbox_Width, hitbox_Width, hitbox_Height)),
                    client.WorldToScreen(vPlayerFuture + Vector3(-hitbox_Width, -hitbox_Width, hitbox_Height)),
                    client.WorldToScreen(vPlayerFuture + Vector3(hitbox_Width, -hitbox_Width, hitbox_Height))
                }]]

                -- Convert 3D coordinates to 2D screen coordinates
                for i, vertex in ipairs(vertices) do
                    vertices[i] = client.WorldToScreen(vertex)
                end

                -- Draw lines between vertices to visualize the box
                if vertices[1] and vertices[2] and vertices[3] and vertices[4] and vertices[5] and vertices[6] and vertices[7] and vertices[8] then
                    -- Draw front face
                    draw.Line(vertices[1][1], vertices[1][2], vertices[2][1], vertices[2][2])
                    draw.Line(vertices[2][1], vertices[2][2], vertices[3][1], vertices[3][2])
                    draw.Line(vertices[3][1], vertices[3][2], vertices[4][1], vertices[4][2])
                    draw.Line(vertices[4][1], vertices[4][2], vertices[1][1], vertices[1][2])

                    -- Draw back face
                    draw.Line(vertices[5][1], vertices[5][2], vertices[6][1], vertices[6][2])
                    draw.Line(vertices[6][1], vertices[6][2], vertices[7][1], vertices[7][2])
                    draw.Line(vertices[7][1], vertices[7][2], vertices[8][1], vertices[8][2])
                    draw.Line(vertices[8][1], vertices[8][2], vertices[5][1], vertices[5][2])

                    -- Draw connecting lines
                    draw.Line(vertices[1][1], vertices[1][2], vertices[5][1], vertices[5][2])
                    draw.Line(vertices[2][1], vertices[2][2], vertices[6][1], vertices[6][2])
                    draw.Line(vertices[3][1], vertices[3][2], vertices[7][1], vertices[7][2])
                    draw.Line(vertices[4][1], vertices[4][2], vertices[8][1], vertices[8][2])
                end
end

callbacks.Unregister("CreateMove", "jumpbughanddd")
callbacks.Register("CreateMove", "jumpbughanddd", OnCreateMove)

--[[callbacks.Unregister("Draw", "accuratemoveD.Draw")
callbacks.Register("Draw", "accuratemoveD", OnDraw)]]




