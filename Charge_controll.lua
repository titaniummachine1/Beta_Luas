-- ChargeControl.lua
--[[
    ChargeControl.lua
    Provides improved mouse control while charging as Demoman in TF2.
    Gives similar turning capabilities to controller/gamepad users.

    Author: Terminator(titaniummachine1)
--]]


-- Main function that processes player input during charge
local function OnCreateMove(cmd)
    -- Check if player exists and is alive
    local player = entities.GetLocalPlayer()
    if not player or not player:IsAlive() then
        return
    end

    -- Only activate during charge (condition 17)
    if not player:InCond(17) then
        return
    end

    -- Get mouse X movement (negative = left, positive = right)
    local mouseDeltaX = -cmd.mousedx

    -- Skip processing if no horizontal mouse movement
    if mouseDeltaX == 0 then
        return
    end

    -- Get current view angles and game settings
    local currentAngles = engine.GetViewAngles()
    local sensitivity = select(2, client.GetConVar("sensitivity")) --Get Second Value of Sensitivity cuz the first is int not float
    local m_yaw = select(2, client.GetConVar("m_yaw"))            --Get m_yaw from game settings

    -- Calculate base turn amount using TF2's formula
    local turnAmount = mouseDeltaX * sensitivity * m_yaw

    -- Limit maximum turn speed based on sensitivity directly
    -- If sensitivity is 3, max rotation will be 3 degrees per frame
    local maxRotation = sensitivity
    turnAmount = math.max(-maxRotation, math.min(maxRotation, turnAmount))

    -- Calculate new yaw angle
    local newYaw = currentAngles.yaw + turnAmount

    -- Handle -180/180 degree boundary crossing
    newYaw = newYaw % 360
    if newYaw > 180 then
        newYaw = newYaw - 360
    elseif newYaw < -180 then
        newYaw = newYaw + 360
    end

    -- Update view angles (both client-side visual and server-side movement)
    local newAngles = EulerAngles(currentAngles.pitch, newYaw, currentAngles.roll)
    engine.SetViewAngles(newAngles)
    cmd:SetViewAngles(currentAngles.pitch, newYaw, currentAngles.roll)
end

-- Register the callback
callbacks.Register("CreateMove", OnCreateMove)
