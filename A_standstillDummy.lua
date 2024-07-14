--[[
    placeHolder Standstill dummy lua
    keeps standign in same place after loading lua
    Author: titaniummachine1 (github.com/titaniummachine1)
]]


-- Constants
local MAX_SPEED = 450 -- Maximum speed the player can move
local TWO_PI = 2 * math.pi
local DEG_TO_RAD = math.pi / 180

    --[[
        Time improvement:

    Before: 0.000030 seconds
    After:  0.000012 seconds
    Improvement: 60% faster


    Memory usage improvement:

    Before: 0.938 KB
    After:  0.289 KB
    Improvement: 69.2% less memory used
    ]]
-- Computes the move vector between two points
---@param userCmd UserCmd
---@param a Vector3
---@param b Vector3
---@return Vector3
local function ComputeMove(userCmd, a, b)
    local dx, dy = b.x - a.x, b.y - a.y

    local targetYaw = (math.atan(dy, dx) + TWO_PI) % TWO_PI
    local _, currentYaw = userCmd:GetViewAngles()
    currentYaw = currentYaw * DEG_TO_RAD

    local yawDiff = (targetYaw - currentYaw + math.pi) % TWO_PI - math.pi

    return Vector3(
        math.cos(yawDiff) * MAX_SPEED,
        math.sin(-yawDiff) * MAX_SPEED,
        0
    )
end

-- Function to calculate the time needed to stop completely
local function CalculateStopTime(velocity, decelerationPerSecond)
    return velocity / decelerationPerSecond
end

-- Converts time to game ticks
---@param time number
---@return integer
local function Time_to_Ticks(time)
    return math.floor(0.5 + time / globals.TickInterval())
end

-- Function to calculate the number of ticks needed to stop completely
local function CalculateStopTicks(velocity, decelerationPerSecond)
    local stopTime = CalculateStopTime(velocity, decelerationPerSecond)
    return Time_to_Ticks(stopTime)
end

-- Function to make the player walk to a destination smoothly
local function WalkTo(pCmd, pLocal, pDestination)
    local localPos = pLocal:GetAbsOrigin()
    local distVector = pDestination - localPos
    local dist = distVector:Length()
    local velocity = pLocal:EstimateAbsVelocity():Length()
    local tickInterval = globals.TickInterval()
    local tickRate = 1 / tickInterval

    -- Calculate the deceleration per second
    local AccelerationPerSecond = 84 * tickRate  -- Converting units per tick to units per second

    -- Calculate the number of ticks to stop
    local stopTicks = CalculateStopTicks(velocity, AccelerationPerSecond)

    -- Calculate the stop distance
    local speedPerTick = velocity / tickRate
    local stopDistance = math.max(10, math.min(speedPerTick * stopTicks, 450))

    local result = ComputeMove(pCmd, localPos, pDestination)

    if dist <= stopDistance then
        -- Calculate precise movement needed to stop perfectly at the target
        local neededVelocity = dist / stopTicks
        local currentVelocity = velocity / tickRate
        local velocityAdjustment = neededVelocity - currentVelocity

        -- Apply the velocity adjustment
        if stopTicks <= 2 then
            pCmd:SetForwardMove(result.x * velocityAdjustment)
            pCmd:SetSideMove(result.y * velocityAdjustment)
        else
            local scaleFactor = dist / 1000
            pCmd:SetForwardMove(result.x * scaleFactor)
            pCmd:SetSideMove(result.y * scaleFactor)
        end
    else
        pCmd:SetForwardMove(result.x)
        pCmd:SetSideMove(result.y)
    end
end

-- ultimate Normalize a vector
local function Normalize(vec)
    return  vec / vec:Length()
end

local PlayerHULL = {Min = Vector3(-23.99, -23.99, 0), Max = Vector3(23.99, 23.99, 82)}
local STEP_HEIGHT = Vector3(0, 0, 18)
local MAX_FALL_DISTANCE = Vector3(0, 0, 500)
local Step_Fraction = STEP_HEIGHT.z / MAX_FALL_DISTANCE.z

local Jump_Height = Vector3(0, 0, 72)
local UP_VECTOR = Vector3(0, 0, 1)
local MIN_STEP_SIZE = 24 -- Minimum step size in units
local SEGMENTS = 5 -- Number of segments for ground check

local MAX_angle = 45 -- Maximum angle for ground check
local MAX_ANGLE_RAD = math.rad(MAX_angle) -- Convert to radians for calculations
local MAX_ITERATIONS = 50 -- Maximum number of iterations to prevent infinite loops

local hullTraces = {}
local lineTraces = {}

local function getHorizontalManhattanDistance(point1, point2)
 -- Calculate absolute horizontal distance  
    return math.abs(point1.x - point2.x) + math.abs(point1.y - point2.y)
end

-- Checks for an obstruction between two points using a hull trace.
local function performHullTrace(startPos, endPos)
    local result = engine.TraceHull(startPos, endPos, PlayerHULL.Min, PlayerHULL.Max, MASK_PLAYERSOLID)
    table.insert(hullTraces, {startPos = startPos, endPos = result.endpos, result = result})
    return result
end

-- Checks for ground stability using a line trace.
local function performLineTrace(startPos, endPos)
    local result = engine.TraceLine(startPos, endPos, MASK_PLAYERSOLID)
    table.insert(lineTraces, {startPos = startPos, endPos = result.endpos, result = result})
    return result
end

-- Pre-calculate the threshold based on maximum slope angle and UP_VECTOR
local MAX_SLOPE_ANGLE_COS = math.cos(MAX_ANGLE_RAD)

--[[Function to adjust direction based on ground normal
local function adjustDirectionToGround(direction, groundNormal)
    local angleBetween = math.acos(groundNormal:Dot(UP_VECTOR))
    if angleBetween <= MAX_ANGLE_RAD then
        return Normalize(direction:Cross(UP_VECTOR):Cross(groundNormal))
    end
    return direction -- If the slope is too steep, keep the original direction
end]]

local function adjustDirectionToGround(direction, groundNormal)
    --[[ actual solution unoptymised
        local function adjustDirectionToGround(direction, groundNormal)
        local angle = math.deg(math.acos(groundNormal:Dot(UP_VECTOR)))
        if angle > MAX_angle then
            return direction
        end

        -- Calculate the dot product of direction and groundNormal
        local dot = direction:Dot(groundNormal)

        -- Adjust the z component of the direction vector
        local adjustedDirection = Vector(direction.x, direction.y, direction.z - groundNormal.z * dot)

        return adjustedDirection
    end
    ]]
    -- Adjust the z component of the direction vector
    return (math.deg(math.acos(groundNormal:Dot(UP_VECTOR))) > MAX_angle) and direction or
    (Vector3(direction.x, direction.y, direction.z - groundNormal.z * direction:Dot(groundNormal)))
end


-- Main function to check walkability
local function IsWalkable(startPos, goalPos)
    -- Clear global tables for debugging
    hullTraces = {}
    lineTraces = {}

    local currentPos = startPos

    -- Initial ground collision check
    local groundTrace = performHullTrace(startPos + STEP_HEIGHT, startPos - MAX_FALL_DISTANCE)
    if groundTrace.fraction == 1 then
        return false -- No ground found initially
    end

    local lastP = groundTrace.endpos
    local lastDirection = adjustDirectionToGround(Normalize(Vector3(goalPos.x - startPos.x, goalPos.y - startPos.y, 0)), groundTrace.plane)
    local goalDistance = getHorizontalManhattanDistance(startPos, goalPos) + 1

    for i = 1, MAX_ITERATIONS do
        local Distance = (currentPos - goalPos):Length()
        local direction = lastDirection
        currentPos = lastP + direction * Distance

        -- Forward collision
        local wallTrace = performHullTrace(lastP + STEP_HEIGHT, currentPos + STEP_HEIGHT)
        currentPos = wallTrace.endpos

       -- Ground collision with segmentation
        Distance = (currentPos - lastP):Length()
        local segmentLength = math.max(Distance / SEGMENTS, MIN_STEP_SIZE)
        local numSegments = math.min(SEGMENTS, math.floor(Distance / segmentLength))

        for seg = 1, numSegments do
            local t = seg / numSegments
            local segmentEnd = lastP + (currentPos - lastP) * t
            local groundCheckEnd = segmentEnd - MAX_FALL_DISTANCE
            groundTrace = performHullTrace(segmentEnd + STEP_HEIGHT, groundCheckEnd + STEP_HEIGHT)

            if groundTrace.fraction > Step_Fraction or seg == SEGMENTS then -- always last trace adjsut position to ground
                direction = adjustDirectionToGround(direction, groundTrace.plane)
                currentPos = groundTrace.endpos
                break
            elseif groundTrace == 0 or groundTrace == 1 then
                return false -- Stuck in map geometry or we fall too much, return false
            end
        end


        -- wall check
        if wallTrace.fraction < 1 then
            local downTrace = performHullTrace(currentPos + STEP_HEIGHT + direction * 1, currentPos - STEP_HEIGHT + direction * 1)
            if downTrace.fraction == 0 then
                return false -- Wall blocked
            end
        end

        if not currentPos then
            return false
        end

        local currentDistance = getHorizontalManhattanDistance(currentPos, goalPos)

        -- If at goal return
        if currentDistance < 24 then
            local finalGroundTrace = performLineTrace(currentPos, goalPos)
            if finalGroundTrace.fraction == 1 and (currentPos - goalPos):Length() < 24 then
                return true -- We are under the goal below the floor
            else
                return false
            end
        elseif goalDistance < currentDistance then
            return false
        end

        -- Add the prediction record
        lastP, lastDirection = currentPos, direction
    end

    return false -- Max iterations reached without finding a path
end

local returnVec = entities.GetLocalPlayer():GetAbsOrigin()
local pLocalPos = Vector3()
local PosPlaced = true
local isWalkable = true

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

    if PosPlaced and isWalkable then
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

    -- Check if arrow size is too small (compared to a threshold or minimum length)
    local min_acceptable_length = arrowhead_length + (arrowhead_width / 2)
    if direction:Length() < min_acceptable_length then
      -- Draw a regular line if arrow size is too small
      local w2s_start, w2s_end = client.WorldToScreen(start_pos), client.WorldToScreen(end_pos)
      if not (w2s_start and w2s_end) then return end
        draw.Line(w2s_start[1], w2s_start[2],w2s_end[1], w2s_end[2])
      return
    end

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
        draw.Color(255, 255, 255, 255)
        Draw3DBox(10, returnVec)
        if (pLocalPos - returnVec):Length() > 10 then
            isWalkable = IsWalkable(pLocalPos, returnVec)
            if isWalkable then
                draw.Color(0, 255, 0, 255)
            else
                draw.Color(255, 0, 0, 255)
            end
            ArrowLine(pLocalPos, returnVec, 10, 20, false)
        end

        -- Draw all line traces
        for _, trace in ipairs(lineTraces) do
            draw.Color(255, 255, 255, 255) -- White for line traces
            local w2s_start, w2s_end = client.WorldToScreen(trace.startPos), client.WorldToScreen(trace.endPos)
            if w2s_start and w2s_end then
                draw.Line(w2s_start[1], w2s_start[2], w2s_end[1], w2s_end[2])
            end
        end

        -- Draw all hull traces
        for _, trace in ipairs(hullTraces) do
            draw.Color(0, 50, 255, 255) -- Blue for hull traces
            ArrowLine(trace.startPos, trace.endPos - Vector3(0,0,0.5), 10, 20, false)
        end
    end
end

callbacks.Unregister("CreateMove", "AP_CreateMove")
callbacks.Register("CreateMove", "AP_CreateMove", OnCreateMove)

callbacks.Unregister("Draw", "Ssd_Draw")                        -- Unregister the "Draw" callback
callbacks.Register("Draw", "Ssd_Draw", doDraw)                               -- Register the "Draw" callback

client.Command('play "ui/buttonclick"', true)