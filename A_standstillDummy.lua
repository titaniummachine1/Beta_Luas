--[[
    placeHolder Standstill dummy lua
    keeps standign in same place after loading lua
    Author: titaniummachine1 (github.com/titaniummachine1)
]]

local MaxInputStrength = 450
local TICK_RATE = 66

local function Normalize(vec)
    local length = math.sqrt(vec.x * vec.x + vec.y * vec.y + vec.z * vec.z)
    return Vector3(vec.x / length, vec.y / length, vec.z / length)
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
    local move = Vector3(math.cos(yaw), -math.sin(yaw), -math.cos(pitch))

    return move
end

-- Function to scale a vector by a given factor
function Scale(vector, factor)
    return {x = vector.x * factor, y = vector.y * factor}
end

function WalkTo(pCmd, pLocal, pDestination)
    local StartPos = pLocal:GetAbsOrigin()
    local distance = (pDestination - StartPos):Length()
    local velocity = pLocal:EstimateAbsVelocity():Length()
    -- Calculate distance that would be covered in one tick at the current speed
    local SlowDownDistance = math.max(10, math.min(velocity / TICK_RATE, MaxInputStrength))
    local MaxSpeed = pLocal:GetPropFloat("m_flMaxspeed")  -- Max speed for the class
    local Friction = pLocal:GetPropFloat("m_flFriction")  -- Friction for the class
    local ScaleFactor = MaxSpeed / MaxInputStrength

    -- Apply the movement commands
    if distance < SlowDownDistance then
        -- Calculate the needed speed adjustment
        local adjustedSpeed
        if distance < SlowDownDistance then
            -- Decelerate if within stopping distance
            adjustedSpeed = math.max(velocity - Friction, 0)
        else
            -- Accelerate if not within stopping distance and below max speed
            adjustedSpeed = math.min(velocity + Friction, MaxSpeed)
        end

        -- Adjust speed to not overshoot the target, convert to input strength, then scale
        adjustedSpeed = math.min(adjustedSpeed, distance)
        local inputStrength = adjustedSpeed / ScaleFactor

        -- Scale the normalized result by the adjusted input strength
        -- Compute the movement input needed to go towards the target
        local Result = ComputeMove(pCmd, StartPos, pDestination)

        local scaledResult = Vector3()
        scaledResult.x = Result.x * inputStrength
        scaledResult.y = Result.y * inputStrength

        pCmd:SetForwardMove(scaledResult.x)
        pCmd:SetSideMove(scaledResult.y)
    else
        local Result = ComputeMove(pCmd, StartPos, pDestination)

        pCmd:SetForwardMove(Result.x * MaxInputStrength)
        pCmd:SetSideMove(Result.y * MaxInputStrength)
    end
end

local returnVec = entities.GetLocalPlayer():GetAbsOrigin()
local pLocalPos = Vector3()
local PosPlaced = true

local function OnCreateMove(Cmd)
    local pLocal = entities.GetLocalPlayer()
    if not pLocal and pLocal:IsAlive() then return end
    pLocalPos = pLocal:GetAbsOrigin()

    if Cmd:GetForwardMove() ~= 0 or Cmd:GetSideMove() ~= 0 then return end --movement bypass

    if input.IsButtonDown(KEY_LSHIFT) then
        returnVec = entities.GetLocalPlayer():GetAbsOrigin()
        PosPlaced = false
    else
        PosPlaced = true
    end

    if PosPlaced then
        WalkTo(Cmd, pLocal, returnVec)
    end
end

local function Draw3DBox(size, pos)
    local halfSize = size / 2
    if not corners then
        corners1 = {
            Vector3(-halfSize, -halfSize, -halfSize),
            Vector3(halfSize, -halfSize, -halfSize),
            Vector3(halfSize, halfSize, -halfSize),
            Vector3(-halfSize, halfSize, -halfSize),
            Vector3(-halfSize, -halfSize, halfSize),
            Vector3(halfSize, -halfSize, halfSize),
            Vector3(halfSize, halfSize, halfSize),
            Vector3(-halfSize, halfSize, halfSize)
        }
    end

    local linesToDraw = {
        {1, 2}, {2, 3}, {3, 4}, {4, 1},
        {5, 6}, {6, 7}, {7, 8}, {8, 5},
        {1, 5}, {2, 6}, {3, 7}, {4, 8}
    }

    local screenPositions = {}
    for _, cornerPos in ipairs(corners1) do
        local worldPos = pos + cornerPos
        local screenPos = client.WorldToScreen(worldPos)
        if screenPos then
            table.insert(screenPositions, { x = screenPos[1], y = screenPos[2] })
        end
    end

    for _, line in ipairs(linesToDraw) do
        local p1, p2 = screenPositions[line[1]], screenPositions[line[2]]
        if p1 and p2 then
            draw.Line(p1.x, p1.y, p2.x, p2.y)
        end
    end
end

local function ArrowLine(start_pos, end_pos, arrowhead_length, arrowhead_width, invert)
    if not (start_pos and end_pos) then return end

    -- If invert is true, swap start_pos and end_pos
    if invert then
        start_pos, end_pos = end_pos, start_pos
    end

    -- Calculate direction from start to end
    local direction = end_pos - start_pos
    local direction_length = direction:Length()
    if direction_length == 0 then return end

    -- Normalize the direction vector
    local normalized_direction = Normalize(direction)

    -- Calculate the arrow base position by moving back from end_pos in the direction of start_pos
    local arrow_base = end_pos - normalized_direction * arrowhead_length

    -- Calculate the perpendicular vector for the arrow width
    local perpendicular = Vector3(-normalized_direction.y, normalized_direction.x, 0) * (arrowhead_width / 2)

    -- Convert world positions to screen positions
    local w2s_start, w2s_end = client.WorldToScreen(start_pos), client.WorldToScreen(end_pos)
    local w2s_arrow_base = client.WorldToScreen(arrow_base)
    local w2s_perp1 = client.WorldToScreen(arrow_base + perpendicular)
    local w2s_perp2 = client.WorldToScreen(arrow_base - perpendicular)

    if not (w2s_start and w2s_end and w2s_arrow_base and w2s_perp1 and w2s_perp2) then return end

    -- Draw the line from start to the base of the arrow (not all the way to the end)
    draw.Line(w2s_start[1], w2s_start[2], w2s_arrow_base[1], w2s_arrow_base[2])

    -- Draw the sides of the arrowhead
    draw.Line(w2s_end[1], w2s_end[2], w2s_perp1[1], w2s_perp1[2])
    draw.Line(w2s_end[1], w2s_end[2], w2s_perp2[1], w2s_perp2[2])

    -- Optionally, draw the base of the arrowhead to close it
    draw.Line(w2s_perp1[1], w2s_perp1[2], w2s_perp2[1], w2s_perp2[2])
end

local function doDraw()
    if not (engine.Con_IsVisible() or engine.IsGameUIVisible()) then
        draw.Color( 255, 255, 255, 255 )
        Draw3DBox(10, returnVec)
        if (pLocalPos - returnVec):Length() > 10 then
            ArrowLine(pLocalPos, returnVec, 10, 20, false)
        end
    end
end

callbacks.Unregister("CreateMove", "AP_CreateMove")
callbacks.Register("CreateMove", "AP_CreateMove", OnCreateMove)

callbacks.Unregister("Draw", "Ssd_Draw")                        -- Unregister the "Draw" callback
callbacks.Register("Draw", "Ssd_Draw", doDraw)                               -- Register the "Draw" callback

client.Command('play "ui/buttonclick"', true)