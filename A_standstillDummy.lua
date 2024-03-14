--[[
    placeHolder Standstill dummy lua
    keeps standign in same place after loading lua
    Author: titaniummachine1 (github.com/titaniummachine1)
]]

local MaxInputStrength = 450

local function Normalize(vec)
    local length = math.sqrt(vec.x * vec.x + vec.y * vec.y + vec.z * vec.z)
    return Vector3(vec.x / length, vec.y / length, vec.z / length)
end

-- Function to compute the move direction
local function ComputeMove(Cmd, a, b)
    local diff = (b - a)
    if diff:Length() == 0 then return Vector3(0, 0, 0) end

    local x = diff.x
    local y = diff.y
    local vSilent = Vector3(x, y, 0)

    local ang = vSilent:Angles()
    local cPitch, cYaw, cRoll = Cmd:GetViewAngles()
    local yaw = math.rad(ang.y - cYaw)
    local pitch = math.rad(ang.x - cPitch)
    local move = Vector3(math.cos(yaw), -math.sin(yaw), -math.cos(pitch))

    return move
end

-- Function to scale a vector by a given factor
function Scale(vector, factor)
    return {x = vector.x * factor, y = vector.y * factor}
end

function WalkTo(Cmd, pLocal, pDestination)
    local StartPos = pLocal:GetAbsOrigin()
    local distVector = pDestination - StartPos
    local distance = distVector:Length()
    local velocityVector = pLocal:EstimateAbsVelocity()
    local velocity = velocityVector:Length()
    local TICK_RATE = globals.TickInterval()
    local MaxSpeed = pLocal:GetPropFloat("m_flMaxspeed")
    local Friction = pLocal:GetPropFloat("m_flFriction")
    local ScaleFactor = MaxSpeed / MaxInputStrength

    local stoppingDistance = math.max(10, math.min(velocity, MaxInputStrength)) -- Calculate dynamic stopping distance

    -- Compute the movement input needed to go towards the target
    local Result = ComputeMove(Cmd, StartPos, pDestination)

    if distance <= stoppingDistance and distance > 0.1 then
        -- Calculate the fastest possible speed we can go to the target without overshooting
        local decelerationRate = Friction * TICK_RATE
        local neededDeceleration = velocity^2 / (2 * distance)
        local adjustedSpeed

        -- If the needed deceleration is greater than the deceleration rate, we need to slow down
        if neededDeceleration > decelerationRate then
            adjustedSpeed = velocity - decelerationRate
        else
            -- Otherwise, we can speed up, but not beyond the maximum speed
            adjustedSpeed = math.min(velocity + decelerationRate, MaxSpeed)
        end

        function round(num, numDecimalPlaces)
            local mult = 10^(numDecimalPlaces or 0)
            return math.floor(num * mult + 0.5) / mult
        end

        local correctionFactor = 0.0000003576279 -- Adjust this value as needed
        local inputStrength = ((1 / MaxSpeed) * MaxInputStrength) + correctionFactor
        inputStrength = math.max(1, math.min(inputStrength, 450)) -- Ensure inputStrength is within the range [1, 450]
        inputStrength = round(inputStrength, 10) -- Round to 10 decimal places

        local adjustedSpeed = math.min(velocity / MaxSpeed, 1)
        inputStrength = adjustedSpeed * MaxInputStrength

        -- Scale the input based on the adjusted speed
        Cmd:SetForwardMove(Result.x * inputStrength)
        Cmd:SetSideMove(Result.y * inputStrength)
    elseif distance > stoppingDistance then
        -- If outside the stopping distance, move towards the target at maximum possible input strength
        Cmd:SetForwardMove(Result.x * MaxInputStrength)
        Cmd:SetSideMove(Result.y * MaxInputStrength)
    else
        Cmd:SetForwardMove(0)
        Cmd:SetSideMove(0)
    end
end



local returnVec = entities.GetLocalPlayer():GetAbsOrigin()
local pLocalPos = Vector3()
local PosPlaced = true

local function OnCreateMove(Cmd)
    local pLocal = entities.GetLocalPlayer()
    if not pLocal and pLocal:IsAlive() then return end
    pLocalPos = pLocal:GetAbsOrigin()

    if input.IsButtonDown(KEY_LSHIFT) then
        returnVec = entities.GetLocalPlayer():GetAbsOrigin()
        PosPlaced = false
    else
        PosPlaced = true
    end

    if Cmd:GetForwardMove() ~= 0 or Cmd:GetSideMove() ~= 0 then return end --movement bypass

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