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
local MAX_SPEED = 320  -- Maximum speed
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

-- Simulates movement for a player over a given number of ticks
local function SimulatePlayer(me, ticks, strafeAngle)
    -- Update the simulation cache
    UpdateSimulationCache()

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
    end

    return {pos = Endpos, OnGround = lastG}
end

---@param me WPlayer
local function CalculateHitboxOffsets(me)
    local absOrigin = me:GetAbsOrigin()
    local box1 = me:HitboxSurroundingBox()
    local min = box1[1]
    local max = box1[2]

    local minOffset = min - absOrigin
    local maxOffset = max - absOrigin

    return {minOffset, maxOffset}
end

local box = {Vector3(), Vector3()}
local PredPos = Vector3(0, 0, 0)
local LastGround = false

local function OnCreateMove(cmd)
        pLocal = entities.GetLocalPlayer()
    if not pLocal or not pLocal:IsAlive() then return end
        local pFlags = pLocal:GetPropInt("m_fFlags")

        local velocity = pLocal:EstimateAbsVelocity()
    --if pLocal:EstimateAbsVelocity().z > -649 then return end
        vHitbox = CalculateHitboxOffsets(pLocal)
        local strafeAngle = CalcStrafe(pLocal)
         -- Predict the player'
        local predData = SimulatePlayer(pLocal, 2, strafeAngle)
    if not predData then return nil end
        PredPos = predData.pos
        box = {PredPos + vHitbox[1] , PredPos + vHitbox[2]}

        if (pFlags & FL_ONGROUND) == 1 then
            if LastGround then
                LastGround = false
                cmd:SetButtons(cmd.buttons | (IN_JUMP))
            end
            return
        end --disable when airborne

        if predData.OnGround then
            LastGround = true
            cmd:SetButtons(cmd.buttons & (~IN_DUCK))
        else
            cmd.buttons = cmd.buttons | IN_DUCK
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

callbacks.Unregister("Draw", "accuratemoveD.Draw")
callbacks.Register("Draw", "accuratemoveD", OnDraw)




