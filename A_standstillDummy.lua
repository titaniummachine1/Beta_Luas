--[[
    placeHolder Standstill dummy lua
    keeps standign in same place after loading lua
    Author: titaniummachine1 (github.com/titaniummachine1)
]]

-- Table to store benchmark records
local benchmarkRecords = {}
local MAX_RECORDS = 66

-- Global variables for UI display
AverageMemoryUsage = 0
AverageTimeUsage = 0

-- Local variables for benchmark calculations
local startTime, startMemory

-- Function to start the benchmark
function BenchmarkStart()
	collectgarbage("collect") -- Force a full garbage collection
	startMemory = collectgarbage("count")
	startTime = os.clock()
end

-- Function to stop the benchmark and update the results
function BenchmarkStop()
	local stopTime = os.clock()
	collectgarbage("collect") -- Force a full garbage collection
	local stopMemory = collectgarbage("count")

	local elapsedTime = math.max(stopTime - startTime, 0)
	local memoryDelta = math.abs(stopMemory - startMemory)

	-- Add new record to the beginning of the table
	table.insert(benchmarkRecords, 1, { time = elapsedTime, memory = memoryDelta })

	-- Remove oldest record if we've exceeded MAX_RECORDS
	if #benchmarkRecords > MAX_RECORDS then
		table.remove(benchmarkRecords)
	end

	-- Calculate averages
	local totalTime, totalMemory = 0, 0
	for _, record in ipairs(benchmarkRecords) do
		totalTime = totalTime + record.time
		totalMemory = totalMemory + record.memory
	end

	-- Update global variables for UI display
	AverageTimeUsage = totalTime / #benchmarkRecords
	AverageMemoryUsage = totalMemory / #benchmarkRecords
end

-- Constants
local MAX_SPEED = 450 -- Maximum speed the player can move
local TWO_PI = 2 * math.pi
local DEG_TO_RAD = math.pi / 180

--[[
    Ground-physics helpers (synced with server convars)
]]

local DEFAULT_GROUND_FRICTION = 4 -- fallback for sv_friction
local DEFAULT_SV_ACCELERATE = 10 -- fallback for sv_accelerate

local function GetGroundFriction()
	local ok, val = pcall(client.GetConVar, "sv_friction")
	if ok and val and val > 0 then
		return val
	end
	return DEFAULT_GROUND_FRICTION
end

local function GetGroundMaxDeltaV(player, tick)
	tick = (tick and tick > 0) and tick or 1 / 66.67
	local svA = client.GetConVar("sv_accelerate") or 0
	if svA <= 0 then
		svA = DEFAULT_SV_ACCELERATE
	end

	local cap = player and player:GetPropFloat("m_flMaxspeed") or MAX_SPEED
	if not cap or cap <= 0 then
		cap = MAX_SPEED
	end

	return svA * cap * tick
end

-- Computes the move vector between two points
---@param userCmd UserCmd
---@param a Vector3
---@param b Vector3
---@return Vector3
local function ComputeMove(userCmd, a, b)
	local dx, dy = b.x - a.x, b.y - a.y

	local targetYaw = (math.atan(dy, dx) + TWO_PI) % TWO_PI
	local _, currentYaw = userCmd:GetViewAngles()
	currentYaw = currentYaw * DEG_TO_RAD

	local yawDiff = (targetYaw - currentYaw + math.pi) % TWO_PI - math.pi

	return Vector3(math.cos(yawDiff) * MAX_SPEED, math.sin(-yawDiff) * MAX_SPEED, 0)
end

-- Function to calculate the time needed to stop completely
local function CalculateStopTime(velocity, decelerationPerSecond)
	return velocity / decelerationPerSecond
end

-- Converts time to game ticks
---@param time number
---@return integer
local function Time_to_Ticks(time)
	return math.floor(0.5 + time / globals.TickInterval())
end

-- Function to calculate the number of ticks needed to stop completely
local function CalculateStopTicks(velocity, decelerationPerSecond)
	local stopTime = CalculateStopTime(velocity, decelerationPerSecond)
	return Time_to_Ticks(stopTime)
end

--[[
    Ground-physics helpers (borrowed from SentryRider)
    -------------------------------------------------
    Keep braking rules in sync with server settings so the dummy
    can stop faster without overshooting.
]]

-- Predictive/no-overshoot WalkTo
local function WalkTo(cmd, player, dest)
	if not (cmd and player and dest) then
		return
	end

	local pos = player:GetAbsOrigin()
	if not pos then
		return
	end

	local tick = globals.TickInterval()
	if tick <= 0 then
		tick = 1 / 66.67
	end

	-- Current horizontal velocity (ignore Z)
	local vel = player:EstimateAbsVelocity() or Vector3(0, 0, 0)
	vel.z = 0

	-- Predict passive drag to next tick
	local drag = math.max(0, 1 - GetGroundFriction() * tick)
	local velNext = vel * drag
	local predicted = Vector3(pos.x + velNext.x * tick, pos.y + velNext.y * tick, pos.z)

	-- Remaining displacement after coast
	local need = dest - predicted
	need.z = 0
	local dist = need:Length()
	if dist < 1.5 then
		cmd:SetForwardMove(0)
		cmd:SetSideMove(0)
		return
	end

	-- Velocity we need at start of next tick to land on dest
	local deltaV = (need / tick) - velNext
	local deltaLen = deltaV:Length()
	if deltaLen < 0.1 then
		cmd:SetForwardMove(0)
		cmd:SetSideMove(0)
		return
	end

	-- Accel clamp from sv_accelerate
	local aMax = GetGroundMaxDeltaV(player, tick)
	local accelDir = deltaV / deltaLen
	local accelLen = math.min(deltaLen, aMax)

	-- wishspeed proportional to allowed Δv
	local wishSpeed = math.max(MAX_SPEED * (accelLen / aMax), 20)

	-- Overshoot guard
	local maxNoOvershoot = dist / tick
	wishSpeed = math.min(wishSpeed, maxNoOvershoot)
	if wishSpeed < 5 then
		wishSpeed = 0
	end

	-- Convert accelDir into local move inputs
	local dirEnd = pos + accelDir
	local moveVec = ComputeMove(cmd, pos, dirEnd)
	local fwd = (moveVec.x / MAX_SPEED) * wishSpeed
	local side = (moveVec.y / MAX_SPEED) * wishSpeed

	cmd:SetForwardMove(fwd)
	cmd:SetSideMove(side)
end

--[[           IsWalkable module         ]]
--
--[[       Made and optimized by        ]]
--
--[[         Titaniummachine1           ]]
--
--[[ https://github.com/Titaniummachine1 ]]
--

-- Constants
local pLocal = entities.GetLocalPlayer()
local PLAYER_HULL = { Min = Vector3(-24, -24, 0), Max = Vector3(24, 24, 82) } -- Player collision hull
local MaxSpeed = pLocal:GetPropFloat("m_flMaxspeed") or 450 -- Default to 450 if max speed not available
local gravity = client.GetConVar("sv_gravity") or 800 -- Gravity or default one
local STEP_HEIGHT = pLocal:GetPropFloat("localdata", "m_flStepSize") or 18 -- Maximum height the player can step up
local STEP_HEIGHT_Vector = Vector3(0, 0, STEP_HEIGHT)
local MAX_FALL_DISTANCE = 250 -- Maximum distance the player can fall without taking fall damage
local MAX_FALL_DISTANCE_Vector = Vector3(0, 0, MAX_FALL_DISTANCE)
local STEP_FRACTION = STEP_HEIGHT / MAX_FALL_DISTANCE

local UP_VECTOR = Vector3(0, 0, 1)
local MIN_STEP_SIZE = MaxSpeed * globals.TickInterval() -- Minimum step size to consider for ground checks

local MAX_SURFACE_ANGLE = 45 -- Maximum angle for ground surfaces
local MAX_ITERATIONS = 37 -- Maximum number of iterations to prevent infinite loops

-- Traces tables for debugging
local hullTraces = {}
local lineTraces = {}

-- Helper Functions
local function shouldHitEntity(entity)
	return entity ~= pLocal -- Ignore self (the player being simulated)
end

-- Normalize a vector
local function Normalize(vec)
	return vec / vec:Length()
end

-- Calculate horizontal Manhattan distance between two points
local function getHorizontalManhattanDistance(point1, point2)
	return math.abs(point1.x - point2.x) + math.abs(point1.y - point2.y)
end

-- Perform a hull trace to check for obstructions between two points
local function performTraceHull(startPos, endPos)
	local result =
		engine.TraceHull(startPos, endPos, PLAYER_HULL.Min, PLAYER_HULL.Max, MASK_PLAYERSOLID, shouldHitEntity)
	table.insert(hullTraces, { startPos = startPos, endPos = result.endpos })
	return result
end

-- Adjust the direction vector to align with the surface normal
local function adjustDirectionToSurface(direction, surfaceNormal)
	direction = Normalize(direction)
	local angle = math.deg(math.acos(surfaceNormal:Dot(UP_VECTOR)))

	-- Check if the surface is within the maximum allowed angle for adjustment
	if angle > MAX_SURFACE_ANGLE then
		return direction
	end

	local dotProduct = direction:Dot(surfaceNormal)

	-- Adjust the z component of the direction in place
	direction.z = direction.z - surfaceNormal.z * dotProduct

	-- Normalize the direction after adjustment
	return Normalize(direction)
end

-- Main function to check walkability
local function IsWalkable(startPos, goalPos)
	-- Clear trace tables for debugging
	hullTraces = {}
	lineTraces = {}
	local blocked = false

	-- Initialize variables
	local currentPos = startPos

	-- Adjust start position to ground level
	local startGroundTrace = performTraceHull(startPos + STEP_HEIGHT_Vector, startPos - MAX_FALL_DISTANCE_Vector)

	currentPos = startGroundTrace.endpos

	-- Initial direction towards goal, adjusted for ground normal
	local lastPos = currentPos
	local lastDirection = adjustDirectionToSurface(goalPos - currentPos, startGroundTrace.plane)

	local MaxDistance = getHorizontalManhattanDistance(startPos, goalPos)

	-- Main loop to iterate towards the goal
	for iteration = 1, MAX_ITERATIONS do
		-- Calculate distance to goal and update direction
		local distanceToGoal = (currentPos - goalPos):Length()
		local direction = lastDirection

		-- Calculate next position
		local NextPos = lastPos + direction * distanceToGoal

		-- Forward collision check
		local wallTrace = performTraceHull(lastPos + STEP_HEIGHT_Vector, NextPos + STEP_HEIGHT_Vector)
		currentPos = wallTrace.endpos

		if wallTrace.fraction == 0 then
			blocked = true -- Path is blocked by a wall
		end

		-- Ground collision with segmentation
		local totalDistance = (currentPos - lastPos):Length()
		local numSegments = math.max(1, math.floor(totalDistance / MIN_STEP_SIZE))

		for seg = 1, numSegments do
			local t = seg / numSegments
			local segmentPos = lastPos + (currentPos - lastPos) * t
			local segmentTop = segmentPos + STEP_HEIGHT_Vector
			local segmentBottom = segmentPos - MAX_FALL_DISTANCE_Vector

			local groundTrace = performTraceHull(segmentTop, segmentBottom)

			if groundTrace.fraction == 1 then
				return false -- No ground beneath; path is unwalkable
			end

			if groundTrace.fraction > STEP_FRACTION or seg == numSegments then
				-- Adjust position to ground
				direction = adjustDirectionToSurface(direction, groundTrace.plane)
				currentPos = groundTrace.endpos
				blocked = false
				break
			end
		end

		-- Calculate current horizontal distance to goal
		local currentDistance = getHorizontalManhattanDistance(currentPos, goalPos)
		if blocked or currentDistance > MaxDistance then --if target is unreachable
			return false
		elseif currentDistance < 24 then --within range
			local verticalDist = math.abs(goalPos.z - currentPos.z)
			if verticalDist < 24 then --within vertical range
				return true -- Goal is within reach; path is walkable
			else --unreachable
				return false -- Goal is too far vertically; path is unwalkable
			end
		end

		-- Prepare for the next iteration
		lastPos = currentPos
		lastDirection = direction
	end

	return false -- Max iterations reached without finding a path
end

----------------------------------------------------------------------

local returnVec = entities.GetLocalPlayer():GetAbsOrigin()
local pLocalPos = Vector3()
local PosPlaced = true
local isWalkable = true

local function OnCreateMove(Cmd)
	local pLocal = entities.GetLocalPlayer()
	if not pLocal and pLocal:IsAlive() then
		return
	end
	pLocalPos = pLocal:GetAbsOrigin()

	if input.IsButtonDown(KEY_LSHIFT) then
		returnVec = entities.GetLocalPlayer():GetAbsOrigin()
		PosPlaced = false
	else
		PosPlaced = true
	end

	if Cmd:GetForwardMove() ~= 0 or Cmd:GetSideMove() ~= 0 then
		return
	end --movement bypass

	if PosPlaced and isWalkable then
		WalkTo(Cmd, pLocal, returnVec)
	end
end

local function Draw3DBox(size, pos)
	local halfSize = size / 2
	if not corners then
		corners1 = {
			Vector3(-halfSize, -halfSize, -halfSize),
			Vector3(halfSize, -halfSize, -halfSize),
			Vector3(halfSize, halfSize, -halfSize),
			Vector3(-halfSize, halfSize, -halfSize),
			Vector3(-halfSize, -halfSize, halfSize),
			Vector3(halfSize, -halfSize, halfSize),
			Vector3(halfSize, halfSize, halfSize),
			Vector3(-halfSize, halfSize, halfSize),
		}
	end

	local linesToDraw = {
		{ 1, 2 },
		{ 2, 3 },
		{ 3, 4 },
		{ 4, 1 },
		{ 5, 6 },
		{ 6, 7 },
		{ 7, 8 },
		{ 8, 5 },
		{ 1, 5 },
		{ 2, 6 },
		{ 3, 7 },
		{ 4, 8 },
	}

	local screenPositions = {}
	for _, cornerPos in ipairs(corners1) do
		local worldPos = pos + cornerPos
		local screenPos = client.WorldToScreen(worldPos)
		if screenPos then
			table.insert(screenPositions, { x = screenPos[1], y = screenPos[2] })
		end
	end

	for _, line in ipairs(linesToDraw) do
		local p1, p2 = screenPositions[line[1]], screenPositions[line[2]]
		if p1 and p2 then
			draw.Line(p1.x, p1.y, p2.x, p2.y)
		end
	end
end

local function ArrowLine(start_pos, end_pos, arrowhead_length, arrowhead_width, invert)
	if not (start_pos and end_pos) then
		return
	end

	-- If invert is true, swap start_pos and end_pos
	if invert then
		start_pos, end_pos = end_pos, start_pos
	end

	-- Calculate direction from start to end
	local direction = end_pos - start_pos

	-- Check if arrow size is too small (compared to a threshold or minimum length)
	local min_acceptable_length = arrowhead_length + (arrowhead_width / 2)
	if direction:Length() < min_acceptable_length then
		-- Draw a regular line if arrow size is too small
		local w2s_start, w2s_end = client.WorldToScreen(start_pos), client.WorldToScreen(end_pos)
		if not (w2s_start and w2s_end) then
			return
		end
		draw.Line(w2s_start[1], w2s_start[2], w2s_end[1], w2s_end[2])
		return
	end

	-- Normalize the direction vector
	local normalized_direction = Normalize(direction)

	-- Calculate the arrow base position by moving back from end_pos in the direction of start_pos
	local arrow_base = end_pos - normalized_direction * arrowhead_length

	-- Calculate the perpendicular vector for the arrow width
	local perpendicular = Vector3(-normalized_direction.y, normalized_direction.x, 0) * (arrowhead_width / 2)

	-- Convert world positions to screen positions
	local w2s_start, w2s_end = client.WorldToScreen(start_pos), client.WorldToScreen(end_pos)
	local w2s_arrow_base = client.WorldToScreen(arrow_base)
	local w2s_perp1 = client.WorldToScreen(arrow_base + perpendicular)
	local w2s_perp2 = client.WorldToScreen(arrow_base - perpendicular)

	if not (w2s_start and w2s_end and w2s_arrow_base and w2s_perp1 and w2s_perp2) then
		return
	end

	-- Draw the line from start to the base of the arrow (not all the way to the end)
	draw.Line(w2s_start[1], w2s_start[2], w2s_arrow_base[1], w2s_arrow_base[2])

	-- Draw the sides of the arrowhead
	draw.Line(w2s_end[1], w2s_end[2], w2s_perp1[1], w2s_perp1[2])
	draw.Line(w2s_end[1], w2s_end[2], w2s_perp2[1], w2s_perp2[2])

	-- Optionally, draw the base of the arrowhead to close it
	draw.Line(w2s_perp1[1], w2s_perp1[2], w2s_perp2[1], w2s_perp2[2])
end

local Fonts = { Verdana = draw.CreateFont("Verdana", 14, 510) }
local function doDraw()
	if not (engine.Con_IsVisible() or engine.IsGameUIVisible()) then
		draw.SetFont(Fonts.Verdana)
		draw.Color(255, 255, 255, 255)
		Draw3DBox(10, returnVec)
		if (pLocalPos - returnVec):Length() > 10 then
			BenchmarkStart()
			isWalkable = IsWalkable(pLocalPos, returnVec)
			BenchmarkStop()
			if isWalkable then
				draw.Color(0, 255, 0, 255)
			else
				draw.Color(255, 0, 0, 255)
			end
			ArrowLine(pLocalPos, returnVec, 10, 20, false)
		end

		draw.Color(255, 255, 255, 255)

		draw.Text(20, 120, string.format("Memory usage: %.2f KB", AverageMemoryUsage))
		draw.Text(20, 150, string.format("Time usage: %.2f ms", AverageTimeUsage * 1000))

		-- Draw all line traces
		for _, trace in ipairs(lineTraces) do
			draw.Color(255, 255, 255, 255) -- White for line traces
			local w2s_start, w2s_end = client.WorldToScreen(trace.startPos), client.WorldToScreen(trace.endPos)
			if w2s_start and w2s_end then
				draw.Line(w2s_start[1], w2s_start[2], w2s_end[1], w2s_end[2])
			end
		end

		-- Draw all hull traces
		for _, trace in ipairs(hullTraces) do
			draw.Color(0, 50, 255, 255) -- Blue for hull traces
			ArrowLine(trace.startPos, trace.endPos - Vector3(0, 0, 0.5), 10, 20, false)
		end
	end
end

callbacks.Unregister("CreateMove", "AP_CreateMove")
callbacks.Register("CreateMove", "AP_CreateMove", OnCreateMove)

callbacks.Unregister("Draw", "Ssd_Draw") -- Unregister the "Draw" callback
callbacks.Register("Draw", "Ssd_Draw", doDraw) -- Register the "Draw" callback

client.Command('play "ui/buttonclick"', true)
