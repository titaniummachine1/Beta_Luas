--[[
    placeHolder Standstill dummy lua
    keeps standign in same place after loading lua
    Author: titaniummachine1 (github.com/titaniummachine1)
]]

-- Constants for minimum and maximum speed
local MIN_SPEED = 100  -- Minimum speed to avoid jittery movements
local MAX_SPEED = 450 -- Maximum speed the player can move

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
    local move = Vector3(math.cos(yaw) * MAX_SPEED, -math.sin(yaw) * MAX_SPEED, -math.cos(pitch) * MAX_SPEED)

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

local returnVec = entities.GetLocalPlayer():GetAbsOrigin()
PosPlaced = true

local function OnCreateMove(pCmd)
    local pLocal = entities.GetLocalPlayer()
    if not pLocal then return end

    if pLocal:IsAlive() then
        local localPos = pLocal:GetAbsOrigin()

            local distVector = returnVec - localPos
            local dist = distVector:Length()
            if dist > 20 then
                WalkTo(pCmd, pLocal, returnVec)
            else
                return
            end
    end
end

callbacks.Unregister("CreateMove", "AP_CreateMove")
callbacks.Register("CreateMove", "AP_CreateMove", OnCreateMove)

client.Command('play "ui/buttonclick"', true)