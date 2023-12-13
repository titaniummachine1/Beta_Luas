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

-- Initialize the global wait time and cache the last best target
local waitTime = 0
local lastBestTarget = nil
local lastBestFov = 360
local lastCheckTime = 0
local checkInterval = 0.10  -- Time interval in seconds to check for the best target

local function GetBestTarget(me)
    local currentTime = globals.CurTime()
    if currentTime - lastCheckTime < checkInterval then
        return lastBestTarget, lastBestFov
    end

    lastCheckTime = currentTime
    local players = entities.FindByClass("CTFPlayer")
    local bestTarget = nil
    local bestFov = 360

    for _, player in pairs(players) do
        if player:IsAlive() and not player:IsDormant() and player:GetTeamNumber() ~= me:GetTeamNumber() and (gui.GetValue("ignore cloaked") == 1 and not player:InCond(4)) then
            local angles = Math.PositionAngles(me:GetAbsOrigin(), player:GetAbsOrigin())
            local fov = Math.AngleFov(angles, engine.GetViewAngles())
            
            if fov <= bestFov and fov <= 90 then
                bestTarget = player
                bestFov = fov
            end
        end
    end

    lastBestTarget = bestTarget
    lastBestFov = bestFov
    return bestTarget, bestFov
end

local function OnCreateMove()
    pLocal = entities.GetLocalPlayer()

    if pLocal then
        local bestTarget, fov = GetBestTarget(pLocal)
        if bestTarget and IsVisible(bestTarget) then
            local reactionTimeRange = fov < 10 and {50, 100} or {250, 450}
            local reactionTime = math.random(reactionTimeRange[1], reactionTimeRange[2])

            if waitTime <= 0 then
                gui.SetValue("trigger shoot delay (MS)", reactionTime)
                waitTime = reactionTime
            else
                waitTime = waitTime - 15
            end
        else
            local reactionTime = math.random(400, 700)
            if waitTime <= 0 then
                gui.SetValue("trigger shoot delay (MS)", reactionTime)
                waitTime = reactionTime
            else
                waitTime = waitTime - 15
            end
        end
    end
end

-- Unregister and register callbacks
callbacks.Unregister("CreateMove", "legit_CreateMove")
callbacks.Register("CreateMove", "legit_CreateMove", OnCreateMove)
