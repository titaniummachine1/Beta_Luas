
--[[  Movement assist for  Lmaobox  ]]--
--[[           --Author--           ]]--
--[[           Terminator           ]]--
--[[  (github.com/titaniummachine1  ]]--

---@alias AimTarget { entity : Entity, angles : EulerAngles, factor : number }

---@type boolean, lnxLib
local libLoaded, lnxLib = pcall(require, "lnxLib")
assert(libLoaded, "lnxLib not found, please install it!")
assert(lnxLib.GetVersion() >= 0.995, "lnxLib version is too old, please update it!")
UnloadLib() --unloads all packages

local Math, Conversion = lnxLib.Utils.Math, lnxLib.Utils.Conversion
local WPlayer, WWeapon = lnxLib.TF2.WPlayer, lnxLib.TF2.WWeapon
local Helpers = lnxLib.TF2.Helpers
local Prediction = lnxLib.TF2.Prediction
local Fonts = lnxLib.UI.Fonts

local pLocal = entities.GetLocalPlayer()
local rockets = entities.FindByClass("CTFProjectile_Rocket")

local function NormalizeVector(vector)
    local length = math.sqrt(vector.x * vector.x + vector.y * vector.y + vector.z * vector.z)
    if length == 0 then
        return Vector3(0, 0, 0)
    else
        return Vector3(vector.x / length, vector.y / length, vector.z / length)
    end
end
--[[
local function calculateAveragePosition(pointsList)
    local totalPoints = #pointsList
    local sumX, sumY, sumZ = 0, 0, 0

    for _, point in ipairs(pointsList) do
        sumX = sumX + point.x
        sumY = sumY + point.y
        sumZ = sumZ + point.z
    end

    return { x = sumX / totalPoints, y = sumY / totalPoints, z = sumZ / totalPoints }
end

local function findEffectivePosition(position, pointsList)
    local averagePosition = calculateAveragePosition(pointsList)
    local directionVector = (averagePosition - position)
    local magnitude = directionVector:Length()

    if magnitude >= 50 then
        return position -- If the current position is already 50 units away from the average position, no need to move.
    else
        local targetPosition = { x = position.x + directionVector.x / magnitude * 50, 
                                 y = position.y + directionVector.y / magnitude * 50,
                                 z = position.z + directionVector.z / magnitude * 50 }
        return targetPosition
    end
end]]
local destination
local function OnCreateMove(userCmd)
    pLocal = entities.GetLocalPlayer()
    rockets = entities.FindByClass("CTFProjectile_Rocket")

    local closestRocket = nil
    local closestDistance = 500

    for i, rocket in pairs(rockets) do
        local rocketPos = rocket:GetAbsOrigin()
        local distance = (pLocal:GetAbsOrigin() - rocketPos):Length()

        if distance < closestDistance then
            closestDistance = distance
            closestRocket = rocket
        end
    end

    if closestRocket ~= nil then
        local rocketPos = closestRocket:GetAbsOrigin()
        local rocketVel = closestRocket:EstimateAbsVelocity()
        local hitPos = rocketPos + rocketVel * (closestDistance / (rocketVel:Length() * 2))

        destination = -hitPos
        if (destination - rocketPos):Length() < 50 then
            destination = -destination
        end
        print(math.abs((pLocal:GetAbsOrigin() - hitPos):Length()))
        if math.abs((pLocal:GetAbsOrigin() - hitPos):Length()) < 250 then
            Helpers.WalkTo(userCmd, pLocal, destination)
        end
    end
end

local function doDraw()
    rockets = entities.FindByClass("CTFProjectile_Rocket")

    for i, rocket in pairs(rockets) do
        local rocketPos = rocket:GetAbsOrigin()

        
        local distance = (pLocal:GetAbsOrigin() - rocketPos):Length()
        local RocketVel = NormalizeVector(rocket:EstimateAbsVelocity())

        local Target =  rocketPos + (RocketVel * distance)

        local startpos = client.WorldToScreen(rocketPos)
        local rocketTrace = engine.TraceLine(rocketPos, Target, MASK_SHOT_HULL)
        local endpos = client.WorldToScreen(rocketTrace.endpos)

        --local destination = source1 + viewAngles * distance

        if startpos ~= nil and endpos ~= nil then
            draw.Color(255, 255, 255, 255)
            draw.Line(startpos[1], startpos[2], endpos[1], endpos[2])
        end

        local Walkto = client.WorldToScreen(destination)
        local ppos = client.WorldToScreen(pLocal:GetAbsOrigin())
        if Walkto ~= nil and ppos ~= nil then
            draw.Color(0, 255, 0, 255)
            draw.Line(ppos[1], ppos[2], Walkto[1], Walkto[2])
        end
    end
end

--[[ Remove the menu when unloaded ]]--
local function OnUnload()                                -- Called when the script is unloaded
    UnloadLib() --unloading lualib
    client.Command('play "ui/buttonclickrelease"', true) -- Play the "buttonclickrelease" sound
end

--[[ Unregister previous callbacks ]]--
callbacks.Unregister("CreateMove", "AMAT_CreateMove")            -- Unregister the "CreateMove" callback
callbacks.Unregister("Unload", "AMAT_Unload")                    -- Unregister the "Unload" callback
callbacks.Unregister("Draw", "AMAT_Draw")                        -- Unregister the "Draw" callback
--[[ Register callbacks ]]--
callbacks.Register("CreateMove", "AMAT_CreateMove", OnCreateMove)             -- Register the "CreateMove" callback
callbacks.Register("Unload", "AMAT_Unload", OnUnload)                         -- Register the "Unload" callback
callbacks.Register("Draw", "AMAT_Draw", doDraw)                               -- Register the "Draw" callback

--[[ Play sound when loaded ]]--
client.Command('play "ui/buttonclick"', true) -- Play the "buttonclick" sound when the script is loaded