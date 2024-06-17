---@type boolean, lnxLib
local libLoaded, lnxLib = pcall(require, "lnxLib")
assert(libLoaded, "lnxLib not found, please install it!")

local Math = lnxLib.Utils.Math
local Prediction = lnxLib.TF2.Prediction
local WPlayer = lnxLib.TF2.WPlayer

-- globals
local lastAngle = nil ---@type number
local vHitbox = { Vector3(-23.99, -23.99, 0), Vector3(23.99, 23.99, 82) }
local pLocal = entities.GetLocalPlayer()
local onGround = true
local Ducking = false
local PredPos = Vector3(0, 0, 0)
local JumpPeekPos = Vector3(0, 0, 0)
local ShouldJump = false

GMenu = {
    Enable = true,
    DuckJump = true,
    SmartJump = true,
    EdgeJump = true,
}

-- State Definitions
local STATE_IDLE = "STATE_IDLE"
local STATE_PREPARE_JUMP = "STATE_PREPARE_JUMP"
local STATE_CTAP = "STATE_CTAP"
local STATE_ASCENDING = "STATE_ASCENDING"
local STATE_DESCENDING = "STATE_DESCENDING"

-- Initial state
local jumpState = STATE_IDLE

-- Constants for angle thresholds
local MAX_JUMP_HEIGHT = Vector3(0, 0, 72) -- Example maximum jump height vector
local MAX_WALKABLE_ANGLE = 45 -- Maximum angle considered walkable
--local MAX_CLIMBABLE_ANGLE = 55 -- Maximum angle considered climbable
local gravity = 800 --gravity per second
local jumpForce = 277 -- Initial vertical boost for a duck jump

-- Function to normalize a vector
local function NormalizeVector(vector)
    local length = vector:Length()
    return Vector3(vector.x / length, vector.y / length, vector.z / length)
end


local function RotateVectorByYaw(vector, yaw)
    local rad = math.rad(yaw)
    local cos, sin = math.cos(rad), math.sin(rad)

    return Vector3(
        cos * vector.x - sin * vector.y,
        sin * vector.x + cos * vector.y,
        vector.z
    )
end

-- Function to check the angle of the surface
local function isSurfaceWalkable(normal)
    local vUp = Vector3(0, 0, 1)
    local angle = math.deg(math.acos(normal:Dot(vUp)))
    return angle < MAX_WALKABLE_ANGLE
end

-- Helper function to check if the player is on the ground
local function isPlayerOnGround(player)
    local pFlags = player:GetPropInt("m_fFlags")
    return (pFlags & FL_ONGROUND) == FL_ONGROUND
end

-- Helper function to check if the player is on the ground
local function isPlayerDucking(player)
    return (player:GetPropInt("m_fFlags") & FL_DUCKING) == FL_DUCKING
end

---@param me WPlayer?
local function CalcStrafe(me)
    if not me then return end --nil check

    -- Reset data for dormant or dead players and teammates
    local angle = me:EstimateAbsVelocity():Angles() -- get angle of velocity vector

    -- Calculate the delta angle
    local delta = 0
    if lastAngle then
        delta = angle.y - lastAngle
        delta = Math.NormalizeAngle(delta)
    end

    return delta
end

-- Function to calculate the jump peak
local function GetJumpPeak(horizontalVelocityVector, startPos)

    -- Calculate the time to reach the jump peak
    local timeToPeak = jumpForce / gravity

    -- Calculate horizontal velocity length
    local horizontalVelocity = horizontalVelocityVector:Length()

    -- Calculate distance traveled horizontally during time to peak
    local distanceTravelled = horizontalVelocity * timeToPeak

    -- Calculate peak position vector
    local peakPosVector = startPos + NormalizeVector(horizontalVelocityVector) * distanceTravelled

    -- Calculate direction to peak position
    local directionToPeak = NormalizeVector(peakPosVector - startPos)

    return peakPosVector, directionToPeak
end

--make the velocity adjusted towards direction we wanna walk
local function SmartVelocity(cmd)
    if not pLocal then return end --nil check

    -- Calculate the player's movement direction
    local moveDir = Vector3(cmd.forwardmove, -cmd.sidemove, 0)
    local viewAngles = engine.GetViewAngles()
    local rotatedMoveDir = RotateVectorByYaw(moveDir, viewAngles.yaw)
    local normalizedMoveDir = NormalizeVector(rotatedMoveDir)
    local vel = pLocal:EstimateAbsVelocity()

    -- Normalize moveDir if its length isn't 0, then ensure velocity matches the intended movement direction
    if moveDir:Length() > 0 then
        if onGround then
        -- Calculate the intended speed based on input magnitude. This could be a fixed value or based on current conditions like player's max speed.
        local intendedSpeed = math.max(1, vel:Length()) -- Ensure the speed is at least 1

        -- Adjust the player's velocity to match the intended direction and speed
        vel = normalizedMoveDir * intendedSpeed
        end
    else
        -- If there's no input, you might want to handle the case where the player should stop or maintain current velocity
        vel = Vector3(0, 0, 0)
    end
    return vel
end

-- Smart jump logic
local function SmartJump(cmd)
    if not pLocal then return end

    -- Get the player's data
    local pLocalPos = pLocal:GetAbsOrigin()
    local vel = SmartVelocity(cmd) -- Adjust velocity based on movement input

    if onGround then
        local JumpPeekPerfectPos, JumpDirection = GetJumpPeak(vel, pLocalPos)
        JumpPeekPos = JumpPeekPerfectPos

        -- Trace to the peak position
        local trace = engine.TraceHull(pLocalPos, JumpPeekPos, vHitbox[1], vHitbox[2], MASK_PLAYERSOLID_BRUSHONLY)
        JumpPeekPos = trace.endpos

        if trace.fraction < 1 then
            -- Move up by jump height
            local startrace = trace.endpos + MAX_JUMP_HEIGHT

            -- Move one unit forward
            local endtrace = startrace + JumpDirection * 1

            -- Forward trace to check for sliding on possible walls
            local forwardTrace = engine.TraceHull(startrace, endtrace, vHitbox[1], vHitbox[2], MASK_PLAYERSOLID_BRUSHONLY)
            JumpPeekPos = forwardTrace.endpos

            -- Lastly, trace down to check for landing
            local traceDown = engine.TraceHull(JumpPeekPos, JumpPeekPos - MAX_JUMP_HEIGHT, vHitbox[1], vHitbox[2], MASK_PLAYERSOLID_BRUSHONLY)
            JumpPeekPos = traceDown.endpos

            if traceDown.fraction > 0 and traceDown.fraction < 0.75 then
                local normal = traceDown.plane
                if isSurfaceWalkable(normal) then
                    ShouldJump = true
                else
                    ShouldJump = false
                end
            end
        end
    elseif input.IsButtonDown(KEY_SPACE) then
        ShouldJump = true
    else
        ShouldJump = false
    end
end

local function OnCreateMove(cmd)
    -- Get the local player
    pLocal = entities.GetLocalPlayer()
    local WLocal = WPlayer.GetLocal()

    -- Check if the local player is valid and alive
    if not pLocal or not pLocal:IsAlive() or not WLocal then
        jumpState = STATE_IDLE  -- Reset to STATE_IDLE state if player is not valid or alive
        return
    end

    -- cache player flags
    onGround = isPlayerOnGround(pLocal)
    Ducking = isPlayerDucking(pLocal)

    -- Calculate the strafe angle
    local strafeAngle = CalcStrafe(WLocal)

    --fix the hitbox
    if Ducking then
        vHitbox[2].z = 62
    else
        vHitbox[2].z = 82
    end

    -- Check if the player is on the ground and fully crouched, and handle edge case
    if onGround and (pLocal:GetPropVector("m_vecViewOffset[0]").z < 65 or Ducking) and jumpState ~= STATE_CTAP then
        jumpState = STATE_CTAP  -- Transition to STATE_CTAP to resolve the logical error
    end

    -- State machine for CTAP and jumping
    if jumpState == STATE_IDLE then
        -- STATE_IDLE: Waiting for jump commands
        SmartJump(cmd) --do smartjump logic

        if onGround or ShouldJump then
            if ShouldJump then
                jumpState = STATE_PREPARE_JUMP  -- Transition to STATE_PREPARE_JUMP if jump key is pressed or ShouldJump is true
            end
        end

    elseif jumpState == STATE_PREPARE_JUMP then
        -- STATE_PREPARE_JUMP: Start crouching
        cmd:SetButtons(cmd.buttons | IN_DUCK)  -- Duck
        cmd:SetButtons(cmd.buttons & (~IN_JUMP))  -- Uncrouch
        jumpState = STATE_CTAP  -- Transition to STATE_CTAP to prepare for jump
        return

    elseif jumpState == STATE_CTAP then
        -- STATE_CTAP: Uncrouch and jump
        cmd:SetButtons(cmd.buttons & (~IN_DUCK))  -- UnDuck
        cmd:SetButtons(cmd.buttons | IN_JUMP)     -- Jump
        jumpState = STATE_ASCENDING  -- Transition to STATE_ASCENDING after initiating jump
        return

    elseif jumpState == STATE_ASCENDING then
        -- STATE_ASCENDING: Player is moving upwards
        cmd:SetButtons(cmd.buttons | IN_DUCK)  -- Crouch mid-air
        if pLocal:EstimateAbsVelocity().z <= 0 then
            jumpState = STATE_DESCENDING  -- Transition to STATE_DESCENDING once upward velocity stops
        end
        return

    elseif jumpState == STATE_DESCENDING then
        -- STATE_DESCENDING: Player is falling down
        cmd:SetButtons(cmd.buttons & (~IN_DUCK))  -- UnDuck when falling

        local predData = Prediction.Player(WLocal, 1, strafeAngle, nil)
        if not predData then return end

        PredPos = predData.pos[1] --update predpos

        if not predData.onGround[1] or not onGround then --when on ground or will be on ground next tick
            SmartJump(cmd)
            if ShouldJump then
                cmd:SetButtons(cmd.buttons & (~IN_DUCK))
                cmd:SetButtons(cmd.buttons | IN_JUMP)
                jumpState = STATE_PREPARE_JUMP  -- Transition back to STATE_PREPARE_JUMP for bhop
            end
        else
            cmd:SetButtons(cmd.buttons | IN_DUCK)
            jumpState = STATE_IDLE  -- Transition back to STATE_IDLE once player lands
        end
    end
end

local function OnDraw()
    -- Inside your OnDraw function
    pLocal = entities.GetLocalPlayer()
    if not pLocal then return end
    local pLocalPos = pLocal:GetAbsOrigin()
    draw.Color(255, 0, 0, 255)
    local screenPos = client.WorldToScreen(PredPos)
    local screenpeekpos = client.WorldToScreen(JumpPeekPos)
            if screenPos then
                draw.Color(255, 0, 0, 255)  -- Red color for backstab position
                draw.FilledRect(screenPos[1] - 5, screenPos[2] - 5, screenPos[1] + 5, screenPos[2] + 5)
            end
            if screenpeekpos then
                draw.Color(0, 255, 0, 255)  -- Red color for backstab position
                draw.FilledRect(screenpeekpos[1] - 5, screenpeekpos[2] - 5, screenpeekpos[1] + 5, screenpeekpos[2] + 5)
            end

                -- Calculate min and max points
                local minPoint = vHitbox[1] + JumpPeekPos
                local maxPoint = vHitbox[2] + JumpPeekPos

                -- Calculate vertices of the AABB
                -- Assuming minPoint and maxPoint are the minimum and maximum points of the AABB:
                local vertices = {
                    Vector3(minPoint.x, minPoint.y, minPoint.z),  -- Bottom-back-left
                    Vector3(minPoint.x, maxPoint.y, minPoint.z),  -- Bottom-front-left
                    Vector3(maxPoint.x, maxPoint.y, minPoint.z),  -- Bottom-front-right
                    Vector3(maxPoint.x, minPoint.y, minPoint.z),  -- Bottom-back-right
                    Vector3(minPoint.x, minPoint.y, maxPoint.z),  -- Top-back-left
                    Vector3(minPoint.x, maxPoint.y, maxPoint.z),  -- Top-front-left
                    Vector3(maxPoint.x, maxPoint.y, maxPoint.z),  -- Top-front-right
                    Vector3(maxPoint.x, minPoint.y, maxPoint.z)   -- Top-back-right
                }



                --[[local vertices = {
                    client.WorldToScreen(vPlayerFuture + Vector3(hitbox_Width, hitbox_Width, 0)),
                    client.WorldToScreen(vPlayerFuture + Vector3(-hitbox_Width, hitbox_Width, 0)),
                    client.WorldToScreen(vPlayerFuture + Vector3(-hitbox_Width, -hitbox_Width, 0)),
                    client.WorldToScreen(vPlayerFuture + Vector3(hitbox_Width, -hitbox_Width, 0)),
                    client.WorldToScreen(vPlayerFuture + Vector3(hitbox_Width, hitbox_Width, hitbox_Height)),
                    client.WorldToScreen(vPlayerFuture + Vector3(-hitbox_Width, hitbox_Width, hitbox_Height)),
                    client.WorldToScreen(vPlayerFuture + Vector3(-hitbox_Width, -hitbox_Width, hitbox_Height)),
                    client.WorldToScreen(vPlayerFuture + Vector3(hitbox_Width, -hitbox_Width, hitbox_Height))
                }]]

                -- Convert 3D coordinates to 2D screen coordinates
                for i, vertex in ipairs(vertices) do
                    vertices[i] = client.WorldToScreen(vertex)
                end

                -- Draw lines between vertices to visualize the box
                if vertices[1] and vertices[2] and vertices[3] and vertices[4] and vertices[5] and vertices[6] and vertices[7] and vertices[8] then
                    -- Draw front face
                    draw.Line(vertices[1][1], vertices[1][2], vertices[2][1], vertices[2][2])
                    draw.Line(vertices[2][1], vertices[2][2], vertices[3][1], vertices[3][2])
                    draw.Line(vertices[3][1], vertices[3][2], vertices[4][1], vertices[4][2])
                    draw.Line(vertices[4][1], vertices[4][2], vertices[1][1], vertices[1][2])

                    -- Draw back face
                    draw.Line(vertices[5][1], vertices[5][2], vertices[6][1], vertices[6][2])
                    draw.Line(vertices[6][1], vertices[6][2], vertices[7][1], vertices[7][2])
                    draw.Line(vertices[7][1], vertices[7][2], vertices[8][1], vertices[8][2])
                    draw.Line(vertices[8][1], vertices[8][2], vertices[5][1], vertices[5][2])

                    -- Draw connecting lines
                    draw.Line(vertices[1][1], vertices[1][2], vertices[5][1], vertices[5][2])
                    draw.Line(vertices[2][1], vertices[2][2], vertices[6][1], vertices[6][2])
                    draw.Line(vertices[3][1], vertices[3][2], vertices[7][1], vertices[7][2])
                    draw.Line(vertices[4][1], vertices[4][2], vertices[8][1], vertices[8][2])
                end
end

callbacks.Unregister("CreateMove", "jumpbughanddd")
callbacks.Register("CreateMove", "jumpbughanddd", OnCreateMove)

callbacks.Unregister("Draw", "accuratemoveD.Draw")
callbacks.Register("Draw", "accuratemoveD", OnDraw)
