-- CONFIGURABLES:
local safe_turn = true

-- ALL VALUES TESTED AT 60 FPS
local yaw_diff = 45 -- chosen for 8 cardinals
-- TODO: Handle initial velocity before charge to recalculate yaw_diff_max (it is a negative correlation)
local yaw_diff_max = 73.04 -- Calculated via testing, max turn before charge breaks (only valid when initially stationary)
local sticky_yaw_margin = 1.16 -- View shift constant, probably tick related
local sticky_yaw_begin = yaw_diff / 2 -- Near the boundaries (+- 180 and 0), it is difficult to change the view angle
local sticky_yaw_end = 180 - sticky_yaw_begin
local move_direction = true

local MOVE_SPEED = 450

--- Issue all movement & view changes via the UserCmd
---@param cmd UserCmd
---@param directionRight boolean  true = strafe right, false = strafe left
---@param pitch number            desired pitch (or 0)
---@param yaw number              desired yaw
---@param roll number             desired roll (or 0)
---@param is_end boolean          if true, stop all movement
---@param do_back boolean         if true, move backwards instead of forwards
local function DoMove(cmd, directionRight, pitch, yaw, roll, is_end, do_back)
	if is_end then
		-- stop all motion
		cmd:SetForwardMove(0)
		cmd:SetSideMove(0)
		return
	end

	-- apply our view angles
	cmd:SetViewAngles(pitch, yaw, roll)

	-- forward/back
	local forward = do_back and -MOVE_SPEED or MOVE_SPEED
	cmd:SetForwardMove(forward)

	-- side‑move
	local side = directionRight and MOVE_SPEED or -MOVE_SPEED
	cmd:SetSideMove(side)
end

local function ChargeTurnCallback(cmd)
	if entities.GetLocalPlayer():InCond(17) then
		gui.SetValue("Auto Strafe", 0)
		pitch, yaw, roll = cmd:GetViewAngles()
		local new_yaw = 0
		local reverse_facing = false -- Unsure if this actually does anything...

		-- TODO: Clamp view angles so we do not auto drift towards +- 180, but this might be unavoidable

		if input.IsButtonDown(KEY_D) then
			move_direction = true
			local ideal_yaw = yaw - yaw_diff -- Uses base turn distance of yaw_diff
			local target_yaw = ideal_yaw -- Will use max turn distance of yaw_diff_max

			if yaw > sticky_yaw_begin then
				target_yaw = -yaw
				if safe_turn and yaw >= yaw_diff_max and yaw <= 180 - yaw_diff_max then -- Ensure the turn will not break immediately (yaw_diff_max should be dynamically calculated)
					if yaw >= 90 then
						target_yaw = -(180 - yaw_diff_max)
					else
						target_yaw = -yaw_diff_max
					end
				end
				reverse_facing = true
			end

			if yaw <= -sticky_yaw_begin + sticky_yaw_margin then
				target_yaw = target_yaw - 360 -- Near +- 180, we can only access other quadrant by overflowing yaw
			end

			new_yaw = target_yaw - sticky_yaw_margin

			DoMove(cmd, move_direction, pitch, new_yaw, roll, false, reverse_facing)
		else
			DoMove(cmd, move_direction, 0, 0, 0, true, reverse_facing)
		end
		if input.IsButtonDown(KEY_A) then
			move_direction = false
			local ideal_yaw = yaw + yaw_diff -- Uses base turn distance of yaw_diff
			local target_yaw = ideal_yaw -- Will use max turn distance of yaw_diff_max

			if yaw < -sticky_yaw_begin then
				target_yaw = math.abs(yaw)
				if safe_turn and yaw >= -(180 - yaw_diff_max) and yaw <= -yaw_diff_max then
					if yaw <= -90 then
						target_yaw = 180 - yaw_diff_max
					else
						target_yaw = yaw_diff_max
					end
				end
				reverse_facing = true
			end

			if yaw >= sticky_yaw_end - sticky_yaw_margin then
				target_yaw = target_yaw + 360
			end

			new_yaw = target_yaw + sticky_yaw_margin

			DoMove(cmd, move_direction, pitch, new_yaw, roll, false, reverse_facing)
		else
			DoMove(cmd, move_direction, 0, 0, 0, true, reverse_facing)
		end
	else
		gui.SetValue("Auto Strafe", 2)
	end
end

callbacks.Register("CreateMove", "ChargeTurnCallback", ChargeTurnCallback)
