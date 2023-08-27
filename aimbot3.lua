--[[
    Custom Aimbot for Lmaobox
    Author: github.com/lnx00
]]

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

local Hitbox = {
    Head = 1,
    Neck = 2,
    Pelvis = 4,
    Body = 5,
    Chest = 7
}

local vHitbox = { Vector3(-1, -1, -1), Vector3(1, 1, 1) }
local options = {
    AimKey = KEY_LSHIFT,
    AutoShoot = true,
    Silent = true,
    AimPos = {
        Hitscan = Hitbox.Head,
        Projectile = 11
    },
    AimFov = 120,
    PredTicks = 67,
    StrafePrediction = true,
    StrafeSamples = 20,
    MinHitchance = 20,
    DebugInfo = true
}

local latency = 0
local lerp = 0
local lastAngles = {} ---@type EulerAngles[]
local strafeAngles = {} ---@type number[]
local hitChance = 0
local lastPosition = {}
local vPath
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

        -- Ignore teammates (for now)
        if entity:GetTeamNumber() == me:GetTeamNumber() then
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

-- Finds the best position for hitscan weapons
---@param me WPlayer
---@param weapon WWeapon
---@param player WPlayer
---@return AimTarget?
local function CheckHitscanTarget(me, weapon, player)
    -- FOV Check
    local aimPos = player:GetHitboxPos(options.AimPos.Hitscan)
    if not aimPos then return nil end
    local angles = Math.PositionAngles(me:GetEyePos(), aimPos)
    local fov = Math.AngleFov(angles, engine.GetViewAngles())

    -- Visiblity Check
    if not Helpers.VisPos(player:Unwrap(), me:GetEyePos(), aimPos) then return nil end

    -- The target is valid
    local target = { entity = player, angles = angles, factor = fov }
    return target
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

-- Finds the best position for projectile weapons
---@param me WPlayer
---@param weapon WWeapon
---@param player WPlayer
---@return AimTarget?
local function CheckProjectileTarget(me, weapon, player)
    local projInfo = weapon:GetProjectileInfo()
    if not projInfo then return nil end
    local idx = player:GetIndex()
    local speed = projInfo[1]

    --local ProjShootOffset = Vector3(23.5, 8.0, -3.0)
    --local destination = source + engine.GetViewAngles():Forward()

    --local rotatedOffset = destination + ProjShootOffset

    local shootPos = me:GetEyePos() --+ rotatedOffset -- TODO: Add weapon offset
    local aimPos = player:GetAbsOrigin() + Vector3(0, 0, 10)
    local aimOffset = aimPos - player:GetAbsOrigin()
    --local aimOffset = Vector3()

    -- Distance check
    local maxDistance = options.PredTicks * speed
    if me:DistTo(player) > maxDistance then return nil end

    -- Visiblity Check
    if not Helpers.VisPos(player:Unwrap(), shootPos, player:GetAbsOrigin()) then return nil end

    -- Predict the player
    local strafeAngle = options.StrafePrediction and strafeAngles[player:GetIndex()] or nil
    local predData = Prediction.Player(player, 1, strafeAngle)
    if not predData then return nil end

    if lastPosition[idx] == nil then
        lastPosition[idx] = predData.pos[1]
        return nil
    end

    hitChance = calculateHitChancePercentage(lastPosition[idx], player:GetAbsOrigin())
    if hitChance < options.MinHitchance then -- if target is unpredictable, don't aim
        lastPosition[idx] = predData.pos[1]
        return nil
    end

    predData = Prediction.Player(player, options.PredTicks, strafeAngle)

    local fov
    -- Find a valid prediction
    for i = 0, options.PredTicks do
        local pos = predData.pos[i] + aimOffset

        local solution = Math.SolveProjectile(shootPos, pos, projInfo[1], projInfo[2])
        if not solution then goto continue end

        -- Calculate the fov
        fov = Math.AngleFov(solution.angles, engine.GetViewAngles())
        if fov > options.AimFov then
            goto continue
        end

        -- Time check
        local time = solution.time + latency + lerp
        local ticks = Conversion.Time_to_Ticks(time) + 1
        if ticks > i then goto continue end

        -- Visiblity Check
        if not Helpers.VisPos(player:Unwrap(), shootPos, pos) then
            goto continue
        end

        local projectileCollision = engine.TraceHull(shootPos, pos, vHitbox[1], vHitbox[2], MASK_PLAYERSOLID, shouldHitEntity)
        if not projectileCollision and projectileCollision.endpos == pos then goto continue end
    
        -- The prediction is valid
        targetAngles = solution.angles
        vPath = {path = predData.pos, lengh = i}
        break
        ::continue::
    end

    -- We didn't find a valid prediction
    if not targetAngles then return nil end
    lastPosition[idx] = predData.pos[1]

    --if target is too close, don't aim direction
    if (player:GetAbsOrigin() - me:GetAbsOrigin()):Length() < 100 then return end

    -- The target is valid
    local target = { entity = player, angles = targetAngles, factor = fov }
    return target
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

    -- FOV check
    local angles = Math.PositionAngles(me:GetEyePos(), player:GetAbsOrigin())
    local fov = Math.AngleFov(angles, engine.GetViewAngles())
    if fov > options.AimFov then return nil end

    if weapon:IsShootingWeapon() then
        -- TODO: Improve this

        local projType = weapon:GetWeaponProjectileType()
        if projType == 1 then
            -- Hitscan weapon
            return CheckHitscanTarget(me, weapon, player)
        else
            -- Projectile weapon
            return CheckProjectileTarget(me, weapon, player)
        end
    elseif weapon:IsMeleeWeapon() then
        -- TODO: Melee Aimbot
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
    local bestFactor = math.huge

    -- Check all players
    for _, entity in pairs(players) do
        local target = CheckTarget(me, weapon, entity)
        if not target then goto continue end

        -- Add valid target
        if target.factor < bestFactor then
            bestFactor = target.factor
            bestTarget = target
        end

        -- TODO: Continue searching
        break

        ::continue::
    end

    return bestTarget
end

---@param userCmd UserCmd
local function OnCreateMove(userCmd)
    if not input.IsButtonDown(options.AimKey) then
        if client.GetConVar("cl_autoreload") == 0 then
            client.Command("cl_autoreload 1", true)
        end
        return
    end

    local me = WPlayer.GetLocal()
    if not me or not me:IsAlive() then return end

    -- Calculate strafe angles (optional)
    if options.StrafePrediction then
        CalcStrafe(me)
    end

    local weapon = me:GetActiveWeapon()
    if not weapon then return end

    -- Check if we can shoot if not reload weapon
    local flCurTime = globals.CurTime()
    local canShoot = me:GetNextAttack() <= flCurTime
    if canShoot then
        if client.GetConVar("cl_autoreload") == 1 then
            client.Command("cl_autoreload 0", true)
        end
    else
        if client.GetConVar("cl_autoreload") == 0 then
            client.Command("cl_autoreload 1", true)
        end
        return
    end

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
    if not options.Silent then
        engine.SetViewAngles(currentTarget.angles)
    end

    -- Auto Shoot
    if options.AutoShoot then
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

    -- Dynamic optymisator
    if globals.FrameCount() % fps_check_interval == 0 then
        current_fps = math.floor(1 / globals.FrameTime())
        last_fps_check = globals.FrameCount()

        if input.IsButtonDown(options.AimKey) and targetFound then
            -- decrease values by 5 if FPS is less than 59
            if current_fps < 59 then
                options.PredTicks = math.max(options.PredTicks - 1, 1)
                options.StrafeSamples = math.max(options.StrafeSamples - 5, 4)
            end
            -- increase values every 100 frames if FPS is equal to or higher than 59 and aim key is pressed
            if current_fps >= fps_threshold and globals.FrameCount() - last_increase_frame >= 100 then
                options.PredTicks = options.PredTicks + 1
                options.StrafeSamples = options.StrafeSamples + 1
                last_increase_frame = globals.FrameCount()
            end
        end
    end

    if not options.DebugInfo then return end

    draw.SetFont(Fonts.Verdana)
    draw.Color(255, 255, 255, 255)

    draw.Text(20, 120, "Pred Ticks: " .. options.PredTicks)
    draw.Text(20, 140, "Strafe Samples: " .. options.StrafeSamples)
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

               --draw predicted local position with strafe prediction
               local screenPos = client.WorldToScreen(me:GetEyePos() + Vector3(23.5, 8.0, -3.0))
               if screenPos ~= nil then
                   draw.Line( screenPos[1] + 10, screenPos[2], screenPos[1] - 10, screenPos[2])
                   draw.Line( screenPos[1], screenPos[2] - 10, screenPos[1], screenPos[2] + 10)
               end


    -- Draw lines between the predicted positions
    if not vPath then return end

    for i = 1, vPath.lengh - 1 do
        local pos1 = vPath.path[i]
        local pos2 = vPath.path[i + 1]
 
        local screenPos1 = client.WorldToScreen(pos1)
        local screenPos2 = client.WorldToScreen(pos2)
 
        if screenPos1 ~= nil and screenPos2 ~= nil then
            draw.Line(screenPos1[1], screenPos1[2], screenPos2[1], screenPos2[2])
        end
    end
end

callbacks.Unregister("CreateMove", "LNX.Aimbot.CreateMove")
callbacks.Register("CreateMove", "LNX.Aimbot.CreateMove", OnCreateMove)

callbacks.Unregister("Draw", "LNX.Aimbot.Draw")
callbacks.Register("Draw", "LNX.Aimbot.Draw", OnDraw)