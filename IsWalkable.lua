
--[[           IsWalkable module         ]]--
--[[       made by Titaniummachine1      ]]--
--[[    Optymised by Titaniummachine1    ]]--
--[[ https://github.com/Titaniummachine1 ]]--

local IsWalkable = {} --define module

local PlayerHULL = {Min = Vector3(-23.99, -23.99, 0), Max = Vector3(23.99, 23.99, 82)}
local STEP_HEIGHT = Vector3(0, 0, 18)
local MAX_FALL_DISTANCE = Vector3(0, 0, 500)
local Step_Fraction = STEP_HEIGHT.z / MAX_FALL_DISTANCE.z

local UP_VECTOR = Vector3(0, 0, 1)
local MIN_STEP_SIZE = 12 -- Minimum step size in units
local SEGMENTS = 5 -- Number of segments for ground check

local MAX_Ground_Angle = 45 -- Maximum angle for ground check
local MAX_Wall_Angle = 55 -- Maximum angle for ground check
local MAX_ITERATIONS = 27 -- Maximum number of iterations to prevent infinite loops

--preinicialize the values
local segmentEnd = Vector3(0,0,0)
local currentPos = Vector3(0,0,0)
local currentDistance = 0
local Distance = 0
local Blocked = false
local wallTrace
local segmentLength
local numSegments

-- ultimate Normalize a vector
local function Normalize(vec)
    return  vec / vec:Length()
end

--calcualte horizontal distance
---@param point1 Vector3
---@param point2 Vector3
local function getHorizontalManhattanDistance(point1, point2)
    return math.abs(point1.x - point2.x) + math.abs(point1.y - point2.y)
end

-- Checks for an obstruction between two points using a hull trace.
local function performTraceHull(startPos, endPos)
    return engine.TraceHull(startPos, endPos, PlayerHULL.Min, PlayerHULL.Max, MASK_PLAYERSOLID)
end

-- Checks for ground stability using a line trace.
local function performTraceLine(startPos, endPos)
    return engine.TraceLine(startPos, endPos, MASK_PLAYERSOLID)
end

-- Adjust the z component of the direction vector
local function adjustDirectionToGround(direction, groundNormal)
    --[[
    local angle = math.deg(math.acos(groundNormal:Dot(UP_VECTOR)))
    if angle > MAX_Ground_Angle then
        return direction
    end

    -- Calculate the dot product of direction and groundNormal
    local dot = direction:Dot(groundNormal)

    -- Adjust the z component of the direction vector
    local adjustedDirection = Vector(direction.x, direction.y, direction.z - groundNormal.z * dot)

    return Normalize(adjustedDirection)
    ]]
    direction = Normalize(direction)
    return (math.deg(math.acos(groundNormal:Dot(UP_VECTOR))) > MAX_Ground_Angle) and direction or
    (Vector3(direction.x, direction.y, direction.z - groundNormal.z * direction:Dot(groundNormal)))
end

-- Adjust the z component of the direction vector
local function adjustDirectionToWall(direction, groundNormal)
    direction = Normalize(direction)
    return (math.deg(math.acos(groundNormal:Dot(UP_VECTOR))) > MAX_Wall_Angle) and direction or
    (Vector3(direction.x, direction.y, direction.z - groundNormal.z * direction:Dot(groundNormal)))
end

-- Main function to check walkability
function IsWalkable.path(startPos, goalPos)
    --preinicialize the values
    local direction = Vector3(0,0,0)
    segmentEnd = Vector3(0,0,0)
    currentPos = startPos
    Distance = 0
    Blocked = false
    wallTrace = nil
    numSegments = nil

    -- Initial ground collision check
    local groundTrace = performTraceLine(startPos + STEP_HEIGHT, startPos - MAX_FALL_DISTANCE)

    local lastP = startPos
    local lastDirection = adjustDirectionToGround(goalPos - startPos, groundTrace.plane)
    local goalDistance = getHorizontalManhattanDistance(startPos, goalPos)

    for i = 1, MAX_ITERATIONS do
        Distance = (currentPos - goalPos):Length()
        direction = lastDirection
        currentPos = lastP + direction * Distance

        -- Forward collision
        wallTrace = performTraceHull(lastP + STEP_HEIGHT, currentPos + STEP_HEIGHT)
        currentPos = wallTrace.endpos
        direction = adjustDirectionToWall(currentPos - lastP, groundTrace.plane)

        -- wall check
        Blocked = (wallTrace.fraction < 1) and performTraceHull(currentPos + STEP_HEIGHT + direction, currentPos - STEP_HEIGHT + direction).fraction == 0 or false

       -- Ground collision with segmentation
        Distance = (currentPos - lastP):Length()
        segmentLength = math.max(Distance / SEGMENTS, MIN_STEP_SIZE)
        numSegments = math.min(SEGMENTS, math.floor(Distance / segmentLength))
        for seg = 1, numSegments do
            segmentEnd = lastP + STEP_HEIGHT + (currentPos - lastP) * seg / numSegments
            groundTrace = performTraceHull(segmentEnd, segmentEnd - MAX_FALL_DISTANCE)
            Blocked = ((groundTrace == 1 or groundTrace == 0)) and true or Blocked
            if groundTrace.fraction > Step_Fraction or seg == SEGMENTS then
                -- always last trace adjsut position to ground
                direction = adjustDirectionToGround(direction, groundTrace.plane)
                currentPos = groundTrace.endpos
                break
            end
        end

        currentDistance = getHorizontalManhattanDistance(currentPos, goalPos)
        if Blocked or goalDistance < currentDistance or currentDistance < 24 then
            return performTraceLine(currentPos, goalPos).fraction == 1 -- We see the target
        end

        -- Add the prediction record
        lastP, lastDirection = currentPos, direction
    end

    return false -- Max iterations reached without finding a path
end

return IsWalkable