--[[
    ═══════════════════════════════════════════════════════════════════════════════
    SENTRY RIDER - Automated Sentry Positioning Script
    ═══════════════════════════════════════════════════════════════════════════════

    CORE CONCEPT:
    Position player 66 units above sentry, 24 units behind where it's aiming.
    This exploits TF2's sentry targeting mechanics - sentries can't target what's
    directly on top of them, creating a safe riding zone.

    ═══════════════════════════════════════════════════════════════════════════════
    PROGRAMMING ARCHITECTURE:
    ═══════════════════════════════════════════════════════════════════════════════

    1. SENTRY AIM DETECTION (Level-Agnostic):
       ┌─────────────────────────────────────────────────────────────────────────┐
       │ • Use level-specific back hitboxes to determine facing direction        │
       │ • Level 1/Mini: Hitbox 9 = back bone                                   │
       │ • Level 2: Hitbox 23 = back structure                                  │
       │ • Level 3: Hitbox 22 = back structure                                  │
       │ • Calculate direction for "behind sentry" positioning                  │
       └─────────────────────────────────────────────────────────────────────────┘

    2. DYNAMIC HITBOX CALCULATION (Mainly Mini-Sentries):
       ┌─────────────────────────────────────────────────────────────────────────┐
       │ • Regular sentries have consistent 48x48 footprint                     │
       │ • Mini-sentries are smaller and need precise calculation               │
       │ • Calculate safe walking area: sentry size + player hitbox + diagonal  │
       │ • Prevents falling off edges during movement                           │
       └─────────────────────────────────────────────────────────────────────────┘

    3. SMART INPUT DETECTION (Local Space Vector Analysis):
       ┌─────────────────────────────────────────────────────────────────────────┐
       │ • Convert player WASD input to local space vector                      │
       │ • Convert script target direction to same local space                  │
       │ • Calculate angle between vectors using dot product                    │
       │ • < 60° = small correction, continue riding                            │
       │ • > 60° = clear intent to leave, disengage script                      │
       └─────────────────────────────────────────────────────────────────────────┘

    4. PROTECTION PERIOD (Anti-Slip Mechanism):
       ┌─────────────────────────────────────────────────────────────────────────┐
       │ • First 22 ticks after mounting: ignore all manual input               │
       │ • Prevents accidental disengagement from residual movement             │
       │ • After 22 ticks: respect player movement intentions                   │
       └─────────────────────────────────────────────────────────────────────────┘

    5. SMOOTH MOVEMENT PHYSICS (TF2-Aware Pathfinding):
       ┌─────────────────────────────────────────────────────────────────────────┐
       │ • Calculate deceleration distance based on current velocity            │
       │ • Far from target: full speed movement                                 │
       │ • Near target: gradual deceleration for precise positioning            │
       │ • Uses TF2's ground acceleration constant (84 units/sec²)              │
       └─────────────────────────────────────────────────────────────────────────┘

    ═══════════════════════════════════════════════════════════════════════════════
    EXECUTION FLOW:
    ═══════════════════════════════════════════════════════════════════════════════

    OnCreateMove() → Dead Check → Find Sentries → Select Best → Update AABB →
    Check Zones → Handle Input Conflicts → Apply Movement → Repeat

    OnDraw() → Dead Check → Display Status → Draw Visual Indicators → Repeat

    ═══════════════════════════════════════════════════════════════════════════════
    WHY THIS APPROACH WORKS:
    ═══════════════════════════════════════════════════════════════════════════════

    • LEVEL-AGNOSTIC: Uses actual hitbox data instead of hardcoded offsets
    • RESPONSIVE: Local space input detection allows precise control
    • SAFE: Protection period prevents accidental falls
    • SMOOTH: Physics-aware movement provides natural feel
    • MINIMAL: Only calculates AABB for mini-sentries (others use standard 48x48)
    • ROBUST: Multiple fallback methods for sentry detection and aim calculation

    Based on standstill dummy script
    Author: titaniummachine1 (github.com/titaniummachine1)
]]

-- Movement and detection constants
local TWO_PI = 2 * math.pi
local DEG_TO_RAD = math.pi / 180

-- Default upper-bound for movement speed. Real cap will be
-- pulled dynamically from the player entity each tick.
local DEFAULT_MAX_SPEED = 450 -- Scout speed / Source hard-limit

-- When crouched, Source clamps speed to roughly 33% of normal.
-- This constant lets WalkTo honour that restriction explicitly.
local DUCK_SPEED_MULT = 0.33

-- Sentry positioning configuration
local RIDE_DISTANCE = 24 -- How far behind sentry to position
local SENTRY_AABB_SIZE = 48 -- Radius around sentry where we actively ride (dynamically updated for mini-sentries)

-- Player hitbox constants (from TF2: 24,24,82)
local PLAYER_HITBOX_HALF_WIDTH = 24 -- Half width of player (x and y)

-- Debug settings
local ENABLE_DEBUG = true
local ENABLE_VISUALS = true

-- Separate switch for console spam so overlay can stay on
local ENABLE_DEBUG_PRINTS = false

-- Global state variables
local targetRidePosition = nil
local activeSentry = nil
local ridingStartTick = 0
local PROTECTION_TICKS = 22 -- Ignore manual input for this many ticks after starting to ride

-- Safety margin added around calculated radius (tweak if falling off)
local SAFETY_MARGIN = 8

-- Extra buffer (units) beyond riding zone used for initial activation detection
local ACTIVATE_BUFFER = 24

-- Player flag constants (partial)
local FL_DUCKING = _G.FL_DUCKING or 2 -- Player is ducking/crouched (Source engine); fallback to 2

-- Forward declaration so WalkTo can reference it safely
local IsPlayerDucking

-- Converts seconds to game ticks (helper placed here so WalkTo sees it)
local function Time_to_Ticks(timeSec)
	return math.floor(0.5 + timeSec / globals.TickInterval())
end

--[[
    DYNAMIC SPEED / ACCELERATION HELPERS
    -----------------------------------
    These remove hard-coded "magic" values so the script honours
    class, weapon or server modifiers automatically.

    • GetMaxAllowedSpeed( player )
        – Reads m_flMaxSpeed (updated every frame by the engine).
        – Falls back to DEFAULT_MAX_SPEED when unavailable.

    • GetGroundAccelPerSecond()
        – Uses default 84 uu/s² unless we can query a convar
          (sv_accelerate * 10.5 ≈ uu/s² in TF2). For simplicity
          we keep the constant but centralise it here so it's not
          sprinkled through the code.
]]

local function GetMaxAllowedSpeed(p)
	if not p then
		return DEFAULT_MAX_SPEED
	end
	local ok, speed = pcall(function()
		return p:GetPropFloat("m_flMaxSpeed")
	end)
	if ok and speed and speed > 0 then
		-- m_flMaxSpeed is already clamped by the engine (Scoped Sniper = 80, Heavy = 230, etc.)
		return math.min(speed, DEFAULT_MAX_SPEED)
	end
	return DEFAULT_MAX_SPEED
end

-- Default friction (drag) constant – tf2 uses sv_friction (4 by default).
local DEFAULT_GROUND_FRICTION = 4

-- Default for sv_accelerate (10 on most TF2 servers). See forums/alliedmods & valve wiki.
local DEFAULT_SV_ACCELERATE = 10

local function GetGroundFriction()
	-- Try to read sv_friction, fall back to default.
	local ok, val = pcall(function()
		if engine and engine.GetConVarFloat then
			return engine.GetConVarFloat("sv_friction")
		end
	end)
	if ok and val and val > 0 then
		return val
	end
	return DEFAULT_GROUND_FRICTION
end

--[[
	Returns the *maximum horizontal velocity change* (Δv) we can legally add this
	frame, mirroring the Source "Accelerate" routine where:
		Δv = sv_accelerate * wishspeed * tick
	We approximate wishspeed using the player's class-capped run speed.
	This makes the script respect custom server settings (bhop, surf, etc.).
]]
local function GetGroundMaxDeltaV(player, tickInt)
	tickInt = tickInt or globals.TickInterval()
	if tickInt <= 0 then
		tickInt = 1 / 66.67
	end

	-- sv_accelerate (server cvar) – fall back to default when we cannot query.
	local svAccel = DEFAULT_SV_ACCELERATE
	local ok, val = pcall(function()
		if engine and engine.GetConVarFloat then
			return engine.GetConVarFloat("sv_accelerate")
		end
	end)
	if ok and val and val > 0 then
		svAccel = val
	end

	local wishSpeed = GetMaxAllowedSpeed(player)
	return svAccel * wishSpeed * tickInt -- units/sec added this frame (Δv)
end

--[[
    MOVEMENT UTILITY HELPERS
    ------------------------
    These helpers abstract angle→movement math so future path-finding or
    acceleration tweaks can replace WalkTo() without touching the low-level
    WASD conversion.
]]

-- Converts a world-space direction (from src → dst) into local forward/side
-- components relative to the player's current view yaw (in radians).
-- Returns a *normalized* 2-D vector (length = 1) where:
--   x = forward  (+forward, -back)
--   y = side     (+right,   -left)
local function WorldDirToLocalInput(srcPos, dstPos, viewYawRad)
	local dx, dy = dstPos.x - srcPos.x, dstPos.y - srcPos.y

	-- IDIOT-PROOF: Check if we're already at destination
	if math.abs(dx) < 0.01 and math.abs(dy) < 0.01 then
		return 0, 0 -- Already there
	end

	-- World direction → yaw angle (0..2π)
	local targetYaw = (math.atan(dy, dx) + TWO_PI) % TWO_PI

	-- IDIOT-PROOF: Normalize view yaw to 0..2π range
	viewYawRad = (viewYawRad + TWO_PI) % TWO_PI

	-- Shortest angular delta between where we look and where we want to go
	local yawDiff = (targetYaw - viewYawRad + math.pi) % TWO_PI - math.pi

	-- Map angle delta to forward/side inputs (unit circle)
	local fwd = math.cos(yawDiff) -- forward component
	local side = -math.sin(yawDiff) -- side component (negated to match TF2 right-handed coords)

	-- IDIOT-PROOF: Ensure we always return normalized vector
	local len = math.sqrt(fwd * fwd + side * side)
	if len < 0.001 then -- Avoid division by zero
		return 0, 0
	end
	return fwd / len, side / len
end

-- Scales normalized input vector by desired speed and writes to usercmd
local function ApplyMovement(cmd, fwdNorm, sideNorm, speed)
	-- IDIOT-PROOF: ensure finite numbers then write to usercmd
	if not speed or speed ~= speed then
		speed = 0
	end
	-- Clamp to ±DEFAULT_MAX_SPEED (engine will apply its own rules afterwards)
	speed = math.max(-DEFAULT_MAX_SPEED, math.min(speed, DEFAULT_MAX_SPEED))

	-- IDIOT-PROOF: Clamp input values to prevent weird behavior
	fwdNorm = math.max(-1, math.min(1, fwdNorm or 0))
	sideNorm = math.max(-1, math.min(1, sideNorm or 0))

	cmd:SetForwardMove(fwdNorm * speed)
	cmd:SetSideMove(sideNorm * speed)
end

--[[
    SMOOTH WALKING ALGORITHM (Refactored & Idiot-Proofed)
    -------------------------------------
    1. Convert desired world direction into local movement inputs.
    2. Decide target speed based on distance vs. stop distance.
    3. Apply scaled movement.
]]
local function WalkTo(cmd, player, destination)
	-- IDIOT-PROOF: Validate inputs
	if not cmd or not player or not destination then
		return
	end

	local pos = player:GetAbsOrigin()
	if not pos then
		return
	end

	-- ==== ONE-TICK PHYSICS PREVIEW =================================================
	local tickInt = globals.TickInterval()
	if tickInt <= 0 then
		tickInt = 1 / 66.67 -- Fallback to common tick interval
	end

	-- Current horizontal velocity (ignore Z for ground movement)
	local vel = player:EstimateAbsVelocity() or Vector3(0, 0, 0)
	vel.z = 0

	-- Passive drag the engine applies while on ground this frame
	local friction = GetGroundFriction()
	local dragFactor = math.max(0, 1 - friction * tickInt)

	local velNext = vel * dragFactor -- velocity the engine will carry into next tick
	local predictedPos = Vector3(pos.x + velNext.x * tickInt, pos.y + velNext.y * tickInt, pos.z)

	-- Delta we *still* need after that free coast
	local needVec = destination - predictedPos
	needVec.z = 0
	local dist = needVec:Length()

	-- Close enough?  Stop all input.
	if dist < 1.5 then
		ApplyMovement(cmd, 0, 0, 0)
		return
	end

	-- Velocity we must be at *start of next tick* to land exactly on the destination
	local vTarget = needVec / tickInt

	-- How much we have to change our current (coasted) velocity by this frame
	local deltaV = vTarget - velNext
	local deltaLen = deltaV:Length()
	if deltaLen < 0.1 then -- negligible
		ApplyMovement(cmd, 0, 0, 0)
		return
	end

	-- Maximum horizontal speed change Source lets us add in one frame (respect sv_accelerate)
	local aMax = GetGroundMaxDeltaV(player, tickInt)

	-- Choose how hard we can push this tick
	local accelDir = deltaV / deltaLen -- normalised desired acceleration direction
	local accelLen = math.min(deltaLen, aMax) -- full or clamped

	-- Store for debug drawing (convert to positional offset per tick for clarity)
	debugAccelVec = accelDir * (accelLen * tickInt) -- real units per tick

	-- ==== TRANSLATE ACCELERATION → USERCMD INPUT ===================================
	-- We approximate that wishspeed proportional to desired Δv within [0, maxSpeed]
	local maxSpeed = GetMaxAllowedSpeed(player)
	-- Respect crouch speed penalty if the player is currently ducking (safe call)
	local isDuck = IsPlayerDucking and IsPlayerDucking(player)
	if isDuck then
		maxSpeed = maxSpeed * DUCK_SPEED_MULT
	end
	local speedFraction = accelLen / aMax -- 0..1 when inside budget, 1 when clamped

	-- Initial wish speed based on required Δv
	local wishSpeed = math.max(maxSpeed * speedFraction, 20)

	-- GUARANTEED NO-OVERSHOOT ----------------------------------------------------
	-- If our plain-English goal is "worst case we land *on* the spot, never past
	-- it", then the horizontal distance we can safely cover this frame is exactly
	-- `dist` (how far the *predicted* coast point is from the target).  Any faster
	-- and we risk stepping over the destination when the engine integrates
	-- velocity → position.

	local maxNoOvershoot = dist / tickInt -- uu/sec that arrives *exactly* on point
	wishSpeed = math.min(wishSpeed, maxNoOvershoot)

	-- Optional tiny floor so friction doesn't stall us completely when we're
	-- basically there, but still respects the no-overshoot rule.
	if wishSpeed < 5 then
		wishSpeed = 0
	end

	-- Convert world-space accelDir into local forward / side for WASD
	local _, viewYawDeg = cmd:GetViewAngles()
	local viewYawRad = (viewYawDeg or 0) * DEG_TO_RAD

	-- Re-use helper but pass a pseudo-destination so it returns direction of accelDir
	local pseudoDst = Vector3(accelDir.x, accelDir.y, 0) -- relative direction only
	local fwdNorm, sideNorm = WorldDirToLocalInput(Vector3(0, 0, 0), pseudoDst, viewYawRad)

	ApplyMovement(cmd, fwdNorm, sideNorm, wishSpeed)

	-- ==== PREDICTION ERROR & DEBUG ==================================================
	if lastPredictedPos then
		local errVec = pos - lastPredictedPos
		debugPredictionError = errVec
		if ENABLE_DEBUG_PRINTS and activeSentry then
			print(string.format("[SentryRider] Prediction error: Δx=%.1f Δy=%.1f", errVec.x, errVec.y))
		end
	end
	lastPredictedPos = predictedPos

	-- ==== DEBUG PRINTS =============================================================
	if ENABLE_DEBUG_PRINTS and activeSentry then
		print(
			string.format(
				"[SentryRider] Δv=%.2f aMax=%.2f speed=%.1f fwd=%.2f side=%.2f dist=%.2f",
				deltaLen,
				aMax,
				wishSpeed,
				fwdNorm,
				sideNorm,
				dist
			)
		)
	end
end

--[[
    DECELERATION PHYSICS
    TF2 has specific deceleration mechanics - we need to calculate when to start
    slowing down to stop precisely at the target position
]]
local function CalculateStopTime(velocity, decelerationPerSecond)
	return velocity / math.max(decelerationPerSecond, 1) -- Prevent division by zero
end

local function CalculateStopTicks(velocity, decelerationPerSecond)
	local stopTime = CalculateStopTime(velocity, decelerationPerSecond)
	return Time_to_Ticks(stopTime)
end

-- Vector normalization utility (IDIOT-PROOFED)
local function normalize(v)
	local len = v:Length()
	if len < 0.001 then -- Avoid division by zero
		return Vector3(0, 0, 0)
	end
	return v / len
end

--[[
    SENTRY AABB DETECTION

    PRINCIPLE: Get min/max bounds using proper API method

    Uses the hitbox surrounding box method that returns table of Vector3 mins and maxs
    directly from the entity - no manual calculation needed.
]]
local function getSentryHitbox(sentry)
	if not sentry or not sentry:IsValid() then
		return nil, nil
	end

	-- METHOD 1: Use hitbox surrounding box API (most accurate)
	local ok, bounds = pcall(function()
		return sentry:GetHitboxSurroundingBox()
	end)
	if ok and bounds and bounds[1] and bounds[2] then
		return bounds[1], bounds[2] -- mins, maxs
	end

	-- METHOD 2: Try alternative surrounding box methods
	local methods = {
		"GetSurroundingBox",
		"GetBoundingBox",
		"GetHitboxBounds",
	}

	for _, method in ipairs(methods) do
		local ok, bounds = pcall(function()
			return sentry[method](sentry)
		end)
		if ok and bounds and bounds[1] and bounds[2] then
			return bounds[1], bounds[2] -- mins, maxs
		end
	end

	-- METHOD 3: Try entity collision properties
	local propPairs = {
		{ "m_vecMins", "m_vecMaxs" },
		{ "m_Collision.m_vecMins", "m_Collision.m_vecMaxs" },
		{ "localdata.m_vecMins", "localdata.m_vecMaxs" },
	}

	for _, pair in ipairs(propPairs) do
		local minProp, maxProp = pair[1], pair[2]
		local ok1, minVec = pcall(function()
			return sentry:GetPropVector(minProp)
		end)
		local ok2, maxVec = pcall(function()
			return sentry:GetPropVector(maxProp)
		end)

		if ok1 and ok2 and minVec and maxVec then
			return minVec, maxVec
		end
	end

	-- METHOD 4: Default sentry AABB (48x48x64 units)
	return Vector3(-24, -24, 0), Vector3(24, 24, 64)
end

--[[
    SAFE WALKING AREA CALCULATION

    PRINCIPLE: Calculate how much area we have to walk on top of sentry
    without falling off

    MATH:
    - Add player hitbox to sentry dimensions
    - Account for diagonal movement (multiply by √2 ≈ 1.414)
    - This ensures player never falls off edges
]]
local function calculateSafeWalkingArea(sentry)
	local minBounds, maxBounds = getSentryHitbox(sentry)
	if not minBounds or not maxBounds then
		return 48 -- fallback
	end

	-- Horizontal extents
	local width = math.abs(maxBounds.x - minBounds.x)
	local depth = math.abs(maxBounds.y - minBounds.y)

	-- Half-size of square footprint
	local halfExtent = math.max(width, depth) * 0.5

	-- Add player half-width and safety margin so feet stay on
	local safeRadius = halfExtent + PLAYER_HITBOX_HALF_WIDTH + SAFETY_MARGIN

	-- Clamp
	safeRadius = math.max(24, math.min(safeRadius, 128))
	return math.floor(safeRadius)
end

--[[
    SENTRY LEVEL DETECTION

    PURPOSE: Different sentry levels have different hitbox layouts
    Level 1/Mini: Hitbox 9 = back
    Level 2: Hitbox 23 = back
    Level 3: Hitbox 22 = back

    FALLBACK: Try multiple property names, then model detection
]]
local function getSentryLevel(sentry)
	if not sentry or not sentry:IsValid() then
		return 1
	end

	-- Try various level properties
	local levelProps = {
		"m_iUpgradeLevel",
		"m_iUpgradeMetal",
		"m_iState",
		"m_nUpgradeLevel",
	}

	for _, prop in pairs(levelProps) do
		local ok, level = pcall(function()
			return sentry:GetPropInt(prop)
		end)
		if ok and level and level >= 1 and level <= 3 then
			if ENABLE_DEBUG then
				print(string.format("[SentryRider] Detected sentry level %d via property %s", level, prop))
			end
			return level
		end
	end

	-- Fallback: detect by model name
	local model = sentry:GetModel()
	if model then
		if string.find(model:lower(), "mini") then
			if ENABLE_DEBUG then
				print("[SentryRider] Detected mini-sentry via model name")
			end
			return 0 -- Mini-sentry
		elseif string.find(model:lower(), "level3") or string.find(model:lower(), "lvl3") then
			if ENABLE_DEBUG then
				print("[SentryRider] Detected level 3 sentry via model name")
			end
			return 3
		elseif string.find(model:lower(), "level2") or string.find(model:lower(), "lvl2") then
			if ENABLE_DEBUG then
				print("[SentryRider] Detected level 2 sentry via model name")
			end
			return 2
		end
	end

	if ENABLE_DEBUG then
		print("[SentryRider] Defaulting to level 1 sentry (no detection method worked)")
	end
	return 1 -- Default to level 1
end

--[[
    DYNAMIC AABB UPDATES

    PURPOSE: Only mini-sentries really need dynamic calculation
    Regular sentries have consistent 48x48 footprint

    WHY: Mini-sentries are smaller and need precise positioning
]]
local function updateSentryAABB(sentry)
	-- Recalculate safe radius for every sentry type so the riding zone always matches the real hitbox
	local newSize = calculateSafeWalkingArea(sentry)
	if newSize ~= SENTRY_AABB_SIZE then
		SENTRY_AABB_SIZE = newSize
	end
end

--[UNUSED FUNCTION - kept for potential future use]
local function getBarrelPosition(sentry)
	local hitboxes = sentry:GetHitboxes()
	if not hitboxes then
		local origin = sentry:GetAbsOrigin()
		local angles = sentry:GetAbsAngles()
		if angles then
			local forward = angles:Forward()
			return origin + (forward * 40)
		end
		return origin
	end

	local level = getSentryLevel(sentry)
	local barrelHitboxIndex = 5 -- Default for level 1 and mini

	if level == 2 then
		barrelHitboxIndex = 23
	elseif level == 3 then
		barrelHitboxIndex = 22
	elseif level == 0 then -- Mini-sentry
		barrelHitboxIndex = 5
	else -- Level 1
		barrelHitboxIndex = 5
	end

	if hitboxes[barrelHitboxIndex] then
		return (hitboxes[barrelHitboxIndex][1] + hitboxes[barrelHitboxIndex][2]) * 0.5
	end

	if hitboxes[5] then
		return (hitboxes[5][1] + hitboxes[5][2]) * 0.5
	end

	local origin = sentry:GetAbsOrigin()
	local angles = sentry:GetAbsAngles()
	if angles then
		local forward = angles:Forward()
		return origin + (forward * 40)
	end

	return origin
end

--[[
    SENTRY AIM DIRECTION DETECTION

    CORE PRINCIPLE: Use back hitbox to determine where sentry is facing

    WHY THIS WORKS:
    - Each sentry level has a "back" hitbox that moves with turret rotation
    - Vector from origin to back hitbox = back direction
    - Opposite of back direction = front/aim direction
    - This works regardless of sentry level without complex offsets

    HITBOX MAPPING:
    - Level 1 & Mini: Hitbox 9 = back bone
    - Level 2: Hitbox 23 = back structure
    - Level 3: Hitbox 22 = back structure
]]
local function getSentryAimAngles(sentry)
	local sentryOrigin = sentry:GetAbsOrigin()
	local hitboxes = sentry:GetHitboxes()
	local level = getSentryLevel(sentry)

	-- Map sentry level to back hitbox ID
	local backHitboxIndex = 9 -- Default for level 1 and mini-sentry
	if level == 2 then
		backHitboxIndex = 23 -- Level 2 back hitbox
	elseif level == 3 then
		backHitboxIndex = 22 -- Level 3 back hitbox
	elseif level == 0 then -- Mini-sentry
		backHitboxIndex = 9 -- Mini back hitbox (confirmed by user)
	else -- Level 1
		backHitboxIndex = 9 -- Level 1 back hitbox
	end

	-- Use back hitbox to determine sentry facing direction
	if hitboxes and hitboxes[backHitboxIndex] then
		local backHitbox = hitboxes[backHitboxIndex]
		local backCenter = (backHitbox[1] + backHitbox[2]) * 0.5

		-- Calculate vector from origin to back hitbox
		local dx = backCenter.x - sentryOrigin.x
		local dy = backCenter.y - sentryOrigin.y

		-- Only proceed if there's meaningful directional data
		if math.abs(dx) > 0.1 or math.abs(dy) > 0.1 then
			-- Back direction = direction from origin to back hitbox
			local backYaw = math.deg(math.atan(dy, dx))
			-- Front/aim direction = opposite of back direction
			local frontYaw = (backYaw + 180) % 360

			if ENABLE_DEBUG then
				print(
					string.format(
						"[SentryRider] Level %d using hitbox %d - Back yaw: %.1f, Front/Aim yaw: %.1f",
						level,
						backHitboxIndex,
						backYaw,
						frontYaw
					)
				)
			end

			return EulerAngles(0, frontYaw, 0)
		end
	end

	if ENABLE_DEBUG then
		print(string.format("[SentryRider] Hitbox method failed for level %d sentry, trying fallbacks", level))
	end

	-- FINAL FALLBACK: Use entity base angles
	local angles = sentry:GetAbsAngles()
	if ENABLE_DEBUG then
		if angles then
			print(string.format("[SentryRider] Using entity base angles: yaw=%.1f", angles.y))
		else
			print("[SentryRider] All angle detection methods failed!")
		end
	end
	return angles and EulerAngles(angles.x, angles.y, 0) or EulerAngles(0, 0, 0)
end

--[[
    TEAM DETECTION

    PURPOSE: Ensure we only target enemy sentries, not friendly ones

    WHY: You don't want to ride your own team's sentries, only enemy ones
    that are actually threatening you
]]
local function isEnemySentry(sentry, localPlayer)
	if not sentry or not sentry:IsValid() or not localPlayer then
		return false
	end

	-- Get team indices
	local playerTeam = localPlayer:GetTeamNumber()
	local sentryTeam = sentry:GetTeamNumber()

	-- Only target sentries from opposing team
	local isEnemy = playerTeam ~= sentryTeam

	if ENABLE_DEBUG and isEnemy then
		local teamNames = { [2] = "RED", [3] = "BLU" }
		print(
			string.format(
				"[SentryRider] Found enemy sentry - Player: %s, Sentry: %s",
				teamNames[playerTeam] or "UNKNOWN",
				teamNames[sentryTeam] or "UNKNOWN"
			)
		)
	end

	return isEnemy
end

--[[
    SENTRY DISCOVERY

    PURPOSE: Find all active ENEMY sentries on the map
    Uses multiple class names as fallback since different game modes
    might use slightly different entity names

    IMPORTANT: Only returns enemy sentries - filters out friendly ones
]]
local function findAllSentries()
	local pLocal = entities.GetLocalPlayer()
	if not pLocal then
		return {}
	end

	local sentries = {}

	-- Primary method: standard TF2 sentry class
	local found = entities.FindByClass("CObjectSentrygun")
	for _, sentry in pairs(found) do
		if sentry:IsValid() and not sentry:IsDormant() and isEnemySentry(sentry, pLocal) then
			table.insert(sentries, sentry)
		end
	end

	-- Backup: try alternative class names (different servers/mods)
	if #sentries == 0 then
		local classCandidates = {
			"CObjectSentryGun",
			"C_ObjectSentrygun",
			"C_ObjectSentryGun",
			"obj_sentrygun",
			"obj_sentry",
		}

		for _, name in ipairs(classCandidates) do
			local ents = entities.FindByClass(name)
			for _, ent in ipairs(ents) do
				if ent:IsValid() and not ent:IsDormant() and isEnemySentry(ent, pLocal) then
					-- Prevent duplicates
					local duplicate = false
					for _, existing in ipairs(sentries) do
						if existing == ent then
							duplicate = true
							break
						end
					end
					if not duplicate then
						table.insert(sentries, ent)
					end
				end
			end
		end
	end

	return sentries
end

--[[
    RIDE POSITION CALCULATION

    CORE ALGORITHM:
    1. Get sentry's aim direction using back hitbox method
    2. Calculate opposite direction (behind sentry)
    3. Position player 24 units behind, 66 units above

    WHY 66 UNITS UP: This positions player on top of sentry hitbox
    WHY 24 UNITS BACK: Safe distance to avoid sentry's rotation radius
]]
local function calculateRidePosition(sentry)
	local sentryPos = sentry:GetAbsOrigin()
	local aimAngles = getSentryAimAngles(sentry)

	-- Get sentry's forward direction vector
	local forward = aimAngles:Forward()

	-- Calculate behind direction (opposite of forward)
	local behind = Vector3(-forward.x, -forward.y, 0) -- Keep Z=0 for horizontal movement
	behind = normalize(behind)

	-- Position behind sentry at safe distance
	local ridePos = sentryPos + (behind * RIDE_DISTANCE)

	-- Elevate to ride on top of sentry (66 units above origin)
	ridePos.z = sentryPos.z + 66

	return ridePos
end

--[[
    AREA DETECTION FUNCTIONS

    PURPOSE: Define zones where script should activate

    isInSentryArea: Initial detection zone (larger, looser requirements)
    isInRidingZone: Active riding zone (smaller, precise requirements)

    HEIGHT REQUIREMENTS:
    - Must be 53-79 units above sentry (riding height range)
    - This ensures player is actually on top of sentry
]]
local function isInSentryArea(playerPos, sentryPos)
	-- Check height: player must be riding on top of sentry
	local heightDiff = playerPos.z - sentryPos.z
	if heightDiff < 56 or heightDiff > 76 then
		return false -- Not at riding height
	end

	-- Axis-aligned square check with buffer
	local dx = math.abs(playerPos.x - sentryPos.x)
	local dy = math.abs(playerPos.y - sentryPos.y)
	local halfSize = SENTRY_AABB_SIZE + ACTIVATE_BUFFER
	return dx <= halfSize and dy <= halfSize
end

local function isInRidingZone(playerPos, sentryPos)
	-- Stricter height requirements for active riding
	local heightDiff = playerPos.z - sentryPos.z
	if heightDiff < 53 or heightDiff > 79 then
		return false -- Not at precise riding height
	end

	-- Square AABB check using SENTRY_AABB_SIZE
	local dx = math.abs(playerPos.x - sentryPos.x)
	local dy = math.abs(playerPos.y - sentryPos.y)
	return dx <= SENTRY_AABB_SIZE and dy <= SENTRY_AABB_SIZE
end

--[[
    MANUAL INPUT CONFLICT DETECTION

    PRINCIPLE: Use local space vector comparison (same as fast_accel.lua)

    WHY LOCAL SPACE:
    - Player input is relative to view direction (WASD keys)
    - Script direction is in world space
    - Must convert to same coordinate system for accurate comparison

    ALGORITHM:
    1. Get player input vector (forward/side movement)
    2. Convert script's world target to local space relative to player view
    3. Calculate angle between vectors using dot product
    4. If angle > 60°, player wants to override script

    WHY 60 DEGREES:
    - Allows small corrections (< 60°) while riding
    - Detects clear intent to leave (> 60°)
    - Balances precision vs responsiveness
]]
local function hasConflictingInput(cmd, playerPos, targetPos)
	local forwardMove = cmd:GetForwardMove()
	local sideMove = cmd:GetSideMove()

	-- No input = no conflict
	if math.abs(forwardMove) < 0.1 and math.abs(sideMove) < 0.1 then
		return false
	end

	-- Convert player input to local space vector (like fast_accel.lua)
	local playerMoveDir = Vector3(forwardMove, sideMove, 0)
	local playerMoveLength = playerMoveDir:Length()
	if playerMoveLength < 0.1 then
		return false -- Input too small to matter
	end

	-- Normalize player input vector
	playerMoveDir = playerMoveDir / playerMoveLength

	-- Calculate script's desired direction in world space
	local scriptWorldDir = targetPos - playerPos
	local scriptWorldLength = scriptWorldDir:Length()
	if scriptWorldLength < 0.1 then
		return false -- Already at target
	end

	-- Transform script's world direction to local space (relative to player view)
	local _, currentYaw = cmd:GetViewAngles()
	currentYaw = currentYaw * DEG_TO_RAD

	-- Rotation matrix to convert world to local space
	local cosYaw = math.cos(-currentYaw) -- Negative for world→local conversion
	local sinYaw = math.sin(-currentYaw)
	local scriptLocalX = scriptWorldDir.x * cosYaw - scriptWorldDir.y * sinYaw
	local scriptLocalY = scriptWorldDir.x * sinYaw + scriptWorldDir.y * cosYaw

	-- Normalize script's local direction
	local scriptLocalDir = Vector3(scriptLocalX, scriptLocalY, 0)
	scriptLocalDir = scriptLocalDir / scriptLocalDir:Length()

	-- Calculate angle between vectors using dot product formula
	local dotProduct = playerMoveDir.x * scriptLocalDir.x + playerMoveDir.y * scriptLocalDir.y
	local angle = math.acos(math.max(-1, math.min(1, dotProduct))) -- Clamp to prevent NaN
	local angleDegrees = math.deg(angle)

	-- Return true if angle difference exceeds threshold
	return angleDegrees > 60
end

--[[
    MAIN CONTROL LOGIC

    EXECUTION FLOW:
    1. Early exit if player is dead (no processing needed)
    2. Find all sentries on map
    3. Find closest sentry in detection range
    4. Update AABB size if needed (mainly for mini-sentries)
    5. Check if starting new sentry ride (reset protection timer)
    6. If in riding zone: handle movement and input conflicts
    7. Apply protection period (22 ticks) to prevent accidental disengagement

    PROTECTION PERIOD PURPOSE:
    - When first getting on sentry, ignore manual input for 22 ticks
    - Prevents accidental slip-offs due to residual movement input
    - After 22 ticks, respect player's movement intentions
]]
local function OnCreateMove(cmd)
	local pLocal = entities.GetLocalPlayer()
	-- EARLY EXIT: Disable all functionality when dead
	if not pLocal or not pLocal:IsAlive() then
		-- Clear state when dead
		targetRidePosition = nil
		activeSentry = nil
		ridingStartTick = 0
		return
	end

	local playerPos = pLocal:GetAbsOrigin()
	local currentTick = globals.TickCount()

	-- STEP 1: Find all available sentries
	local sentries = findAllSentries()
	if #sentries == 0 then
		-- No sentries found - clear state
		targetRidePosition = nil
		activeSentry = nil
		ridingStartTick = 0
		if ENABLE_DEBUG then
			print("[SentryRider] No enemy sentries found")
		end
		return
	end

	if ENABLE_DEBUG then
		print(string.format("[SentryRider] Found %d enemy sentries", #sentries))
	end

	-- STEP 2: Find the best sentry to ride
	local bestSentry = nil
	local bestDistance = math.huge

	for _, sentry in pairs(sentries) do
		local sentryPos = sentry:GetAbsOrigin()
		local distance = (playerPos - sentryPos):Length()

		if ENABLE_DEBUG then
			local heightDiff = playerPos.z - sentryPos.z
			local horizontalDist = math.sqrt((playerPos.x - sentryPos.x) ^ 2 + (playerPos.y - sentryPos.y) ^ 2)
			local inArea = isInSentryArea(playerPos, sentryPos)
			print(
				string.format(
					"[SentryRider] Sentry check - Height: %.1f, HorzDist: %.1f, InArea: %s",
					heightDiff,
					horizontalDist,
					inArea and "YES" or "NO"
				)
			)
		end

		-- Only consider sentries we can actually ride (height + distance check)
		if isInSentryArea(playerPos, sentryPos) and distance < bestDistance then
			bestSentry = sentry
			bestDistance = distance
			if ENABLE_DEBUG then
				print(string.format("[SentryRider] Selected sentry at distance %.1f", distance))
			end
		end
	end

	if bestSentry then
		local sentryPos = bestSentry:GetAbsOrigin()

		-- STEP 3: Update safe walking area (mainly needed for mini-sentries)
		updateSentryAABB(bestSentry)

		-- STEP 4: Track sentry changes and start protection period
		if activeSentry ~= bestSentry then
			ridingStartTick = currentTick
			-- Note: Debug print removed to avoid spam when dead
		end

		-- STEP 5: Active riding logic (only when precisely positioned)
		if isInRidingZone(playerPos, sentryPos) then
			activeSentry = bestSentry
			targetRidePosition = calculateRidePosition(bestSentry)

			-- STEP 6: Handle manual input conflicts with protection period
			local ticksSinceStart = currentTick - ridingStartTick
			local inProtectionPeriod = ticksSinceStart < PROTECTION_TICKS
			local hasConflictingMovement = hasConflictingInput(cmd, playerPos, targetRidePosition)

			-- Check if player wants to override (but respect protection period)
			if hasConflictingMovement and not inProtectionPeriod then
				-- Player clearly wants to take control - disengage script
				return
			end

			-- STEP 7: Apply smooth movement to ride position
			WalkTo(cmd, pLocal, targetRidePosition)
		else
			-- Near sentry but not in riding zone - just track it
			activeSentry = bestSentry
			targetRidePosition = calculateRidePosition(bestSentry)
		end
	else
		-- No suitable sentry found - clear state
		targetRidePosition = nil
		activeSentry = nil
		ridingStartTick = 0
	end
end

-- Visual debugging
local function DrawBox(pos, size, color)
	if not pos then
		return
	end

	local halfSize = size / 2
	local corners = {
		Vector3(-halfSize, -halfSize, 0),
		Vector3(halfSize, -halfSize, 0),
		Vector3(halfSize, halfSize, 0),
		Vector3(-halfSize, halfSize, 0),
	}

	local screenCorners = {}
	for _, corner in ipairs(corners) do
		local worldPos = pos + corner
		local screenPos = client.WorldToScreen(worldPos)
		if screenPos then
			table.insert(screenCorners, { x = screenPos[1], y = screenPos[2] })
		end
	end

	if #screenCorners == 4 then
		draw.Color(color[1], color[2], color[3], color[4])
		for i = 1, 4 do
			local next_i = (i % 4) + 1
			local x1, y1 = math.floor(screenCorners[i].x), math.floor(screenCorners[i].y)
			local x2, y2 = math.floor(screenCorners[next_i].x), math.floor(screenCorners[next_i].y)
			draw.Line(x1, y1, x2, y2)
		end
	end
end

-- Draw a circle at a 3D position with given radius
local function DrawCircle(pos, radius, color, segments)
	if not pos then
		return
	end

	segments = segments or 32 -- Default to 32 segments for smooth circle
	local angleStep = TWO_PI / segments

	local points = {}
	for i = 0, segments - 1 do
		local angle = i * angleStep
		local x = math.cos(angle) * radius
		local y = math.sin(angle) * radius
		local worldPos = pos + Vector3(x, y, 0)
		local screenPos = client.WorldToScreen(worldPos)
		if screenPos then
			table.insert(points, { x = math.floor(screenPos[1]), y = math.floor(screenPos[2]) })
		end
	end

	if #points >= 3 then
		draw.Color(color[1], color[2], color[3], color[4])
		for i = 1, #points do
			local next_i = (i % #points) + 1
			draw.Line(points[i].x, points[i].y, points[next_i].x, points[next_i].y)
		end
	end
end

-- Draw the actual sentry hitbox
local function DrawSentryHitbox(sentry, color)
	if not sentry or not sentry:IsValid() then
		return
	end

	local sentryPos = sentry:GetAbsOrigin()
	local minBounds, maxBounds = getSentryHitbox(sentry)

	if not minBounds or not maxBounds then
		return
	end

	-- Calculate the 8 corners of the hitbox
	local corners = {
		sentryPos + Vector3(minBounds.x, minBounds.y, minBounds.z), -- bottom-back-left
		sentryPos + Vector3(maxBounds.x, minBounds.y, minBounds.z), -- bottom-back-right
		sentryPos + Vector3(maxBounds.x, maxBounds.y, minBounds.z), -- bottom-front-right
		sentryPos + Vector3(minBounds.x, maxBounds.y, minBounds.z), -- bottom-front-left
		sentryPos + Vector3(minBounds.x, minBounds.y, maxBounds.z), -- top-back-left
		sentryPos + Vector3(maxBounds.x, minBounds.y, maxBounds.z), -- top-back-right
		sentryPos + Vector3(maxBounds.x, maxBounds.y, maxBounds.z), -- top-front-right
		sentryPos + Vector3(minBounds.x, maxBounds.y, maxBounds.z), -- top-front-left
	}

	-- Convert to screen coordinates
	local screenCorners = {}
	for i, corner in ipairs(corners) do
		local screenPos = client.WorldToScreen(corner)
		if screenPos then
			screenCorners[i] = { x = math.floor(screenPos[1]), y = math.floor(screenPos[2]) }
		end
	end

	-- Draw the hitbox outline
	draw.Color(color[1], color[2], color[3], color[4])

	-- Draw bottom face (corners 1-4)
	for i = 1, 4 do
		local next_i = (i % 4) + 1
		if screenCorners[i] and screenCorners[next_i] then
			draw.Line(screenCorners[i].x, screenCorners[i].y, screenCorners[next_i].x, screenCorners[next_i].y)
		end
	end

	-- Draw top face (corners 5-8) - this is the important part for riding
	for i = 5, 8 do
		local next_i = ((i - 5) % 4) + 5
		if screenCorners[i] and screenCorners[next_i] then
			draw.Line(screenCorners[i].x, screenCorners[i].y, screenCorners[next_i].x, screenCorners[next_i].y)
		end
	end

	-- Draw vertical lines connecting bottom to top
	for i = 1, 4 do
		if screenCorners[i] and screenCorners[i + 4] then
			draw.Line(screenCorners[i].x, screenCorners[i].y, screenCorners[i + 4].x, screenCorners[i + 4].y)
		end
	end
end

local function DrawArrow(startPos, endPos, color)
	if not startPos or not endPos then
		return
	end

	local w2s_start = client.WorldToScreen(startPos)
	local w2s_end = client.WorldToScreen(endPos)

	if w2s_start and w2s_end then
		draw.Color(color[1], color[2], color[3], color[4])
		local x1, y1 = math.floor(w2s_start[1]), math.floor(w2s_start[2])
		local x2, y2 = math.floor(w2s_end[1]), math.floor(w2s_end[2])
		draw.Line(x1, y1, x2, y2)

		-- Simple arrowhead
		local dx = x2 - x1
		local dy = y2 - y1
		local len = math.sqrt(dx * dx + dy * dy)
		if len > 10 then
			local ux, uy = dx / len, dy / len
			local size = 8
			local ax1, ay1 = math.floor(x2 - ux * size + uy * size / 2), math.floor(y2 - uy * size - ux * size / 2)
			local ax2, ay2 = math.floor(x2 - ux * size - uy * size / 2), math.floor(y2 - uy * size + ux * size / 2)
			draw.Line(x2, y2, ax1, ay1)
			draw.Line(x2, y2, ax2, ay2)
		end
	end
end

local font = draw.CreateFont("Verdana", 14, 510)

--[[
    VISUAL DEBUG DISPLAY

    PURPOSE: Show real-time information about sentry riding status
    - Only displays when player is alive and visuals are enabled
    - Shows riding status, sentry info, and positioning data
    - Draws visual indicators for sentry hitbox, aim direction, target position
]]
local function OnDraw()
	if not ENABLE_VISUALS then
		return
	end
	if engine.Con_IsVisible() or engine.IsGameUIVisible() then
		return
	end

	local pLocal = entities.GetLocalPlayer()
	-- EARLY EXIT: Hide all debug info when dead
	if not pLocal or not pLocal:IsAlive() then
		return
	end

	local playerPos = pLocal:GetAbsOrigin()

	draw.SetFont(font)

	-- Draw status information
	draw.Color(255, 255, 255, 255)
	local yOffset = 20

	-- Show automatic riding status (always enabled now)
	draw.Color(100, 255, 100, 255) -- Light green
	draw.Text(20, yOffset, "Sentry Riding: ACTIVE (automatic)")
	yOffset = yOffset + 20
	draw.Color(255, 255, 255, 255) -- Reset to white

	if activeSentry then
		local sentryPos = activeSentry:GetAbsOrigin()
		local distance = (playerPos - sentryPos):Length()
		local inRidingZone = isInRidingZone(playerPos, sentryPos)

		-- Show sentry information
		draw.Text(20, yOffset, string.format("Active Sentry Distance: %.1f", distance))
		yOffset = yOffset + 20
		draw.Text(20, yOffset, string.format("In Riding Zone: %s", inRidingZone and "YES" or "NO"))
		yOffset = yOffset + 20

		-- Show team information to confirm enemy targeting
		local playerTeam = pLocal:GetTeamNumber()
		local sentryTeam = activeSentry:GetTeamNumber()
		local teamNames = { [2] = "RED", [3] = "BLU" }
		local playerTeamName = teamNames[playerTeam] or "UNKNOWN"
		local sentryTeamName = teamNames[sentryTeam] or "UNKNOWN"

		draw.Color(255, 200, 100, 255) -- Orange for team info
		draw.Text(20, yOffset, string.format("Teams - Player: %s, Sentry: %s", playerTeamName, sentryTeamName))
		yOffset = yOffset + 20
		draw.Color(255, 255, 255, 255) -- Reset to white

		-- Show sentry level and dimensions
		local level = getSentryLevel(activeSentry)
		local levelText = level == 0 and "Mini" or ("Level " .. level)
		draw.Text(20, yOffset, string.format("Sentry Type: %s", levelText))
		yOffset = yOffset + 20

		local minBounds, maxBounds = getSentryHitbox(activeSentry)
		if minBounds and maxBounds then
			local sentryWidth = math.abs(maxBounds.x - minBounds.x)
			local sentryDepth = math.abs(maxBounds.y - minBounds.y)
			local sentryHeight = math.abs(maxBounds.z - minBounds.z)
			draw.Text(20, yOffset, string.format("Sentry Size: %.0fx%.0fx%.0f", sentryWidth, sentryDepth, sentryHeight))
			yOffset = yOffset + 20
		end
		draw.Text(20, yOffset, string.format("Riding Zone Radius: %d", SENTRY_AABB_SIZE))
		yOffset = yOffset + 20

		-- Show protection period status
		local currentTick = globals.TickCount()
		local ticksSinceStart = currentTick - ridingStartTick
		if ticksSinceStart < PROTECTION_TICKS then
			draw.Color(255, 255, 100, 255) -- Yellow during protection
			draw.Text(20, yOffset, string.format("Protection Period: %d/%d ticks", ticksSinceStart, PROTECTION_TICKS))
			yOffset = yOffset + 20
			draw.Color(255, 255, 255, 255) -- Reset to white
		end

		-- VISUAL INDICATORS
		-- Draw actual sentry hitbox (cyan outline)
		DrawSentryHitbox(activeSentry, { 0, 255, 255, 150 })

		-- Draw riding zone area (yellow square at riding height)
		local ridingZonePos = Vector3(sentryPos.x, sentryPos.y, sentryPos.z + 66)
		DrawBox(ridingZonePos, SENTRY_AABB_SIZE * 2, { 255, 255, 0, 150 })

		-- Draw sentry aim direction (red arrow)
		local aimAngles = getSentryAimAngles(activeSentry)
		local forward = aimAngles:Forward()
		local aimEnd = sentryPos + (forward * 100)
		DrawArrow(sentryPos, aimEnd, { 255, 0, 0, 255 })

		-- Draw target ride position and path
		if targetRidePosition then
			-- Draw target position (green circle)
			DrawCircle(targetRidePosition, 12, { 0, 255, 0, 255 })

			-- Draw path from player to target (green arrow)
			DrawArrow(playerPos, targetRidePosition, { 0, 255, 0, 200 })

			-- MOVEMENT DEBUG: Draw where the movement system will actually move us
			-- Calculate the actual movement direction using the same logic as WalkTo
			local _, viewYaw = entities.GetLocalPlayer():GetEyeAngles()
			if viewYaw then
				local fwdNorm, sideNorm = WorldDirToLocalInput(playerPos, targetRidePosition, viewYaw * DEG_TO_RAD)

				-- Convert back to world space to visualize
				local viewYawRad = viewYaw * DEG_TO_RAD
				local worldFwd = math.cos(viewYawRad) * fwdNorm - math.sin(viewYawRad) * sideNorm
				local worldSide = math.sin(viewYawRad) * fwdNorm + math.cos(viewYawRad) * sideNorm
				local actualMoveDir = Vector3(worldFwd, worldSide, 0)
				local actualMoveEnd = playerPos + (actualMoveDir * 80) -- more visible length

				-- Draw movement intent direction (orange arrow)
				DrawArrow(playerPos, actualMoveEnd, { 255, 128, 0, 255 })

				-- Draw acceleration vector (magenta) scaled to in-game units per tick
				if debugAccelVec then
					local scale = 10 -- visual scaling so arrow is noticeable (10 uu == 1px approx)
					local accelEnd = playerPos + (debugAccelVec * scale)
					DrawArrow(playerPos, accelEnd, { 255, 0, 255, 255 })
				end
			end

			local rideDistance = (playerPos - targetRidePosition):Length()
			draw.Text(20, yOffset, string.format("Ride Position Distance: %.1f", rideDistance))
			yOffset = yOffset + 20

			-- MOVEMENT DEBUG: Show exact direction calculations
			local dx = targetRidePosition.x - playerPos.x
			local dy = targetRidePosition.y - playerPos.y
			local worldAngle = math.deg(math.atan(dy, dx))
			draw.Text(20, yOffset, string.format("World Direction Angle: %.1f°", worldAngle))
			yOffset = yOffset + 20

			-- Show player view angle for comparison
			local _, viewYaw = activeSentry and entities.GetLocalPlayer() and entities.GetLocalPlayer():GetEyeAngles()
				or { 0, 0 }
			if viewYaw then
				draw.Text(20, yOffset, string.format("Player View Yaw: %.1f°", viewYaw))
				yOffset = yOffset + 20

				local angleDiff = ((worldAngle - viewYaw + 180) % 360) - 180
				draw.Text(20, yOffset, string.format("Angle Difference: %.1f°", angleDiff))
			end
		end
	else
		draw.Text(20, yOffset, "No active sentry")
	end
end

-- Register callbacks
callbacks.Unregister("CreateMove", "SentryRider_CreateMove")
callbacks.Register("CreateMove", "SentryRider_CreateMove", OnCreateMove)

callbacks.Unregister("Draw", "SentryRider_Draw")
callbacks.Register("Draw", "SentryRider_Draw", OnDraw)

client.Command('play "ui/buttonclick"', true)
print("[SentryRider] Loaded successfully!")

--[[
    ONE-TICK PREDICTION
    -------------------
    We ignore gravity (Z-axis) and predict where the player will be at the
    start of the *next* tick *without* extra input. This lets us tell how
    far the script must move *this* tick to keep convergence tight.

    newVel  = vel * (1 - friction * tick)    -- Source style ground drag
    newPos  = pos + newVel * tick            -- Euler forward step
]]

local function PredictNextTickPosHorizontal(player, tickInt)
	local pos = player:GetAbsOrigin()
	local vel = player:EstimateAbsVelocity()
	if not pos or not vel then
		return pos
	end

	-- zero Z so we only care about ground plane
	vel.z = 0

	local friction = GetGroundFriction()
	local dragFactor = math.max(0, 1 - friction * tickInt)

	local newVel = vel * dragFactor
	local horizStep = newVel * tickInt

	return Vector3(pos.x + horizStep.x, pos.y + horizStep.y, pos.z) -- keep same height
end

-- Helper: returns true if player crouched, false otherwise
function IsPlayerDucking(p)
	if not p or not p:IsValid() then
		return false
	end
	local ok, flags = pcall(function()
		return p:GetPropInt("m_fFlags")
	end)
	if not ok or not flags then
		return false
	end
	return (flags & FL_DUCKING) ~= 0 -- Rule #22: use bitwise & constant
end
