-- Kalman Filter Implementation
local KalmanFilter = {}
KalmanFilter.__index = KalmanFilter

function KalmanFilter.new(process_noise, measurement_noise, estimated_error, initial_value)
    local self = setmetatable({}, KalmanFilter)
    self.q = process_noise
    self.r = measurement_noise
    self.p = estimated_error
    self.x = initial_value
    self.k = 0
    return self
end

function KalmanFilter:update(measurement)
    -- Prediction step
    self.p = self.p + self.q

    -- Measurement update
    self.k = self.p / (self.p + self.r)
    self.x = self.x + self.k * (measurement - self.x)
    self.p = (1 - self.k) * self.p

    return self.x
end

-- Initialize Kalman Filters for pitch and yaw with tuned parameters
local kf_pitch = KalmanFilter.new(0.001, 0.01, 1, 0)
local kf_yaw   = KalmanFilter.new(0.001, 0.01, 1, 0)

-- Configuration Parameters
local angle_history = {}
local max_history = 25
local simulation_time = 0.4 -- seconds ahead
local set_fov = 20            -- FOV threshold for detecting enemies
local max_angle_change = 1   -- Max angle magnitude change per tick (degrees)
local deadzone_fov = 1.7     -- Deadzone FOV: if correction < 2°, do nothing
local max_direction_change = 15 -- Max allowed angle difference in direction (degrees)

-- Font for Drawing
local Verdana = draw.CreateFont("Verdana", 16, 800)

-- Utility Functions
local function isNaN(x)
    return x ~= x
end

local function GetHitboxPos(player, hitboxID)
    local hitbox = player:GetHitboxes()[hitboxID]
    if not hitbox then return nil end
    return (hitbox[1] + hitbox[2]) * 0.5
end

local function PositionAngles(source, dest)
    local delta = source - dest
    local pitch = math.deg(math.atan(delta.z / delta:Length2D()))
    local yaw = math.deg(math.atan(delta.y / delta.x))

    if delta.x >= 0 then
        yaw = yaw + 180
    end

    if isNaN(pitch) then pitch = 0 end
    if isNaN(yaw) then yaw = 0 end

    return EulerAngles(pitch, yaw, 0)
end

local function AngleFov(vFrom, vTo)
    local vSrc = vFrom:Forward()
    local vDst = vTo:Forward()
    local denom = vDst:LengthSqr()
    if denom == 0 then return 0 end
    local dot_val = vDst:Dot(vSrc) / denom
    if dot_val > 1 then dot_val = 1 end
    if dot_val < -1 then dot_val = -1 end
    local fov = math.deg(math.acos(dot_val))
    if isNaN(fov) then fov = 0 end
    return fov
end

local function NormalizeAngle(a)
    while a > 180 do a = a - 360 end
    while a < -180 do a = a + 360 end
    return a
end

local function GetViewPos(player)
    return player:GetAbsOrigin() + player:GetPropVector("localdata", "m_vecViewOffset[0]")
end

local function AngleDifference(a, b)
    local dp = NormalizeAngle(a.pitch - b.pitch)
    local dy = NormalizeAngle(a.yaw - b.yaw)
    return EulerAngles(dp, dy, 0)
end

-- Moving Average Implementation for Smoothing Velocities
local pitch_vel_history = {}
local yaw_vel_history = {}
local function MovingAverage(history, val, size)
    table.insert(history, val)
    if #history > size then table.remove(history, 1) end
    local sum = 0
    for _,v in ipairs(history) do sum = sum + v end
    return sum / #history
end

-- Determine Mouse Movement by Checking if the Mouse Isn't Centered
local screen_w, screen_h = draw.GetScreenSize()
local center_x, center_y = math.floor(screen_w / 2), math.floor(screen_h / 2)
local function IsMouseMoving()
    local mouse_x, mouse_y = input.GetMousePos()[1], input.GetMousePos()[2]
    return (mouse_x ~= center_x or mouse_y ~= center_y)
end

local previous_angles = nil

-- Shared Data Structures for Drawing
local predicted_positions_draw = {}
local predicted_angles_draw = {}
local best_step_draw = nil
local best_enemy_angle_draw = nil

-- Compute Current Direction in Angle-Space
local function GetCurrentDirection(angle_history)
    if #angle_history < 3 then return nil end
    -- Use last 2 changes to find direction
    local prev = angle_history[#angle_history-1]
    local curr = angle_history[#angle_history]
    local dpitch = NormalizeAngle(curr.pitch - prev.pitch)
    local dyaw = NormalizeAngle(curr.yaw - prev.yaw)
    local mag = math.sqrt(dpitch * dpitch + dyaw * dyaw)
    if mag < 0.001 then return nil end
    return {dp = dpitch / mag, dy = dyaw / mag} -- unit vector in angle space
end

-- Limit Direction Change: Rotate angle_diff so it doesn't exceed max_direction_change from current direction
local function LimitDirectionChange(angle_diff, direction, max_dir_angle)
    if not direction then return angle_diff end
    -- Convert direction and angle_diff to vectors
    local dp, dy = angle_diff.pitch, angle_diff.yaw
    local mag_diff = math.sqrt(dp * dp + dy * dy)
    if mag_diff < 1e-6 then return angle_diff end -- no change needed

    local dir_dp, dir_dy = direction.dp, direction.dy
    -- Compute angle between direction and angle_diff
    local dot = dir_dp * (dp / mag_diff) + dir_dy * (dy / mag_diff)
    if dot > 1 then dot = 1 end
    if dot < -1 then dot = -1 end
    local angle_between = math.deg(math.acos(dot))

    if angle_between > max_dir_angle then
        -- Rotate angle_diff to form exactly max_dir_angle with direction
        local excess_angle = angle_between - max_dir_angle
        local rad = math.rad(-excess_angle)
        local cos_rad = math.cos(rad)
        local sin_rad = math.sin(rad)
        local new_dp = dp * cos_rad - dy * sin_rad
        local new_dy = dp * sin_rad + dy * cos_rad
        return EulerAngles(new_dp, new_dy, 0)
    end

    return angle_diff
end

-- CreateMove Callback: Handles Logic and Angle Adjustment
local function CreateMove(cmd)
    local localPlayer = entities.GetLocalPlayer()
    if not localPlayer then
        previous_angles = nil
        return
    end

    local current_angles = engine.GetViewAngles()
    table.insert(angle_history, {pitch = current_angles.pitch, yaw = current_angles.yaw})
    if #angle_history > max_history then
        table.remove(angle_history, 1)
    end

    if #angle_history < 3 then
        previous_angles = current_angles
        return
    end

    local frame_time = globals.TickInterval() -- Use TickInterval for CreateMove

    -- Compute Velocities
    local velocities = {}
    for i = 2, #angle_history do
        local prev = angle_history[i-1]
        local curr = angle_history[i]
        local dpitch = NormalizeAngle(curr.pitch - prev.pitch)
        local dyaw = NormalizeAngle(curr.yaw - prev.yaw)

        local pitch_vel = dpitch / frame_time
        local yaw_vel = dyaw / frame_time
        table.insert(velocities, {pitch_vel = pitch_vel, yaw_vel = yaw_vel})
    end

    if #velocities < 2 then
        previous_angles = current_angles
        return
    end

    -- Average Velocities using Moving Average
    local pitch_vel = velocities[#velocities].pitch_vel
    local yaw_vel = velocities[#velocities].yaw_vel
    local smoothed_pitch_vel = MovingAverage(pitch_vel_history, pitch_vel, 5)
    local smoothed_yaw_vel = MovingAverage(yaw_vel_history, yaw_vel, 5)

    -- Compute Acceleration
    local total_pitch_vel_change = 0
    local total_yaw_vel_change = 0
    local accel_count = 0
    for i = 2, #velocities do
        local prev = velocities[i-1]
        local curr = velocities[i]
        total_pitch_vel_change = total_pitch_vel_change + (curr.pitch_vel - prev.pitch_vel)
        total_yaw_vel_change = total_yaw_vel_change + (curr.yaw_vel - prev.yaw_vel)
        accel_count = accel_count + 1
    end

    if accel_count == 0 then
        previous_angles = current_angles
        return
    end

    local avg_pitch_accel = (total_pitch_vel_change / accel_count) / frame_time
    local avg_yaw_accel = (total_yaw_vel_change / accel_count) / frame_time

    -- Kalman Filter Velocities
    local filtered_pitch_velocity = kf_pitch:update(smoothed_pitch_vel)
    local filtered_yaw_velocity = kf_yaw:update(smoothed_yaw_vel)

    -- Predict Future Angles
    local steps = math.ceil(simulation_time / frame_time)
    local step_interval = simulation_time / steps

    -- Clear previous predictions
    predicted_positions_draw = {}
    predicted_angles_draw = {}
    best_step_draw = nil
    best_enemy_angle_draw = nil

    local viewPos = GetViewPos(localPlayer)
    local players = entities.FindByClass("CTFPlayer")

    local best_fov = math.huge
    local best_step = nil
    local best_enemy_angle = nil

    local previous_fov = nil -- To track FOV changes

    for i = 1, steps do
        local t = i * step_interval

        local future_pitch = current_angles.pitch + (filtered_pitch_velocity * t) + (0.5 * avg_pitch_accel * t * t)
        local future_yaw = current_angles.yaw + (filtered_yaw_velocity * t) + (0.5 * avg_yaw_accel * t * t)

        future_pitch = NormalizeAngle(future_pitch)
        future_yaw = NormalizeAngle(future_yaw)

        local future_angle = EulerAngles(future_pitch, future_yaw, 0)
        future_angle:Normalize()

        local forward_vec = future_angle:Forward()
        local predictedPos = viewPos + (forward_vec * 100)

        local screenpos = client.WorldToScreen(predictedPos)
        if screenpos then
            predicted_positions_draw[i] = {x = math.floor(screenpos[1]), y = math.floor(screenpos[2])}
            predicted_angles_draw[i] = future_angle
        else
            predicted_positions_draw[i] = nil
            predicted_angles_draw[i] = future_angle
        end

        -- Initialize a flag to check if any target is found in this step
        local target_found_in_step = false

        -- Check for Best FOV Match
        for _, ply in ipairs(players) do
            if ply:IsAlive() and ply ~= localPlayer and ply:GetTeamNumber() ~= localPlayer:GetTeamNumber() then
                local headPos = GetHitboxPos(ply, 1)
                if headPos then
                    local angleToPlayer = PositionAngles(viewPos, headPos)
                    local fov = AngleFov(future_angle, angleToPlayer)

                    -- Only consider if within set_fov
                    if fov <= set_fov then
                        if fov < best_fov then
                            best_fov = fov
                            best_step = i
                            best_enemy_angle = angleToPlayer
                        end

                        target_found_in_step = true
                        -- Update previous_fov to current fov
                        if previous_fov then
                            if fov > previous_fov then
                                -- FOV started increasing, stop further predictions
                                break
                            end
                        end
                        previous_fov = fov
                    end
                end
            end
        end

        -- If FOV started increasing after finding a target, stop further predictions
        if target_found_in_step and previous_fov and (best_fov and best_fov > set_fov) then
            break
        end
    end

    -- Store best step and enemy angle for drawing
    best_step_draw = best_step
    best_enemy_angle_draw = best_enemy_angle

    -- Aim Assistance Logic
    local mouse_moving = IsMouseMoving()

    if best_step and best_enemy_angle and mouse_moving then
        local closest_pred_angle = predicted_angles_draw[best_step]
        local angle_diff = AngleDifference(best_enemy_angle, closest_pred_angle)

        -- Deadzone check
        local diff_mag = math.sqrt(angle_diff.pitch^2 + angle_diff.yaw^2)
        if diff_mag < deadzone_fov then
            previous_angles = current_angles
            return
        end

        -- Limit Direction Change
        local direction = GetCurrentDirection(angle_history)
        angle_diff = LimitDirectionChange(angle_diff, direction, max_direction_change)

        -- Limit Magnitude to max_angle_change
        local dp, dy = angle_diff.pitch, angle_diff.yaw
        local mag = math.sqrt(dp * dp + dy * dy)
        if mag > max_angle_change then
            local scale = max_angle_change / mag
            dp = dp * scale
            dy = dy * scale
        end

        -- Compute User's Own Angle Change
        local user_angle_change = 0
        if previous_angles then
            local user_diff = AngleDifference(current_angles, previous_angles)
            user_angle_change = math.sqrt(user_diff.pitch^2 + user_diff.yaw^2)
        end

        -- Prevent Script from Exceeding User's Angle Change
        if user_angle_change > 0 then
            local allowed_scale = user_angle_change / max_angle_change
            if allowed_scale < 1 then
                dp = dp * allowed_scale
                dy = dy * allowed_scale
            end
        end

        -- Final Angle Adjustment
        local final_angle = EulerAngles(
            NormalizeAngle(current_angles.pitch + dp),
            NormalizeAngle(current_angles.yaw + dy),
            0
        )
        final_angle:Normalize()

        -- Apply the final angle to the view
        engine.SetViewAngles(final_angle)
    end

    previous_angles = current_angles
end

-- Draw Callback: Handles Visualization
local function OnDraw()
    -- Draw Predicted Points
    draw.SetFont(Verdana)
    for i, pos in ipairs(predicted_positions_draw) do
        if pos then
            local cr, cg, cb = 255, 255, 255 -- Default color: White
            if best_step_draw and i == best_step_draw then
                cr, cg, cb = 255, 0, 0 -- Best match step: Red
            end
            draw.Color(cr, cg, cb, 255)
            draw.FilledRect(pos.x - 2, pos.y - 2, pos.x + 2, pos.y + 2)
        end
    end

    -- Connect Predicted Points with Lines
    draw.Color(255, 255, 255, 255) -- White lines
    for i = 1, (#predicted_positions_draw - 1) do
        local p1 = predicted_positions_draw[i]
        local p2 = predicted_positions_draw[i + 1]
        if p1 and p2 then
            draw.Line(p1.x, p1.y, p2.x, p2.y)
        end
    end

    -- Optionally, draw the best enemy target's predicted position
    if best_step_draw and predicted_positions_draw[best_step_draw] then
        local target_pos = predicted_positions_draw[best_step_draw]
        draw.Color(0, 255, 0, 255) -- Green for target
        draw.FilledRect(target_pos.x, target_pos.y, target_pos.x, target_pos.y) -- Draw a circle with radius 5
    end
end

-- Register Callbacks
callbacks.Register("CreateMove", CreateMove)
callbacks.Register("Draw", OnDraw)
