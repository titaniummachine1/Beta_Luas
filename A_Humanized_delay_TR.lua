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

local pLocal = entities:GetLocalPlayer()
local allPlayers = entities.FindByClass("CTFPlayer")
local function VisPos(target, from, to)
    local trace = engine.TraceLine(from, to, MASK_SHOT | CONTENTS_GRATE)
    return (trace.entity == target) or (trace.fraction > 0.99)
end

local function IsVisible(fromEntity)
    return VisPos(pLocal, fromEntity:GetAbsOrigin(), pLocal:GetAbsOrigin())
end

-- Normalizes a vector to a unit vector
local function NormalizeVector(vec)
    if vec == nil then return Vector3(0, 0, 0) end
    local length = math.sqrt(vec.x^2 + vec.y^2 + vec.z^2)
    if length == 0 then return Vector3(0, 0, 0) end
    return Vector3(vec.x / length, vec.y / length, vec.z / length)
end

local function GetBestTarget(me)
    local players = entities.FindByClass("CTFPlayer")
    local bestTarget = nil
    local bestFov = 360

    for _, player in pairs(players) do
        if player == nil or not player:IsAlive()
        or player:IsDormant()
        or player == me or player:GetTeamNumber() == me:GetTeamNumber()
        or gui.GetValue("ignore cloaked") == 1 and player:InCond(4) then
            goto continue
        end
        
        local angles = Math.PositionAngles(me:GetAbsOrigin() + Vector3(0,0, 75), player:GetAbsOrigin() + Vector3(0,0, 75))
        local fov = Math.AngleFov(angles, engine.GetViewAngles())
        
        if fov > 90 then
            goto continue
        end

        if fov <= bestFov then
            bestTarget = player
            bestFov = fov
        end

        ::continue::
    end

    if bestTarget then
        return bestTarget, bestFov
    else
        return nil
    end
end

-- Function to generate a random number based on a Gaussian distribution
local function GaussianRandom(mean, stddev, min, max)
    local function gaussian()
        return math.sqrt(-2 * math.log(math.random())) * math.cos(2 * math.pi * math.random())
    end

    local num = mean + gaussian() * stddev
    return math.max(min, math.min(max, num))
end

-- Function to calculate the reaction time based on FOV using Gaussian distribution
local function CalculateReactionTime(fov)
    local minTime, maxTime
    if fov < 10 then
        minTime, maxTime = 50, 150
    elseif fov <= 90 then
        minTime, maxTime = 250, 450
    else
        minTime, maxTime = 400, 700
    end
    local meanTime = (minTime + maxTime) / 2
    local stddevTime = (maxTime - meanTime) / 3 -- 3 standard deviations cover 99.7% of the bell curve
    return GaussianRandom(meanTime, stddevTime, minTime, maxTime)
end

-- Initialize global variables
local waitTime = 0
local lastUpdateTime = 0
local updateInterval = 0.2  -- Update interval in seconds
local mistakeShootTime = 0
local aimingAtHead = false

-- Function to generate a random time for potential mistake shot
local function RandomMistakeTime()
    return math.random(30, 70) / 1000  -- Random time between 30ms and 70ms
end

-- Function to check if the player is aiming at the head
local function IsAimingAtHead()
    local me = entities.GetLocalPlayer()
    local source = me:GetAbsOrigin() + me:GetPropVector("localdata", "m_vecViewOffset[0]")
    local destination = source + engine.GetViewAngles():Forward() * 1000
    local trace = engine.TraceLine(source, destination, MASK_SHOT)
    return trace.hitgroup == 1
end

local missChance = 30  -- Percentage chance of making a mistake shot
local shouldMiss = true

local function OnCreateMove(cmd)
    local currentTime = globals.CurTime()
    pLocal = entities.GetLocalPlayer()

    if pLocal then
        local bestTarget, fov = GetBestTarget(pLocal)

        if bestTarget and IsVisible(bestTarget) then
            local currentlyAimingAtHead = IsAimingAtHead()

            if currentlyAimingAtHead then
                if not aimingAtHead then
                    aimingAtHead = true
                    mistakeShootTime = 0  -- Reset mistake shoot time
                end
            else
                if aimingAtHead and mistakeShootTime == 0 then
                    mistakeShootTime = currentTime + RandomMistakeTime()
                end
            end

            if waitTime <= 0 or currentTime - lastUpdateTime >= updateInterval then
                local reactionTime = math.floor(CalculateReactionTime(fov))
                gui.SetValue("trigger shoot delay (MS)", reactionTime)
                waitTime = reactionTime
                lastUpdateTime = currentTime
            else
                waitTime = waitTime - 15
            end

            -- Check for mistake shot
            if shouldMiss and not currentlyAimingAtHead and currentTime >= mistakeShootTime and mistakeShootTime > 0 then
                local randomChance = math.random(100)  -- Generate a random number between 1 and 100
                if randomChance <= missChance then
                    -- If random number is less than or equal to miss chance, simulate mistake shot
                    cmd:SetButtons(cmd:GetButtons() | IN_ATTACK)
                end
                aimingAtHead = false  -- Reset aiming at head flag
                mistakeShootTime = 0  -- Reset mistake time for next potential shot
            end
        else
            if waitTime <= 0 or currentTime - lastUpdateTime >= updateInterval then
                local reactionTime = math.floor(CalculateReactionTime(360))
                gui.SetValue("trigger shoot delay (MS)", reactionTime)
                waitTime = reactionTime
                lastUpdateTime = currentTime
            else
                waitTime = waitTime - 15
            end
        end
    end
end




-- Unregister previous callbacks
callbacks.Unregister("CreateMove", "legit_CreateMove") -- Unregister the "CreateMove" callback
-- Register callbacks
callbacks.Register("CreateMove", "legit_CreateMove", OnCreateMove) -- Register the "CreateMove" callback