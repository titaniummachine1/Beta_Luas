local function NormalizeVector(vector)
    local length = math.sqrt(vector.x * vector.x + vector.y * vector.y)
    if length == 0 then
        return Vector3(0, 0, 0)
    else
        return Vector3(vector.x / length, vector.y / length, 0)
    end
end

callbacks.Register("CreateMove", function(cmd)
    local pLocal = entities.GetLocalPlayer()
    if not pLocal then return end

    local pFlags = pLocal:GetPropInt("m_fFlags")
    local OnGround = (pFlags & FL_ONGROUND) == 1

    if not OnGround then return end
    if cmd.buttons & IN_ATTACK ~= 0 then return end -- Don't do anything if the player is shooting

    -- Combine forward and sideward movements into a single vector
    local moveDir = Vector3(cmd.forwardmove, cmd.sidemove, 0)

    -- Normalize the movement direction
    local normalizedMoveDir = NormalizeVector(moveDir)

    -- Create a separate vector for the look direction with the sidemove inverted
    local lookDir = Vector3(cmd.forwardmove, -cmd.sidemove, 0)

    -- Normalize the look direction
    local normalizedLookDir = NormalizeVector(lookDir)

    -- Calculate the desired aim direction based on normalized side and forward movement
    local lookAngle = math.atan(normalizedLookDir.y, normalizedLookDir.x)
    local aimAngle = math.deg(lookAngle)

    -- Get the current view angles
    local viewAngles = engine.GetViewAngles()

    -- If player is moving (normalizedMoveDir has length), adjust view angles to align with look direction
    if normalizedLookDir.x ~= 0 or normalizedLookDir.y ~= 0 then
        local correctedAngle = viewAngles.y + aimAngle

        -- Adjust the player's view angles to face the direction of look
        cmd:SetViewAngles(viewAngles.x, correctedAngle, viewAngles.z)
        -- Adjust forward and sidemove based on normalized direction
        cmd.forwardmove = normalizedMoveDir.x * 450
        cmd.sidemove = normalizedMoveDir.y * 450
    end
end)