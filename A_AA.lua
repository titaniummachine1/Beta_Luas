--[[
    Advanced Antyaim Lua for lmaobox
    Author: github.com/titaniummachine1
]]
---@alias AimTarget { entity : Entity, pos : Vector3, angles : EulerAngles, factor : number }

---@type boolean, lnxLib
local libLoaded, lnxLib = pcall(require, "lnxLib")
assert(pcall(require, "lnxLib"), "lnxLib not found, please install it!")
--assert(lnxLib.GetVersion() >= 0.967, "LNXlib version is too old, please update it!")

client.SetConVar("cl_vWeapon_sway_interp", 0)              -- Set cl_vWeapon_sway_interp to 0
client.SetConVar("cl_jiggle_bone_framerate_cutoff", 0)     -- Set cl_jiggle_bone_framerate_cutoff to 0
client.SetConVar("cl_bobcycle", 10000)                     -- Set cl_bobcycle to 10000
client.SetConVar("sv_cheats", 1)                           -- debug fast setup
client.SetConVar("mp_disable_respawn_times", 1)
client.SetConVar("mp_respawnwavetime", -1)
client.SetConVar("mp_teams_unbalance_limit", 1000)
--client.Command('cl_interp 0', true)
--client.Command('cl_lerp 0', true)

--local mHeadShield        = menu:AddComponent(MenuLib.Checkbox("head Shield", true))

--menu:AddComponent(MenuLib.Label("                 Resolver(soon)"), ItemFlags.FullWidth)
--local BruteforceYaw       = menu:AddComponent(MenuLib.Checkbox("Bruteforce Yaw", false))
local pLocal
local pLocalOrigin
local tick_count    = 0
local pitch         = 0
local targetAngle = 0
local yaw_real      = nil
local yaw_Fake      = nil
local offset        = 0
local Angles_Real = 0
local Angles_Fake = 0
local pitchtype1    = gui.GetValue("Anti Aim - Pitch")
local players       = entities.FindByClass("CTFPlayer")
local pLocalView = Vector3()
local closestPoint1
local HeadOffsetHorizontal
local HeadHeightOffset
local Headpos
local Circle_Circle_segments = 8
local LocalViewAngle = engine.GetViewAngles()
local vheight = Vector3(0, 0, 70)
local distance1 = 0
local gotshot = false
local Latency = 0
local timershootdelay
local tickRate = client.GetConVar("sv_maxcmdrate")
local Serversite_angle

-- Global variable to hold reload times for each attacker
local attackerReloadTimes = {}


local Math          = lnxLib.Utils.Math
local WPlayer       = lnxLib.TF2.WPlayer
local Helpers       = lnxLib.TF2.Helpers

local currentTarget = nil

local settings = {
    MinDistance = 100,
    MaxDistance = 1000,
    MinFOV = 0,
    MaxFOV = 360,
}

--[[local function CanShoot(player)
    local pWeapon = player:GetPropEntity("m_hActiveWeapon")
    if (not pWeapon) or (pWeapon:IsMeleeWeapon()) then return false end

    local nextPrimaryAttack = pWeapon:GetPropFloat("LocalActiveWeaponData", "m_flNextPrimaryAttack")
    local nextAttack = player:GetPropFloat("bcc_localdata", "m_flNextAttack")
    if (not nextPrimaryAttack) or (not nextAttack) then return false end

    return nextPrimaryAttack, nextAttack
end]]

local targetList = {}

local function normalizeAngle(offsetNumber)
    offsetNumber = offsetNumber % 360
    if offsetNumber > 180 then
        offsetNumber = offsetNumber - 360
    elseif offsetNumber < -180 then
        offsetNumber = offsetNumber + 360
    end
    return offsetNumber
end

---@param me WPlayer
---@return AimTarget? target
local function GetBestTarget(me)
    players = entities.FindByClass("CTFPlayer")
    local localPlayer = entities.GetLocalPlayer()
    if not localPlayer then return end

    -- Clear previous target list
    targetList = {}
    --print(vheight)
    vheight = pLocal:GetPropVector("localdata", "m_vecViewOffset[0]")

    -- Calculate target factors
    for i, player in ipairs(players) do
        local classNum = player:GetPropInt("m_iClass")
        if classNum ~= 2 and classNum ~= 8 then goto continue end --class check ignore players who dont headshot
        if player == localPlayer
            or player:GetTeamNumber() == localPlayer:GetTeamNumber()
            or not player:IsAlive()
            or player:IsDormant() then goto continue end --filter non threats

        if classNum == 8 then --if spy
            if (gui.GetValue("ignore cloaked") == 1 and player:InCond(4)) then --ignore invisible spies
                goto continue
            end
        end

        local distance = (player:GetAbsOrigin() - localPlayer:GetAbsOrigin()):Length()

        -- Visibility Check
        local angles = Math.PositionAngles(pLocalOrigin + vheight, player:GetAbsOrigin() + Vector3(0, 0, 75))
        local fov = Math.AngleFov(LocalViewAngle, angles)

        local distanceFactor = Math.RemapValClamped(distance, settings.MinDistance, settings.MaxDistance, 1, 1)
        local fovFactor = Math.RemapValClamped(fov, settings.MinFOV, settings.MaxFOV, 1, 0.1)

        -- Assume visibilityFactor to be 0.5 for non-visible and 1 for visible targets
        local visibilityFactor = Helpers.VisPos(player, pLocal:GetAbsOrigin() + vheight, player:GetAbsOrigin() + Vector3(0, 0, 75)) and 1 or 0.5

        local ThreatFactor = attackerReloadTimes[player:GetIndex()] and 1 or 0.5


        local factor = distanceFactor * fovFactor * visibilityFactor * ThreatFactor

        targetList[i] = { player = player, factor = factor }

        ::continue:: --skips current player
    end



    -- Sort target list by factor
    table.sort(targetList, function(a, b)
        return a.factor > b.factor
    end)

    local bestTarget = nil

    if #targetList > 0 then
        local player = targetList[1].player
        local aimPos = player:GetAbsOrigin() + Vector3(0, 0, 75)
        local angles = Math.PositionAngles(localPlayer:GetAbsOrigin(), aimPos)
        local fov = Math.AngleFov(LocalViewAngle, angles)

        -- Set as best target
        bestTarget = { entity = player, angles = angles, factor = targetList[1].factor }
    end
    return bestTarget
end

-- Define resolver yaw settings
local resolverYawSettings = {
    ["default"] = 0,
    ["left"] = -90,
    ["right"] = 90,
    ["invert"] = 180,
    ["forward"] = 0,
    ["back"] = 180
}
-- Global variables
local targetResolverSettings = {}  -- Table to keep track of resolver settings for each target
local resolverSequence = {"default", "left", "right", "invert", "forward", "back"}

-- Function to get the next resolver setting in the sequence
local function getNextResolverSetting(currentSetting)
    for i, setting in ipairs(resolverSequence) do
        if setting == currentSetting then
            return resolverSequence[(i % #resolverSequence) + 1]
        end
    end
    return "default"  -- Default if not found
end

-- Function to predict the next yaw angle
local function predictNextYaw(currentYaw, currentSetting)
    local nextSetting = getNextResolverSetting(currentSetting)
    local offset1 = resolverYawSettings[nextSetting] or 0  -- Fixed typo here
    local nextYaw = currentYaw + offset1
    return normalizeAngle(nextYaw), nextSetting
end

-- Function to apply resolver yaw setting
local function applyResolverYaw(setting, currentYaw)
    local offset1 = resolverYawSettings[setting] or 0
    local newYaw = currentYaw + offset1
    return normalizeAngle(newYaw)
end

local fluctuation = 0
local function updateYaw(Real_offset, Fake_offset, userCmd)
    -- Get local player and local yaw
    local localPlayer = entities.GetLocalPlayer()
    local LocalYaw = LocalViewAngle.yaw
    
    if fluctuation == 0 then
        fluctuation = 180
    else
        fluctuation = 0
    end

    -- Calculate the real yaw based on target angle, offset and local yaw
    local realYaw = (targetAngle - LocalYaw) + Real_offset + fluctuation

    realYaw = math.floor(realYaw)
    -- Normalize real yaw
    realYaw = normalizeAngle(realYaw)
--todo add second dirction to negative check

    -- Update the GUI value for real yaw
    gui.SetValue("Anti Aim - Custom Yaw (Real)", realYaw)

    -- Calculate the fake yaw based on target angle, offset and local yaw
    local fakeYaw = (targetAngle - LocalYaw) + Fake_offset + fluctuation
    fakeYaw = math.floor(fakeYaw)

    -- Normalize fake yaw
    fakeYaw = normalizeAngle(fakeYaw)

    -- Update the GUI value for fake yaw
    gui.SetValue("Anti Aim - Custom Yaw (Fake)", fakeYaw)
end

local sniperdotspoitions = {}

local function UpdateSniperDots()
    local SniperDots = entities.FindByClass("CSniperDot")
    sniperdotspoitions = {}  -- Clear previous positions

    for key, SniperDot in pairs(SniperDots) do
        local position = SniperDot:GetAbsOrigin()
        local owner = SniperDot:GetPropEntity("m_hOwnerEntity"):GetName()  -- Replace with correct function if this is not it
        sniperdotspoitions[key] = {Position = position, Owner = owner}
         --print(SniperDot:GetPropEntity("m_hOwnerEntity"):GetName())
        --table.insert( SniperDot:GetPropEntity("m_hOwnerEntity"), {Laser = SniperDot:GetAbsOrigin()})
    end
end

-- Function to update reload times
local function updateReloadTimes()
    for attackerIndex, ticks in pairs(attackerReloadTimes) do
        if ticks > Latency then
            attackerReloadTimes[attackerIndex] = ticks - 1
        else
            attackerReloadTimes[attackerIndex] = nil  -- Remove the attacker from the table when reload time reaches 0
        end
    end
end

-- Function to add a new attacker to the table by index
local function addNewAttackerByIndex(attackerIndex)
    attackerReloadTimes[attackerIndex] = 99  -- Initialize reload time to 106 ticks
end

local queue = {}
local floor = math.floor
local x, y = draw.GetScreenSize()
local font_calibri = draw.CreateFont("Calibri", 18, 18)
local offsetNumber_right = 400
local offsetNumber_left = 480
local offsetNumber_back = 730
local offsetNumber_forward = 630

local offsetNumber = offsetNumber_back --274 -- 74 is forwrds offset 274 for back
local gotheadshot = false

local function event_hook(ev)
    if ev:GetName() ~= "player_hurt" then return end
    if not currentTarget then return end

        local victim_entity = entities.GetByUserID(ev:GetInt("userid"))
        local attacker = entities.GetByUserID(ev:GetInt("attacker"))
        local localplayer = entities.GetLocalPlayer()
        local damage = ev:GetInt("damageamount")
  
    if victim_entity ~= localplayer then return end
    gotshot = true

    local attackerIndex = attacker:GetIndex()

    addNewAttackerByIndex(attackerIndex)


    if damage > 50 then
        gotheadshot = true

        -- Anti-bruteforce
        local currentYaw = offsetNumber  -- Replace with the actual current yaw angle

        local currentSetting = targetResolverSettings[attacker] or "default"
        local nextYaw, nextSetting = predictNextYaw(currentYaw, currentSetting)
        print("Next Yaw: " .. nextYaw)
        print("Next Setting: " .. nextSetting)

        -- Update the resolver setting for the current target
        targetResolverSettings[currentTarget] = nextSetting

        -- Update angles
        offsetNumber = normalizeAngle(nextYaw)
        Angles_Fake = offsetNumber
        Angles_Real = -offsetNumber + 90
        Angles_Real = normalizeAngle(Angles_Real)

        print("Hit detected at offsets", Angles_Real)
    else
        -- Advance the attacker's resolver setting when you're hit
        local currentSetting = targetResolverSettings[attacker] or "default"
        local nextSetting = getNextResolverSetting(currentSetting)
        targetResolverSettings[attacker] = nextSetting
        print("Hit in the body by attacker, advancing to next setting: " .. nextSetting)
    end
    --gui.SetValue("Anti Aim", 0) --force aa update

    --insert table
    table.insert(queue, {
        string = string.format("Hit for %d damage (%d yaw offset)", damage, offsetNumber, iscrit),
        delay = globals.RealTime() + 5.5,
        alpha = 0,
    })

    printc(100, 255, 100, 255, string.format("[LMAOBOX] Hit for %d damage (%d yaw offset) ", damage, offsetNumber, iscrit))
end

local function paint_logs()
    draw.SetFont(font_calibri)
    for i, v in pairs(queue) do
        local alpha = floor(v.alpha)
        local text = v.string
        local y_pos = floor(y / 2) + (i * 20)
        players = entities.FindByClass("CTFPlayer")
        --for players 
        --local enemypos = 
        draw.Color(255, 255, 255, alpha)
        draw.Text(700, y_pos - 100, text)
    end
end

local function anim()
    for i, v in pairs(queue) do
        if globals.RealTime() < v.delay then --checks if delay is over or not
            v.alpha = math.min(v.alpha + 1, 255) --fade in animation
        else
            v.string = string.sub(v.string, 1, string.len(v.string) - 1) --removes last character
            if 0 >= string.len(v.string) then
                table.remove(queue, i) --if theres no text left, remove the table
            end
        end
    end
end
callbacks.Register("FireGameEvent", "unique_event_hook", event_hook)

local reloadTicks = 0
-- OnTickUpdate
local function OnCreateMove(userCmd)
    local me = WPlayer.GetLocal(); pLocal = entities.GetLocalPlayer()
    if not pLocal or not pLocal:IsAlive() or not me then return end
    if  gui.GetValue("Anti Aim") == 0 then
        --gui.SetValue("Anti Aim", 1)
    end
    updateReloadTimes()
    UpdateSniperDots() --refreshes lsit of sniper dots

        pLocalOrigin = pLocal:GetAbsOrigin() + vheight; LocalViewAngle = engine.GetViewAngles() --update local viewnangle
            --local LocalViewAngles = pLocal:GetPropVector("tfnonlocaldata", "m_angEyeAngles[0]")

        -- Constants for yaw settings
        local Real_Yaw = 0
        local Fake_Yaw = 0

            local vVelocity = pLocal:EstimateAbsVelocity()
            if (userCmd.sidemove == 0) then             -- Check if we not currently moving
                if userCmd.command_number % 2 == 0 then -- Check if the command number is even. (Potentially inconsistent, but it works).
                    userCmd:SetSideMove(33)
                else
                    userCmd:SetSideMove(-33)
                end
            elseif (userCmd.forwardmove == 0) then
                if userCmd.command_number % 2 == 0 then -- Check if the command number is even. (Potentially inconsistent, but it works).
                    userCmd:SetForwardMove(3)
                else
                    userCmd:SetForwardMove(-3)
                end
            end

        currentTarget = GetBestTarget(me) --GetClosestTarget(me, me:GetAbsOrigin()) -- Get the best target
    if currentTarget == nil then goto continue end ; currentTarget = currentTarget.entity --Check if we have target

        -- Get player and weapon info
        local class = pLocal:GetPropInt("m_iClass"); local pWeapon = me:GetPropEntity("m_hActiveWeapon")
        local currentTargetOrigin = currentTarget:GetAbsOrigin()
        distance1 = (pLocal:GetAbsOrigin() - currentTargetOrigin):Length()

        -- Calculate view information
        pLocalView = pLocal:GetAbsOrigin() + vheight
        local PViewPos = currentTargetOrigin + currentTarget:GetPropVector("localdata", "m_vecViewOffset[0]")
        --print(currentTarget:GetPropVector("tfnonlocaldata", "m_angEyeAngles[0]"))
        local viewAngles = currentTarget:GetPropVector("tfnonlocaldata", "m_angEyeAngles[0]"):Forward()
        local destination = PViewPos + viewAngles * distance1

        -- Calculate angles and FOV
        local angles = Math.PositionAngles(pLocalView, PViewPos); targetAngle = angles.yaw

        --print(viewAngles.pitch)
        -- Get hitbox and calculate offsets
        local hitboxes = pLocal:GetHitboxes()
        local hitbox = hitboxes[1]
        Headpos = (hitbox[1] + hitbox[2]) / 2
        HeadHeightOffset = Vector3(0, 0, pLocalView.z - Headpos.z)
        HeadOffsetHorizontal = ((pLocalView - HeadHeightOffset) - Headpos):Length()
    
        -- Circle parameters
        local radius = HeadOffsetHorizontal
        Circle_segments = 8
        local center = pLocalView - HeadHeightOffset

        -- Initialize variables for the closest point
        local closestPoint = nil
        local closestAngleDiff = math.huge

        -- Get the current latency and lerp
        local latOut = clientstate.GetLatencyOut()
        local latIn = clientstate.GetLatencyIn()
            local lerp = client.GetConVar("cl_interp") or 0
            Latency = (latOut + latIn + lerp)
            Latency = math.floor(Latency * tickRate) -- Convert the delay to ticks

        -- Generate circle vertices
        local vertices = {}
        local yaw_offset = targetAngle -- Replace this with the yaw offset you want to apply, in degrees

            --[--adjust yaw at enemy--]
            --Angles_Real = Real_Yaw; Angles_Fake = Fake_Yaw
            updateYaw(Angles_Real, Angles_Fake, userCmd)                 -- update yaw at enemy with selected offset

        -- process the lasrdots
        Serversite_angle = nil
        for key, dotInfo in pairs(sniperdotspoitions) do
            if dotInfo.Owner == currentTarget:GetName() then
                Serversite_angle = Math.PositionAngles(PViewPos, dotInfo.Position)
                print(Serversite_angle)
            end
      
            -- dotInfo.Position contains the position
            -- dotInfo.Owner contains the owner's name
            -- Do something with these, for example:
            -- Draw3DBox(9, dotInfo.Position)
            -- print("Owner: " .. dotInfo.Owner)
        end

    if viewAngles.x > 89 or viewAngles.x < -89 then goto continue end -- detect not shooting at us

        --if not gotshot then goto continue end
        local fov = math.abs(Math.AngleFov(viewAngles, angles))
    if fov > 30 then goto continue end --check if aimed at us

    if attackerReloadTimes[currentTarget] ~= nil then goto continue end --skip if target is reloading

        for i = 1, Circle_segments do
            local angle = math.rad(i * (360 / Circle_segments) + yaw_offset)
            local direction = Vector3(math.cos(angle), math.sin(angle), 0)
            local endpos = center + direction * radius
            vertices[i] = { pos = endpos, offset = angle }
        end

        -- Find the closest point on the circle to the enemy's FOV
        for i = 1, Circle_segments do
            local pointInfo = vertices[i]
            local point = pointInfo.pos
            local Pointoffset = pointInfo.offset
            local pointAngle = Math.PositionAngles(PViewPos, point)
            local angleDiff = Math.AngleFov(viewAngles, pointAngle)
            
            if angleDiff < closestAngleDiff then
                closestPoint = { pos = point, Pointoffset = Pointoffset }
                closestAngleDiff = angleDiff
            end
        end

    if not closestPoint then goto continue end
        targetResolverSettings[currentTarget] = closestPoint.Pointoffset
        
        local shootingAngle = closestPoint.Pointoffset  -- The shooting angle in radians

        -- Convert the angles to degrees for easier manipulation
        --shootingAngle = math.deg(shootingAngle)
    if not shootingAngle then goto continue end

        gotheadshot = false
        updateYaw(Angles_Real, Angles_Fake, userCmd)                 -- update yaw at enemy with selected offset

        closestPoint1 = Headpos --sets the point at headpos to avoid nil errors when not aiming at us
        closestPoint1 = closestPoint.pos
        closestPoint = closestPoint.pos

    ::continue::
end

-------------------------------VISUALS----------------------------------------------
local corners1
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
            Vector3(-halfSize, halfSize, halfSize)
        }
    end

    local linesToDraw = {
        {1, 2}, {2, 3}, {3, 4}, {4, 1},
        {5, 6}, {6, 7}, {7, 8}, {8, 5},
        {1, 5}, {2, 6}, {3, 7}, {4, 8}
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

local myfont = draw.CreateFont("Verdana", 16, 800) -- Create a font for doDraw
local direction = Vector3(0, 0, 0)
local directionReal = Vector3(0, 0, 0)
local function OnDraw()
    paint_logs()
    anim()
    draw.SetFont(myfont)
    if currentTarget == nil or
     engine.IsGameUIVisible() or
     engine.Con_IsVisible() then
        return
    end

    if not pLocal:IsAlive() then return end -- if not alive return

    local yaw

    if targetAngle ~= nil then

        yaw = targetAngle + Angles_Real + fluctuation
        draw.Text(0, 0, tostring(offsetNumber)) --debug

        if targetAngle then
            direction = Vector3(math.cos(math.rad(yaw)), math.sin(math.rad(yaw)), 0)
        end
    else
        yaw = gui.GetValue("Anti Aim - Custom Yaw (Real)")

        if targetAngle then
            direction = Vector3(math.cos(math.rad(yaw)), math.sin(math.rad(yaw)), 0)
        end
    end
    if targetAngle == nil then goto continue end

    local center = pLocal:GetAbsOrigin()
    local range = 50 --mmIndicator:GetValue()     -- Adjust the range of the line as needed

    -- Real
    draw.Color(81, 255, 54, 255)
    local screenPos = client.WorldToScreen(center)
    if screenPos ~= nil then
        local endPoint = center + direction * range
        directionReal = direction
        local screenPos1 = client.WorldToScreen(endPoint)
        if screenPos1 ~= nil then
            draw.Line(screenPos[1], screenPos[2], screenPos1[1], screenPos1[2])
        end
    end

    if targetAngle ~= nil then

        yaw = targetAngle + Angles_Fake + fluctuation

        if targetAngle then
            direction = Vector3(math.cos(math.rad(yaw)), math.sin(math.rad(yaw)), 0)
        end
    else
        yaw = gui.GetValue("Anti Aim - Custom Yaw (Real)")

        if targetAngle then
            direction = Vector3(math.cos(math.rad(yaw)), math.sin(math.rad(yaw)), 0)
        end
    end

    -- fake
    draw.Color(255, 0, 0, 255)
    screenPos = client.WorldToScreen(center)
    if screenPos ~= nil then
        local endPoint = center + direction * range
        local screenPos1 = client.WorldToScreen(endPoint)
        if screenPos1 ~= nil then
            draw.Line(screenPos[1], screenPos[2], screenPos1[1], screenPos1[2])
        end
    end

    local radius = HeadOffsetHorizontal
    local yawOffset = targetAngle  -- Replace with your yaw offset value
    center = pLocalView - HeadHeightOffset --pLocalView
    -- Set the color for the circle
    draw.Color(255, 255, 255, 255)

    -- Initialize table to store circle vertices
    local vertices = {}

    -- Calculate vertex positions around the circle
    for i = 1, Circle_segments do
        -- Add yaw offset to the angle for vertex calculation
        local angle = math.rad(i * (360 / Circle_segments) + yawOffset)
        
        -- Calculate direction based on the angle
        direction = Vector3(math.cos(angle), math.sin(angle), 0)

        -- Calculate the end position for the vertex
        local endpos = center + direction * radius

        -- Transform world position to screen position
        vertices[i] = client.WorldToScreen(endpos)
    end

    -- Draw the circle by connecting vertices
    for i = 1, Circle_segments do
        local j = (i % Circle_segments) + 1  -- Loop back to the start after the last segment
        if vertices[i] and vertices[j] then
            draw.Line(vertices[i][1], vertices[i][2], vertices[j][1], vertices[j][2])
        end
    end

    --[viewlines]
             --draw assumed head pos
             if closestPoint1 then
                screenPos = client.WorldToScreen(closestPoint1)
                Draw3DBox(9, closestPoint1)
             end

            for key, Dot in pairs(sniperdotspoitions) do
                Draw3DBox(9, Dot.Position)
            end
            
             --[[if screenPos ~= nil then
                 draw.Line( screenPos[1] + 10, screenPos[2], screenPos[1] - 10, screenPos[2])
                 draw.Line( screenPos[1], screenPos[2] - 10, screenPos[1], screenPos[2] + 10)
             end]]

        --local rockets = entities.FindByClass("CTFProjectile_Rocket") -- Find all rockets

        if not currentTarget or not currentTarget:IsAlive() or currentTarget:IsDormant() or pLocal:GetIndex() == currentTarget:GetIndex() then goto continue end

            local PViewPos = currentTarget:GetAbsOrigin() + currentTarget:GetPropVector("localdata", "m_vecViewOffset[0]")
            local viewAngles = currentTarget:GetPropVector("tfnonlocaldata", "m_angEyeAngles[0]"):Forward()
            if Serversite_angle then
                viewAngles = Serversite_angle:Forward()
                print(viewAngles)
            end
    
            if viewAngles and PViewPos then
                local destination = PViewPos + viewAngles * distance1

                local startScreenPos = client.WorldToScreen(PViewPos)
                local endScreenPos = client.WorldToScreen(destination)

                if startScreenPos ~= nil and endScreenPos ~= nil then
                    draw.Line(startScreenPos[1], startScreenPos[2], endScreenPos[1], endScreenPos[2])
                end
            end

        ::continue::
end

---------------------------------Resolver and angles UPDATE---------------------------------------------

local function OnPropUpdate()
    local viewangles = pLocal:GetPropVector("tflocaldata", "m_angEyeAngles[0]")
    if directionReal then
    pLocal:SetPropVector(Vector3(viewangles.x, viewangles.y, directionReal.z), "tfnonlocaldata", "m_angEyeAngles[0]")
    else
        print("NowYAW")
    end
end

--[[ Remove the menu when unloaded ]]
--
local function OnUnload()                                -- Called when the script is unloaded
    client.Command('play "ui/buttonclickrelease"', true) -- Play the "buttonclickrelease" sound
end

callbacks.Unregister("PostPropUpdate", "PostPropUpdateAA")
callbacks.Unregister("CreateMove", "CreateMoveAA")
callbacks.Unregister("Unload", "UnloadAA")         -- Unregister the "Unload" callback
callbacks.Unregister("Draw", "DrawAA")

callbacks.Register("PostPropUpdate", "PostPropUpdateAA", OnPropUpdate)
callbacks.Register("CreateMove", "CreateMoveAA", OnCreateMove)
callbacks.Register("Unload", "UnloadAA", OnUnload) -- Register the "Unload" callback
callbacks.Register("Draw", "DrawAA", OnDraw)

client.Command('play "ui/buttonclickrelease"', true) -- Play the "buttonclickrelease" sound