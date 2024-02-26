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
    local velocity = pLocal:EstimateAbsVelocity():Length()

    -- If distance is greater than 1, proceed with walking
    if dist > 1 then
        local result = ComputeMove(pCmd, localPos, pDestination)
        -- If distance is less than 10, scale down the speed further
        if dist < 10 + velocity then
            local scaleFactor = dist / 100
            pCmd:SetForwardMove(result.x * scaleFactor)
            pCmd:SetSideMove(result.y * scaleFactor)
        else
            pCmd:SetForwardMove(result.x)
            pCmd:SetSideMove(result.y)
        end
    end
end

local returnVec = entities.GetLocalPlayer():GetAbsOrigin()
local PosPlaced = true

local function OnCreateMove(pCmd)
    local pLocal = entities.GetLocalPlayer()
    if not pLocal and pLocal:IsAlive() then return end

    if input.IsButtonDown(KEY_LSHIFT) then
        returnVec = entities.GetLocalPlayer():GetAbsOrigin()
        PosPlaced = false
    else
        PosPlaced = true
    end

    if PosPlaced then
        WalkTo(pCmd, pLocal, returnVec)
    end
end

callbacks.Unregister("CreateMove", "AP_CreateMove")
callbacks.Register("CreateMove", "AP_CreateMove", OnCreateMove)

client.Command('play "ui/buttonclick"', true)