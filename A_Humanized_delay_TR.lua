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
        
        local angles = Math.PositionAngles(me:GetAbsOrigin(), player:GetAbsOrigin())
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
    
    return bestTarget
end

-- Initialize the global wait time
local waitTime = 0

local function OnCreateMove()
    pLocal = entities.GetLocalPlayer()

    if pLocal then
        local bestTarget, fov = GetBestTarget(pLocal)
        if bestTarget and IsVisible(bestTarget) then
            -- Target is visible, adjust reaction time based on FOV
            local reactionTime
            if fov < 10 then
                -- FOV is less than 10, set reaction time to 100-200ms
                reactionTime = math.random(50, 100)
            else
                -- FOV is 10 or more, set reaction time to 250-450ms
                reactionTime = math.random(250, 450)
            end

            if waitTime <= 0 then
                -- Set the reaction time and wait time
                gui.SetValue("trigger shoot delay (MS)", reactionTime)
                waitTime = reactionTime
            else
                -- Decrease wait time until it reaches 0
                waitTime = waitTime - 15.1515
            end
        else
            -- Target is not visible, set reaction time to 400-700ms
            local reactionTime = math.random(400, 700)

            if waitTime <= 0 then
                -- Set the reaction time and wait time
                gui.SetValue("trigger shoot delay (MS)", reactionTime)
                waitTime = reactionTime
            else
                -- Decrease wait time until it reaches 0
                waitTime = waitTime - 15.1515
            end
        end
    end
end


-- Unregister previous callbacks
callbacks.Unregister("CreateMove", "legit_CreateMove") -- Unregister the "CreateMove" callback
-- Register callbacks
callbacks.Register("CreateMove", "legit_CreateMove", OnCreateMove) -- Register the "CreateMove" callback