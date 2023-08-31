--[[
    Custom projectile Aimbot for Lmaobox
    author:
    github.com/titaniummachine1

    credit for proof of concept:
    github.com/lnx00
]]

local Hitbox = {
    Head = 1,
    Neck = 2,
    Pelvis = 4,
    Body = 5,
    Chest = 7,
    Feet = 11,
}

local AimModes = {
    Leading = true,
    Trailing = false,
}

local Menu = { -- this is the config that will be loaded every time u load the script

    tabs = { -- dont touch this, this is just for managing the tabs in the menu
        Main = true,
        Advanced = false,
        Visuals = false
    },

    Main = {
        Active = true,
        AimKey = KEY_LSHIFT,
        AutoShoot = true,
        Silent = true,
        AimPos = {
            Hitscan = Hitbox.Head,
            Projectile = Hitbox.Feet
        },
        AimFov = 120,
        MinHitchance = 35,
    },

    Advanced = {
        PredTicks = 69,
        StrafePrediction = true,
        StrafeSamples = 2,
        Aim_Modes = {
            Leading = true,
            trailing = false,
        },
        DebugInfo = true,
    },

    Visuals = {
        Active = true,
        VisualizePath = true,
        VisualizeProjectile = false,
        VisualizeHitPos = false,
    },
}

local menuLoaded, ImMenu = pcall(require, "ImMenu")
assert(menuLoaded, "ImMenu not found, please install it!")
assert(ImMenu.GetVersion() >= 0.66, "ImMenu version is too old, please update it!")

local lastToggleTime = 0
local Lbox_Menu_Open = true
local function toggleMenu()
    local currentTime = globals.RealTime()
    if currentTime - lastToggleTime >= 0.1 then
        if Lbox_Menu_Open == false then
            Lbox_Menu_Open = true
        elseif Lbox_Menu_Open == true then
            Lbox_Menu_Open = false
        end
        lastToggleTime = currentTime
    end
end

if UnloadLib then UnloadLib() end

---@alias AimTarget { entity : Entity, angles : EulerAngles, factor : number }

---@type boolean, lnxLib
local libLoaded, lnxLib = pcall(require, "lnxLib")
assert(libLoaded, "lnxLib not found, please install it!")
assert(lnxLib.GetVersion() >= 0.987, "lnxLib version is too old, please update it!")

local Math, Conversion = lnxLib.Utils.Math, lnxLib.Utils.Conversion
local WPlayer, WWeapon = lnxLib.TF2.WPlayer, lnxLib.TF2.WWeapon
local Helpers = lnxLib.TF2.Helpers
local Prediction = lnxLib.TF2.Prediction
local Fonts = lnxLib.UI.Fonts
local shouldHitEntity = function (e, _) return false end

local vHitbox = { Vector3(-1, -1, -1), Vector3(1, 1, 1) }

local latency = 0
local lerp = 0
local lastAngles = {} ---@type EulerAngles[]
local strafeAngles = {} ---@type number[]
local hitChance = 0
local lastPosition = nil
local vPath = {}
local targetFound

---@param me WPlayer
local function CalcStrafe(me)
    local players = entities.FindByClass("CTFPlayer")
    for idx, entity in ipairs(players) do
        if entity:IsDormant() or not entity:IsAlive() then
            lastAngles[idx] = nil
            strafeAngles[idx] = nil
            goto continue
        end

        -- Ignore teammates
        if entity:GetTeamNumber() == me:GetTeamNumber() then
            lastAngles[idx] = nil
            strafeAngles[idx] = nil
            goto continue
        end

        local v = entity:EstimateAbsVelocity()
        local angle = v:Angles()

        -- Play doesn't have a last angle
        if lastAngles[idx] == nil then
            lastAngles[idx] = angle
            goto continue
        end

        -- Calculate the delta angle
        if angle.y ~= lastAngles[idx].y then
            local delta = Math.NormalizeAngle(angle.y - lastAngles[idx].y)
            strafeAngles[idx] = math.clamp(delta, -5, 5)
        end
        lastAngles[idx] = angle

        ::continue::
    end
end


-- Predict the position of a player
---@param player WPlayer
---@param t integer
---@param d number?
---@param initialData { pos: Vector3, vel: Vector3, onGround: boolean }
---@param skipTicks integer
---@return { pos : Vector3[], vel: Vector3[], onGround: boolean[] }?
local function OptymisedPrediction(player, t, d, skipTicks)
    local gravity = client.GetConVar("sv_gravity")
    local stepSize = player:GetPropFloat("localdata", "m_flStepSize")
    if not gravity or not stepSize then return nil end

    local vUp = Vector3(0, 0, 1)
    vHitbox = { Vector3(-20, -20, 0), Vector3(20, 20, 80) }
    local vStep = Vector3(0, 0, stepSize / 2) -- smaller step size for more precision
    shouldHitEntity = function (e, _) return false end

    -- Add the current record
    local _out = {
        pos = { [0] = player:GetAbsOrigin() },
        vel = { [0] = player:EstimateAbsVelocity() },
        onGround = { [0] = player:IsOnGround() }
    }

    -- Cache math functions
    local acos = math.acos
    local deg = math.deg

    -- Perform the prediction
    local skipPhysics = false
    for i = 1, t * 2 do -- increase the number of iterations for more precision
        local lastP, lastV, lastG = _out.pos[i - 1], _out.vel[i - 1], _out.onGround[i - 1]

        local pos = lastP + lastV * globals.TickInterval()
        local vel = lastV
        local onGround = lastG

        -- Apply deviation
        if d then
            local ang = vel:Angles()
            ang.y = ang.y + d
            vel = ang:Forward() * vel:Length()
        end

        --[[ Forward collision ]]

        local wallTrace = engine.TraceHull(lastP + vStep, pos + vStep, vHitbox[1], vHitbox[2], MASK_PLAYERSOLID, shouldHitEntity)
        --DrawLine(last.p + vStep, pos + vStep)
        if wallTrace.fraction < 1 then
            -- We'll collide
            local normal = wallTrace.plane
            local angle = deg(acos(normal:Dot(vUp)))

            -- Check the wall angle
            if angle > 55 then
                -- The wall is too steep, we'll collide
                local dot = vel:Dot(normal)
                vel = vel - normal * dot
            end

            pos.x, pos.y = wallTrace.endpos.x, wallTrace.endpos.y
        end

        --[[ Ground collision ]]

        -- Don't step down if we're in-air
        local downStep = vStep
        if not onGround then downStep = Vector3() end

        local groundTrace = engine.TraceHull(pos + vStep, pos - downStep, vHitbox[1], vHitbox[2], MASK_PLAYERSOLID, shouldHitEntity)
        --DrawLine(pos + vStep, pos - downStep)
        if groundTrace.fraction < 1 then
            -- We'll hit the ground
            local normal = groundTrace.plane
            local angle = deg(acos(normal:Dot(vUp)))

            -- Check the ground angle
            if angle < 45 then
                pos = groundTrace.endpos
                onGround = true
            elseif angle < 55 then
                -- The ground is too steep, we'll slide [TODO]
                vel.x, vel.y, vel.z = 0, 0, 0
                onGround = false
            else
                -- The ground is too steep, we'll collide
                local dot = vel:Dot(normal)
                vel = vel - normal * dot
                onGround = true
            end

            -- Don't apply gravity if we're on the ground
            if onGround then vel.z = 0 end
        else
            -- We're in the air
            onGround = false
        end

        -- Gravity
        if not onGround then
            vel.z = vel.z - gravity * globals.TickInterval()
        end

        -- Add the prediction record
        _out.pos[i], _out.vel[i], _out.onGround[i] = pos, vel, onGround

        -- Skip physics calculations for the specified number of ticks
        if i >= skipTicks and not skipPhysics then
            local lastPos = _out.pos[i - skipTicks]
            local trace = engine.TraceHull(lastPos + vStep, pos + vStep, vHitbox[1], vHitbox[2], MASK_PLAYERSOLID, shouldHitEntity)
            if trace.fraction < 1 then
                skipPhysics = true
                i = i - skipTicks
            end
        end

        -- Reset skipPhysics flag
        if skipPhysics and i % skipTicks == 0 then
            skipPhysics = false
        end
    end

    return _out
end

local function calculateHitChancePercentage(lastPredictedPos, currentPos)

    local horizontalDistance = math.sqrt((currentPos.x - lastPredictedPos.x)^2 + (currentPos.y - lastPredictedPos.y)^2)
    local verticalDistanceUp = currentPos.z - lastPredictedPos.z
    local verticalDistanceDown = lastPredictedPos.z - currentPos.z
    
    -- You can adjust these values based on game's mechanics
    local maxHorizontalDistance = 16
    local maxVerticalDistanceUp = 45
    local maxVerticalDistanceDown = 0
    
    if horizontalDistance > maxHorizontalDistance or verticalDistanceUp > maxVerticalDistanceUp or verticalDistanceDown > maxVerticalDistanceDown then
        return 0 -- No chance to hit
    else
        local horizontalHitChance = 100 - (horizontalDistance / maxHorizontalDistance) * 100
        local verticalHitChance = 100 - (verticalDistanceUp / maxVerticalDistanceUp) * 100
        local overallHitChance = (horizontalHitChance + verticalHitChance) / 2
        return overallHitChance
    end
end

-- Constants
local FORWARD_COLLISION_ANGLE = 55
local GROUND_COLLISION_ANGLE_LOW = 45
local GROUND_COLLISION_ANGLE_HIGH = 55

-- Helper function for forward collision
local function handleForwardCollision(vel, wallTrace, vUp)
    local normal = wallTrace.plane
    local angle = math.deg(math.acos(normal:Dot(vUp)))
    if angle > FORWARD_COLLISION_ANGLE then
        local dot = vel:Dot(normal)
        vel = vel - normal * dot
    end
    return wallTrace.endpos.x, wallTrace.endpos.y
end

-- Helper function for ground collision
local function handleGroundCollision(vel, groundTrace, vUp)
    local normal = groundTrace.plane
    local angle = math.deg(math.acos(normal:Dot(vUp)))
    local onGround = false
    if angle < GROUND_COLLISION_ANGLE_LOW then
        onGround = true
    elseif angle < GROUND_COLLISION_ANGLE_HIGH then
        vel.x, vel.y, vel.z = 0, 0, 0
    else
        local dot = vel:Dot(normal)
        vel = vel - normal * dot
        onGround = true
    end
    if onGround then vel.z = 0 end
    return groundTrace.endpos, onGround
end

-- Main function
local function CheckProjectileTarget(me, weapon, player)
    -- Initialization and Checks
    local projInfo = weapon:GetProjectileInfo()
    if not projInfo then return nil end
    local idx = player:GetIndex()
    local speed = projInfo[1]
    local PredTicks = Menu.Advanced.PredTicks
    local shootPos = me:GetEyePos()
    local aimPos = player:GetAbsOrigin() + Vector3(0, 0, 10)
    local aimOffset = aimPos - player:GetAbsOrigin()
    if me:DistTo(player) > PredTicks * speed then return nil end
    if not Helpers.VisPos(player:Unwrap(), shootPos, player:GetAbsOrigin()) then return nil end
    local strafeAngle = Menu.Advanced.StrafePrediction and strafeAngles[player:GetIndex()] or nil

    local lastP = player:GetAbsOrigin()
    local lastV = player:EstimateAbsVelocity()
    local lastG = player:IsOnGround()
    local Deviation = strafeAngle
    local gravity = client.GetConVar("sv_gravity")
    local stepSize = player:GetPropFloat("localdata", "m_flStepSize")
    if not gravity or not stepSize then return nil end

    local vUp = Vector3(0, 0, 1)
    vHitbox = { Vector3(-20, -20, 0), Vector3(20, 20, 80) }
    local vStep = Vector3(0, 0, stepSize / 2)
    local targetAngles, fov
    hitChance = 0  -- Initialize to maximum
    vPath = {}
    local CurrPos

    -- Main Loop for Prediction and Projectile Calculations
    for i = 1, PredTicks * 2 do
        local pos = lastP + lastV * globals.TickInterval()
        local vel = lastV
        local onGround = lastG

        -- Apply deviation
        if Deviation then
            local ang = vel:Angles()
            ang.y = ang.y + Deviation
            vel = ang:Forward() * vel:Length()
        end

        -- Forward Collision
        local wallTrace = engine.TraceHull(lastP + vStep, pos + vStep, vHitbox[1], vHitbox[2], MASK_PLAYERSOLID, shouldHitEntity)
        if wallTrace.fraction < 1 then
            pos.x, pos.y = handleForwardCollision(vel, wallTrace, vUp)
        end

        -- Ground Collision
        local downStep = vStep
        if not onGround then downStep = Vector3() end
        local groundTrace = engine.TraceHull(pos + vStep, pos - downStep, vHitbox[1], vHitbox[2], MASK_PLAYERSOLID, shouldHitEntity)
        if groundTrace.fraction < 1 then
            pos, onGround = handleGroundCollision(vel, groundTrace, vUp)
        else
            onGround = false
        end

        -- Gravity
        if not onGround then
            vel.z = vel.z - gravity * globals.TickInterval()
        end

        -- Update lastP, lastV, lastG for the next iteration
        lastP, lastV, lastG = pos, vel, onGround

        -- Store the predicted position in the predicted path table
            table.insert(vPath, pos)

        -- Projectile Targeting Logic
        pos = lastP + aimOffset

        local solution = Math.SolveProjectile(shootPos, pos, projInfo[1], projInfo[2])
        if not solution then goto continue end

        lastPosition = pos
        fov = Math.AngleFov(solution.angles, engine.GetViewAngles())
        if fov > Menu.Main.AimFov then goto continue end

        local time = solution.time + latency + lerp
        local ticks = Conversion.Time_to_Ticks(time) + 1
        if ticks > i then goto continue end

        if not Helpers.VisPos(player:Unwrap(), shootPos, pos) then goto continue end

        -- Found a Valid Target
        targetAngles = solution.angles

        --[[if lastPosition == nil then
            lastPosition = pos
            return nil
        end

        hitChance = calculateHitChancePercentage(lastPosition, player:GetAbsOrigin())
        if hitChance < Menu.Main.MinHitchance then -- if target is unpredictable, don't aim
            lastPosition = pos
            return nil
        end]] --wil do it next time

        break
        ::continue::
    end

    if not targetAngles then return nil end

    -- Additional Checks and Finalization
    if (player:GetAbsOrigin() - me:GetAbsOrigin()):Length() < 100 then return end
    strafeAngle = 0 --reset deviation
    return { entity = player, angles = targetAngles, factor = fov }
end



-- Checks the given target for the given weapon
---@param me WPlayer
---@param weapon WWeapon
---@param entity Entity
---@return AimTarget?
local function CheckTarget(me, weapon, entity)
    if not entity then return nil end
    if not entity:IsAlive() then return nil end
    if entity:GetTeamNumber() == me:GetTeamNumber() then return nil end

    local player = WPlayer.FromEntity(entity)

    if weapon:IsShootingWeapon() then
        -- TODO: Improve this

        local projType = weapon:GetWeaponProjectileType()
        if projType == 1 then
            -- Hitscan weapon
            return --CheckHitscanTarget(me, weapon, player)
        else
            -- Projectile weapon
            return CheckProjectileTarget(me, weapon, player)
        end
    --[[elseif weapon:IsMeleeWeapon() then
        -- TODO: Melee Aimbot]]
    end

    return nil
end

-- Returns the best target for the given weapon
---@param me WPlayer
---@param weapon WWeapon
---@return AimTarget? target
local function GetBestTarget(me, weapon)
    local players = entities.FindByClass("CTFPlayer")
    local bestTarget = nil
    local bestFov = 360
    -- Check all players
    for _, entity in pairs(players) do
        local target = CheckTarget(me, weapon, entity)
        if not target then goto continue end

        -- FOV check
        local angles = Math.PositionAngles(me:GetEyePos(), entity:GetAbsOrigin())
        local fov = Math.AngleFov(angles, engine.GetViewAngles())
        if fov > Menu.Main.AimFov then return nil end

        -- Add valid target
        if fov <= bestFov then
            bestTarget = target
            bestFov = fov
        end

        -- TODO: Continue searching
        break

        ::continue::
    end

    return bestTarget
end

---@param userCmd UserCmd
local function OnCreateMove(userCmd)
    if not input.IsButtonDown(Menu.Main.AimKey) then
        return
    end

    local me = WPlayer.GetLocal()
    if not me or not me:IsAlive() then return end

    -- Calculate strafe angles (optional)
    if Menu.Advanced.StrafePrediction then
        CalcStrafe(me)
    end

    local weapon = me:GetActiveWeapon()
    if not weapon then return end

    -- Check if we can shoot if not reload weapon
    local flCurTime = globals.CurTime()
    --[[local canShoot = me:GetNextAttack() <= flCurTime
    if canShoot then
        if client.GetConVar("cl_autoreload") == 1 then
            client.Command("cl_autoreload 0", true)
        end
    else
        if client.GetConVar("cl_autoreload") == 0 then
            client.Command("cl_autoreload 1", true)
        end
        return
    end]]

    -- Get current latency
    local latIn, latOut = clientstate.GetLatencyIn(), clientstate.GetLatencyOut()
    latency = (latIn or 0) + (latOut or 0)

    -- Get current lerp
    lerp = client.GetConVar("cl_interp") or 0

    -- Get the best target
    local currentTarget = GetBestTarget(me, weapon)
    if not currentTarget then
        targetFound = nil
        return
    end
    targetFound = currentTarget
  
    -- Aim at the target
    userCmd:SetViewAngles(currentTarget.angles:Unpack())
    if not Menu.Main.Silent then
        engine.SetViewAngles(currentTarget.angles)
    end

    -- Auto Shoot
    if Menu.Main.AutoShoot then
        if weapon:GetWeaponID() == TF_WEAPON_COMPOUND_BOW
        or weapon:GetWeaponID() == TF_WEAPON_PIPEBOMBLAUNCHER then
            -- Huntsman
            if weapon:GetChargeBeginTime() > 0 then
                userCmd.buttons = userCmd.buttons & ~IN_ATTACK
            else
                userCmd.buttons = userCmd.buttons | IN_ATTACK
            end
        else
            -- Normal weapon
            userCmd.buttons = userCmd.buttons | IN_ATTACK
        end
    end
end

local function convertPercentageToRGB(percentage)
    local value = math.floor(percentage / 100 * 255)
    return math.max(0, math.min(255, value))
end

local current_fps = 0
local last_fps_check = 0
local fps_check_interval = 8 -- check FPS every 100 frames
local fps_threshold = 59 -- increase values if FPS is equal to or higher than 59
local last_increase_frame = 0 -- last frame when values were increased


local function OnDraw()
    local PredTicks = Menu.Advanced.PredTicks
    draw.SetFont(Fonts.Verdana)
    draw.Color(255, 255, 255, 255)

    if input.IsButtonPressed( KEY_END ) or input.IsButtonPressed( KEY_INSERT ) or input.IsButtonPressed( KEY_F11 ) then 
        toggleMenu()
    end
    --[[ Dynamic optymisator
    if globals.FrameCount() % fps_check_interval == 0 then
        current_fps = math.floor(1 / globals.FrameTime())
        last_fps_check = globals.FrameCount()

        if input.IsButtonDown(Menu.Main.AimKey) and targetFound then
            -- decrease values by 5 if FPS is less than 59
            if current_fps < 59 then
                --PredTicks = math.max(PredTicks - 1, 1)
                --Menu.Advanced.StrafeSamples = math.max(Menu.Advanced.StrafeSamples - 5, 4)
            end
            -- increase values every 100 frames if FPS is equal to or higher than 59 and aim key is pressed
            if current_fps >= fps_threshold and globals.FrameCount() - last_increase_frame >= 100 then
                PredTicks = PredTicks + 1
                Menu.Advanced.StrafeSamples = Menu.Advanced.StrafeSamples + 1
                last_increase_frame = globals.FrameCount()
            end
        end
    end]]

    -- Draw lines between the predicted positions
    if Menu.Visuals.VisualizePath and vPath then
        for i = 1, #vPath - 1 do
            local pos1 = vPath[i]
            local pos2 = vPath[i + 1]
    
            local screenPos1 = client.WorldToScreen(pos1)
            local screenPos2 = client.WorldToScreen(pos2)
    
            if screenPos1 ~= nil and screenPos2 ~= nil then
                draw.Line(screenPos1[1], screenPos1[2], screenPos2[1], screenPos2[2])
            end
        end
    end

    if not Menu.Visuals.DebugInfo then
        draw.SetFont(Fonts.Verdana)
        draw.Color(255, 255, 255, 255)

        draw.Text(20, 120, "Pred Ticks: " .. PredTicks)
        draw.Text(20, 140, "Strafe Samples: " .. Menu.Advanced.StrafeSamples)
        draw.Text(20, 160, "fps: " .. current_fps)
        -- Draw current latency and lerp
        draw.Text(20, 180, string.format("Latency: %.2f", latency))
        draw.Text(20, 200, string.format("Lerp: %.2f", lerp))

        local me = WPlayer.GetLocal()
        if not me or not me:IsAlive() then return end

        local weapon = me:GetActiveWeapon()
        if not weapon then return end

            -- Draw current weapon
        draw.Text(20, 220, string.format("Weapon: %s", weapon:GetName()))
        draw.Text(20, 240, string.format("Weapon ID: %d", weapon:GetWeaponID()))
        draw.Text(20, 260, string.format("Weapon DefIndex: %d", weapon:GetDefIndex()))


        local greenValue = convertPercentageToRGB(hitChance)
        local blueValue = convertPercentageToRGB(hitChance)
        draw.Color(255, greenValue, blueValue, 255)
        draw.Text(20, 280, string.format("%.2f", hitChance) .. "% Hitchance")
    end

    if Menu.Visuals.VisualizeProjectile then
    --draw predicted local position with strafe prediction
        local screenPos = client.WorldToScreen(me:GetEyePos() + Vector3(23.5, 8.0, -3.0))
        if screenPos ~= nil then
            draw.Line( screenPos[1] + 10, screenPos[2], screenPos[1] - 10, screenPos[2])
            draw.Line( screenPos[1], screenPos[2] - 10, screenPos[1], screenPos[2] + 10)
        end
    end

    if Lbox_Menu_Open == true and ImMenu.Begin("Custom Projectile Aimbot", true) then -- managing the menu
        --local menuWidth, menuHeight = 2500, 3000
        ImMenu.BeginFrame(1) -- tabs
        if ImMenu.Button("Main") then
            Menu.tabs.Main = true
            Menu.tabs.Advanced = false
            Menu.tabs.Visuals = false
        end

        if ImMenu.Button("Advanced") then
            Menu.tabs.Main = false
            Menu.tabs.Advanced = true
            Menu.tabs.Visuals = false
        end

        if ImMenu.Button("Visuals") then
            Menu.tabs.Main = false
            Menu.tabs.Advanced = false
            Menu.tabs.Visuals = true
        end
        ImMenu.EndFrame()

        if Menu.tabs.Main == true then
            ImMenu.BeginFrame(1)
            ImMenu.Text("The menu keys are INSERT, END and F11")
            ImMenu.EndFrame()

            ImMenu.BeginFrame(1)
            Menu.Main.Active = ImMenu.Checkbox("Active", Menu.Main.Active)
            ImMenu.EndFrame()

            ImMenu.BeginFrame(1)
            Menu.Main.AimFov = ImMenu.Slider("Fov", Menu.Main.AimFov , 0.1, 360)
            ImMenu.EndFrame()

            ImMenu.BeginFrame(1)
            Menu.Main.Silent = ImMenu.Checkbox("Silent", Menu.Main.Silent)
            ImMenu.EndFrame()

            --[[ImMenu.BeginFrame(1)
            ImMenu.Text("Hitbox")
            Menu.Main.AimPos.projectile = ImMenu.Option(Menu.Main.AimPos.projectile, Hitbox)
            ImMenu.EndFrame()]]
        end

        --[[if Menu.tabs.Advanced == true then
            ImMenu.BeginFrame(1)
            ImMenu.Text("Aim Mode")
            Menu.Advanced.Aim_Modes.projectiles = ImMenu.Option(Menu.Advanced.Aim_Modes.projectiles, AimModes)
            ImMenu.EndFrame()
        end]]
        ImMenu.End()
    end
end

callbacks.Unregister("CreateMove", "LNX.Aimbot.CreateMove")
callbacks.Register("CreateMove", "LNX.Aimbot.CreateMove", OnCreateMove)

callbacks.Unregister("Draw", "LNX.Aimbot.Draw")
callbacks.Register("Draw", "LNX.Aimbot.Draw", OnDraw)