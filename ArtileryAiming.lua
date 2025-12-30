-------------------------------
-- CONFIGURATION
-------------------------------
local config = {
	polygon = {
		enabled = true, -- Set to true to display impact circle
		r = 255,
		g = 200,
		b = 155,
		a = 25,
		size = 10,
		segments = 20,
	},
	line = {
		enabled = true,
		r = 255,
		g = 255,
		b = 255,
		a = 255,
	},
	flags = {
		enabled = true,
		r = 255,
		g = 0,
		b = 0,
		a = 255,
		size = 5,
	},
	outline = {
		line_and_flags = true,
		polygon = true,
		r = 0,
		g = 0,
		b = 0,
		a = 155,
	},
	measure_segment_size = 2.5, -- Range: 0.5 to 8; lower values = worse performance
}

-------------------------------
-- CONSTANTS
-------------------------------
local IN_ATTACK = 1
local STICKY_BASE_SPEED = 900
local STICKY_MAX_SPEED = 2400
local STICKY_UPWARD_VEL = 200
local STICKY_GRAVITY = 800
local DOWNWARD_SEARCH_STEPS = 24

-------------------------------
-- PROJECTILE CAMERA CONFIG
-------------------------------
local projCamConfig = {
	key = KEY_F,
	width = 650,
	height = 400,
	x = 25,
	y = 300,
	scrollStep = 0.01,
	interpSpeed = 0.15,
	fov = 90,
	toggle = true,
}

-------------------------------
-- PROJECTILE CAMERA STATE
-------------------------------
local projCamState = {
	pathPercent = 0.5,
	smoothedAngles = EulerAngles(0, 0, 0),
	smoothedPos = Vector3(0, 0, 0),
	isDragging = false,
	dragOffsetX = 0,
	dragOffsetY = 0,
	lastScrollTick = 0,
	materialsReady = false,
	texture = nil,
	material = nil,
	storedPositions = {},
	storedVelocities = {},
	lastView = nil,
	active = false,
	lastKeyState = false,
	storedImpactPos = nil,
	storedImpactPlane = nil,
	storedFlagOffset = Vector3(0, 0, 0),
	storedPolygonTexture = nil,

	-- Unified Trajectory Cache
	trajectory = {
		positions = {},
		velocities = {},
		impactPos = nil,
		impactPlane = nil,
		flagOffset = Vector3(0, 0, 0),
		isValid = false,
	},
}

-------------------------------
-- BOMBARDING MODE STATE
-------------------------------
local bombardMode = {
	chargeMode = false, -- false = scroll controls position, true = scroll controls charge
	lastVKeyState = false,
	chargeLevel = 0.5, -- 0.0 to 1.0
	scrollStep = 0.05, -- How much charge changes per scroll
	useStoredCharge = false, -- true = use stored charge for trajectory, reset when window toggled
}

-------------------------------
-- BOMBARDING AIM STATE
-------------------------------
local bombardAim = {
	enabled = true, -- Always active when preview visible
	lastCKeyState = false,
	targetDistance = 500, -- Distance in units we want to hit
	targetYaw = 0, -- Yaw offset from player view
	scrollMode = 0, -- 0=position, 1=charge, 2=distance
	minDistance = 10, -- Allow very close targets
	maxDistance = 3000, -- Will be calculated dynamically
	distanceStep = 50,
	useHighArc = false, -- false = low arc (direct), true = high arc (lob)
	calculatedPitch = -45,
	targetPoint = nil,
	originPoint = nil,
	lastMouseX = 0,
	lastMouseY = 0,
	sensitivity = 1.0, -- Increased sensitivity
	useTopAngle = false, -- C key toggles between top angle and dynamic angle
	-- Caching to prevent expensive recalculation
	lastCalculatedDistance = -1,
	cachedCharge = 0,
	cachedPitch = -45,
	cachedValid = false,
}

local projCamFont = draw.CreateFont("Tahoma", 12, 800, FONTFLAG_OUTLINE)

-------------------------------
-- UTILITY FUNCTIONS
-------------------------------
local function cross(a, b, c)
	return (b[1] - a[1]) * (c[2] - a[2]) - (b[2] - a[2]) * (c[1] - a[1])
end

local function findDownwardPitch(speed, targetDistance, gravity, upwardVel)
	local minPitch = -89
	local maxPitch = 0
	local bestPitch = nil
	local smallestDiff = math.huge

	for _ = 1, DOWNWARD_SEARCH_STEPS do
		local midPitch = 0.5 * (minPitch + maxPitch)
		local midRange = calculateRange(speed, math.rad(-midPitch), gravity, upwardVel)
		local rangeDiff = midRange - targetDistance

		if rangeDiff > 0 then
			maxPitch = midPitch
		else
			minPitch = midPitch
		end

		local absDiff = math.abs(rangeDiff)
		if absDiff < smallestDiff then
			smallestDiff = absDiff
			bestPitch = midPitch
		end
	end

	return bestPitch
end

local function clamp(val, minVal, maxVal)
	if val < minVal then
		return minVal
	end
	if val > maxVal then
		return maxVal
	end
	return val
end

-- Sticky bomb physics constants
local STICKY_BASE_SPEED = 900
local STICKY_MAX_SPEED = 2400
local STICKY_UPWARD_VEL = 200
local STICKY_GRAVITY = 800
local DOWNWARD_SEARCH_STEPS = 24

-- Calculate projectile range for given speed and pitch (in radians)
local function calculateRange(speed, pitchRad, gravity, upwardVel)
	local vx = speed * math.cos(pitchRad)
	local vy = speed * math.sin(pitchRad) + upwardVel

	-- Solve quadratic: 0.5*g*t^2 - vy*t = 0 for time to hit ground
	-- t = 0 (start) or t = 2*vy/g
	-- For downward trajectories (vy < 0), we need to solve: 0.5*g*t^2 - vy*t - h = 0
	-- For simplicity, use absolute value and handle both cases
	if vy > 0 then
		-- Upward trajectory
		local flightTime = (2 * vy) / gravity
		local range = vx * flightTime
		return range
	else
		-- Downward trajectory - hits ground faster
		-- Approximate time to hit ground from current height
		local flightTime = math.abs(vy) / gravity
		local range = vx * flightTime
		return range
	end
end

-- Direct mathematical solution for pitch angles (no iterations)
local function solvePitchForDistance(speed, targetDistance, gravity, upwardVel)
	-- Using the quartic equation from "Cannons that Never Miss"
	-- |ΔP - ½gt²|² = (st)² where ΔP is horizontal distance, g is gravity

	-- For sticky bombs with upward velocity, we need to account for it
	-- Modified equation: (v*cos(θ))*t = distance, where t = 2*(v*sin(θ) + upwardVel)/gravity

	-- This gives us: distance = v*cos(θ) * 2*(v*sin(θ) + upwardVel)/gravity
	-- Simplifying: distance*gravity = 2*v²*cos(θ)*sin(θ) + 2*v*cos(θ)*upwardVel
	-- Using trig identity: 2*cos(θ)*sin(θ) = sin(2θ)
	-- distance*gravity = v²*sin(2θ) + 2*v*cos(θ)*upwardVel

	local g = gravity
	local d = targetDistance
	local u = upwardVel

	-- This is a quadratic in terms of tan(θ)
	-- Let's solve it directly using the quadratic formula
	local discriminant = speed * speed - g * (g * d * d - 4 * d * u * speed) / (4 * d * d)

	if discriminant < 0 then
		return nil, nil -- No solution
	end

	local sqrt_disc = math.sqrt(discriminant)

	-- Two solutions: low arc and high arc
	local tan1 = (speed * speed - sqrt_disc) / (g * d)
	local tan2 = (speed * speed + sqrt_disc) / (g * d)

	-- Convert to pitch angles (negative because pitch is downward)
	local pitch1 = -math.deg(math.atan(tan1))
	local pitch2 = -math.deg(math.atan(tan2))

	return pitch1, pitch2
end

-- Aliases for external functions:
local traceHull = engine.TraceHull
local traceLine = engine.TraceLine
local worldToScreen = client.WorldToScreen
local texturedPolygon = draw.TexturedPolygon
local drawLine = draw.Line
local setColor = draw.Color
local getScreenSize = draw.GetScreenSize

-------------------------------
-- PROJECTILE CAMERA FUNCTIONS
-------------------------------
local function initProjCamMaterials()
	if projCamState.materialsReady then
		return true
	end

	if not materials or not materials.CreateTextureRenderTarget then
		error("Materials API not available")
	end

	local texName = "projCamTexture"
	projCamState.texture = materials.CreateTextureRenderTarget(texName, projCamConfig.width, projCamConfig.height)
	if not projCamState.texture then
		error("Failed to create render texture")
	end

	if not materials.Create then
		error("Materials.Create API not available")
	end

	projCamState.material = materials.Create(
		"projCamMaterial",
		string.format(
			[[
		UnlitGeneric
		{
			$basetexture    "%s"
			$ignorez        1
			$nofog          1
		}
	]],
			texName
		)
	)

	if not projCamState.material then
		error("Failed to create projectile camera material")
	end

	projCamState.materialsReady = true
	return true
end

local function lerpAngle(a, b, t)
	local diff = b - a
	while diff > 180 do
		diff = diff - 360
	end
	while diff < -180 do
		diff = diff + 360
	end
	return a + diff * t
end

local function lerpVector(a, b, t)
	return Vector3(a.x + (b.x - a.x) * t, a.y + (b.y - a.y) * t, a.z + (b.z - a.z) * t)
end

local function getVelocityAngles(vel)
	local speed = vel:Length()
	if speed < 0.001 then
		return EulerAngles(0, 0, 0)
	end

	local pitch = -math.deg(math.asin(vel.z / speed))
	local yaw = math.deg(math.atan(vel.y, vel.x))
	return EulerAngles(pitch, yaw, 0)
end

local function isMouseInWindow()
	local mx, my = table.unpack(input.GetMousePos())
	local x, y = projCamConfig.x, projCamConfig.y
	local w, h = projCamConfig.width, projCamConfig.height
	return mx >= x and mx <= x + w and my >= y - 20 and my <= y + h
end

local function handleProjCamToggle()
	local keyDown = input.IsButtonDown(projCamConfig.key)
	if projCamConfig.toggle then
		if keyDown and not projCamState.lastKeyState then
			local wasActive = projCamState.active
			projCamState.active = not projCamState.active
			-- Reset to using actual charge when window is toggled off
			if wasActive and not projCamState.active then
				bombardMode.useStoredCharge = false
			end
		end
		projCamState.lastKeyState = keyDown
	else
		projCamState.active = keyDown
	end
end

local function handleBombardModeToggle()
	local vKeyDown = input.IsButtonDown(KEY_V)
	if vKeyDown and not bombardMode.lastVKeyState then
		-- Toggle between scroll modes: 0=position, 1=charge
		bombardAim.scrollMode = (bombardAim.scrollMode + 1) % 2
		bombardMode.chargeMode = (bombardAim.scrollMode == 1)
	end
	bombardMode.lastVKeyState = vKeyDown
end

local function handleBombardAimToggle()
	local cKeyDown = input.IsButtonDown(KEY_C)
	if cKeyDown and not bombardAim.lastCKeyState then
		-- Toggle between LOW arc and HIGH arc
		bombardAim.useHighArc = not bombardAim.useHighArc
	end
	bombardAim.lastCKeyState = cKeyDown
end

-- Calculate max range dynamically based on current charge
local function calculateMaxRange(charge)
	local speed = STICKY_BASE_SPEED + charge * (STICKY_MAX_SPEED - STICKY_BASE_SPEED)
	local g = STICKY_GRAVITY
	return (speed * speed) / g -- Max range at 45 degrees
end

local function isProjCamActive()
	return projCamState.active and #projCamState.storedPositions > 1
end

local function handleProjCamInput()
	local menuOpen = gui.GetValue("Menu") == 1

	if menuOpen then
		local mx, my = table.unpack(input.GetMousePos())
		local titleBarY = projCamConfig.y - 20

		if input.IsButtonDown(MOUSE_LEFT) then
			if not projCamState.isDragging then
				if
					mx >= projCamConfig.x
					and mx <= projCamConfig.x + projCamConfig.width
					and my >= titleBarY
					and my <= projCamConfig.y
				then
					projCamState.isDragging = true
					projCamState.dragOffsetX = mx - projCamConfig.x
					projCamState.dragOffsetY = my - projCamConfig.y
				end
			else
				local screenW, screenH = getScreenSize()
				projCamConfig.x = clamp(mx - projCamState.dragOffsetX, 0, screenW - projCamConfig.width)
				projCamConfig.y = clamp(my - projCamState.dragOffsetY, 25, screenH - projCamConfig.height)
			end
		else
			projCamState.isDragging = false
		end
	else
		projCamState.isDragging = false
	end

	-- Scroll only controls camera position % on trajectory
	if input.IsButtonPressed(MOUSE_WHEEL_UP) then
		projCamState.pathPercent = clamp(projCamState.pathPercent + projCamConfig.scrollStep, 0, 0.9)
	elseif input.IsButtonPressed(MOUSE_WHEEL_DOWN) then
		projCamState.pathPercent = clamp(projCamState.pathPercent - projCamConfig.scrollStep, 0, 0.9)
	end
end

local function getPathDataAtPercent(positions, velocities, percent)
	local count = #positions
	if count < 2 then
		return nil, nil
	end

	local exactIndex = 1 + (count - 1) * percent
	local lowIdx = math.floor(exactIndex)
	local highIdx = math.ceil(exactIndex)
	local frac = exactIndex - lowIdx

	lowIdx = clamp(lowIdx, 1, count)
	highIdx = clamp(highIdx, 1, count)

	local pos = lerpVector(positions[lowIdx], positions[highIdx], frac)

	local vel
	if velocities and #velocities >= highIdx then
		vel = lerpVector(velocities[lowIdx], velocities[highIdx], frac)
	else
		vel = positions[highIdx] - positions[lowIdx]
	end

	return pos, vel
end

local function drawProjCamWindow()
	local x, y = projCamConfig.x, projCamConfig.y
	local w, h = projCamConfig.width, projCamConfig.height

	setColor(235, 64, 52, 255)
	draw.OutlinedRect(x, y, x + w, y + h)
	draw.OutlinedRect(x, y - 20, x + w, y)

	setColor(130, 26, 17, 255)
	draw.FilledRect(x + 1, y - 19, x + w - 1, y - 1)

	draw.SetFont(projCamFont)
	setColor(255, 255, 255, 255)

	local titleText = bombardAim.enabled and "Bombarding Aim" or "Projectile Cam"
	local textW, _ = draw.GetTextSize(titleText)
	draw.Text(math.floor(x + w * 0.5 - textW * 0.5), y - 16, titleText)

	-- Camera position (scroll controls this)
	setColor(0, 255, 0, 255)
	local posText = string.format("Cam Pos: %.0f%% [Scroll]", projCamState.pathPercent * 100)
	draw.Text(x + 5, y + 5, posText)

	-- Arc mode status (C key toggles)
	local aimText = string.format("[C] %s ARC", bombardAim.useHighArc and "HIGH" or "LOW")
	setColor(
		bombardAim.useHighArc and 255 or 0,
		bombardAim.useHighArc and 150 or 255,
		bombardAim.useHighArc and 0 or 100,
		255
	)
	draw.Text(x + 5, y + 20, aimText)

	-- Show calculated values when camera is active
	if projCamState.active then
		setColor(0, 200, 255, 255)
		local distText = string.format("Target: %.0f / %.0f", bombardAim.targetDistance, bombardAim.maxDistance)
		draw.Text(x + 5, y + 35, distText)

		setColor(255, 200, 0, 255)
		local chargeText = string.format("Charge: %.0f%%", bombardMode.chargeLevel * 100)
		draw.Text(x + 5, y + 50, chargeText)

		setColor(255, 255, 0, 255)
		local pitchText = string.format(
			"Pitch: %s",
			bombardAim.calculatedPitch and string.format("%.1f°", bombardAim.calculatedPitch) or "N/A"
		)
		draw.Text(x + 5, y + 65, pitchText)

		setColor(150, 255, 150, 255)
		local arcDesc = bombardAim.useHighArc and "Lob (over obstacles)" or "Direct (faster)"
		draw.Text(x + 5, y + 80, arcDesc)
	end

	setColor(255, 255, 255, 180)
	local controls
	if bombardAim.enabled then
		controls = {
			"MouseY=Dist MouseX=Dir",
			"Scroll=CamPos M1=Fire",
		}
	else
		controls = {
			"F=Cam C=BombardAim",
			"Scroll=CamPos M1=Fire",
		}
	end
	for i, text in ipairs(controls) do
		draw.Text(x + 5, y + h + 5 + (i - 1) * 14, text)
	end
end

local function drawAimGuideMainView()
	if not bombardAim.originPoint or not bombardAim.targetPoint then
		return
	end

	local start2d = worldToScreen(bombardAim.originPoint)
	local end2d = worldToScreen(bombardAim.targetPoint)
	if not start2d or not end2d then
		return
	end

	setColor(0, 255, 0, 255)
	drawLine(math.floor(start2d[1]), math.floor(start2d[2]), math.floor(end2d[1]), math.floor(end2d[2]))
end

local function drawAimGuideCamera()
	if not bombardAim.originPoint or not bombardAim.targetPoint then
		return
	end

	local start2d = worldToScreen(bombardAim.originPoint)
	local end2d = worldToScreen(bombardAim.targetPoint)
	if not start2d or not end2d then
		return
	end

	setColor(0, 255, 0, 255)
	drawLine(math.floor(start2d[1]), math.floor(start2d[2]), math.floor(end2d[1]), math.floor(end2d[2]))
end

local function updateProjCamSmoothing()
	local positions = projCamState.storedPositions
	local velocities = projCamState.storedVelocities

	if #positions < 2 then
		return
	end

	local targetPos, targetVel = getPathDataAtPercent(positions, velocities, projCamState.pathPercent)
	if not targetPos or not targetVel then
		return
	end

	local targetAngles = getVelocityAngles(targetVel)
	targetAngles.x = targetAngles.x + 5

	projCamState.smoothedPos = lerpVector(projCamState.smoothedPos, targetPos, projCamConfig.interpSpeed)
	projCamState.smoothedAngles = EulerAngles(
		lerpAngle(projCamState.smoothedAngles.x, targetAngles.x, projCamConfig.interpSpeed),
		lerpAngle(projCamState.smoothedAngles.y, targetAngles.y, projCamConfig.interpSpeed),
		0
	)
end

local function renderProjCamView(view)
	if not view or #projCamState.storedPositions < 2 then
		return
	end

	if not render or not render.Push3DView or not render.ViewDrawScene or not render.PopView then
		return
	end

	if not projCamState.texture then
		return
	end

	-- Configure for preview window
	local savedOrigin = view.origin
	local savedAngles = view.angles
	local savedFov = view.fov
	local savedX, savedY = view.x, view.y
	local savedW, savedH = view.width, view.height

	view.origin = projCamState.smoothedPos
	view.angles = projCamState.smoothedAngles
	view.fov = projCamConfig.fov

	-- CRITICAL: Set viewport to match the render target size
	view.x = 0
	view.y = 0
	view.width = projCamConfig.width
	view.height = projCamConfig.height

	render.Push3DView(view, E_ClearFlags.VIEW_CLEAR_COLOR | E_ClearFlags.VIEW_CLEAR_DEPTH, projCamState.texture)
	render.ViewDrawScene(true, true, view)
	render.PopView()

	view.origin = savedOrigin
	view.angles = savedAngles
	view.fov = savedFov
	view.x = savedX
	view.y = savedY
	view.width = savedW
	view.height = savedH
end

local function projectToCamera(worldPos, camOrigin, camAngles, fov, winX, winY, winW, winH)
	if not projCamState.lastView then
		return nil
	end

	-- Create a temporary view setup for projection
	-- We use a copy of the last captured view to ensure all engine flags are correct
	local tempView = projCamState.lastView
	tempView.origin = camOrigin
	tempView.angles = camAngles
	tempView.fov = fov
	tempView.x = 0
	tempView.y = 0
	tempView.width = winW
	tempView.height = winH

	local screenPos = client.WorldToScreen(worldPos, tempView)
	if not screenPos then
		return nil
	end

	-- Offset by window position because the view was relative to the texture (0,0)
	return { screenPos[1] + winX, screenPos[2] + winY }
end

-- Check if a point is within the camera window bounds
local function isInBounds(pos, winX, winY, winW, winH)
	return pos and pos[1] >= winX and pos[1] <= winX + winW and pos[2] >= winY and pos[2] <= winY + winH
end

-- Draw an outlined line for better visibility.
local function drawOutlinedLine(from, to)
	setColor(config.outline.r, config.outline.g, config.outline.b, config.outline.a)
	if math.abs(from[1] - to[1]) > math.abs(from[2] - to[2]) then
		drawLine(math.floor(from[1]), math.floor(from[2] - 1), math.floor(to[1]), math.floor(to[2] - 1))
		drawLine(math.floor(from[1]), math.floor(from[2] + 1), math.floor(to[1]), math.floor(to[2] + 1))
	else
		drawLine(math.floor(from[1] - 1), math.floor(from[2]), math.floor(to[1] - 1), math.floor(to[2]))
		drawLine(math.floor(from[1] + 1), math.floor(from[2]), math.floor(to[1] + 1), math.floor(to[2]))
	end
end

local function drawProjCamTrajectory()
	local cache = projCamState.trajectory
	if not cache.isValid then
		return
	end

	local camOrigin = projCamState.smoothedPos
	local camAngles = projCamState.smoothedAngles
	local fov = projCamConfig.fov
	local winX, winY = projCamConfig.x, projCamConfig.y
	local winW, winH = projCamConfig.width, projCamConfig.height

	local lastScreen = nil
	for i = #cache.positions, 1, -1 do
		local worldPos = cache.positions[i]
		local screenPos = projectToCamera(worldPos, camOrigin, camAngles, fov, winX, winY, winW, winH)

		if lastScreen and screenPos then
			-- MANDATORY: Only draw if BOTH points are within window bounds.
			if isInBounds(screenPos, winX, winY, winW, winH) and isInBounds(lastScreen, winX, winY, winW, winH) then
				if config.line.enabled then
					if config.outline.line_and_flags then
						drawOutlinedLine(lastScreen, screenPos)
					end
					setColor(config.line.r, config.line.g, config.line.b, config.line.a)
					drawLine(
						math.floor(lastScreen[1]),
						math.floor(lastScreen[2]),
						math.floor(screenPos[1]),
						math.floor(screenPos[2])
					)
				end

				-- Also draw flags/upward markers if enabled
				local flagScreenPos =
					projectToCamera(worldPos + cache.flagOffset, camOrigin, camAngles, fov, winX, winY, winW, winH)
				if config.flags.enabled and isInBounds(flagScreenPos, winX, winY, winW, winH) then
					if config.outline.line_and_flags then
						drawOutlinedLine(flagScreenPos, screenPos)
					end
					setColor(config.flags.r, config.flags.g, config.flags.b, config.flags.a)
					drawLine(
						math.floor(flagScreenPos[1]),
						math.floor(flagScreenPos[2]),
						math.floor(screenPos[1]),
						math.floor(screenPos[2])
					)
				end
			end
		end
		lastScreen = screenPos
	end

	-- Impact circle rendering in preview
	if cache.impactPos and cache.impactPlane and config.polygon.enabled then
		local origin = cache.impactPos
		local plane = cache.impactPlane
		local polygonPositions = {}
		local radius = config.polygon.size
		local segments = config.polygon.segments
		local segAngleOffset = math.pi / segments
		local segAngle = (math.pi / segments) * 2

		local allIn = true

		if math.abs(plane.z) >= 0.99 then
			for i = 1, segments do
				local ang = i * segAngle + segAngleOffset
				local pos = projectToCamera(
					origin + Vector3(radius * math.cos(ang), radius * math.sin(ang), 0),
					camOrigin,
					camAngles,
					fov,
					winX,
					winY,
					winW,
					winH
				)
				if not isInBounds(pos, winX, winY, winW, winH) then
					allIn = false
					break
				end
				polygonPositions[i] = pos
			end
		else
			local right = Vector3(-plane.y, plane.x, 0)
			local up = Vector3(plane.z * right.y, -plane.z * right.x, (plane.y * right.x) - (plane.x * right.y))
			radius = radius / math.cos(math.asin(plane.z))
			for i = 1, segments do
				local ang = i * segAngle + segAngleOffset
				local pos = projectToCamera(
					origin + (right * (radius * math.cos(ang))) + (up * (radius * math.sin(ang))),
					camOrigin,
					camAngles,
					fov,
					winX,
					winY,
					winW,
					winH
				)
				if not isInBounds(pos, winX, winY, winW, winH) then
					allIn = false
					break
				end
				polygonPositions[i] = pos
			end
		end

		-- Only draw the impact circle if 100% of it is bounded within the preview window
		if allIn then
			setColor(config.polygon.r, config.polygon.g, config.polygon.b, 255)
			local last = polygonPositions[#polygonPositions]
			for i = 1, #polygonPositions do
				local cur = polygonPositions[i]
				drawLine(math.floor(last[1]), math.floor(last[2]), math.floor(cur[1]), math.floor(cur[2]))
				last = cur
			end
		end
	end
end

local function drawProjCamTexture()
	if not projCamState.trajectory.isValid then
		return
	end

	if not projCamState.material then
		return
	end

	if not render or not render.DrawScreenSpaceRectangle then
		return
	end

	render.DrawScreenSpaceRectangle(
		projCamState.material,
		projCamConfig.x,
		projCamConfig.y,
		projCamConfig.width,
		projCamConfig.height,
		0,
		0,
		projCamConfig.width,
		projCamConfig.height,
		projCamConfig.width,
		projCamConfig.height
	)

	drawProjCamTrajectory()
end

-------------------------------
-- ITEM DEFINITIONS MAPPING
-------------------------------
local ItemDefinitions = {}
do
	local defs = {
		[222] = 11,
		[812] = 12,
		[833] = 12,
		[1121] = 11,
		[18] = -1,
		[205] = -1,
		[127] = -1,
		[228] = -1,
		[237] = -1,
		[414] = -1,
		[441] = -1,
		[513] = -1,
		[658] = -1,
		[730] = -1,
		[800] = -1,
		[809] = -1,
		[889] = -1,
		[898] = -1,
		[907] = -1,
		[916] = -1,
		[965] = -1,
		[974] = -1,
		[1085] = -1,
		[1104] = -1,
		[15006] = -1,
		[15014] = -1,
		[15028] = -1,
		[15043] = -1,
		[15052] = -1,
		[15057] = -1,
		[15081] = -1,
		[15104] = -1,
		[15105] = -1,
		[15129] = -1,
		[15130] = -1,
		[15150] = -1,
		[442] = -1,
		[1178] = -1,
		[39] = 8,
		[351] = 8,
		[595] = 8,
		[740] = 8,
		[1180] = 0,
		[19] = 5,
		[206] = 5,
		[308] = 5,
		[996] = 6,
		[1007] = 5,
		[1151] = 4,
		[15077] = 5,
		[15079] = 5,
		[15091] = 5,
		[15092] = 5,
		[15116] = 5,
		[15117] = 5,
		[15142] = 5,
		[15158] = 5,
		[20] = 1,
		[207] = 1,
		[130] = 3,
		[265] = 3,
		[661] = 1,
		[797] = 1,
		[806] = 1,
		[886] = 1,
		[895] = 1,
		[904] = 1,
		[913] = 1,
		[962] = 1,
		[971] = 1,
		[1150] = 2,
		[15009] = 1,
		[15012] = 1,
		[15024] = 1,
		[15038] = 1,
		[15045] = 1,
		[15048] = 1,
		[15082] = 1,
		[15083] = 1,
		[15084] = 1,
		[15113] = 1,
		[15137] = 1,
		[15138] = 1,
		[15155] = 1,
		[588] = -1,
		[997] = 9,
		[17] = 10,
		[204] = 10,
		[36] = 10,
		[305] = 9,
		[412] = 10,
		[1079] = 9,
		[56] = 7,
		[1005] = 7,
		[1092] = 7,
		[58] = 11,
		[1083] = 11,
		[1105] = 11,
	}
	local maxIndex = 0
	for k, _ in pairs(defs) do
		if k > maxIndex then
			maxIndex = k
		end
	end
	for i = 1, maxIndex do
		ItemDefinitions[i] = defs[i] or false
	end
end

-------------------------------
-- PHYSICS ENVIRONMENT CLASS
-------------------------------
local PhysicsEnv = {}
PhysicsEnv.__index = PhysicsEnv

function PhysicsEnv:new()
	if not physics or not physics.CreateEnvironment then
		error("Physics API not available")
	end
	local env = physics.CreateEnvironment()
	if not env then
		error("Failed to create physics environment")
	end
	env:SetGravity(Vector3(0, 0, -800))
	env:SetAirDensity(2.0)
	env:SetSimulationTimestep(globals.TickInterval() or (1 / 66))
	self = setmetatable({
		env = env,
		objects = {},
		activeIndex = 0,
	}, PhysicsEnv)
	return self
end

function PhysicsEnv:initializeObjects()
	if #self.objects > 0 then
		return
	end
	local function addObject(path)
		if not physics or not physics.ParseModelByName then
			error("Physics ParseModelByName API not available")
		end
		local solid, model = physics.ParseModelByName(path)
		if not solid or not model then
			error("Failed to parse model: " .. tostring(path))
		end
		local surfaceProp = solid:GetSurfacePropName()
		local objParams = solid:GetObjectParameters()
		if not surfaceProp or not objParams then
			error("Failed to get model properties for: " .. tostring(path))
		end
		local obj = self.env:CreatePolyObject(model, surfaceProp, objParams)
		if not obj then
			error("Failed to create physics object for: " .. tostring(path))
		end
		table.insert(self.objects, obj)
	end
	addObject("models/weapons/w_models/w_stickybomb.mdl") -- Stickybomb
	addObject("models/workshop/weapons/c_models/c_kingmaker_sticky/w_kingmaker_stickybomb.mdl") -- QuickieBomb
	addObject("models/weapons/w_models/w_stickybomb_d.mdl") -- ScottishResistance, StickyJumper
	if #self.objects > 0 then
		self.objects[1]:Wake()
		self.activeIndex = 1
	end
end

function PhysicsEnv:destroyObjects()
	self.activeIndex = 0
	for i, obj in ipairs(self.objects) do
		self.env:DestroyObject(obj)
	end
	self.objects = {}
end

function PhysicsEnv:getObject(index)
	if index < 1 or index > #self.objects then
		error("Invalid physics object index: " .. tostring(index))
	end
	if index ~= self.activeIndex then
		local currentObj = self.objects[self.activeIndex]
		if currentObj then
			currentObj:Sleep()
		end
		local newObj = self.objects[index]
		if not newObj then
			error("Physics object at index " .. tostring(index) .. " is nil")
		end
		newObj:Wake()
		self.activeIndex = index
	end
	return self.objects[self.activeIndex]
end

function PhysicsEnv:simulate(dt)
	self.env:Simulate(dt)
end

function PhysicsEnv:reset()
	self.env:ResetSimulationClock()
end

function PhysicsEnv:destroy()
	self:destroyObjects()
	physics.DestroyEnvironment(self.env)
end

-------------------------------
-- TRAJECTORY LINE CLASS
-------------------------------
local TrajectoryLine = {}
TrajectoryLine.__index = TrajectoryLine

function TrajectoryLine:new()
	self = setmetatable({}, TrajectoryLine)
	self.positions = {}
	self.flagOffset = Vector3(0, 0, 0)
	return self
end

function TrajectoryLine:clear()
	self.positions = {}
end

function TrajectoryLine:insert(pos)
	table.insert(self.positions, pos)
end

function TrajectoryLine:render()
	local num = #self.positions
	if num < 2 then
		return
	end
	local lastScreen = nil
	for i = num, 1, -1 do
		local worldPos = self.positions[i]
		local screenPos = worldToScreen(worldPos)
		local flagScreenPos = worldToScreen(worldPos + self.flagOffset)
		if lastScreen and screenPos then
			if config.line.enabled then
				if config.outline.line_and_flags then
					drawOutlinedLine(lastScreen, screenPos)
				end
				setColor(config.line.r, config.line.g, config.line.b, config.line.a)
				drawLine(lastScreen[1], lastScreen[2], screenPos[1], screenPos[2])
			end
			if config.flags.enabled and flagScreenPos then
				if config.outline.line_and_flags then
					drawOutlinedLine(flagScreenPos, screenPos)
				end
				setColor(config.flags.r, config.flags.g, config.flags.b, config.flags.a)
				drawLine(flagScreenPos[1], flagScreenPos[2], screenPos[1], screenPos[2])
			end
		end
		lastScreen = screenPos
	end
end

-------------------------------
-- IMPACT POLYGON CLASS
-------------------------------
local ImpactPolygon = {}
ImpactPolygon.__index = ImpactPolygon

function ImpactPolygon.new()
	local tex = draw.CreateTextureRGBA(
		string.char(
			0xff,
			0xff,
			0xff,
			config.polygon.a,
			0xff,
			0xff,
			0xff,
			config.polygon.a,
			0xff,
			0xff,
			0xff,
			config.polygon.a,
			0xff,
			0xff,
			0xff,
			config.polygon.a
		),
		2,
		2
	)
	local instance = setmetatable({
		texture = tex,
		segments = config.polygon.segments,
		segAngleOffset = math.pi / config.polygon.segments,
		segAngle = (math.pi / config.polygon.segments) * 2,
	}, ImpactPolygon)
	return instance
end

function ImpactPolygon:draw(plane, origin)
	if not config.polygon.enabled then
		return
	end
	local positions = {}
	local radius = config.polygon.size
	if math.abs(plane.z) >= 0.99 then
		for i = 1, self.segments do
			local ang = i * self.segAngle + self.segAngleOffset
			local pos = worldToScreen(origin + Vector3(radius * math.cos(ang), radius * math.sin(ang), 0))
			if not pos then
				return
			end
			positions[i] = pos
		end
	else
		local right = Vector3(-plane.y, plane.x, 0)
		local up = Vector3(plane.z * right.y, -plane.z * right.x, (plane.y * right.x) - (plane.x * right.y))
		radius = radius / math.cos(math.asin(plane.z))
		for i = 1, self.segments do
			local ang = i * self.segAngle + self.segAngleOffset
			local pos = worldToScreen(origin + (right * (radius * math.cos(ang))) + (up * (radius * math.sin(ang))))
			if not pos then
				return
			end
			positions[i] = pos
		end
	end

	-- Draw outline if enabled.
	if config.outline.polygon then
		setColor(config.outline.r, config.outline.g, config.outline.b, config.outline.a)
		local last = positions[#positions]
		for i = 1, #positions do
			local cur = positions[i]
			drawLine(last[1], last[2], cur[1], cur[2])
			last = cur
		end
	end

	-- Draw filled polygon.
	setColor(config.polygon.r, config.polygon.g, config.polygon.b, 255)
	local pts, ptsReversed = {}, {}
	local sum = 0
	for i, pos in ipairs(positions) do
		local pt = { pos[1], pos[2], 0, 0 }
		pts[i] = pt
		ptsReversed[#positions - i + 1] = pt
		local nextPos = positions[(i % #positions) + 1]
		sum = sum + cross(pos, nextPos, positions[1])
	end
	local polyPts = (sum < 0) and ptsReversed or pts
	if texturedPolygon and self.texture then
		texturedPolygon(self.texture, polyPts, true)
	end

	-- Draw final outline.
	local last = positions[#positions]
	for i = 1, #positions do
		local cur = positions[i]
		drawLine(last[1], last[2], cur[1], cur[2])
		last = cur
	end
end

function ImpactPolygon:destroy()
	if self.texture then
		draw.DeleteTexture(self.texture)
		self.texture = nil
	end
end

----------------------------------------
-- PROJECTILE INFORMATION FUNCTION
----------------------------------------
-- Returns (offset, forward velocity, upward velocity, collision hull, gravity, drag)
local function GetProjectileInformation(pWeapon, bDucking, iCase, iDefIndex, iWepID, pLocal)
	local chargeTime = pWeapon:GetPropFloat("m_flChargeBeginTime") or 0

	-- If using stored charge (set via scroll), use that for trajectory visualization
	if bombardMode.useStoredCharge and iCase == 1 then
		chargeTime = bombardMode.chargeLevel * 4.0 -- Max charge in 4 seconds
	elseif chargeTime ~= 0 then
		chargeTime = globals.CurTime() - chargeTime
	end

	-- Predefined offsets and collision sizes:
	local offsets = {
		Vector3(16, 8, -6), -- Index 1: Sticky Bomb, Iron Bomber, etc.
		Vector3(23.5, -8, -3), -- Index 2: Huntsman, Crossbow, etc.
		Vector3(23.5, 12, -3), -- Index 3: Flare Gun, Guillotine, etc.
		Vector3(16, 6, -8), -- Index 4: Syringe Gun, etc.
	}
	local collisionMaxs = {
		Vector3(0, 0, 0), -- For projectiles that use TRACE_LINE (e.g. rockets)
		Vector3(1, 1, 1),
		Vector3(2, 2, 2),
		Vector3(3, 3, 3),
	}

	if iCase == -1 then
		-- Rocket Launcher types: force a zero collision hull so that TRACE_LINE is used.
		local vOffset = Vector3(23.5, -8, bDucking and 8 or -3)
		local vCollisionMax = collisionMaxs[1] -- Zero hitbox
		local fForwardVelocity = 1200
		if iWepID == 22 or iWepID == 65 then
			vOffset.y = (iDefIndex == 513) and 0 or 12
			fForwardVelocity = (iWepID == 65) and 2000 or ((iDefIndex == 414) and 1550 or 1100)
		elseif iWepID == 109 then
			vOffset.y, vOffset.z = 6, -3
		else
			fForwardVelocity = 1200
		end
		return vOffset, fForwardVelocity, 0, vCollisionMax, 0, nil
	elseif iCase == 1 then
		return offsets[1], 900 + clamp(chargeTime / 4, 0, 1) * 1500, 200, collisionMaxs[3], 0, nil
	elseif iCase == 2 then
		return offsets[1], 900 + clamp(chargeTime / 1.2, 0, 1) * 1500, 200, collisionMaxs[3], 0, nil
	elseif iCase == 3 then
		return offsets[1], 900 + clamp(chargeTime / 4, 0, 1) * 1500, 200, collisionMaxs[3], 0, nil
	elseif iCase == 4 then
		return offsets[1], 1200, 200, collisionMaxs[4], 400, 0.45
	elseif iCase == 5 then
		local vel = (iDefIndex == 308) and 1500 or 1200
		local drag = (iDefIndex == 308) and 0.225 or 0.45
		return offsets[1], vel, 200, collisionMaxs[4], 400, drag
	elseif iCase == 6 then
		return offsets[1], 1440, 200, collisionMaxs[3], 560, 0.5
	elseif iCase == 7 then
		return offsets[2],
			1800 + clamp(chargeTime, 0, 1) * 800,
			0,
			collisionMaxs[2],
			200 - clamp(chargeTime, 0, 1) * 160,
			nil
	elseif iCase == 8 then
		-- Flare Gun: Use a small nonzero collision hull and a higher drag value to make drag noticeable.
		return Vector3(23.5, 12, bDucking and 8 or -3), 2000, 0, Vector3(0.1, 0.1, 0.1), 120, 0.5
	elseif iCase == 9 then
		local idx = (iDefIndex == 997) and 2 or 4
		return offsets[2], 2400, 0, collisionMaxs[idx], 80, nil
	elseif iCase == 10 then
		return offsets[4], 1000, 0, collisionMaxs[2], 120, nil
	elseif iCase == 11 then
		return Vector3(23.5, 8, -3), 1000, 200, collisionMaxs[4], 450, nil
	elseif iCase == 12 then
		return Vector3(23.5, 8, -3), 3000, 300, collisionMaxs[3], 900, 1.3
	end
end

-------------------------------
-- GLOBALS & INITIALIZATION
-------------------------------
local physicsEnv = PhysicsEnv:new()
if not physicsEnv then
	return -- Physics API unavailable, disable script
end
local trajectoryLine = TrajectoryLine:new()
local impactPolygon = ImpactPolygon:new()
projCamState.storedPolygonTexture = impactPolygon.texture

local g_fTraceInterval = clamp(config.measure_segment_size, 0.5, 8) / 66
local g_fFlagInterval = g_fTraceInterval * 1320

-------------------------------
-- BOMBARDING AIM LOGIC
-------------------------------
local function ExecuteBombardingAim(cmd)
	-- Always active when camera window is visible
	if not projCamState.active then
		return
	end

	local pLocal = entities.GetLocalPlayer()
	if not pLocal or not pLocal:IsValid() or not pLocal:IsAlive() then
		return
	end

	local pWeapon = pLocal:GetPropEntity("m_hActiveWeapon")
	if not pWeapon or not pWeapon:IsValid() then
		return
	end

	-- Get weapon type
	local iItemDefinitionIndex = pWeapon:GetPropInt("m_iItemDefinitionIndex")
	if not iItemDefinitionIndex then
		return
	end

	-- Guard: Only work for projectile weapons (Primary/Secondary)
	local projectileType = pWeapon:GetWeaponProjectileType()
	if not projectileType or projectileType < 2 then
		bombardAim.calculatedPitch = nil
		projCamState.trajectory.isValid = false
		return
	end

	local weaponType = ItemDefinitions[iItemDefinitionIndex] or 0

	-- 1. Get accurate projectile info for current weapon state
	local weaponID = pWeapon:GetWeaponID()
	local iItemDef = pWeapon:GetPropInt("m_iItemDefinitionIndex")
	local iCase = ItemDefinitions[iItemDef] or 0
	local isDucking = (pLocal:GetPropInt("m_fFlags") & 2) ~= 0

	local vOffset, fForwardVelocity, fUpwardVelocity, vCollisionMax, fGravity, fDrag =
		GetProjectileInformation(pWeapon, isDucking, iCase, iItemDef, weaponID or 0, pLocal)

	local baseSpeed = 900
	local maxSpeed = 2400
	if iCase == 4 or iCase == 5 or iCase == 6 then -- Grenades/Launchers
		baseSpeed = fForwardVelocity
		maxSpeed = fForwardVelocity
	end

	local hasCharge = (iCase == 1 or iCase == 3)
	local gravity = fGravity > 0 and fGravity or STICKY_GRAVITY

	-- 2. Calculate dynamic max distance
	local maxRangeSpeed = hasCharge and maxSpeed or fForwardVelocity
	bombardAim.maxDistance = (maxRangeSpeed * maxRangeSpeed) / gravity -- Basic estimate

	-- 3. Simple point control logic
	local mouseX = cmd.mousedx or 0
	local mouseY = cmd.mousedy or 0

	-- Mouse Y controls distance with fixed ratio (0.50 units per pixel)
	if gui.GetValue("Menu") ~= 1 then
		local distanceDelta = -mouseY * 0.50
		bombardAim.targetDistance = clamp(bombardAim.targetDistance + distanceDelta, 0, bombardAim.maxDistance)
	end

	-- Get player's absolute position
	local absOrigin = pLocal:GetAbsOrigin()
	local viewAngles = engine.GetViewAngles()
	if not absOrigin or not viewAngles then
		return
	end

	-- 4. Calculate accurate start position
	local viewOffset = pLocal:GetPropVector("localdata", "m_vecViewOffset[0]")
	local vHeadPos = absOrigin + viewOffset

	-- Account for weapon offset as simulation does
	local vStartPos = vHeadPos
		+ (viewAngles:Forward() * vOffset.x)
		+ (viewAngles:Right() * (vOffset.y * (pWeapon:IsViewModelFlipped() and -1 or 1)))
		+ (viewAngles:Up() * vOffset.z)

	bombardAim.originPoint = vStartPos

	-- 5. Set target point at calculated distance on the yaw line
	local yawRad = math.rad(viewAngles.y)
	local direction = Vector3(math.cos(yawRad), math.sin(yawRad), 0)

	local targetZ = 0
	if projCamState.trajectory.isValid and projCamState.trajectory.impactPos then
		targetZ = projCamState.trajectory.impactPos.z - vStartPos.z
	end

	bombardAim.targetPoint = vStartPos + (direction * bombardAim.targetDistance) + Vector3(0, 0, targetZ)

	-- 6. Precise Ballistic Solver (accounts for upward boost)
	local dx = bombardAim.targetDistance
	local dy = targetZ

	local function checkSolution(speed, pitch)
		local ang = EulerAngles(pitch, viewAngles.y, 0)
		local vVel = (ang:Forward() * speed) + (ang:Up() * fUpwardVelocity)

		-- Use basic kinematics for high performance solver
		-- dy = v_z * t - 0.5 * g * t^2
		-- dx = v_x * t
		local vx = math.sqrt(vVel.x * vVel.x + vVel.y * vVel.y)
		local vz = vVel.z

		if vx < 1 then
			return -999999
		end
		local t = dx / vx
		return (vz * t) - (0.5 * gravity * t * t)
	end

	local function findPitchForArc(speed, isHighArc)
		-- Search range based on arc preference
		local lowP, highP = (isHighArc and -89 or -45), (isHighArc and -45 or 89)
		local bestP = nil

		for i = 1, 15 do
			local mid = (lowP + highP) / 2
			local hitZ = checkSolution(speed, mid)

			if isHighArc then
				-- High Arc: aim more UP (-89) to hit shorter/lower at dx
				if hitZ > dy then
					highP = mid
				else
					lowP = mid
				end
			else
				-- Low Arc: aim more DOWN (89) to hit shorter/lower at dx
				if hitZ > dy then
					lowP = mid
				else
					highP = mid
				end
			end
			bestP = mid
		end

		-- Final validation
		local finalZ = checkSolution(speed, bestP)
		if math.abs(finalZ - dy) < 100 then
			return bestP
		end
		return nil
	end

	if hasCharge then
		local bestCharge, bestPitch = nil, nil

		-- Try both arcs and find the lowest charge required
		for _, isHigh in ipairs({ bombardAim.useHighArc, not bombardAim.useHighArc }) do
			local maxC, minC = 1.0, 0.0
			for i = 1, 15 do
				local mid = (maxC + minC) / 2
				local speed = baseSpeed + mid * (maxSpeed - baseSpeed)
				local pitch = findPitchForArc(speed, isHigh)
				if pitch then
					bestCharge, bestPitch = mid, pitch
					maxC = mid
				else
					minC = mid
				end
			end
			if bestPitch then
				break
			end
		end

		bombardMode.chargeLevel = bestCharge or 1.0
		bombardAim.calculatedPitch = bestPitch
	else
		-- Try preferred arc, fallback to other
		local pitch = findPitchForArc(baseSpeed, bombardAim.useHighArc)
		if not pitch then
			pitch = findPitchForArc(baseSpeed, not bombardAim.useHighArc)
		end
		bombardAim.calculatedPitch = pitch
		bombardMode.chargeLevel = 0
	end

	if bombardAim.calculatedPitch then
		cmd.mousedx = 0
		cmd.mousedy = 0

		local aimAngles = EulerAngles(bombardAim.calculatedPitch, viewAngles.y, 0)
		engine.SetViewAngles(aimAngles)
		cmd.viewangles = Vector3(bombardAim.calculatedPitch, viewAngles.y, 0)

		bombardMode.useStoredCharge = hasCharge
	else
		bombardAim.originPoint = nil
		bombardAim.targetPoint = nil
	end
end

----------------------------------------
-- UNIFIED PROJECTILE SIMULATION
----------------------------------------
local function UpdateProjectileSimulation(cmd)
	local cache = projCamState.trajectory

	-- Clear previous cache
	cache.positions = {}
	cache.velocities = {}
	cache.impactPos = nil
	cache.impactPlane = nil
	cache.isValid = false

	local pLocal = entities.GetLocalPlayer()
	if not pLocal or not pLocal:IsValid() or pLocal:InCond(7) or not pLocal:IsAlive() then
		return
	end

	local pWeapon = pLocal:GetPropEntity("m_hActiveWeapon")
	if not pWeapon or not pWeapon:IsValid() then
		return
	end

	local projectileType = pWeapon:GetWeaponProjectileType()
	if not projectileType or projectileType < 2 then
		return
	end

	local iItemDefinitionIndex = pWeapon:GetPropInt("m_iItemDefinitionIndex")
	if not iItemDefinitionIndex then
		return
	end
	local iItemDefinitionType = ItemDefinitions[iItemDefinitionIndex] or 0
	if iItemDefinitionType == 0 then
		return
	end

	local weaponID = pWeapon:GetWeaponID()
	if not weaponID then
		return
	end

	local vOffset, fForwardVelocity, fUpwardVelocity, vCollisionMax, fGravity, fDrag = GetProjectileInformation(
		pWeapon,
		(pLocal:GetPropInt("m_fFlags") & FL_DUCKING) == 2,
		iItemDefinitionType,
		iItemDefinitionIndex,
		weaponID,
		pLocal
	)
	local vCollisionMin = -vCollisionMax

	-- CRITICAL: Always use physics origin and command view angles
	local vStartPosition = pLocal:GetAbsOrigin() + pLocal:GetPropVector("localdata", "m_vecViewOffset[0]")
	local vStartAngle = cmd and EulerAngles(cmd.viewangles.x, cmd.viewangles.y, cmd.viewangles.z)
		or engine.GetViewAngles()

	local results = traceHull(
		vStartPosition,
		vStartPosition
			+ (vStartAngle:Forward() * vOffset.x)
			+ (vStartAngle:Right() * (vOffset.y * (pWeapon:IsViewModelFlipped() and -1 or 1)))
			+ (vStartAngle:Up() * vOffset.z),
		vCollisionMin,
		vCollisionMax,
		100679691
	)
	if results.fraction ~= 1 then
		return
	end
	vStartPosition = results.endpos

	if
		iItemDefinitionType == -1
		or ((iItemDefinitionType >= 7 and iItemDefinitionType < 11) and fForwardVelocity ~= 0)
	then
		local res = traceLine(results.startpos, results.startpos + (vStartAngle:Forward() * 2000), 100679691)
		vStartAngle = (
			((res.fraction <= 0.1) and (results.startpos + (vStartAngle:Forward() * 2000)) or res.endpos)
			- vStartPosition
		):Angles()
	end

	local vVelocity = (vStartAngle:Forward() * fForwardVelocity) + (vStartAngle:Up() * fUpwardVelocity)
	cache.flagOffset = vStartAngle:Right() * -config.flags.size

	table.insert(cache.positions, vStartPosition)
	table.insert(cache.velocities, vVelocity)

	if iItemDefinitionType == -1 then
		results = traceHull(
			vStartPosition,
			vStartPosition + (vStartAngle:Forward() * 10000),
			vCollisionMin,
			vCollisionMax,
			100679691
		)
		if results.startsolid then
			return
		end
		local segCount = math.floor((results.endpos - results.startpos):Length() / g_fFlagInterval)
		local vForward = vStartAngle:Forward()
		for i = 1, segCount do
			local segPos = vForward * (i * g_fFlagInterval) + vStartPosition
			table.insert(cache.positions, segPos)
			table.insert(cache.velocities, vVelocity)
		end
		table.insert(cache.positions, results.endpos)
		table.insert(cache.velocities, vVelocity)
	elseif iItemDefinitionType > 3 then
		local vPos = Vector3(0, 0, 0)
		for i = 0.01515, 5, g_fTraceInterval do
			local scalar = (fDrag == nil) and i or ((1 - math.exp(-fDrag * i)) / fDrag)
			vPos.x = vVelocity.x * scalar + vStartPosition.x
			vPos.y = vVelocity.y * scalar + vStartPosition.y
			vPos.z = (vVelocity.z - fGravity * i) * scalar + vStartPosition.z

			local vCurVel = Vector3(vVelocity.x, vVelocity.y, vVelocity.z - fGravity * i)
			if fDrag then
				local dragFactor = math.exp(-fDrag * i)
				vCurVel = Vector3(vCurVel.x * dragFactor, vCurVel.y * dragFactor, vCurVel.z * dragFactor)
			end

			if vCollisionMax.x ~= 0 then
				results = traceHull(results.endpos, vPos, vCollisionMin, vCollisionMax, 100679691)
			else
				results = traceLine(results.endpos, vPos, 100679691)
			end
			table.insert(cache.positions, results.endpos)
			table.insert(cache.velocities, vCurVel)
			if results.fraction ~= 1 then
				break
			end
		end
	else
		local obj = physicsEnv:getObject(iItemDefinitionType)
		obj:SetPosition(vStartPosition, vStartAngle, true)
		obj:SetVelocity(vVelocity, Vector3(0, 0, 0))
		local prevPos = vStartPosition
		for i = 2, 330 do
			local curPos = obj:GetPosition()
			if not curPos then
				break
			end
			results = traceHull(results.endpos, curPos, vCollisionMin, vCollisionMax, 100679691)

			local deltaPos = curPos - prevPos
			table.insert(cache.positions, results.endpos)
			table.insert(cache.velocities, deltaPos * 66)
			prevPos = curPos

			if results.fraction ~= 1 then
				break
			end
			physicsEnv:simulate(g_fTraceInterval)
		end
		physicsEnv:reset()
	end

	if results and results.plane then
		cache.impactPos = results.endpos
		cache.impactPlane = results.plane
	end
	cache.isValid = #cache.positions > 1

	-- Sync to legacy state for compatibility with UI rendering
	projCamState.storedPositions = cache.positions
	projCamState.storedVelocities = cache.velocities
	projCamState.storedImpactPos = cache.impactPos
	projCamState.storedImpactPlane = cache.impactPlane
	projCamState.storedFlagOffset = cache.flagOffset
end

callbacks.Register("CreateMove", "LoadPhysicsObjects", function()
	callbacks.Unregister("CreateMove", "LoadPhysicsObjects")
	physicsEnv:initializeObjects()

	callbacks.Register("CreateMove", "ArtilleryLogic", function(cmd)
		-- 1. Handle Input Toggles
		handleProjCamToggle()
		handleBombardModeToggle()
		handleBombardAimToggle()

		-- 2. Run Aiming Logic (sets view angles)
		ExecuteBombardingAim(cmd)

		-- 3. Run Simulation & Refresh Cache
		UpdateProjectileSimulation(cmd)

		-- 4. Handle Preview Window Input
		if projCamState.active then
			handleProjCamInput()
			updateProjCamSmoothing()
		end
	end)

	callbacks.Register("Draw", "ArtilleryDraw", function()
		if engine.Con_IsVisible() or engine.IsGameUIVisible() then
			return
		end

		local cache = projCamState.trajectory
		if not cache.isValid then
			return
		end

		-- Draw Impact Polygon
		if cache.impactPlane and cache.impactPos then
			impactPolygon:draw(cache.impactPlane, cache.impactPos)
		end

		-- Draw World Trajectory
		local num = #cache.positions
		local lastScreen = nil
		for i = num, 1, -1 do
			local worldPos = cache.positions[i]
			local screenPos = worldToScreen(worldPos)
			local flagScreenPos = worldToScreen(worldPos + cache.flagOffset)
			if lastScreen and screenPos then
				if config.line.enabled then
					if config.outline.line_and_flags then
						drawOutlinedLine(lastScreen, screenPos)
					end
					setColor(config.line.r, config.line.g, config.line.b, config.line.a)
					drawLine(lastScreen[1], lastScreen[2], screenPos[1], screenPos[2])
				end
				if config.flags.enabled and flagScreenPos then
					if config.outline.line_and_flags then
						drawOutlinedLine(flagScreenPos, screenPos)
					end
					setColor(config.flags.r, config.flags.g, config.flags.b, config.flags.a)
					drawLine(flagScreenPos[1], flagScreenPos[2], screenPos[1], screenPos[2])
				end
			end
			lastScreen = screenPos
		end

		-- drawAimGuideMainView()

		if isProjCamActive() then
			drawProjCamTexture()
			drawProjCamWindow()
			-- drawAimGuideCamera()
		end
	end)
end)

-------------------------------
-- PROJECTILE CAMERA RENDER
-------------------------------
callbacks.Register("PostRenderView", "ProjCamStoreView", function(view)
	if view then
		projCamState.lastView = view
	end
end)

callbacks.Register("DoPostScreenSpaceEffects", "ProjCamRender", function()
	if engine.Con_IsVisible() or engine.IsGameUIVisible() then
		return
	end

	if not isProjCamActive() then
		return
	end

	local pLocal = entities.GetLocalPlayer()
	if not pLocal or not pLocal:IsValid() or not pLocal:IsAlive() then
		return
	end

	local pWeapon = pLocal:GetPropEntity("m_hActiveWeapon")
	if not pWeapon or not pWeapon:IsValid() or pWeapon:GetWeaponProjectileType() < 2 then
		return
	end

	if not projCamState.lastView then
		return
	end

	if not initProjCamMaterials() then
		return
	end

	renderProjCamView(projCamState.lastView)
end)

-------------------------------
-- STICKY SPAM FIRING LOGIC
-------------------------------
callbacks.Register("CreateMove", "StickySpamFire", function(cmd)
	if not bombardMode.useStoredCharge then
		return
	end

	local pLocal = entities.GetLocalPlayer()
	if not pLocal or not pLocal:IsValid() or not pLocal:IsAlive() then
		return
	end

	local pWeapon = pLocal:GetPropEntity("m_hActiveWeapon")
	if not pWeapon or not pWeapon:IsValid() then
		return
	end

	-- Only work with sticky bomb launcher (item definition type 1)
	local iItemDefinitionIndex = pWeapon:GetPropInt("m_iItemDefinitionIndex")
	if not iItemDefinitionIndex then
		return
	end
	local iItemDefinitionType = ItemDefinitions[iItemDefinitionIndex] or 0
	if iItemDefinitionType ~= 1 then
		return
	end

	-- Get current charge percentage
	local chargeBeginTime = pWeapon:GetPropFloat("m_flChargeBeginTime")
	if not chargeBeginTime then
		chargeBeginTime = 0
	end
	local currentCharge = 0
	if chargeBeginTime > 0 then
		currentCharge = (globals.CurTime() - chargeBeginTime) / 4.0 -- 4 seconds = 100%
	end

	-- Target charge level from scroll setting
	local targetCharge = bombardMode.chargeLevel

	-- When current charge reaches target, release attack to fire the sticky
	if currentCharge >= targetCharge and chargeBeginTime > 0 then
		cmd.buttons = cmd.buttons & ~IN_ATTACK
	end
end)

-------------------------------
-- UNLOAD CALLBACK
-------------------------------
callbacks.Register("Unload", function()
	physicsEnv:destroy()
	impactPolygon:destroy()
	projCamState.texture = nil
	projCamState.material = nil
	projCamState.materialsReady = false
	projCamState.storedPositions = {}
	projCamState.storedVelocities = {}
end)
