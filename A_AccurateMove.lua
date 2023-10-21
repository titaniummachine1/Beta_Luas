-- Constants for minimum and maximum speed
local MIN_SPEED = 10  -- Minimum speed to avoid jittery movements
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

local lastKeySide = nil  -- Variable to store the last key pressed for sidemove
local lastKeyForward = nil  -- Variable to store the last key pressed for forwardmove

local function handleMovement(cmd)
    local localPlayer = entities.GetLocalPlayer()
    if not localPlayer then return end
    local pFlags = localPlayer:GetPropInt("m_fFlags")
    if (pFlags & FL_ONGROUND) == 0 then return end --disable when airbone
    local velocity = localPlayer:EstimateAbsVelocity()
    -- Define movement speed
    local moveSpeed = 660

    -- Initial speeds based on current command
    local sideSpeed = 0
    local forwardSpeed = 0

    -- Separate checks for side and forward movement keys
    if input.IsButtonDown(KEY_A) or input.IsButtonDown(KEY_D) then
        if input.IsButtonDown(KEY_A) then
            lastKeySide = KEY_A
        elseif input.IsButtonDown(KEY_D) then
            lastKeySide = KEY_D
        end
    else
        lastKeySide = nil  -- Reset lastKeySide when no keys for sidemove are pressed
    end

    if input.IsButtonDown(KEY_W) or input.IsButtonDown(KEY_S) then
        if input.IsButtonDown(KEY_W) then
            lastKeyForward = KEY_W
        elseif input.IsButtonDown(KEY_S) then
            lastKeyForward = KEY_S
        end
    else
        lastKeyForward = nil  -- Reset lastKeyForward when no keys for forwardmove are pressed
    end

    -- Set speeds based on the last keys pressed for sidemove and forwardmove
    if lastKeySide == KEY_A then
        sideSpeed = -moveSpeed
    elseif lastKeySide == KEY_D then
        sideSpeed = moveSpeed
    end

    if lastKeyForward == KEY_W then
        forwardSpeed = moveSpeed
    elseif lastKeyForward == KEY_S then
        forwardSpeed = -moveSpeed
    end

    -- If no keys are held, stop movement immediately by moving in the opposite direction of current velocity
    if lastKeySide == nil and lastKeyForward == nil then
        local oppositePoint = localPlayer:GetAbsOrigin() - velocity
        WalkTo(cmd, localPlayer, oppositePoint)
        return
    end

    -- Set the movement speeds
    cmd.forwardmove = forwardSpeed
    cmd.sidemove = sideSpeed
end

callbacks.Register("CreateMove", "handleMovement", handleMovement)



