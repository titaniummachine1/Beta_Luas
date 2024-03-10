--[[ Movement Recorder ]]

---@type boolean, lnxLib
local libLoaded, lnxLib = pcall(require, "lnxLib")
assert(libLoaded, "lnxLib not found, please install it!")
assert(lnxLib.GetVersion() >= 0.965, "lnxLib version is too old, please update it!")

local Fonts = lnxLib.UI.Fonts

---@type boolean, ImMenu
local menuLoaded, ImMenu = pcall(require, "ImMenu")
assert(menuLoaded, "ImMenu not found, please install it!")
assert(ImMenu.GetVersion() >= 0.66, "ImMenu version is too old, please update it!")


-- Constants for minimum and maximum speed
local MIN_SPEED = 100  -- Minimum speed to avoid jittery movements
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
    local velocity = pLocal:EstimateAbsVelocity():Length()

    -- If distance is greater than 1, proceed with walking
    if dist > 1 then
        local result = ComputeMove(pCmd, localPos, pDestination)
        -- If distance is less than 10, scale down the speed further
        if dist < 10 + velocity then
            local scaleFactor = dist / 100
            pCmd:SetForwardMove(result.x * scaleFactor)
            pCmd:SetSideMove(result.y * scaleFactor)
        else
            pCmd:SetForwardMove(result.x)
            pCmd:SetSideMove(result.y)
        end
    end
end

local currentTick = 0
local currentData = {}
local currentSize = 1

local isRecording = false
local isPlaying = false

local doRepeat = false
local doViewAngles = true

local vHitbox = {Min = Vector3(-23, -23, 0), Max = Vector3(23, 23, 81)}
local setuptimer = 128
local AtRightPos = false
---@param userCmd UserCmd
local function OnCreateMove(userCmd)
    local pLocal = entities.GetLocalPlayer()
    if not pLocal and pLocal:IsAlive() then return end

    if isRecording then
        AtRightPos = false
        local yaw, pitch, roll = userCmd:GetViewAngles()
        currentData[currentTick] = {
            viewAngles = EulerAngles(yaw, pitch, roll),
            forwardMove = userCmd:GetForwardMove(),
            sideMove = userCmd:GetSideMove(),
            buttons = userCmd:GetButtons(),
            position =  pLocal:GetAbsOrigin(),
        }

        currentSize = currentSize + 1
        currentTick = currentTick + 1
    elseif isPlaying then
        if userCmd.forwardmove ~= 0 or userCmd.sidemove ~= 0 then return end --input bypass

        if currentTick >= currentSize - 1 or currentTick >= currentSize + 1 then
            if doRepeat then
                currentTick = 0
                AtRightPos = false
            else
                AtRightPos = false
                isPlaying = false
            end
        end

        local data = currentData[currentTick]
        if currentData[currentTick] == nil then return end --dont do anyyhign if data is inalid

            userCmd:SetViewAngles(data.viewAngles:Unpack())
            userCmd:SetForwardMove(data.forwardMove)
            userCmd:SetSideMove(data.sideMove)
            userCmd:SetButtons(data.buttons)

            if doViewAngles then
                engine.SetViewAngles(data.viewAngles)
            end

            local distance = (pLocal:GetAbsOrigin() - data.position):Length()
            local velocityLength = pLocal:EstimateAbsVelocity():Length()

            velocityLength = math.max(0.1, math.min(velocityLength, 50))

            if not AtRightPos then
                WalkTo(userCmd, pLocal, data.position)
                if distance > velocityLength then
                    setuptimer = setuptimer - 1
                    if setuptimer < 1 and velocityLength < 5 or setuptimer < 66 and velocityLength < 1 then --or AntiStucktrace.fraction < 1 and setuptimer < 1 and velocityLength < 5 then
                        AtRightPos = true
                        setuptimer = 128
                    end
                    return
                end
            else
                if (distance < pLocal:EstimateAbsVelocity():Length() + 50) then
                    WalkTo(userCmd, pLocal, data.position)
                    if velocityLength < 1 then--or AntiStucktrace.fraction < 1 and velocityLength < 5 then
                        AtRightPos = true
                    end
                else
                    setuptimer = 128
                    AtRightPos = false
                end
            end

            --local AntiStucktrace = engine.TraceHull(pLocal:GetAbsOrigin(), data.position, vHitbox.Min, vHitbox.Max, MASK_PLAYERSOLID_BRUSHONLY)
            --f AntiStucktrace.fraction < 1 zthen
                currentTick = currentTick + 1
            --else
            --    currentTick = currentTick - 1
            --end
    end
end

local function Reset()
    AtRightPos = false
    isRecording = false
    isPlaying = false
    currentTick = 0
    currentData = {}
    currentSize = 1
end

local function OnDraw()
    draw.SetFont(Fonts.Verdana)
    draw.Color(255, 255, 255, 255)

    if isRecording then
        draw.Text(20, 120, string.format("Recording... (%d)", currentTick, currentSize))
    elseif not AtRightPos then
        draw.Text(20, 120, string.format("Preparing Starting Pos... (%d / %d)", currentTick, currentSize))
    elseif isPlaying then
        draw.Text(20, 120, string.format("Playing... (%d / %d)", currentTick, currentSize))
    end

    if not engine.IsGameUIVisible() and not (isPlaying or isRecording) then return end

    if ImMenu.Begin("Movement Recorder", true) then

        -- Progress bar
        ImMenu.BeginFrame(1)
        ImMenu.PushStyle("ItemSize", { 385, 30 })

        local MaxSize = (currentSize > 0 and currentSize < 1000 and isRecording and not isPlaying) and 1000 or currentSize
        if isRecording and (currentSize > MaxSize or currentTick > MaxSize) then
            MaxSize = math.max(currentSize, currentTick)
        end
        if isRecording then
            currentTick = ImMenu.Slider("Tick", currentTick, 0, MaxSize)
        else
            currentTick = ImMenu.Slider("Tick", currentTick, 0, currentSize)
        end

        ImMenu.PopStyle()
        ImMenu.EndFrame()

        -- Buttons
        ImMenu.BeginFrame(1)
        ImMenu.PushStyle("ItemSize", { 125, 30 })

            local recordButtonText = isRecording and "Stop Recording" or "Start Recording"
            if ImMenu.Button(recordButtonText) then
                isRecording = not isRecording
                if isRecording then
                    isPlaying = false
                    currentTick = 0
                    currentData = {}
                    currentSize = 1
                else
                    isPlaying = true
                end
            end

            local playButtonText
            if currentData[currentTick] == nil and currentTick == 0 then
                playButtonText = "No Record"
            elseif isPlaying then
                playButtonText = "Pause"
            else
                playButtonText = "Play"
            end

            if ImMenu.Button(playButtonText) then
                if isRecording then
                    isRecording = false
                    isPlaying = true
                    currentTick = 0
                elseif isPlaying then
                    isPlaying = false
                else
                    isPlaying = true
                    currentTick = 0
                end
            end

            if ImMenu.Button("Reset") then
                Reset()
            end

        ImMenu.PopStyle()
            ImMenu.EndFrame()

            -- Options
            ImMenu.BeginFrame(1)

                doRepeat = ImMenu.Checkbox("Auto Repeat", doRepeat)
                doViewAngles = ImMenu.Checkbox("Apply View Angles", doViewAngles)

            ImMenu.EndFrame()

        ImMenu.End()
    end
end

callbacks.Unregister("CreateMove", "LNX.Recorder.CreateMove")
callbacks.Register("CreateMove", "LNX.Recorder.CreateMove", OnCreateMove)

callbacks.Unregister("Draw", "LNX.Recorder.Draw")
callbacks.Register("Draw", "LNX.Recorder.Draw", OnDraw)