--[[
    ChargeControl.lua
    
    Provides improved mouse control while charging as Demoman in TF2.
    Gives similar turning capabilities to controller/gamepad users
    while maintaining standard mouse sensitivity.
    
    Author: Terminator(titaniummachine1)
--]]

-- Tracking variables for charge state
local prevCharging = false

-- Optional: Apply a small multiplier if you want slightly enhanced turning
-- Set to 1.0 for exactly normal mouse behavior
local TURN_MULTIPLIER = 1.0

-- Maximum degrees to rotate in one frame (prevents disorientation from extreme flicks)
local MAX_ROTATION_PER_FRAME = 73.04

-- Side movement value for A/D simulation (Source engine uses ±450 for full side movement)
local SIDE_MOVE_VALUE = 450

-- Main function that processes player input during charge
local function OnCreateMove(cmd)
    -- Check if player exists and is alive
    local player = entities.GetLocalPlayer()
    if not player or not player:IsAlive() then
        prevCharging = false
        return
    end

    -- Check if player is charging
    local isCharging = player:InCond(17) -- 17 is the charge condition ID

    -- Skip if not charging
    if not isCharging then
        prevCharging = false
        return
    end

    -- Handle charge start
    if isCharging and not prevCharging then
        -- Charge just started
    end
    prevCharging = true

    -- Get mouse X movement (negative = left, positive = right)
    local mouseDeltaX = -cmd.mousedx

    -- Skip processing if no horizontal mouse movement
    if mouseDeltaX == 0 then
        return
    end

    -- Get current view angles and game settings
    local currentAngles = engine.GetViewAngles()
    local m_yaw = select(2, client.GetConVar("m_yaw")) -- Get m_yaw from game settings

    -- Calculate turn amount using standard Source engine formula
    local turnAmount = mouseDeltaX * m_yaw * TURN_MULTIPLIER

    -- Determine turning direction for side movement
    -- Apply side movement based on turning direction (simulate A/D keys)
    -- Note: Due to API bug mentioned by user, we might need to negate the expected values
    if turnAmount > 0 then
        -- Turning left, simulate pressing D (right strafe)
        cmd.sidemove = SIDE_MOVE_VALUE
    else
        -- Turning right, simulate pressing A (left strafe)
        cmd.sidemove = -SIDE_MOVE_VALUE
    end

    -- Limit maximum turn per frame to prevent disorientation
    turnAmount = math.max(-MAX_ROTATION_PER_FRAME, math.min(MAX_ROTATION_PER_FRAME, turnAmount))

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
    cmd:SetViewAngles(currentAngles.pitch, newYaw, currentAngles.roll) --for some reason necesary or else it stuttes camera
end

-- Register the callback
callbacks.Register("CreateMove", OnCreateMove)
